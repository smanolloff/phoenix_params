defmodule PhoenixParams.MixProject do
  use Mix.Project

  def project do
    [
      app: :phoenix_params,
      version: "1.2.0",
      elixir: ">= 1.6.0",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      name: "PhoenixParams"
    ]
  end

  def application do
    []
  end

  defp deps do
    [
      {:phoenix, "~> 1.3"},
      {:decimal, "~> 1.8"},
      {:ex_doc, ">= 0.0.0", only: :dev},
    ]
  end

  defp description() do
    "A plug for Phoenix that validates and transforms HTTP request params."
  end

  defp package() do
    [
      name: "phoenix_params",
      files: ~w(.formatter.exs mix.exs lib README.md LICENSE),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/smanolloff/phoenix_params"}
    ]
  end
end
