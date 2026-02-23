defmodule Razdel.Substring do
  @moduledoc "A located slice of text with character offsets."

  defstruct [:start, :stop, :text]

  @type t :: %__MODULE__{
          start: non_neg_integer(),
          stop: non_neg_integer(),
          text: String.t()
        }

  @doc "Locates chunks within the original text, returning character offsets."
  @spec locate([String.t()], String.t()) :: [t()]
  def locate([], _text), do: []

  def locate(chunks, text) do
    byte_spans = find_byte_spans(chunks, text)
    needed = byte_boundaries(byte_spans)
    char_map = scan_char_offsets(text, needed)

    Enum.map(byte_spans, fn {chunk, byte_start, byte_stop} ->
      %__MODULE__{
        start: Map.fetch!(char_map, byte_start),
        stop: Map.fetch!(char_map, byte_stop),
        text: chunk
      }
    end)
  end

  defp find_byte_spans(chunks, text) do
    text_size = byte_size(text)

    {spans, _} =
      Enum.reduce(chunks, {[], 0}, fn chunk, {acc, offset} ->
        chunk_size = byte_size(chunk)

        case :binary.match(text, chunk, scope: {offset, text_size - offset}) do
          {pos, ^chunk_size} ->
            {[{chunk, pos, pos + chunk_size} | acc], pos + chunk_size}

          _ ->
            {acc, offset}
        end
      end)

    Enum.reverse(spans)
  end

  defp byte_boundaries(spans) do
    spans
    |> Enum.flat_map(fn {_, s, e} -> [s, e] end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp scan_char_offsets(text, needed) do
    needed_set = MapSet.new(needed)
    max_needed = Enum.max(needed, fn -> 0 end)
    walk_binary(text, 0, 0, max_needed, needed_set, %{})
  end

  defp walk_binary(_bin, byte_off, _char_off, max_needed, _needed, map)
       when byte_off > max_needed do
    map
  end

  defp walk_binary(<<>>, byte_off, char_off, _max, needed, map) do
    if MapSet.member?(needed, byte_off), do: Map.put(map, byte_off, char_off), else: map
  end

  defp walk_binary(<<_::utf8, rest::binary>> = bin, byte_off, char_off, max, needed, map) do
    map = if MapSet.member?(needed, byte_off), do: Map.put(map, byte_off, char_off), else: map
    step = byte_size(bin) - byte_size(rest)
    walk_binary(rest, byte_off + step, char_off + 1, max, needed, map)
  end
end
