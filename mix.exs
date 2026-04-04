defmodule PhoenixAI.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/franciscpd/phoenix-ai"

  def project do
    [
      app: :phoenix_ai,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      description: "AI integration library for Elixir inspired by laravel/ai",
      package: package(),
      name: "PhoenixAI",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.1"},
      {:telemetry, "~> 1.3"},
      {:finch, "~> 0.19"},
      {:server_sent_events, "~> 0.2"},
      {:mox, "~> 1.2", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib guides mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "getting-started",
      extras: [
        "guides/getting-started.md",
        "guides/provider-setup.md",
        "guides/agents-and-tools.md",
        "guides/pipelines-and-teams.md",
        "guides/cookbook/rag-pipeline.md",
        "guides/cookbook/multi-agent-team.md",
        "guides/cookbook/streaming-liveview.md",
        "guides/cookbook/custom-tools.md"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/[^\/]+\.md$/,
        Cookbook: ~r/guides\/cookbook\/.+\.md$/
      ],
      groups_for_modules: [
        Core: [AI, PhoenixAI.Message, PhoenixAI.Response, PhoenixAI.Conversation],
        Providers: [~r/PhoenixAI\.Providers\./],
        "Tools & Agent": [PhoenixAI.Tool, PhoenixAI.Agent, PhoenixAI.ToolLoop],
        Orchestration: [PhoenixAI.Pipeline, PhoenixAI.Team],
        Streaming: [PhoenixAI.Stream, PhoenixAI.StreamChunk],
        "Schema & Config": [PhoenixAI.Schema, PhoenixAI.Config],
        Testing: [PhoenixAI.Test, PhoenixAI.Providers.TestProvider]
      ]
    ]
  end
end
