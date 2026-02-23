defmodule Razdel do
  @moduledoc """
  Rule-based Russian sentence and word tokenization.

  Elixir port of [Natasha Razdel](https://github.com/natasha/razdel) —
  a rule-based system optimized for Russian text segmentation.

  ## Usage

      iex> Razdel.sentenize("Привет. Как дела?")
      [%Razdel.Substring{start: 0, stop: 7, text: "Привет."},
       %Razdel.Substring{start: 8, stop: 17, text: "Как дела?"}]

      iex> Razdel.tokenize("Кружка-термос на 0.5л")
      [%Razdel.Substring{start: 0, stop: 13, text: "Кружка-термос"},
       %Razdel.Substring{start: 14, stop: 16, text: "на"},
       %Razdel.Substring{start: 17, stop: 20, text: "0.5"},
       %Razdel.Substring{start: 20, stop: 21, text: "л"}]

  ## Algorithm

  The segmenter uses a split-then-rejoin approach:

  1. Split text at every potential delimiter
  2. For each split point, apply a chain of rules
  3. First rule to return `:join` or `:split` wins
  4. If `:join` — merge adjacent chunks; if `:split` — emit boundary
  """

  alias Razdel.Sentenize
  alias Razdel.Substring
  alias Razdel.Tokenize

  @doc """
  Splits text into sentences. Returns a list of `Razdel.Substring` structs
  with `start`, `stop`, and `text` fields.
  """
  @spec sentenize(String.t()) :: [Substring.t()]
  defdelegate sentenize(text), to: Sentenize

  @doc """
  Splits text into tokens. Returns a list of `Razdel.Substring` structs
  with `start`, `stop`, and `text` fields.
  """
  @spec tokenize(String.t()) :: [Substring.t()]
  defdelegate tokenize(text), to: Tokenize
end
