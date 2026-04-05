# Guardrails

PhoenixAI includes a guardrails pipeline that runs safety policies **before** your AI call.
Policies execute sequentially and halt on the first violation, following the same
railway-oriented pattern used in `PhoenixAI.Pipeline`.

## Quick Start

```elixir
alias PhoenixAI.Guardrails.{Pipeline, Request}
alias PhoenixAI.Message

# Build a request from user messages
request = %Request{
  messages: [%Message{role: :user, content: "Hello, how are you?"}]
}

# Use a preset or build your own policy list
policies = Pipeline.preset(:default)

case Pipeline.run(policies, request) do
  {:ok, request} ->
    # Safe — proceed with AI call
    AI.chat(request.messages, provider: :openai)

  {:error, violation} ->
    # Blocked — return a safe response
    IO.puts("Blocked: #{violation.reason}")
end
```

## Presets

Three built-in presets cover common configurations:

```elixir
# Minimal — jailbreak detection only
Pipeline.preset(:default)
# => [{JailbreakDetection, []}]

# Maximum protection — all three policies
Pipeline.preset(:strict)
# => [{JailbreakDetection, []}, {ContentFilter, []}, {ToolPolicy, []}]

# Reduced false positives — higher jailbreak threshold
Pipeline.preset(:permissive)
# => [{JailbreakDetection, [threshold: 0.9]}]
```

## Configuration with `from_config/1`

Build a policy list from a keyword config validated by NimbleOptions:

```elixir
# From a preset
{:ok, policies} = Pipeline.from_config(preset: :strict)

# Preset with overrides
{:ok, policies} = Pipeline.from_config(
  preset: :default,
  jailbreak_threshold: 0.5,
  jailbreak_scope: :all_user_messages
)

# Explicit policy list
{:ok, policies} = Pipeline.from_config(
  policies: [
    {JailbreakDetection, [threshold: 0.6]},
    {ContentFilter, [pre: &MyApp.sanitize/1]},
    {ToolPolicy, [allow: ["search", "calculate"]]}
  ]
)

# Invalid config returns a descriptive error
{:error, %NimbleOptions.ValidationError{}} =
  Pipeline.from_config(preset: :unknown)
```

### Config Options

| Key | Type | Description |
|-----|------|-------------|
| `:preset` | `:default \| :strict \| :permissive` | Named preset |
| `:policies` | `[{module, keyword}]` | Explicit policy list (overrides preset) |
| `:jailbreak_threshold` | `float` | Override jailbreak score threshold |
| `:jailbreak_scope` | `:last_message \| :all_user_messages` | Override jailbreak scan scope |
| `:jailbreak_detector` | `atom` | Override jailbreak detector module |

## Built-in Policies

### Jailbreak Detection

Detects jailbreak attempts using pattern matching against known attack categories:
role overrides, instruction overrides, DAN patterns, and base64 encoding evasion.

```elixir
# Default threshold (0.7), scans last user message
policies = [{JailbreakDetection, []}]

# Custom threshold and scope
policies = [{JailbreakDetection, [
  threshold: 0.5,
  scope: :all_user_messages
]}]

# Custom detector module
policies = [{JailbreakDetection, [
  detector: MyApp.MLJailbreakDetector
]}]
```

#### Custom Detector

Implement the `JailbreakDetector` behaviour to use your own detection logic:

```elixir
defmodule MyApp.MLJailbreakDetector do
  @behaviour PhoenixAI.Guardrails.JailbreakDetector

  alias PhoenixAI.Guardrails.JailbreakDetector.DetectionResult

  @impl true
  def detect(content, _opts) do
    score = MyApp.ML.score_jailbreak(content)

    result = %DetectionResult{
      score: score,
      patterns: if(score > 0.5, do: ["ml_detected"], else: []),
      details: %{model: "jailbreak-v2"}
    }

    if score > 0.5, do: {:detected, result}, else: {:safe, result}
  end
end
```

### Content Filter

Applies user-defined function hooks for content inspection. The `:pre` hook runs first,
then `:post`. If `:pre` rejects, `:post` is skipped.

```elixir
# Sanitize messages before AI call
pre_hook = fn request ->
  cleaned = Enum.map(request.messages, fn msg ->
    %{msg | content: String.replace(msg.content, ~r/<[^>]+>/, "")}
  end)
  {:ok, %{request | messages: cleaned}}
end

# Validate after all other policies pass
post_hook = fn request ->
  if has_pii?(request.messages) do
    {:error, "PII detected in messages"}
  else
    {:ok, request}
  end
end

policies = [{ContentFilter, [pre: pre_hook, post: post_hook]}]
```

