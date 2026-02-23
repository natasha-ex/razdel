defmodule Razdel.Tokenize do
  @moduledoc """
  Rule-based Russian word tokenization.

  Splits text into atoms (smallest meaningful units), then applies
  rules to rejoin: dashes in compound words (что-то), underscores,
  floats (0.5), fractions (1/2), multi-char punctuation (..., ?!).
  """

  alias Razdel.{Punct, Substring}

  @punct_codepoints ("\\/!#$%&*+,.:;<=>?@^_`|~" <>
                       List.to_string(Punct.dashes()) <>
                       List.to_string(Punct.quotes()) <>
                       to_string(Enum.map(~c"([{)]}", &<<&1::utf8>>)))
                    |> String.to_charlist()
                    |> Kernel.++([0x2116, 0x2026])

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
    Substring.locate(tokens, text)
  end

  # --- Atom scanner using binary pattern matching ---

  defp scan_atoms(text), do: scan_atoms(text, 0, [])

  defp scan_atoms(<<>>, _pos, acc), do: Enum.reverse(acc)

  defp scan_atoms(<<c::utf8, _::binary>> = bin, pos, acc)
       when c in 0x0430..0x044F or c == 0x0451 do
    {token, rest, len} = grab_ru(bin)
    atom = make_atom(pos, len, :ru, token)
    scan_atoms(rest, pos + len, [atom | acc])
  end

  defp scan_atoms(<<c::utf8, _::binary>> = bin, pos, acc)
       when c in 0x0410..0x042F or c == 0x0401 do
    {token, rest, len} = grab_ru(bin)
    atom = make_atom(pos, len, :ru, token)
    scan_atoms(rest, pos + len, [atom | acc])
  end

  defp scan_atoms(<<c, _::binary>> = bin, pos, acc) when c in ?a..?z or c in ?A..?Z do
    {token, rest, len} = grab_lat(bin)
    atom = make_atom(pos, len, :lat, token)
    scan_atoms(rest, pos + len, [atom | acc])
  end

  defp scan_atoms(<<c, _::binary>> = bin, pos, acc) when c in ?0..?9 do
    {token, rest, len} = grab_int(bin)
    atom = make_atom(pos, len, :int, token)
    scan_atoms(rest, pos + len, [atom | acc])
  end

  defp scan_atoms(<<c::utf8, rest::binary>>, pos, acc) when c in @punct_codepoints do
    char = <<c::utf8>>
    len = byte_size(char)
    atom = make_atom(pos, len, :punct, char)
    scan_atoms(rest, pos + len, [atom | acc])
  end

  # Whitespace — skip
  defp scan_atoms(<<c, rest::binary>>, pos, acc) when c in ~c" \t\n\r" do
    scan_atoms(rest, pos + 1, acc)
  end

  # Other non-whitespace
  defp scan_atoms(<<c::utf8, rest::binary>>, pos, acc) do
    char = <<c::utf8>>
    len = byte_size(char)
    atom = make_atom(pos, len, :other, char)
    scan_atoms(rest, pos + len, [atom | acc])
  end

  defp make_atom(start, len, type, text) do
    %{start: start, stop: start + len, type: type, text: text, normal: String.downcase(text)}
  end

  defp grab_ru(bin), do: grab_ru(bin, <<>>, 0)

  defp grab_ru(<<c::utf8, rest::binary>>, acc, len)
       when c in 0x0430..0x044F or c in 0x0410..0x042F or c == 0x0451 or c == 0x0401 do
    char = <<c::utf8>>
    grab_ru(rest, <<acc::binary, char::binary>>, len + byte_size(char))
  end

  defp grab_ru(rest, acc, len), do: {acc, rest, len}

  defp grab_lat(bin), do: grab_lat(bin, <<>>, 0)

  defp grab_lat(<<c, rest::binary>>, acc, len) when c in ?a..?z or c in ?A..?Z do
    grab_lat(rest, <<acc::binary, c>>, len + 1)
  end

  defp grab_lat(rest, acc, len), do: {acc, rest, len}

  defp grab_int(bin), do: grab_int(bin, <<>>, 0)

  defp grab_int(<<c, rest::binary>>, acc, len) when c in ?0..?9 do
    grab_int(rest, <<acc::binary, c>>, len + 1)
  end

  defp grab_int(rest, acc, len), do: {acc, rest, len}

  # --- Token segmenter ---

  defp segment_tokens([], _text), do: []

  defp segment_tokens([first | rest], text) do
    all = [first | rest]

    {buffer, acc} =
      rest
      |> Enum.with_index(1)
      |> Enum.reduce({first.text, []}, fn {current, index}, {buffer, acc} ->
        process_atom(current, index, all, buffer, acc, text)
      end)

    Enum.reverse([buffer | acc])
  end

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
end
