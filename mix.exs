defmodule WandererKills.MixProject do
  use Mix.Project


  def project do
    [
      app: :wanderer_kills,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # The OTP application entrypoint:
  def application do
    [
      mod: {WandererKills.Application, []},
      extra_applications: [:logger, :runtime_tools, :cachex, :jason]
    ]
  end

  defp deps do
    [
      {:plug_cowboy, "~> 2.6"},     # HTTP server for exposing APIs
      {:cachex, "~> 3.6"},          # local in-memory cache
      {:redix, "~> 1.1"},           # Redis client (for cross-container cache, if desired)
      {:httpoison, "~> 2.0"},       # HTTP client (for ESI calls)
      {:jason, "~> 1.4"},           # JSON parsing
      # Add any other dependencies you already use under wanderer_app/zkb:
      # e.g. {:ecto_sql, "~> 3.10"}, {:postgrex, ">= 0.0.0"}, etc.
    ]
  end
end
