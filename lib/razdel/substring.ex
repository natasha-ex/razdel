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
    text_size = byte_size(text)
    do_locate(chunks, text, text_size, 0, 0, [])
  end

  defp do_locate([], _text, _text_size, _byte_off, _char_off, acc), do: Enum.reverse(acc)

  defp do_locate([chunk | rest], text, text_size, byte_off, char_off, acc) do
    chunk_size = byte_size(chunk)

    case :binary.match(text, chunk, scope: {byte_off, text_size - byte_off}) do
      {byte_pos, ^chunk_size} ->
        gap_chars = char_count(text, byte_off, byte_pos - byte_off)
        char_start = char_off + gap_chars
        chunk_chars = char_count(text, byte_pos, chunk_size)
        char_stop = char_start + chunk_chars
        sub = %__MODULE__{start: char_start, stop: char_stop, text: chunk}
        do_locate(rest, text, text_size, byte_pos + chunk_size, char_stop, [sub | acc])

      _ ->
        do_locate(rest, text, text_size, byte_off, char_off, acc)
    end
  end

  defp char_count(_text, _start, 0), do: 0

  defp char_count(text, start, len) do
    <<_::binary-size(start), slice::binary-size(len), _::binary>> = text
    count_utf8_chars(slice, 0)
  end

  defp count_utf8_chars(<<>>, n), do: n
  defp count_utf8_chars(<<_::utf8, rest::binary>>, n), do: count_utf8_chars(rest, n + 1)
end
