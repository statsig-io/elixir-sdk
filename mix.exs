defmodule Statsig.MixProject do
  use Mix.Project

  def project do
    [
      app: :statsig,
      version: "0.1.0",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    case Mix.env() do
      :test ->
        [extra_applications: [:logger, :jason]]
      _ ->
        [
          mod: {Statsig.Application, []},
          extra_applications: [:logger, :jason]
        ]
    end
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support", "test/statsig"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.2"},
      {:ua_parser, "~> 1.8"}
    ]
  end
end
