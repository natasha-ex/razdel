defmodule Razdel.TokenizeTest do
  use ExUnit.Case, async: true

  alias Razdel.Test.Partition

  defp assert_partition(line) do
    {text, expected} = Partition.parse(line)
    actual = Razdel.tokenize(text)

    assert Enum.map(actual, & &1.text) == Enum.map(expected, & &1.text),
           """
           Tokenize mismatch
           input:    #{inspect(text)}
           expected: #{inspect(Enum.map(expected, & &1.text))}
           actual:   #{inspect(Enum.map(actual, & &1.text))}
           """
  end

  # All unit test cases from the original Python test suite.
  @unit_cases [
    "1",
    "что-то",
    "К_тому_же",
    "...",
    "1,5",
    "1/2",

    # punct sequences
    "»||.",
    ")||.",
    "(||«",
    ":)))",
    ":)||,",

    # unicode symbols
    "mβж",
    "Δσ",
    ""
  ]

  for {line, index} <- Enum.with_index(@unit_cases) do
    @line line
    test "unit case #{index}: #{inspect(String.slice(line, 0, 30))}" do
      assert_partition(@line)
    end
  end

  describe "basic" do
    test "empty string" do
      assert Razdel.tokenize("") == []
    end

    test "single word" do
      [t] = Razdel.tokenize("слово")
      assert t.text == "слово"
      assert t.start == 0
      assert t.stop == String.length("слово")
    end

    test "compound word with dash" do
      tokens = Razdel.tokenize("Кружка-термос на 0.5л")
      texts = Enum.map(tokens, & &1.text)
      assert texts == ["Кружка-термос", "на", "0.5", "л"]
    end

    test "fraction" do
      tokens = Razdel.tokenize("50/64")
      assert [%{text: "50/64"}] = tokens
    end

    test "ellipsis" do
      tokens = Razdel.tokenize("...")
      assert [%{text: "..."}] = tokens
    end

    test "substring offsets match text" do
      text = "Кружка-термос на 0.5л (50/64 см³, 516;...)"

      for sub <- Razdel.tokenize(text) do
        assert String.slice(text, sub.start, sub.stop - sub.start) == sub.text
      end
    end
  end

  @int_count 500

  describe "integration (#{@int_count} random samples from tokens.txt)" do
    lines =
      Partition.load_data("tokens.txt")
      |> Partition.sample(@int_count)

    for {line, index} <- Enum.with_index(lines) do
      @line line
      test "tokens.txt sample #{index}" do
        assert_partition(@line)
      end
    end
  end
end
