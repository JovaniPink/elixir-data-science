defmodule ElixirDataScience.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_data_science,
      version: "0.1.0",
      elixir: ">= 1.19.0 and < 1.21.0",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:nx, "~> 0.13.1"},
      {:exla, "~> 0.13.1"},
      {:explorer, "~> 0.12.0"},
      {:scholar, "~> 0.4.2"},
      {:req, "~> 0.7.2"},
      {:vega_lite, "~> 0.1.11"},
      {:kino_vega_lite, "~> 0.1.13", only: :dev}
    ]
  end
end
