defmodule Razdel.Substring do
  @moduledoc "A located slice of text with character offsets."

  defstruct [:start, :stop, :text]

  @type t :: %__MODULE__{
          start: non_neg_integer(),
          stop: non_neg_integer(),
          text: String.t()
        }

  @doc "Locates chunks within the original text, returning character offsets."
  @spec locate(Enumerable.t(), String.t()) :: [t()]
  def locate(chunks, text) do
    graphemes = String.graphemes(text)

    chunks
    |> Enum.reduce({0, graphemes, []}, fn chunk, {char_offset, remaining, acc} ->
      chunk_graphemes = String.graphemes(chunk)
      {skip, rest} = find_chunk(chunk_graphemes, remaining, 0)
      start = char_offset + skip
      stop = start + String.length(chunk)
      rest_after = Enum.drop(rest, String.length(chunk))
      sub = %__MODULE__{start: start, stop: stop, text: chunk}
      {stop, rest_after, [sub | acc]}
    end)
    |> elem(2)
    |> Enum.reverse()
  end

  defp find_chunk([], remaining, skip), do: {skip, remaining}
  defp find_chunk(_chunk, [], skip), do: {skip, []}

  defp find_chunk([ch | _] = chunk, [g | rest], skip) do
    if ch == g do
      {skip, [g | rest]}
    else
      find_chunk(chunk, rest, skip + 1)
    end
  end
end
