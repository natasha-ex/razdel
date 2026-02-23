defmodule Razdel.Segmenter do
  @moduledoc """
  Generic split-then-rejoin segmenter.

  Takes a splitter (produces alternating chunks and split-contexts)
  and a list of rule functions. Walks through split points, asking
  each rule whether to join or split. First rule to decide wins.
  """

  @type action :: :join | :split
  @type rule :: (map() -> action() | nil)

  @doc """
  Segments text using the given splitter and rules.

  The splitter returns a list where text chunks alternate with
  split-context maps: `[chunk, %{...}, chunk, %{...}, chunk]`.

  Each rule is a function `split_context -> :join | :split | nil`.
  """
  @spec segment(list(), [rule()]) :: [String.t()]
  def segment(parts, rules) do
    case parts do
      [] -> []
      [single] -> [single]
      [first | rest] -> do_segment(rest, rules, first, [])
    end
  end

  defp do_segment([], _rules, buffer, acc) do
    Enum.reverse([buffer | acc])
  end

  defp do_segment([split, right | rest], rules, buffer, acc) do
    split = Map.put(split, :buffer, buffer)

    if join?(split, rules) do
      do_segment(rest, rules, buffer <> split.delimiter <> right, acc)
    else
      do_segment(rest, rules, right, [buffer <> split.delimiter | acc])
    end
  end

  defp join?(split, rules) do
    Enum.find_value(rules, fn rule ->
      rule.(split)
    end) == :join
  end
end
