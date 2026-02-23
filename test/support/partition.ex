defmodule Razdel.Test.Partition do
  @moduledoc false

  alias Razdel.Substring

  @fill_pattern ~r/^\s*$/u

  @doc """
  Parses a partition line into {full_text, expected_substrings}.

  Format: chunks separated by `|`. Whitespace-only chunks are fills
  (gaps between segments). Everything else is an expected segment.

  Example: `"Привет.| |Мир!"` → text `"Привет. Мир!"`,
  expected `[%Substring{start: 0, stop: 7, text: "Привет."},
             %Substring{start: 8, stop: 12, text: "Мир!"}]`
  """
  def parse(line) do
    chunks = String.split(line, "|")
    text = Enum.join(chunks)

    {substrings, _} =
      Enum.reduce(chunks, {[], 0}, fn chunk, {acc, pos} ->
        len = String.length(chunk)

        if Regex.match?(@fill_pattern, chunk) do
          {acc, pos + len}
        else
          sub = %Substring{start: pos, stop: pos + len, text: chunk}
          {[sub | acc], pos + len}
        end
      end)

    {text, Enum.reverse(substrings)}
  end

  @doc "Loads partition lines from a test data file."
  def load_data(filename) do
    Path.join([__DIR__, "..", "data", filename])
    |> File.stream!()
    |> Stream.map(&String.trim_trailing(&1, "\n"))
    |> Stream.reject(&(&1 == ""))
  end

  @doc "Samples `count` lines deterministically (matching Python's `random.seed(1)`)."
  def sample(lines, count) do
    all = Enum.to_list(lines)
    total = length(all)

    if count >= total do
      all
    else
      :rand.seed(:exsss, {1, 0, 0})

      0..(total - 1)
      |> Enum.to_list()
      |> Enum.shuffle()
      |> Enum.take(count)
      |> Enum.sort()
      |> Enum.map(&Enum.at(all, &1))
    end
  end
end
