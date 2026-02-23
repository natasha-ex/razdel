defmodule Razdel.Punct do
  @moduledoc false

  @endings ~c".?!…"
  @dashes ~c"‑–—−-"

  # «=U+00AB "=U+201C
  @open_quotes [0x00AB, 0x201C]
  # »=U+00BB "=U+201D '=U+2019
  @close_quotes [0x00BB, 0x201D, 0x2019]
  # "=U+0022 „=U+201E '=U+0027
  @generic_quotes [0x0022, 0x201E, 0x0027]
  @quotes @open_quotes ++ @close_quotes ++ @generic_quotes

  @close_brackets ~c")]}"

  @smiles_pattern ~S"[=:;]-?[)(]{1,3}"

  def endings, do: @endings
  def dashes, do: @dashes
  def close_quotes, do: @close_quotes
  def generic_quotes, do: @generic_quotes
  def quotes, do: @quotes
  def close_brackets, do: @close_brackets
  def smiles_pattern, do: @smiles_pattern

  @delimiters @endings ++ ~c";" ++ @generic_quotes ++ @close_quotes ++ @close_brackets
  def delimiters, do: @delimiters

  def ending?(<<c::utf8>>) when c in @endings, do: true
  def ending?(_), do: false

  def dash?(<<c::utf8>>) when c in @dashes, do: true
  def dash?(_), do: false

  def close_quote?(<<c::utf8>>) when c in @close_quotes, do: true
  def close_quote?(_), do: false

  def generic_quote?(<<c::utf8>>) when c in @generic_quotes, do: true
  def generic_quote?(_), do: false

  def quote?(<<c::utf8>>) when c in @quotes, do: true
  def quote?(_), do: false

  def close_bracket?(<<c::utf8>>) when c in @close_brackets, do: true
  def close_bracket?(_), do: false

  def delimiter?(<<c::utf8>>) when c in @delimiters, do: true
  def delimiter?(_), do: false
end
