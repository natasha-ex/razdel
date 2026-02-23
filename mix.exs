defmodule Razdel.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/natasha-ex/razdel"

  def project do
    [
      app: :razdel,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      name: "Razdel",
      description: "Rule-based Russian sentence and word tokenization",
      source_url: @source_url,
      docs: [main: "Razdel", extras: ["README.md"]]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Danila Poyarkov"]
    ]
  end
end
