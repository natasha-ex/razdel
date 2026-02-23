defmodule Razdel.Tokenize do
  @moduledoc """
  Rule-based Russian word tokenization.

  Splits text into atoms (smallest meaningful units), then applies
  rules to rejoin: dashes in compound words (что-то), underscores,
  floats (0.5), fractions (1/2), multi-char punctuation (..., ?!).
  """

  alias Razdel.{Punct, Substring}

  @puncts "\\/!#$%&*+,.:;<=>?@^_`|~№…" <>
            List.to_string(Punct.dashes()) <>
            List.to_string(Punct.quotes()) <>
            to_string(Enum.map(~c"([{)]}", &<<&1::utf8>>))

  @atom_re Regex.compile!(
             "(?P<ru>[а-яё]+)|(?P<lat>[a-z]+)|(?P<int>\\d+)|(?P<punct>[" <>
               Regex.escape(@puncts) <> "])|(?P<other>\\S)",
             "iu"
           )

  @smile_re Regex.compile!("^" <> Punct.smiles_pattern() <> "$", "u")

  @window 3

  @rules [
    &__MODULE__.dash/1,
    &__MODULE__.underscore/1,
    &__MODULE__.float_num/1,
    &__MODULE__.fraction/1,
    &__MODULE__.punct/1,
    &__MODULE__.other/1
  ]

  @type token_type :: :ru | :lat | :int | :punct | :other
  @type text_atom :: %{
          start: non_neg_integer(),
          stop: non_neg_integer(),
          type: token_type(),
          text: String.t(),
          normal: String.t()
        }

  @doc "Splits text into token substrings."
  @spec tokenize(String.t()) :: [Substring.t()]
  def tokenize(text) do
    atoms = scan_atoms(text)
    tokens = segment_tokens(atoms, text)
    locate_tokens(tokens, text)
  end

  # --- Atom scanner ---

  defp scan_atoms(text) do
    Regex.scan(@atom_re, text, return: :index)
    |> Enum.map(fn matches ->
      [{start, len} | groups] = matches
      text_slice = binary_part(text, start, len)
      type = detect_type(groups)

      %{
        start: start,
        stop: start + len,
        type: type,
        text: text_slice,
        normal: String.downcase(text_slice)
      }
    end)
  end

  # Named groups: ru, lat, int, punct, other
  defp detect_type(groups) do
    types = [:ru, :lat, :int, :punct, :other]

    Enum.zip(types, groups)
    |> Enum.find(fn {_type, {_start, len}} -> len > 0 end)
    |> elem(0)
  end

  # --- Token segmenter ---

  defp segment_tokens([], _text), do: []

  defp segment_tokens([first | rest], text) do
    {buffer, acc} =
      rest
      |> Enum.with_index(1)
      |> Enum.reduce({first.text, []}, fn {current, index}, {buffer, acc} ->
        process_atom(current, index, atoms_list(first, rest), buffer, acc, text)
      end)

    Enum.reverse([buffer | acc])
  end

  defp atoms_list(first, rest), do: [first | rest]

  defp process_atom(current, index, atoms, buffer, acc, text) do
    prev = Enum.at(atoms, index - 1)
    delimiter = binary_part(text, prev.stop, current.start - prev.stop)

    split = %{
      left: prev.text,
      right: current.text,
      delimiter: delimiter,
      left_atoms: window_before(atoms, index),
      right_atoms: window_after(atoms, index),
      buffer: buffer
    }

    if delimiter == "" and join?(split) do
      {buffer <> current.text, acc}
    else
      {current.text, [buffer | acc]}
    end
  end

  defp window_before(atoms, index) do
    start = max(0, index - @window)
    Enum.slice(atoms, start, index - start)
  end

  defp window_after(atoms, index) do
    Enum.slice(atoms, index, @window)
  end

  defp join?(split) do
    Enum.find_value(@rules, fn rule -> rule.(split) end) == :join
  end

  # --- Rules ---

  @doc false
  def dash(split), do: rule_2112(split, &Punct.dash?/1)

  @doc false
  def underscore(split), do: rule_2112(split, &(&1 == "_"))

  @doc false
  def float_num(split), do: rule_2112_int(split, &(&1 in ~w[. ,]))

  @doc false
  def fraction(split), do: rule_2112_int(split, &(&1 in ~w[/ \\]))

  @doc false
  def punct(split) do
    left = left_1(split)
    right = right_1(split)

    if left.type != :punct or right.type != :punct do
      nil
    else
      buffer_text = split.buffer <> right.text

      cond do
        Regex.match?(@smile_re, buffer_text) -> :join
        Punct.ending?(left.text) and Punct.ending?(right.text) -> :join
        (left.text <> right.text) in ~w[-- **] -> :join
        true -> nil
      end
    end
  end

  @doc false
  def other(split) do
    left = left_1(split)
    right = right_1(split)

    cond do
      left.type == :other and right.type in [:other, :ru, :lat] -> :join
      left.type in [:other, :ru, :lat] and right.type == :other -> :join
      true -> nil
    end
  end

  # --- 2112 pattern ---
  # "2112" handles delimiters that can be on either side:
  # "что-|то" (dash on left) or "что|-то" (dash on right)

  defp rule_2112(split, delimiter_check) do
    check_2112(split, delimiter_check, fn a, b -> a.type != :punct and b.type != :punct end)
  end

  defp rule_2112_int(split, delimiter_check) do
    check_2112(split, delimiter_check, fn a, b -> a.type == :int and b.type == :int end)
  end

  defp check_2112(split, delimiter_check, type_check) do
    left = left_1(split)
    right = right_1(split)

    cond do
      delimiter_check.(left.text) ->
        a = left_2(split)
        if a && type_check.(a, right), do: :join

      delimiter_check.(right.text) ->
        b = right_2(split)
        if b && type_check.(left, b), do: :join

      true ->
        nil
    end
  end

  defp left_1(%{left_atoms: [_ | _] = atoms}), do: List.last(atoms)
  defp left_1(_), do: %{type: nil, text: ""}

  defp left_2(%{left_atoms: atoms}) when length(atoms) >= 2, do: Enum.at(atoms, -2)
  defp left_2(_), do: nil

  defp right_1(%{right_atoms: [first | _]}), do: first
  defp right_1(_), do: %{type: nil, text: ""}

  defp right_2(%{right_atoms: [_, second | _]}), do: second
  defp right_2(_), do: nil

  # --- Location ---

  defp locate_tokens(tokens, text) do
    Substring.locate(tokens, text)
  end
end
