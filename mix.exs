defmodule WandererKills.MixProject do
  use Mix.Project

  def project do
    [
      app: :wanderer_kills,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "A standalone service for retrieving and caching EVE Online killmails from zKillboard",
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),

      # Coverage configuration
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        test: :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        "coveralls.xml": :test
      ]
    ]
  end

  # The OTP application entrypoint:
  def application do
    [
      extra_applications: [
        :logger,
        :telemetry_poller
      ],
      mod: {WandererKills.App.Application, []}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Phoenix framework
      {:phoenix, "~> 1.7.14"},
      {:plug_cowboy, "~> 2.7"},

      # JSON parsing
      {:jason, "~> 1.4"},

      # Caching
      {:cachex, "~> 4.1"},

      # HTTP client with retry support
      {:req, "~> 0.5"},
      {:backoff, "~> 1.1"},

      # CSV parsing
      {:nimble_csv, "~> 1.2"},

      # Parallel processing
      {:flow, "~> 1.2"},

      # Telemetry
      {:telemetry_poller, "~> 1.2"},

      # Phoenix PubSub for real-time killmail distribution
      {:phoenix_pubsub, "~> 2.1"},

      # Development and test tools
      {:credo, "~> 1.7.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.3", only: [:dev], runtime: false},
      {:mox, "~> 1.2.0", only: :test},

      # Code coverage
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp package do
    [
      name: "wanderer_kills",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/guarzo/wanderer_kills"}
    ]
  end

  defp aliases do
    [
      check: [
        "format --check-formatted",
        "credo --strict",
        "dialyzer"
      ],
      "test.coverage": ["coveralls.html"],
      "test.coverage.ci": ["coveralls.json"]
    ]
  end
end