Hooks must return `{:ok, %Request{}}` to continue or `{:error, reason}` to halt.

### Tool Policy

Enforces allowlists or denylists for tool calls. Only one mode can be active at a time.

```elixir
# Allowlist — only these tools are permitted
policies = [{ToolPolicy, [allow: ["search", "calculate"]]}]

# Denylist — these tools are blocked, all others pass
policies = [{ToolPolicy, [deny: ["delete_all", "drop_table"]]}]
```

When no tool calls are present in the request, the policy passes through.

## Custom Policies

Implement the `Policy` behaviour to create your own:

```elixir
defmodule MyApp.Guardrails.RateLimitPolicy do
  @behaviour PhoenixAI.Guardrails.Policy

  alias PhoenixAI.Guardrails.{PolicyViolation, Request}

  @impl true
  def check(%Request{} = request, opts) do
    user_id = request.user_id
    limit = Keyword.get(opts, :limit, 100)

    if MyApp.RateLimiter.within_limit?(user_id, limit) do
      {:ok, request}
    else
      {:halt, %PolicyViolation{
        policy: __MODULE__,
        reason: "Rate limit exceeded for user #{user_id}",
        metadata: %{user_id: user_id, limit: limit}
      }}
    end
  end
end

# Use it in a pipeline
policies = [
  {MyApp.Guardrails.RateLimitPolicy, [limit: 50]},
  {JailbreakDetection, []}
]
```

## Inter-Policy Communication

Use the `assigns` field on `Request` to pass data between policies:

```elixir
# First policy adds data
def check(request, _opts) do
  {:ok, %{request | assigns: Map.put(request.assigns, :sanitized, true)}}
end

# Later policy reads it
def check(request, _opts) do
  if request.assigns[:sanitized] do
    {:ok, request}
  else
    {:halt, %PolicyViolation{policy: __MODULE__, reason: "Not sanitized"}}
  end
end
```

## Telemetry

The guardrails pipeline emits telemetry events for observability:

| Event | Metadata |
|-------|----------|
| `[:phoenix_ai, :guardrails, :check, :start]` | `%{policy_count: integer}` |
| `[:phoenix_ai, :guardrails, :check, :stop]` | `%{policy_count: integer}` + duration |
| `[:phoenix_ai, :guardrails, :check, :exception]` | `%{policy_count: integer}` + exception info |
| `[:phoenix_ai, :guardrails, :policy, :start]` | `%{policy: module}` |
| `[:phoenix_ai, :guardrails, :policy, :stop]` | `%{policy: module, result: :pass \| :violation}` + duration |
| `[:phoenix_ai, :guardrails, :jailbreak, :detected]` | `%{score: float, threshold: float, patterns: [String.t()]}` |

### Example: Logging policy execution

```elixir
:telemetry.attach(
  "guardrails-logger",
  [:phoenix_ai, :guardrails, :policy, :stop],
  fn _event, measurements, metadata, _config ->
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.info(
      "Guardrails policy #{inspect(metadata.policy)} " <>
      "result=#{metadata.result} duration=#{duration_ms}ms"
    )
  end,
  nil
)
```

### Example: Alerting on jailbreak detection

```elixir
:telemetry.attach(
  "jailbreak-alert",
  [:phoenix_ai, :guardrails, :jailbreak, :detected],
  fn _event, _measurements, metadata, _config ->
    Logger.warning(
      "Jailbreak detected: score=#{metadata.score} " <>
      "threshold=#{metadata.threshold} patterns=#{inspect(metadata.patterns)}"
    )
  end,
  nil
)
```

## Full Example: Integrating with AI.chat/2

```elixir
defmodule MyApp.SafeChat do
  alias PhoenixAI.Guardrails.{Pipeline, Request}
  alias PhoenixAI.Message

  def chat(user_input, opts \\ []) do
    request = %Request{
      messages: [
        %Message{role: :system, content: "You are a helpful assistant."},
        %Message{role: :user, content: user_input}
      ],
      user_id: opts[:user_id]
    }

    with {:ok, policies} <- Pipeline.from_config(preset: :strict, jailbreak_threshold: 0.5),
         {:ok, safe_request} <- Pipeline.run(policies, request) do
      AI.chat(safe_request.messages, provider: :openai)
    else
      {:error, %PhoenixAI.Guardrails.PolicyViolation{} = v} ->
        {:error, {:blocked, v.reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```
