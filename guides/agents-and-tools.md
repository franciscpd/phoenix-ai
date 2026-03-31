# Agents & Tools

## Tools

Tools allow AI models to call Elixir functions during a conversation. When a model
decides to use a tool, PhoenixAI executes it and feeds the result back automatically.

### Implementing the Tool Behaviour

A tool is a plain module implementing `@behaviour PhoenixAI.Tool` with four callbacks:

```elixir
defmodule MyApp.WeatherTool do
  @behaviour PhoenixAI.Tool

  @impl true
  def name, do: "get_weather"

  @impl true
  def description, do: "Get current weather conditions for a city"

  @impl true
  def parameters_schema do
    %{
      type: :object,
      properties: %{
        city: %{type: :string, description: "The city name"},
        units: %{
          type: :string,
          enum: ["celsius", "fahrenheit"],
          description: "Temperature units"
        }
      },
      required: [:city]
    }
  end

  @impl true
  def execute(%{"city" => city, "units" => units}, _opts) do
    # Call your weather API here
    {:ok, "#{city}: 22°#{String.first(units)}"}
  end

  def execute(%{"city" => city}, opts) do
    execute(%{"city" => city, "units" => "celsius"}, opts)
  end
end
```

### Callback Details

| Callback | Return type | Description |
|---|---|---|
| `name/0` | `String.t()` | Unique function name the model uses to call this tool |
| `description/0` | `String.t()` | Natural language description of what the tool does |
| `parameters_schema/0` | `map()` | JSON Schema (atom-keyed) describing the tool's arguments |
| `execute/2` | `{:ok, String.t()} \| {:error, term()}` | Runs when the model calls the tool |

The `execute/2` arguments are:
- `args` — a string-keyed map of arguments the model provided
- `opts` — keyword list with provider options (api_key, model, etc.)

### Using Tools with AI.chat/2

Pass tool modules in the `:tools` list:

```elixir
{:ok, response} = AI.chat(
  [%PhoenixAI.Message{role: :user, content: "What's the weather in Lisbon?"}],
  provider: :openai,
  tools: [MyApp.WeatherTool]
)

# PhoenixAI automatically:
# 1. Sends tool definitions to the model
# 2. Detects tool call in the response
# 3. Calls MyApp.WeatherTool.execute/2
# 4. Sends the result back to the model
# 5. Returns the final text response

IO.puts(response.content)
# => "The weather in Lisbon is 22°C and sunny."
```

Multiple tools work the same way — pass all of them and the model chooses:

```elixir
{:ok, response} = AI.chat(
  messages,
  provider: :openai,
  tools: [MyApp.WeatherTool, MyApp.CalendarTool, MyApp.SearchTool]
)
```

## Agent GenServer

`PhoenixAI.Agent` is a `GenServer` that owns a single conversation thread. It runs
the completion-tool-call loop asynchronously and accumulates message history.

### Starting an Agent

```elixir
{:ok, pid} = PhoenixAI.Agent.start_link(
  provider: :openai,
  model: "gpt-4o",
  system: "You are a helpful assistant with access to real-time weather data.",
  tools: [MyApp.WeatherTool],
  api_key: System.get_env("OPENAI_API_KEY")
)
```

### Sending Prompts

`PhoenixAI.Agent.prompt/2` blocks until the model (and any tool calls) complete:

```elixir
{:ok, response} = PhoenixAI.Agent.prompt(pid, "What's the weather in Lisbon?")
IO.puts(response.content)
# => "The weather in Lisbon is sunny and 22°C."

{:ok, response} = PhoenixAI.Agent.prompt(pid, "And in Porto?")
# The agent remembers the previous exchange automatically
```

With a custom timeout (default is 60 seconds):

```elixir
{:ok, response} = PhoenixAI.Agent.prompt(pid, "Complex question...", timeout: 120_000)
```

### manage_history Modes

**`manage_history: true`** (default) — The agent accumulates messages between calls:

```elixir
{:ok, pid} = PhoenixAI.Agent.start_link(
  provider: :openai,
  manage_history: true  # default
)

PhoenixAI.Agent.prompt(pid, "My name is Alice.")
PhoenixAI.Agent.prompt(pid, "What is my name?")
# => "Your name is Alice." (remembers previous exchange)
```

**`manage_history: false`** — The agent is stateless; you manage history externally:

```elixir
{:ok, pid} = PhoenixAI.Agent.start_link(
  provider: :openai,
  manage_history: false
)

history = []

{:ok, r1} = PhoenixAI.Agent.prompt(pid, "My name is Alice.", messages: history)
assistant_msg = %PhoenixAI.Message{role: :assistant, content: r1.content}
history = history ++ [
  %PhoenixAI.Message{role: :user, content: "My name is Alice."},
  assistant_msg
]

{:ok, r2} = PhoenixAI.Agent.prompt(pid, "What is my name?", messages: history)
```

### Other Agent Operations

```elixir
# Get all accumulated messages
messages = PhoenixAI.Agent.get_messages(pid)

# Reset conversation history (keeps configuration)
:ok = PhoenixAI.Agent.reset(pid)

# If a prompt is in-flight
{:error, :agent_busy} = PhoenixAI.Agent.reset(pid)
```

### Supervision under DynamicSupervisor

For production use, supervise agents dynamically:

```elixir
# In your application.ex
children = [
  {DynamicSupervisor, name: MyApp.AgentSupervisor, strategy: :one_for_one}
]

# Starting a supervised agent
{:ok, pid} = DynamicSupervisor.start_child(
  MyApp.AgentSupervisor,
  {PhoenixAI.Agent, [
    provider: :openai,
    model: "gpt-4o",
    system: "You are a support agent.",
    name: {:global, "agent:#{user_id}"}
  ]}
)
```

Named registration lets you look up agents by name:

```elixir
# Register with a name
{:ok, _pid} = PhoenixAI.Agent.start_link(
  provider: :openai,
  name: {:via, Registry, {MyApp.AgentRegistry, session_id}}
)

# Look up and use
agent = {:via, Registry, {MyApp.AgentRegistry, session_id}}
PhoenixAI.Agent.prompt(agent, "Hello")
```

### Structured Output

Use `:schema` to get validated structured responses:

```elixir
{:ok, pid} = PhoenixAI.Agent.start_link(
  provider: :openai,
  schema: %{
    name: :string,
    age: :integer,
    email: :string
  }
)

{:ok, response} = PhoenixAI.Agent.prompt(pid, "Extract user info from: Alice, 30, alice@example.com")
response.parsed
# => %{name: "Alice", age: 30, email: "alice@example.com"}
```
