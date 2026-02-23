# Razdel

[![Hex.pm](https://img.shields.io/hexpm/v/razdel.svg)](https://hex.pm/packages/razdel)

Rule-based Russian sentence and word tokenization — Elixir port of [Natasha Razdel](https://github.com/natasha/razdel).

Part of the [natasha-ex](https://github.com/natasha-ex) ecosystem: Russian NLP for Elixir.

## Usage

```elixir
iex> Razdel.sentenize("Привет. Как дела?")
[%Razdel.Substring{start: 0, stop: 7, text: "Привет."},
 %Razdel.Substring{start: 8, stop: 17, text: "Как дела?"}]

iex> Razdel.tokenize("Кружка-термос на 0.5л")
[%Razdel.Substring{start: 0, stop: 13, text: "Кружка-термос"},
 %Razdel.Substring{start: 14, stop: 16, text: "на"},
 %Razdel.Substring{start: 17, stop: 20, text: "0.5"},
 %Razdel.Substring{start: 20, stop: 21, text: "л"}]
```

Handles Russian abbreviations (`т.е.`, `г.`, `ст.`, `к.п.н.`), initials (`Л. В. Щербы`), quotes, brackets, dialogue dashes, list bullets, and smileys.

## Installation

```elixir
def deps do
  [{:razdel, "~> 0.1.0"}]
end
```

## Algorithm

Split-then-rejoin: text is split at every potential delimiter (`.?!;""»…)`), then a chain of heuristic rules decides which splits are false positives and should be rejoined.

Rules (in priority order):
1. **empty_side** — join if either side is empty
2. **no_space_prefix** — join if no space after delimiter
3. **lower_right** — join if next token is lowercase
4. **delimiter_right** — join if next token is punctuation
5. **abbr_left** — join for known abbreviations (400+ entries)
6. **inside_pair_abbr** — join for paired abbreviations (т.е., и т.д.)
7. **initials_left** — join for single uppercase letters (initials)
8. **list_item** — join for numbered/lettered list bullets
9. **close_quote** — handle closing quotes correctly
10. **close_bracket** — handle closing brackets
11. **dash_right** — join dialogue dashes before lowercase words

## Performance

Benchmarked on the original test data (48,735 sentence texts, 208,995 token texts), Apple M5:

| Operation  | Python (CPython 3.13) | Elixir (OTP 27) | Ratio         |
| ---------- | --------------------: | --------------: | ------------- |
| sentenize  |          77,000 /s    |     10,000 /s   | Python ~7.7×  |
| tokenize   |         320,000 /s    |    131,000 /s   | Python ~2.4×  |

```bash
mix run bench/bench.exs
```

## License

MIT — Danila Poyarkov
