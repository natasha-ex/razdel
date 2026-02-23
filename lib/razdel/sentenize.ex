defmodule Razdel.Sentenize do
  @moduledoc """
  Rule-based Russian sentence segmentation.

  Splits text at sentence-ending punctuation (`.?!;…""»)`) then
  applies heuristic rules to rejoin false positives: abbreviations
  (т.е., г., ст.), initials (И.П.), quotes, brackets, list bullets,
  dashes, etc.
  """

  alias Razdel.{Abbr, Punct, Segmenter, Substring}

  @window_bytes 30

  @rules [
    &__MODULE__.empty_side/1,
    &__MODULE__.no_space_prefix/1,
    &__MODULE__.lower_right/1,
    &__MODULE__.delimiter_right/1,
    &__MODULE__.abbr_left/1,
    &__MODULE__.inside_pair_abbr/1,
    &__MODULE__.initials_left/1,
    &__MODULE__.list_item/1,
    &__MODULE__.close_quote/1,
    &__MODULE__.close_bracket/1,
    &__MODULE__.dash_right/1
  ]

  @smile_re Regex.compile!("^\\s*" <> Punct.smiles_pattern() <> "$", "u")
  @bullet_chars MapSet.new(~c"§абвгдеabcdef" |> Enum.map(&<<&1::utf8>>))
  @bullet_bounds MapSet.new(~w[. )])
  @bullet_size 20
  @roman_chars MapSet.new(~c"IVXML" |> Enum.map(&<<&1>>))

  @doc "Splits text into sentence substrings."
  @spec sentenize(String.t()) :: [Substring.t()]
  def sentenize(text) do
    text = String.trim(text)

    if text == "" do
      []
    else
      text
      |> split()
      |> Segmenter.segment(@rules)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Substring.locate(text)
    end
  end

  # --- Splitter: binary scan instead of Regex.scan ---

  @delimiters_set Punct.delimiters() |> Enum.map(&<<&1::utf8>>) |> MapSet.new()

  defp split(text), do: split_scan(text, 0, byte_size(text), [])

  defp split_scan(_text, pos, size, acc) when pos >= size do
    Enum.reverse(acc)
  end

  defp split_scan(text, pos, size, acc) do
    case scan_next_delimiter(text, pos, size) do
      nil ->
        chunk = binary_part(text, pos, size - pos)
        Enum.reverse([chunk | acc])

      {delim_start, delim_len} ->
        chunk = binary_part(text, pos, delim_start - pos)
        delim = binary_part(text, delim_start, delim_len)
        delim_stop = delim_start + delim_len

        left = safe_left(text, delim_start)
        right = safe_right(text, delim_stop, size)
        ctx = build_split_context(left, delim, right)

        if delim_stop >= size do
          Enum.reverse(["", ctx, chunk | acc])
        else
          split_scan(text, delim_stop, size, [ctx, chunk | acc])
        end
    end
  end

  defp scan_next_delimiter(text, pos, size) when pos < size do
    <<_::binary-size(pos), rest::binary>> = text

    case rest do
      # Smile patterns: =) :) ;) =( :( ;( with repetition
      <<c, d, tail::binary>> when c in ~c"=:;" and d in ~c"()" ->
        smile_len = 2 + count_repeated(tail, d)
        {pos, smile_len}

      <<c, ?-, d, tail::binary>> when c in ~c"=:;" and d in ~c"()" ->
        smile_len = 3 + count_repeated(tail, d)
        {pos, smile_len}

      <<c::utf8, _::binary>> ->
        char = <<c::utf8>>

        if MapSet.member?(@delimiters_set, char) do
          {pos, byte_size(char)}
        else
          scan_next_delimiter(text, pos + byte_size(char), size)
        end

      <<>> ->
        nil
    end
  end

  defp scan_next_delimiter(_text, _pos, _size), do: nil

  defp count_repeated(<<c, rest::binary>>, c), do: 1 + count_repeated(rest, c)
  defp count_repeated(_, _), do: 0

  defp safe_left(text, delim_start) do
    start = max(0, delim_start - @window_bytes)
    raw = binary_part(text, start, delim_start - start)
    trim_leading_invalid_utf8(raw)
  end

  defp safe_right(text, delim_stop, size) do
    stop = min(size, delim_stop + @window_bytes)
    raw = binary_part(text, delim_stop, stop - delim_stop)
    trim_trailing_invalid_utf8(raw)
  end

  defp trim_leading_invalid_utf8(<<>>), do: <<>>
  defp trim_leading_invalid_utf8(<<_::utf8, _::binary>> = bin), do: bin
  defp trim_leading_invalid_utf8(<<_, rest::binary>>), do: trim_leading_invalid_utf8(rest)

  defp trim_trailing_invalid_utf8(bin) do
    size = byte_size(bin)

    if String.valid?(bin) do
      bin
    else
      trim_trailing_invalid_utf8(binary_part(bin, 0, size - 1))
    end
  end

  defp build_split_context(left, delimiter, right) do
    %{
      left: left,
      delimiter: delimiter,
      right: right,
      left_token: last_token(left),
      right_token: first_token(right),
      left_pair_abbr: left_pair_abbr(left),
      right_space_prefix: space_prefix?(right),
      left_space_suffix: space_suffix?(left),
      right_word: first_word(right),
      buffer_tokens: nil
    }
  end

  # --- Rules ---

  @doc false
  def empty_side(%{left_token: nil}), do: :join
  def empty_side(%{right_token: nil}), do: :join
  def empty_side(_), do: nil

  @doc false
  def no_space_prefix(%{right_space_prefix: false}), do: :join
  def no_space_prefix(_), do: nil

  @doc false
  def lower_right(%{right_token: token}) when is_binary(token) do
    if lower_alpha?(token), do: :join
  end

  def lower_right(_), do: nil

  @doc false
  def delimiter_right(%{right_token: token}) when is_binary(token) do
    cond do
      Punct.generic_quote?(token) -> nil
      Punct.delimiter?(token) -> :join
      Regex.match?(@smile_re, token) -> :join
      true -> nil
    end
  end

  def delimiter_right(_), do: nil

  @doc false
  def abbr_left(%{delimiter: "."} = split) do
    right = split.right_token

    case split.left_pair_abbr do
      {a, b} -> check_pair_abbr({String.downcase(a), String.downcase(b)}, split.left_token, right)
      nil -> check_single_abbr(split.left_token, right)
    end
  end

  def abbr_left(_), do: nil

  defp check_pair_abbr(left_pair, left_token, right) do
    cond do
      Abbr.head_pair_abbr?(left_pair) ->
        :join

      Abbr.pair_abbr?(left_pair) ->
        if is_binary(right) and abbr_token?(right), do: :join

      true ->
        check_single_abbr(left_token, right)
    end
  end

  defp check_single_abbr(left_token, right) do
    left = String.downcase(left_token || "")

    cond do
      Abbr.head_abbr?(left) -> :join
      Abbr.abbr?(left) and is_binary(right) and abbr_token?(right) -> :join
      true -> nil
    end
  end

  @doc false
  def inside_pair_abbr(%{delimiter: "."} = split) do
    left = String.downcase(split.left_token || "")
    right = String.downcase(split.right_token || "")

    if Abbr.pair_abbr?({left, right}), do: :join
  end

  def inside_pair_abbr(_), do: nil

  @doc false
  def initials_left(%{delimiter: "."} = split) do
    left = split.left_token

    cond do
      is_nil(left) ->
        nil

      single_upper_letter?(left) ->
        :join

      Abbr.initial?(String.downcase(left)) ->
        :join

      true ->
        nil
    end
  end

  def initials_left(_), do: nil

  @doc false
  def list_item(split) do
    buffer = split[:buffer] || ""

    with true <- MapSet.member?(@bullet_bounds, split.delimiter),
         true <- String.length(buffer) <= @bullet_size,
         tokens = scan_tokens(buffer),
         true <- Enum.all?(tokens, &bullet_token?/1) do
      :join
    else
      _ -> nil
    end
  end

  @doc false
  def close_quote(split) do
    delim = split.delimiter

    cond do
      Punct.close_quote?(delim) ->
        close_bound(split)

      Punct.generic_quote?(delim) ->
        if split.left_space_suffix, do: :join, else: close_bound(split)

      true ->
        nil
    end
  end

  @doc false
  def close_bracket(%{delimiter: delim} = split) do
    if Punct.close_bracket?(delim), do: close_bound(split)
  end

  @doc false
  def dash_right(split) do
    right_tok = split.right_token

    if is_binary(right_tok) and Punct.dash?(right_tok) do
      right_word = split.right_word

      if is_binary(right_word) and lower_alpha?(right_word) do
        :join
      end
    end
  end

  # --- Helpers using binary matching instead of regex ---

  defp close_bound(split) do
    left = split.left_token
    if is_binary(left) and Punct.ending?(left), do: nil, else: :join
  end

  defp space_prefix?(<<c, _::binary>>) when c in ~c" \t\n\r", do: true
  defp space_prefix?(_), do: false

  defp space_suffix?(bin) when byte_size(bin) > 0 do
    last = :binary.last(bin)
    last in ~c" \t\n\r"
  end

  defp space_suffix?(_), do: false

  defp lower_alpha?(<<c::utf8>> = _single) when c in ?a..?z, do: true

  defp lower_alpha?(token) do
    all_chars_match?(token, &lower_alpha_char?/1)
  end

  defp lower_alpha_char?(c) when c in ?a..?z, do: true
  defp lower_alpha_char?(c) when c in 0x0430..0x044F, do: true
  defp lower_alpha_char?(0x0451), do: true
  defp lower_alpha_char?(_), do: false

  defp single_upper_letter?(<<c::utf8>>) when c in ?A..?Z, do: true
  defp single_upper_letter?(<<c::utf8>>) when c in 0x0410..0x042F, do: true
  defp single_upper_letter?(<<0x0401::utf8>>), do: true
  defp single_upper_letter?(_), do: false

  defp abbr_token?(token) do
    cond do
      all_digits?(token) -> true
      not all_alpha?(token) -> true
      lower_alpha?(token) -> true
      true -> false
    end
  end

  defp all_digits?(<<>>), do: false
  defp all_digits?(bin), do: all_chars_match?(bin, fn c -> c in ?0..?9 end)

  defp all_alpha?(<<>>), do: false
  defp all_alpha?(bin), do: all_chars_match?(bin, &alpha_char?/1)

  defp alpha_char?(c) when c in ?a..?z, do: true
  defp alpha_char?(c) when c in ?A..?Z, do: true
  defp alpha_char?(c) when c in 0x0410..0x044F, do: true
  defp alpha_char?(0x0401), do: true
  defp alpha_char?(0x0451), do: true
  defp alpha_char?(_), do: false

  defp all_chars_match?(<<>>, _fun), do: true

  defp all_chars_match?(<<c::utf8, rest::binary>>, fun),
    do: fun.(c) and all_chars_match?(rest, fun)

  defp bullet_token?(token) do
    cond do
      all_digits?(token) -> true
      MapSet.member?(@bullet_bounds, token) -> true
      MapSet.member?(@bullet_chars, String.downcase(token)) -> true
      all_roman?(token) -> true
      true -> false
    end
  end

  defp all_roman?(<<>>), do: false

  defp all_roman?(bin) do
    all_chars_match?(bin, fn c -> MapSet.member?(@roman_chars, <<c>>) end)
  end

  # Token extraction via binary pattern matching

  defp first_token(text), do: skip_spaces_then_token(text)

  defp last_token(text) do
    text
    |> String.trim_trailing()
    |> extract_last_token()
  end

  defp first_word(text), do: skip_to_word(text)

  defp left_pair_abbr(text) do
    text = String.trim_trailing(text)
    extract_pair_abbr(text)
  end

  # Skip whitespace, then grab first token (word | digits | single punct)
  defp skip_spaces_then_token(<<c, rest::binary>>) when c in ~c" \t\n\r",
    do: skip_spaces_then_token(rest)

  defp skip_spaces_then_token(bin), do: grab_token(bin, <<>>)

  defp grab_token(<<c::utf8, rest::binary>>, acc) when c in ?a..?z or c in ?A..?Z,
    do: grab_token(rest, <<acc::binary, c::utf8>>)

  defp grab_token(<<c::utf8, rest::binary>>, acc)
       when c in 0x0410..0x044F or c == 0x0401 or c == 0x0451,
       do: grab_token(rest, <<acc::binary, c::utf8>>)

  defp grab_token(<<c, rest::binary>>, acc) when c in ?0..?9,
    do: grab_token(rest, <<acc::binary, c>>)

  defp grab_token(<<?_, rest::binary>>, acc) when byte_size(acc) > 0,
    do: grab_token(rest, <<acc::binary, ?_>>)

  defp grab_token(_, acc) when byte_size(acc) > 0, do: acc

  defp grab_token(<<c::utf8, _::binary>>, <<>>) when c not in ~c" \t\n\r",
    do: <<c::utf8>>

  defp grab_token(_, <<>>), do: nil

  # Find first word (letters/digits) anywhere in text, skipping non-word chars
  defp skip_to_word(<<c::utf8, rest::binary>>) when c in ?a..?z or c in ?A..?Z,
    do: grab_word(rest, <<c::utf8>>)

  defp skip_to_word(<<c::utf8, rest::binary>>)
       when c in 0x0410..0x044F or c == 0x0401 or c == 0x0451,
       do: grab_word(rest, <<c::utf8>>)

  defp skip_to_word(<<c, rest::binary>>) when c in ?0..?9,
    do: grab_word(rest, <<c>>)

  defp skip_to_word(<<_::utf8, rest::binary>>), do: skip_to_word(rest)
  defp skip_to_word(<<>>), do: nil

  defp grab_word(<<c::utf8, rest::binary>>, acc) when c in ?a..?z or c in ?A..?Z,
    do: grab_word(rest, <<acc::binary, c::utf8>>)

  defp grab_word(<<c::utf8, rest::binary>>, acc)
       when c in 0x0410..0x044F or c == 0x0401 or c == 0x0451,
       do: grab_word(rest, <<acc::binary, c::utf8>>)

  defp grab_word(<<c, rest::binary>>, acc) when c in ?0..?9,
    do: grab_word(rest, <<acc::binary, c>>)

  defp grab_word(_, acc) when byte_size(acc) > 0, do: acc
  defp grab_word(_, _), do: nil

  # Extract last token from end of trimmed text
  defp extract_last_token(<<>>), do: nil

  defp extract_last_token(text) do
    {token, _} = extract_trailing_token(text, byte_size(text))
    token
  end

  defp extract_trailing_token(text, size) when size > 0 do
    # Walk backward to find last token boundary
    {last_end, last_start} = find_last_token_range(text, size)

    if last_start < last_end do
      {binary_part(text, last_start, last_end - last_start), last_start}
    else
      {nil, 0}
    end
  end

  defp extract_trailing_token(_, _), do: {nil, 0}

  defp find_last_token_range(text, size) do
    # Find the end of the last token (skip trailing non-token chars from the right)
    last_end = skip_trailing_spaces(text, size)

    if last_end == 0 do
      {0, 0}
    else
      # Check if the char at last_end-1 is a word/digit char
      prefix = binary_part(text, 0, last_end)

      case last_utf8_char(prefix) do
        {cp, cp_size} when cp in ?a..?z or cp in ?A..?Z or cp in ?0..?9 ->
          start = find_token_start(text, last_end - cp_size)
          {last_end, start}

        {cp, cp_size}
        when cp in 0x0410..0x044F or cp == 0x0401 or cp == 0x0451 ->
          start = find_token_start(text, last_end - cp_size)
          {last_end, start}

        {_cp, cp_size} ->
          {last_end, last_end - cp_size}
      end
    end
  end

  defp skip_trailing_spaces(text, pos) when pos > 0 do
    byte = :binary.at(text, pos - 1)

    if byte in ~c" \t\n\r" do
      skip_trailing_spaces(text, pos - 1)
    else
      pos
    end
  end

  defp skip_trailing_spaces(_, 0), do: 0

  defp find_token_start(text, pos) when pos > 0 do
    prefix = binary_part(text, 0, pos)

    case last_utf8_char(prefix) do
      {cp, cp_size}
      when cp in ?a..?z or cp in ?A..?Z or cp in ?0..?9 or cp in 0x0410..0x044F or
             cp == 0x0401 or cp == 0x0451 ->
        find_token_start(text, pos - cp_size)

      _ ->
        pos
    end
  end

  defp find_token_start(_, 0), do: 0

  defp last_utf8_char(<<>>), do: nil

  defp last_utf8_char(bin) do
    size = byte_size(bin)
    # UTF-8 chars are 1-4 bytes; try from 1 back
    try_last_char(bin, size, 1)
  end

  defp try_last_char(bin, size, n) when n <= 4 and n <= size do
    candidate = binary_part(bin, size - n, n)

    case candidate do
      <<c::utf8>> -> {c, n}
      _ -> try_last_char(bin, size, n + 1)
    end
  end

  defp try_last_char(_, _, _), do: nil

  # Extract pair abbreviation: pattern "X . Y" at end of left context
  defp extract_pair_abbr(<<>>), do: nil

  defp extract_pair_abbr(text) do
    # Walk backward: find last word char (b), then ".", then another word char (a)
    size = byte_size(text)
    # Skip trailing spaces
    pos = skip_trailing_spaces(text, size)
    if pos == 0, do: nil, else: do_extract_pair(text, pos)
  end

  defp do_extract_pair(text, pos) do
    # Grab last single word char
    prefix_b = binary_part(text, 0, pos)

    with {b_cp, b_size} <- last_utf8_char(prefix_b),
         true <- word_char?(b_cp),
         b = <<b_cp::utf8>>,
         # Check for "." before it (with optional spaces)
         pos2 = skip_trailing_spaces(text, pos - b_size),
         true <- pos2 > 0,
         true <- :binary.at(text, pos2 - 1) == ?.,
         # Skip spaces before "."
         pos3 = skip_trailing_spaces(text, pos2 - 1),
         true <- pos3 > 0,
         # Grab single word char
         prefix_a = binary_part(text, 0, pos3),
         {a_cp, _} <- last_utf8_char(prefix_a),
         true <- word_char?(a_cp) do
      {<<a_cp::utf8>>, b}
    else
      _ -> nil
    end
  end

  defp word_char?(c) when c in ?a..?z or c in ?A..?Z, do: true
  defp word_char?(c) when c in 0x0410..0x044F or c == 0x0401 or c == 0x0451, do: true
  defp word_char?(c) when c in ?0..?9, do: true
  defp word_char?(_), do: false

  # Scan tokens from text (for buffer_tokens in list_item)
  defp scan_tokens(text), do: do_scan_tokens(text, [])

  defp do_scan_tokens(<<>>, acc), do: Enum.reverse(acc)

  defp do_scan_tokens(<<c, rest::binary>>, acc) when c in ~c" \t\n\r",
    do: do_scan_tokens(rest, acc)

  defp do_scan_tokens(bin, acc) do
    {token, rest} = grab_any_token(bin)

    if token do
      do_scan_tokens(rest, [token | acc])
    else
      Enum.reverse(acc)
    end
  end

  defp grab_any_token(bin), do: grab_any_token(bin, <<>>)

  defp grab_any_token(<<c::utf8, rest::binary>>, acc)
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c in 0x0410..0x044F or
              c == 0x0401 or c == 0x0451,
       do: grab_any_token(rest, <<acc::binary, c::utf8>>)

  defp grab_any_token(rest, acc) when byte_size(acc) > 0, do: {acc, rest}

  defp grab_any_token(<<c::utf8, rest::binary>>, <<>>)
       when c not in ~c" \t\n\r",
       do: {<<c::utf8>>, rest}

  defp grab_any_token(rest, <<>>), do: {nil, rest}
end
