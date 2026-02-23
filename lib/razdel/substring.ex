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
        gap_chars = char_count(byte_pos - byte_off, text, byte_off)
        char_start = char_off + gap_chars
        chunk_chars = count_utf8(chunk, 0)
        char_stop = char_start + chunk_chars
        sub = %__MODULE__{start: char_start, stop: char_stop, text: chunk}
        do_locate(rest, text, text_size, byte_pos + chunk_size, char_stop, [sub | acc])

      _ ->
        do_locate(rest, text, text_size, byte_off, char_off, acc)
    end
  end

  defp char_count(0, _bin, _start), do: 0

  defp char_count(len, bin, start) do
    <<_::binary-size(start), slice::binary-size(len), _::binary>> = bin
    count_utf8(slice, 0)
  end

  defp count_utf8(<<>>, n), do: n
  defp count_utf8(<<_::utf8, rest::binary>>, n), do: count_utf8(rest, n + 1)
end
