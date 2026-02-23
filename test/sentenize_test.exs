defmodule Razdel.SentenizeTest do
  use ExUnit.Case, async: true

  alias Razdel.Test.Partition

  defp assert_partition(line) do
    {text, expected} = Partition.parse(line)
    actual = Razdel.sentenize(text)

    assert Enum.map(actual, & &1.text) == Enum.map(expected, & &1.text),
           """
           Sentenize mismatch
           input:    #{inspect(text)}
           expected: #{inspect(Enum.map(expected, & &1.text))}
           actual:   #{inspect(Enum.map(actual, & &1.text))}
           """
  end

  # All unit test cases from the original Python test suite.
  # Format: "|" separates chunks, " " fill between chunks = sentence boundary.

  @unit_cases [
    # trivial
    "фонетических правил языка; в случае, если",
    "(Прилепин — очень хороший писатель, лучше, чем Лимонов.| |Но враг)",
    "Петров - 176!| |Михайлов - 180!",
    "если бы… не тот широко",
    "Георгий Иванов.| |На грани музыки и сна",
    "исполняется 150 лет.| |31 мая 1859 года после неоднократных",

    # abbreviations
    "И т. д. и т. п.| |В общем, вся газета",
    "специалистом, к.п.н. И. П. Карташовым.",
    "основании п. 2, ст. 5 УПК",
    "Вблизи оз. Селяха",
    "уменьшить с 20 до 18 проц. (при сохранении",
    "6 июля 2007 г. \"в связи с совершением",
    "на 500 тыс. машин",
    "Влияние взглядов Л. В. Щербы",
    "директор фирмы Чарльз Дж. Филлипс",
    "Т.е. ОБЯЗАТЕЛЬНО письменно",
    "была утечка т.н. Таблицы боевых действий",
    "В 1996-1999гг. теффт",
    "России, т. е. 55 % опрошенных",
    "я ощущал в 1990-е.| |Славное было время",

    # bounds
    "словам, \"не будет точно\".| |\"Возможно, у нас",
    "Брось!..\"| |Связываться не хотелось",
    "Peter Goldreich,Scott Tremaine (1979).| |«Относительно теории колец Урана».",
    "Это чудовищные риски.| |\"Яндекс\" попал под удар",
    "кто они такие… »",

    # dashes
    "- \"Так в чем же дело?\"| |- \"Не ра-ду-ют\".",
    "— Ты ей скажи, что я ей гостинца дам.| |— А мне дашь?",

    # bullets
    "4. Я присутствовал во время встречи",
    "IV. Гестационный сахарный диабет",
    "§2. Нахождение оптимального объекта.",
    "8.1. Зачем нужны эти классы?",
    "в данной квартире;| |2) отчуждать свою долю",

    # smiles
    "пастухов - тоже ;)| |Я вспомнила",
    "распределённой жабы :))| |А платить мне будут аж 1200 рублей"
  ]

  for {line, index} <- Enum.with_index(@unit_cases) do
    @line line
    test "unit case #{index}: #{String.slice(line, 0, 60)}" do
      assert_partition(@line)
    end
  end

  describe "basic" do
    test "empty string" do
      assert Razdel.sentenize("") == []
    end

    test "whitespace only" do
      assert Razdel.sentenize("   ") == []
    end

    test "single sentence" do
      [s] = Razdel.sentenize("Привет мир.")
      assert s.text == "Привет мир."
      assert s.start == 0
    end

    test "substring offsets match text" do
      text = "Первое. Второе."

      for sub <- Razdel.sentenize(text) do
        assert String.slice(text, sub.start, sub.stop - sub.start) == sub.text
      end
    end
  end

  @int_count 200

  describe "integration (#{@int_count} random samples from sents.txt)" do
    lines =
      Partition.load_data("sents.txt")
      |> Partition.sample(@int_count)

    for {line, index} <- Enum.with_index(lines) do
      @line line
      test "sents.txt sample #{index}" do
        assert_partition(@line)
      end
    end
  end
end
