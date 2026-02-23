sent_lines =
  File.stream!("test/data/sents.txt")
  |> Stream.map(&String.trim_trailing(&1, "\n"))
  |> Stream.reject(&(&1 == ""))
  |> Enum.to_list()

tok_lines =
  File.stream!("test/data/tokens.txt")
  |> Stream.map(&String.trim_trailing(&1, "\n"))
  |> Stream.reject(&(&1 == ""))
  |> Enum.to_list()

sent_texts = Enum.map(sent_lines, fn l -> l |> String.split("|") |> Enum.join() end)
tok_texts = Enum.map(tok_lines, fn l -> l |> String.split("|") |> Enum.join() end)

IO.puts("Loaded #{length(sent_texts)} sentence texts, #{length(tok_texts)} token texts\n")

Enum.each(Enum.take(sent_texts, 500), &Razdel.sentenize/1)
Enum.each(Enum.take(tok_texts, 500), &Razdel.tokenize/1)

for run <- 1..3 do
  {su, _} = :timer.tc(fn -> Enum.each(sent_texts, &Razdel.sentenize/1) end)
  {tu, _} = :timer.tc(fn -> Enum.each(tok_texts, &Razdel.tokenize/1) end)
  ss = su / 1_000_000
  ts = tu / 1_000_000

  IO.puts(
    "Run #{run}: sentenize #{Float.round(ss, 3)}s (#{round(length(sent_texts) / ss)}/s) | tokenize #{Float.round(ts, 3)}s (#{round(length(tok_texts) / ts)}/s)"
  )
end
