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

  @delimiters_codepoints Punct.delimiters() |> Enum.uniq()

  defp split(text) do
    size = byte_size(text)
    scan(text, text, 0, size, [])
  end

  # Walk the binary tail directly — no position-based slicing
  defp scan(text, <<>>, chunk_start, size, acc) do
    final = binary_part(text, chunk_start, size - chunk_start)
    Enum.reverse([final | acc])
  end

  defp scan(text, <<c, d, tail::binary>>, chunk_start, size, acc)
       when c in ~c"=:;" and d in ~c"()" do
    pos = size - byte_size(<<c, d, tail::binary>>)
    extra = count_repeated(tail, d)
    delim_len = 2 + extra
    emit_split(text, pos, delim_len, chunk_start, size, skip_bytes(tail, extra), acc)
  end

  defp scan(text, <<c, ?-, d, tail::binary>>, chunk_start, size, acc)
       when c in ~c"=:;" and d in ~c"()" do
    pos = size - byte_size(<<c, ?-, d, tail::binary>>)
    extra = count_repeated(tail, d)
    delim_len = 3 + extra
    emit_split(text, pos, delim_len, chunk_start, size, skip_bytes(tail, extra), acc)
  end

  defp scan(text, <<c::utf8, rest::binary>>, chunk_start, size, acc)
       when c in @delimiters_codepoints do
    pos = size - byte_size(<<c::utf8, rest::binary>>)
    delim_len = byte_size(<<c::utf8>>)
    emit_split(text, pos, delim_len, chunk_start, size, rest, acc)
  end

  defp scan(text, <<_::utf8, rest::binary>>, chunk_start, size, acc) do
    scan(text, rest, chunk_start, size, acc)
  end

  defp emit_split(text, delim_start, delim_len, chunk_start, size, rest_after, acc) do
    chunk = binary_part(text, chunk_start, delim_start - chunk_start)
    delim = binary_part(text, delim_start, delim_len)
    delim_stop = delim_start + delim_len

    left = safe_left(text, delim_start)
    right = safe_right(text, delim_stop, size)
    ctx = build_split_context(left, delim, right)

    if rest_after == <<>> do
      Enum.reverse(["", ctx, chunk | acc])
    else
      scan(text, rest_after, delim_stop, size, [ctx, chunk | acc])
    end
  end

  defp count_repeated(<<c, rest::binary>>, c), do: 1 + count_repeated(rest, c)
  defp count_repeated(_, _), do: 0

  defp skip_bytes(bin, 0), do: bin
  defp skip_bytes(<<_, rest::binary>>, n), do: skip_bytes(rest, n - 1)

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
    scan_last_token(text, nil)
  end

  defp first_word(text), do: skip_to_word(text)

  defp left_pair_abbr(text) do
    scan_pair_abbr(text, nil, nil)
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

  # Forward scan — grab all tokens, return the last one found
  defp scan_last_token(<<>>, last), do: last

  defp scan_last_token(<<c, rest::binary>>, last) when c in ~c" \t\n\r",
    do: scan_last_token(rest, last)

  defp scan_last_token(bin, _last) do
    {token, rest} = grab_any_token(bin)
    if token, do: scan_last_token(rest, token), else: nil
  end

  # Match pattern: (\w)\s*\.\s*(\w)\s*$ at end of left context
  # Forward scan, track the last pair_abbr candidate seen
  defp scan_pair_abbr(<<>>, _a, _b), do: nil

  defp scan_pair_abbr(<<c, rest::binary>>, a, b) when c in ~c" \t\n\r",
    do: scan_pair_abbr(rest, a, b)

  defp scan_pair_abbr(<<?., rest::binary>>, _a, b),
    do: scan_pair_after_dot(rest, b)

  defp scan_pair_abbr(<<c::utf8, rest::binary>>, _a, _b) do
    scan_pair_abbr(rest, nil, <<c::utf8>>)
  end

  defp scan_pair_after_dot(<<>>, _b), do: nil

  defp scan_pair_after_dot(<<c, rest::binary>>, b) when c in ~c" \t\n\r",
    do: scan_pair_after_dot(rest, b)

  defp scan_pair_after_dot(<<c::utf8, rest::binary>>, b) do
    new_b = <<c::utf8>>

    case rest_is_end?(rest) do
      true -> if b, do: {b, new_b}
      false -> scan_pair_abbr(rest, nil, new_b)
    end
  end

  defp rest_is_end?(<<>>), do: true
  defp rest_is_end?(<<c, rest::binary>>) when c in ~c" \t\n\r", do: rest_is_end?(rest)
  defp rest_is_end?(_), do: false

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
