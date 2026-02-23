defmodule Razdel.Sentenize do
  @moduledoc """
  Rule-based Russian sentence segmentation.

  Splits text at sentence-ending punctuation (`.?!;…""»)`) then
  applies heuristic rules to rejoin false positives: abbreviations
  (т.е., г., ст.), initials (И.П.), quotes, brackets, list bullets,
  dashes, etc.
  """

  alias Razdel.{Abbr, Punct, Segmenter, Substring}

  @window 10

  @token ~r/([^\W\d]+|\d+|[^\w\s])/u
  @first_token ~r/^\s*([^\W\d]+|\d+|[^\w\s])/u
  @last_token ~r/([^\W\d]+|\d+|[^\w\s])\s*$/u
  @word ~r/([^\W\d]+|\d+)/u
  @pair_abbr ~r/(\w)\s*\.\s*(\w)\s*$/u

  @roman ~r/^[IVXML]+$/u
  @bullet_chars MapSet.new(~c"§абвгдеabcdef" |> Enum.map(&<<&1::utf8>>))
  @bullet_bounds MapSet.new(~w[. )])
  @bullet_size 20

  @space_suffix ~r/\s$/u
  @space_prefix ~r/^\s/u
  @smile_prefix_re Regex.compile!("^\\s*" <> Punct.smiles_pattern(), "u")

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

  # --- Splitter ---

  @delimiter_re Regex.compile!(
                  "(" <>
                    Punct.smiles_pattern() <>
                    "|[" <>
                    Regex.escape(List.to_string(Punct.delimiters())) <> "])",
                  "u"
                )

  defp split(text) do
    matches =
      Regex.scan(@delimiter_re, text, return: :index)
      |> Enum.map(fn [{start, len} | _] -> {start, len} end)

    if matches == [] do
      [text]
    else
      build_parts_from_matches(text, matches)
    end
  end

  defp build_parts_from_matches(text, matches) do
    text_len = String.length(text)

    {parts, prev_stop} =
      Enum.reduce(matches, {[], 0}, fn {byte_start, byte_len}, {acc, prev_byte} ->
        chunk = binary_part(text, prev_byte, byte_start - prev_byte)
        delim = binary_part(text, byte_start, byte_len)
        delim_char_start = String.length(binary_part(text, 0, byte_start))
        delim_char_stop = delim_char_start + String.length(delim)

        left_char_start = max(0, delim_char_start - @window)
        left = String.slice(text, left_char_start, delim_char_start - left_char_start)
        right_end = min(text_len, delim_char_stop + @window)
        right = String.slice(text, delim_char_stop, right_end - delim_char_stop)

        split_ctx = build_split_context(left, delim, right)
        {[split_ctx, chunk | acc], byte_start + byte_len}
      end)

    final_chunk = binary_part(text, prev_stop, byte_size(text) - prev_stop)
    Enum.reverse([final_chunk | parts])
  end

  defp build_split_context(left, delimiter, right) do
    %{
      left: left,
      delimiter: delimiter,
      right: right,
      left_token: last_token(left),
      right_token: first_token(right),
      left_pair_abbr: left_pair_abbr(left),
      right_space_prefix: Regex.match?(@space_prefix, right),
      left_space_suffix: Regex.match?(@space_suffix, left),
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
      Regex.match?(@smile_prefix_re, token) -> :join
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

      String.length(left) == 1 and String.match?(left, ~r/^\p{L}$/u) and
          left == String.upcase(left) ->
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
         tokens = buffer_tokens(buffer),
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

  # --- Helpers ---

  defp close_bound(split) do
    left = split.left_token
    if is_binary(left) and Punct.ending?(left), do: nil, else: :join
  end

  defp lower_alpha?(token) do
    String.match?(token, ~r/^[a-zа-яё]+$/u)
  end

  defp abbr_token?(token) do
    cond do
      String.match?(token, ~r/^\d+$/u) -> true
      not String.match?(token, ~r/^[a-zA-Zа-яёА-ЯЁ]+$/u) -> true
      lower_alpha?(token) -> true
      true -> false
    end
  end

  defp bullet_token?(token) do
    cond do
      String.match?(token, ~r/^\d+$/u) -> true
      MapSet.member?(@bullet_bounds, token) -> true
      MapSet.member?(@bullet_chars, String.downcase(token)) -> true
      Regex.match?(@roman, token) -> true
      true -> false
    end
  end

  defp first_token(text) do
    case Regex.run(@first_token, text) do
      [_, token] -> token
      _ -> nil
    end
  end

  defp last_token(text) do
    case Regex.run(@last_token, text) do
      [_, token] -> token
      _ -> nil
    end
  end

  defp first_word(text) do
    case Regex.run(@word, text) do
      [_, word] -> word
      _ -> nil
    end
  end

  defp left_pair_abbr(text) do
    case Regex.run(@pair_abbr, text) do
      [_, a, b] -> {a, b}
      _ -> nil
    end
  end

  defp buffer_tokens(text) do
    Regex.scan(@token, text) |> Enum.map(fn [t | _] -> t end)
  end
end
