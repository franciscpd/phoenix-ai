# Streaming Transport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add SSE streaming via Finch for all three provider adapters, with a central `PhoenixAI.Stream` module, stateful SSE buffer management, and a public `AI.stream/2` API that delivers chunks via callback or PID.

**Architecture:** Central `PhoenixAI.Stream.run/4` orchestrates Finch → SSE parsing → per-provider `parse_chunk/1` → callback dispatch → Response accumulation. `AI.stream/2` resolves delivery mechanism (:on_chunk callback, :to PID, or default self()) and delegates. Each adapter only implements `parse_chunk/1` and `build_stream_body`.

**Tech Stack:** Elixir, Finch (direct SSE), server_sent_events (SSE parser), Jason (JSON decode), Mox (testing), existing PhoenixAI provider architecture.

**Spec:** `.planning/phases/06-streaming-transport/BRAINSTORM.md`

---

### Task 1: Add `server_sent_events` dependency

**Files:**
- Modify: `mix.exs`

- [ ] **Step 1: Add the dependency**

In `mix.exs`, add `server_sent_events` to the deps list:

```elixir
defp deps do
  [
    {:req, "~> 0.5"},
    {:jason, "~> 1.4"},
    {:nimble_options, "~> 1.1"},
    {:telemetry, "~> 1.3"},
    {:finch, "~> 0.19"},
    {:server_sent_events, "~> 1.0"},
    {:mox, "~> 1.2", only: :test},
    {:excoveralls, "~> 0.18", only: :test},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    {:ex_doc, "~> 0.34", only: :dev, runtime: false}
  ]
end
```

- [ ] **Step 2: Fetch dependencies**

Run: `mix deps.get`
Expected: `server_sent_events` resolves and downloads.

- [ ] **Step 3: Verify it compiles**

Run: `mix compile`
Expected: Clean compile, no warnings from the new dependency.

- [ ] **Step 4: Commit**

```bash
git add mix.exs mix.lock
git commit -m "feat(06): add server_sent_events dependency for SSE parsing"
```

---

### Task 2: OpenAI `parse_chunk/1` and `build_stream_body/3`

**Files:**
- Modify: `lib/phoenix_ai/providers/openai.ex`
- Create: `test/phoenix_ai/providers/openai_stream_test.exs`

- [ ] **Step 1: Write the failing tests**

Create `test/phoenix_ai/providers/openai_stream_test.exs`:

```elixir
defmodule PhoenixAI.Providers.OpenAIStreamTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Providers.OpenAI
  alias PhoenixAI.StreamChunk

  describe "parse_chunk/1" do
    test "extracts delta content from SSE data" do
      chunk = OpenAI.parse_chunk(%{
        event: nil,
        data: ~s({"choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]})
      })

      assert %StreamChunk{delta: "Hello", finish_reason: nil} = chunk
    end

    test "handles [DONE] sentinel" do
      chunk = OpenAI.parse_chunk(%{event: nil, data: "[DONE]"})
      assert %StreamChunk{finish_reason: "stop"} = chunk
    end

    test "extracts finish_reason from final chunk" do
      chunk = OpenAI.parse_chunk(%{
        event: nil,
        data: ~s({"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]})
      })

      assert %StreamChunk{delta: nil, finish_reason: "stop"} = chunk
    end

    test "handles chunk with nil content delta" do
      chunk = OpenAI.parse_chunk(%{
        event: nil,
        data: ~s({"choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]})
      })

      assert %StreamChunk{delta: nil, finish_reason: nil} = chunk
    end

    test "extracts usage from final chunk with usage field" do
      chunk = OpenAI.parse_chunk(%{
        event: nil,
        data: ~s({"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}})
      })

      assert %StreamChunk{usage: %{"prompt_tokens" => 10, "completion_tokens" => 5}} = chunk
    end
  end

  describe "build_stream_body/3" do
    test "adds stream: true and stream_options to body" do
      body = OpenAI.build_stream_body("gpt-4o", [%{"role" => "user", "content" => "Hi"}], [])

      assert body["stream"] == true
      assert body["stream_options"] == %{"include_usage" => true}
      assert body["model"] == "gpt-4o"
      assert body["messages"] == [%{"role" => "user", "content" => "Hi"}]
    end

    test "preserves tools and temperature from opts" do
      opts = [tools_json: [%{"type" => "function"}], temperature: 0.5]
      body = OpenAI.build_stream_body("gpt-4o", [], opts)

      assert body["stream"] == true
      assert body["tools"] == [%{"type" => "function"}]
      assert body["temperature"] == 0.5
    end
  end

  describe "stream_url/1" do
    test "returns chat completions URL with default base" do
      assert OpenAI.stream_url([]) == "https://api.openai.com/v1/chat/completions"
    end

    test "uses custom base_url from opts" do
      assert OpenAI.stream_url(base_url: "https://custom.api.com") ==
               "https://custom.api.com/chat/completions"
    end
  end

  describe "stream_headers/1" do
    test "returns authorization and content-type headers" do
      headers = OpenAI.stream_headers(api_key: "sk-test")

      assert {"authorization", "Bearer sk-test"} in headers
      assert {"content-type", "application/json"} in headers
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/providers/openai_stream_test.exs --trace`
Expected: FAIL — `parse_chunk/1`, `build_stream_body/3`, `stream_url/1`, `stream_headers/1` not defined.

- [ ] **Step 3: Implement parse_chunk/1, build_stream_body/3, stream_url/1, stream_headers/1**

In `lib/phoenix_ai/providers/openai.ex`, add the alias for StreamChunk and these public functions after the existing `build_body/3`:

Update the alias line at the top:

```elixir
alias PhoenixAI.{Error, Message, Response, StreamChunk, ToolCall}
```

Add after `build_body/3`:

```elixir
  @doc false
  @spec build_stream_body(String.t(), [map()], keyword()) :: map()
  def build_stream_body(model, formatted_messages, opts) do
    build_body(model, formatted_messages, opts)
    |> Map.put("stream", true)
    |> Map.put("stream_options", %{"include_usage" => true})
  end

  @doc false
  @spec stream_url(keyword()) :: String.t()
  def stream_url(opts) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    "#{base_url}/chat/completions"
  end

  @doc false
  @spec stream_headers(keyword()) :: [{String.t(), String.t()}]
  def stream_headers(opts) do
    api_key = Keyword.fetch!(opts, :api_key)

    [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]
  end

  @impl PhoenixAI.Provider
  def parse_chunk(%{data: "[DONE]"}), do: %StreamChunk{finish_reason: "stop"}

  def parse_chunk(%{data: data}) do
    json = Jason.decode!(data)
    choice = json |> Map.get("choices", []) |> List.first(%{})
    delta = Map.get(choice, "delta", %{})
    usage = Map.get(json, "usage")

    %StreamChunk{
      delta: Map.get(delta, "content"),
      finish_reason: Map.get(choice, "finish_reason"),
      usage: usage
    }
  end
```

Also update `%StreamChunk{}` in `lib/phoenix_ai/stream_chunk.ex` to add the `usage` field:

```elixir
defmodule PhoenixAI.StreamChunk do
  @moduledoc "A single chunk emitted during a streaming AI response."

  @type t :: %__MODULE__{
          delta: String.t() | nil,
          tool_call_delta: map() | nil,
          finish_reason: String.t() | nil,
          usage: map() | nil
        }

  defstruct [:delta, :tool_call_delta, :finish_reason, :usage]
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/providers/openai_stream_test.exs --trace`
Expected: All tests PASS.

- [ ] **Step 5: Run full test suite for regressions**

Run: `mix test`
Expected: All existing tests pass (the new `usage: nil` default on StreamChunk is backward compatible).

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/stream_chunk.ex lib/phoenix_ai/providers/openai.ex test/phoenix_ai/providers/openai_stream_test.exs
git commit -m "feat(06): add parse_chunk and stream helpers to OpenAI adapter"
```

---

### Task 3: Anthropic `parse_chunk/1` and `build_stream_body/4`

**Files:**
- Modify: `lib/phoenix_ai/providers/anthropic.ex`
- Create: `test/phoenix_ai/providers/anthropic_stream_test.exs`

- [ ] **Step 1: Write the failing tests**

Create `test/phoenix_ai/providers/anthropic_stream_test.exs`:

```elixir
defmodule PhoenixAI.Providers.AnthropicStreamTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Providers.Anthropic
  alias PhoenixAI.StreamChunk

  describe "parse_chunk/1" do
    test "extracts text delta from content_block_delta event" do
      chunk = Anthropic.parse_chunk(%{
        event: "content_block_delta",
        data: ~s({"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}})
      })

      assert %StreamChunk{delta: "Hello", finish_reason: nil} = chunk
    end

    test "extracts finish_reason from message_delta event" do
      chunk = Anthropic.parse_chunk(%{
        event: "message_delta",
        data: ~s({"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":15}})
      })

      assert %StreamChunk{finish_reason: "end_turn", delta: nil} = chunk
    end

    test "extracts usage from message_delta event" do
      chunk = Anthropic.parse_chunk(%{
        event: "message_delta",
        data: ~s({"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":15}})
      })

      assert %StreamChunk{usage: %{"output_tokens" => 15}} = chunk
    end

    test "handles message_stop as finish signal" do
      chunk = Anthropic.parse_chunk(%{event: "message_stop", data: ""})
      assert %StreamChunk{finish_reason: "stop"} = chunk
    end

    test "returns nil for ping event" do
      assert Anthropic.parse_chunk(%{event: "ping", data: ""}) == nil
    end

    test "returns nil for message_start event" do
      data = ~s({"type":"message_start","message":{"id":"msg_1","model":"claude-sonnet-4-5","usage":{"input_tokens":10}}})
      assert Anthropic.parse_chunk(%{event: "message_start", data: data}) == nil
    end

    test "returns nil for content_block_start event" do
      data = ~s({"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}})
      assert Anthropic.parse_chunk(%{event: "content_block_start", data: data}) == nil
    end

    test "returns nil for content_block_stop event" do
      assert Anthropic.parse_chunk(%{event: "content_block_stop", data: ~s({"type":"content_block_stop","index":0})}) == nil
    end
  end

  describe "build_stream_body/4" do
    test "adds stream: true to body" do
      body = Anthropic.build_stream_body(
        "claude-sonnet-4-5",
        [%{"role" => "user", "content" => "Hi"}],
        4096,
        []
      )

      assert body["stream"] == true
      assert body["model"] == "claude-sonnet-4-5"
      assert body["max_tokens"] == 4096
    end

    test "preserves existing body fields" do
      body = Anthropic.build_stream_body(
        "claude-sonnet-4-5",
        [%{"role" => "user", "content" => "Hi"}],
        8192,
        [temperature: 0.7]
      )

      assert body["stream"] == true
      assert body["temperature"] == 0.7
      assert body["max_tokens"] == 8192
    end
  end

  describe "stream_url/1" do
    test "returns messages URL with default base" do
      assert Anthropic.stream_url([]) == "https://api.anthropic.com/v1/messages"
    end

    test "uses custom base_url from opts" do
      assert Anthropic.stream_url(base_url: "https://custom.api.com") ==
               "https://custom.api.com/messages"
    end
  end

  describe "stream_headers/1" do
    test "returns x-api-key, anthropic-version, and content-type headers" do
      headers = Anthropic.stream_headers(api_key: "sk-ant-test")

      assert {"x-api-key", "sk-ant-test"} in headers
      assert {"anthropic-version", "2023-06-01"} in headers
      assert {"content-type", "application/json"} in headers
    end

    test "uses custom anthropic-version from provider_options" do
      headers = Anthropic.stream_headers(
        api_key: "sk-ant-test",
        provider_options: %{"anthropic-version" => "2024-01-01"}
      )

      assert {"anthropic-version", "2024-01-01"} in headers
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/providers/anthropic_stream_test.exs --trace`
Expected: FAIL — functions not defined.

- [ ] **Step 3: Implement parse_chunk/1, build_stream_body/4, stream_url/1, stream_headers/1**

In `lib/phoenix_ai/providers/anthropic.ex`, update the alias and add functions.

Update alias:

```elixir
alias PhoenixAI.{Error, Message, Response, StreamChunk, ToolCall}
```

Add after `build_body/4`:

```elixir
  @doc false
  @spec build_stream_body(String.t(), [map()], non_neg_integer(), keyword()) :: map()
  def build_stream_body(model, formatted_messages, max_tokens, opts) do
    build_body(model, formatted_messages, max_tokens, opts)
    |> Map.put("stream", true)
  end

  @doc false
  @spec stream_url(keyword()) :: String.t()
  def stream_url(opts) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    "#{base_url}/messages"
  end

  @doc false
  @spec stream_headers(keyword()) :: [{String.t(), String.t()}]
  def stream_headers(opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    provider_options = Keyword.get(opts, :provider_options, %{})
    api_version = Map.get(provider_options, "anthropic-version", @default_api_version)

    [
      {"x-api-key", api_key},
      {"anthropic-version", api_version},
      {"content-type", "application/json"}
    ]
  end

  @impl PhoenixAI.Provider
  def parse_chunk(%{event: "content_block_delta", data: data}) do
    json = Jason.decode!(data)
    %StreamChunk{delta: get_in(json, ["delta", "text"])}
  end

  def parse_chunk(%{event: "message_delta", data: data}) do
    json = Jason.decode!(data)
    %StreamChunk{
      finish_reason: get_in(json, ["delta", "stop_reason"]),
      usage: Map.get(json, "usage")
    }
  end

  def parse_chunk(%{event: "message_stop", data: _}), do: %StreamChunk{finish_reason: "stop"}
  def parse_chunk(_), do: nil
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/providers/anthropic_stream_test.exs --trace`
Expected: All tests PASS.

- [ ] **Step 5: Run full test suite for regressions**

Run: `mix test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/providers/anthropic.ex test/phoenix_ai/providers/anthropic_stream_test.exs
git commit -m "feat(06): add parse_chunk and stream helpers to Anthropic adapter"
```

---

### Task 4: OpenRouter `parse_chunk/1` and `build_stream_body/3` (delegates to OpenAI)

**Files:**
- Modify: `lib/phoenix_ai/providers/openrouter.ex`
- Create: `test/phoenix_ai/providers/openrouter_stream_test.exs`

- [ ] **Step 1: Write the failing tests**

Create `test/phoenix_ai/providers/openrouter_stream_test.exs`:

```elixir
defmodule PhoenixAI.Providers.OpenRouterStreamTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Providers.OpenRouter
  alias PhoenixAI.StreamChunk

  describe "parse_chunk/1 delegates to OpenAI" do
    test "extracts delta content" do
      chunk = OpenRouter.parse_chunk(%{
        event: nil,
        data: ~s({"choices":[{"index":0,"delta":{"content":"Hi"},"finish_reason":null}]})
      })

      assert %StreamChunk{delta: "Hi", finish_reason: nil} = chunk
    end

    test "handles [DONE] sentinel" do
      chunk = OpenRouter.parse_chunk(%{event: nil, data: "[DONE]"})
      assert %StreamChunk{finish_reason: "stop"} = chunk
    end
  end

  describe "build_stream_body/3" do
    test "adds stream: true and stream_options" do
      body = OpenRouter.build_stream_body("mistralai/mistral-7b", [%{"role" => "user", "content" => "Hi"}], [])

      assert body["stream"] == true
      assert body["stream_options"] == %{"include_usage" => true}
      assert body["model"] == "mistralai/mistral-7b"
    end
  end

  describe "stream_url/1" do
    test "returns chat completions URL with default base" do
      assert OpenRouter.stream_url([]) == "https://openrouter.ai/api/v1/chat/completions"
    end
  end

  describe "stream_headers/1" do
    test "returns authorization and content-type headers" do
      headers = OpenRouter.stream_headers(api_key: "sk-or-test")

      assert {"authorization", "Bearer sk-or-test"} in headers
      assert {"content-type", "application/json"} in headers
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/providers/openrouter_stream_test.exs --trace`
Expected: FAIL — functions not defined.

- [ ] **Step 3: Implement by delegating to OpenAI**

In `lib/phoenix_ai/providers/openrouter.ex`, add after `build_body/3`:

```elixir
  @doc false
  @spec build_stream_body(String.t(), [map()], keyword()) :: map()
  def build_stream_body(model, formatted_messages, opts) do
    build_body(model, formatted_messages, opts)
    |> Map.put("stream", true)
    |> Map.put("stream_options", %{"include_usage" => true})
  end

  @doc false
  @spec stream_url(keyword()) :: String.t()
  def stream_url(opts) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    "#{base_url}/chat/completions"
  end

  @doc false
  @spec stream_headers(keyword()) :: [{String.t(), String.t()}]
  def stream_headers(opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    provider_options = Keyword.get(opts, :provider_options, %{})

    [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]
    |> maybe_add_header("HTTP-Referer", Map.get(provider_options, "http_referer"))
    |> maybe_add_header("X-Title", Map.get(provider_options, "x_title"))
  end

  @impl PhoenixAI.Provider
  def parse_chunk(event_data), do: PhoenixAI.Providers.OpenAI.parse_chunk(event_data)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/providers/openrouter_stream_test.exs --trace`
Expected: All tests PASS.

- [ ] **Step 5: Run full test suite for regressions**

Run: `mix test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/providers/openrouter.ex test/phoenix_ai/providers/openrouter_stream_test.exs
git commit -m "feat(06): add parse_chunk and stream helpers to OpenRouter adapter"
```

---

### Task 5: `PhoenixAI.Stream` central module

**Files:**
- Create: `lib/phoenix_ai/stream.ex`
- Create: `test/phoenix_ai/stream_test.exs`

- [ ] **Step 1: Write the failing tests**

Create `test/phoenix_ai/stream_test.exs`:

```elixir
defmodule PhoenixAI.StreamTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.{Response, Stream, StreamChunk}

  # A fake provider module for testing
  defmodule FakeOpenAIProvider do
    def parse_chunk(%{data: "[DONE]"}), do: %StreamChunk{finish_reason: "stop"}

    def parse_chunk(%{data: data}) do
      json = Jason.decode!(data)
      choice = json |> Map.get("choices", []) |> List.first(%{})
      delta = Map.get(choice, "delta", %{})

      %StreamChunk{
        delta: Map.get(delta, "content"),
        finish_reason: Map.get(choice, "finish_reason"),
        usage: Map.get(json, "usage")
      }
    end

    def format_messages(messages), do: Enum.map(messages, &%{"role" => to_string(&1.role), "content" => &1.content})
    def build_stream_body(_model, msgs, _opts), do: %{"model" => "gpt-4o", "messages" => msgs, "stream" => true}
    def stream_url(_opts), do: "https://api.openai.com/v1/chat/completions"
    def stream_headers(_opts), do: [{"authorization", "Bearer test"}, {"content-type", "application/json"}]
  end

  describe "process_sse_events/3" do
    test "processes SSE events into chunks and accumulates content" do
      sse_data = """
      event: message
      data: {"choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}

      event: message
      data: {"choices":[{"index":0,"delta":{"content":" world"},"finish_reason":null}]}

      event: message
      data: [DONE]

      """

      chunks = []
      callback = fn chunk -> send(self(), {:chunk, chunk}) end

      acc = %{
        remainder: "",
        provider_mod: FakeOpenAIProvider,
        callback: callback,
        content: "",
        usage: nil,
        finished: false
      }

      result = Stream.process_sse_events(sse_data, acc)

      assert result.content == "Hello world"
      assert result.finished == true

      assert_received {:chunk, %StreamChunk{delta: "Hello"}}
      assert_received {:chunk, %StreamChunk{delta: " world"}}
    end

    test "handles fragmented SSE data across multiple calls" do
      # First fragment: incomplete event
      fragment1 = "event: message\ndata: {\"choices\":[{\"index\":0,\"delta\":{\"conten"

      callback = fn chunk -> send(self(), {:chunk, chunk}) end
      acc = %{
        remainder: "",
        provider_mod: FakeOpenAIProvider,
        callback: callback,
        content: "",
        usage: nil,
        finished: false
      }

      result1 = Stream.process_sse_events(fragment1, acc)
      # No complete events yet
      assert result1.content == ""
      refute_received {:chunk, _}

      # Second fragment: completes the event
      fragment2 = "t\":\"Hi\"},\"finish_reason\":null}]}\n\nevent: message\ndata: [DONE]\n\n"

      result2 = Stream.process_sse_events(fragment2, %{result1 | remainder: result1.remainder})

      assert result2.content == "Hi"
      assert result2.finished == true
      assert_received {:chunk, %StreamChunk{delta: "Hi"}}
    end

    test "ignores nil chunks from provider" do
      # Anthropic-style: ping event returns nil from parse_chunk
      defmodule NilChunkProvider do
        def parse_chunk(_), do: nil
      end

      sse_data = "event: ping\ndata: \n\n"

      callback = fn chunk -> send(self(), {:chunk, chunk}) end
      acc = %{
        remainder: "",
        provider_mod: NilChunkProvider,
        callback: callback,
        content: "",
        usage: nil,
        finished: false
      }

      result = Stream.process_sse_events(sse_data, acc)
      assert result.content == ""
      refute_received {:chunk, _}
    end

    test "captures usage from chunk with usage field" do
      sse_data = """
      event: message
      data: {"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}

      event: message
      data: [DONE]

      """

      callback = fn _chunk -> :ok end
      acc = %{
        remainder: "",
        provider_mod: FakeOpenAIProvider,
        callback: callback,
        content: "",
        usage: nil,
        finished: false
      }

      result = Stream.process_sse_events(sse_data, acc)
      assert result.usage == %{"prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15}
    end
  end

  describe "build_response/1" do
    test "builds Response struct from accumulated state" do
      acc = %{content: "Hello world", usage: %{"total_tokens" => 10}, finished: true}

      response = Stream.build_response(acc)

      assert %Response{content: "Hello world", usage: %{"total_tokens" => 10}} = response
    end

    test "handles nil usage" do
      acc = %{content: "test", usage: nil, finished: true}

      response = Stream.build_response(acc)

      assert %Response{content: "test", usage: %{}} = response
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/stream_test.exs --trace`
Expected: FAIL — `PhoenixAI.Stream` module not found.

- [ ] **Step 3: Implement PhoenixAI.Stream**

Create `lib/phoenix_ai/stream.ex`:

```elixir
defmodule PhoenixAI.Stream do
  @moduledoc """
  Central streaming transport — Finch SSE + per-provider chunk dispatch.

  Orchestrates: Finch connection → SSE parsing → provider parse_chunk/1 →
  callback dispatch → Response accumulation.
  """

  alias PhoenixAI.{Error, Response, StreamChunk}

  @type callback :: (StreamChunk.t() -> any())

  @doc """
  Opens a streaming connection to the provider, dispatches chunks via callback,
  and returns an accumulated Response when the stream completes.
  """
  @spec run(module(), [PhoenixAI.Message.t()], callback(), keyword()) ::
          {:ok, Response.t()} | {:error, term()}
  def run(provider_mod, messages, callback, opts) do
    formatted = provider_mod.format_messages(messages)

    body =
      if function_exported?(provider_mod, :build_stream_body, 4) do
        max_tokens = Keyword.get(opts, :max_tokens, 4096)
        provider_mod.build_stream_body(Keyword.get(opts, :model), formatted, max_tokens, opts)
      else
        provider_mod.build_stream_body(Keyword.get(opts, :model), formatted, opts)
      end

    url = provider_mod.stream_url(opts)
    headers = provider_mod.stream_headers(opts)
    json_body = Jason.encode!(body)

    request = Finch.build(:post, url, headers, json_body)
    finch_name = Keyword.get(opts, :finch_name, PhoenixAI.Finch)

    acc = %{
      remainder: "",
      provider_mod: provider_mod,
      callback: callback,
      content: "",
      usage: nil,
      finished: false,
      status: nil
    }

    case Finch.stream(request, finch_name, acc, &handle_stream_event/2) do
      {:ok, final_acc} ->
        {:ok, build_response(final_acc)}

      {:error, exception} ->
        {:error, %Error{status: nil, message: Exception.message(exception), provider: nil}}
    end
  end

  defp handle_stream_event({:status, status}, acc) do
    %{acc | status: status}
  end

  defp handle_stream_event({:headers, _headers}, acc), do: acc

  defp handle_stream_event({:data, data}, %{status: status} = acc) when status != 200 do
    %{acc | remainder: acc.remainder <> data}
  end

  defp handle_stream_event({:data, data}, acc) do
    process_sse_events(data, acc)
  end

  @doc false
  def process_sse_events(data, acc) do
    raw = acc.remainder <> data
    {events, remainder} = ServerSentEvents.parse(raw)

    acc = %{acc | remainder: remainder}

    Enum.reduce(events, acc, fn event, acc ->
      event_type = Map.get(event, :event)
      event_data = Map.get(event, :data, "")

      case acc.provider_mod.parse_chunk(%{event: event_type, data: event_data}) do
        nil ->
          acc

        %StreamChunk{} = chunk ->
          # Deliver chunk if it has content
          if chunk.delta, do: acc.callback.(chunk)

          # Accumulate content
          new_content =
            if chunk.delta,
              do: acc.content <> chunk.delta,
              else: acc.content

          # Capture usage if present
          new_usage = chunk.usage || acc.usage

          # Detect finish
          new_finished = acc.finished or (chunk.finish_reason != nil)

          %{acc | content: new_content, usage: new_usage, finished: new_finished}
      end
    end)
  end

  @doc false
  def build_response(acc) do
    %Response{
      content: acc.content,
      usage: acc.usage || %{},
      finish_reason: "stop",
      provider_response: %{}
    }
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/stream_test.exs --trace`
Expected: All tests PASS.

- [ ] **Step 5: Run full test suite for regressions**

Run: `mix test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/stream.ex test/phoenix_ai/stream_test.exs
git commit -m "feat(06): add PhoenixAI.Stream central streaming module"
```

---

### Task 6: `AI.stream/2` public API

**Files:**
- Modify: `lib/ai.ex`
- Create: `test/phoenix_ai/ai_stream_test.exs`

- [ ] **Step 1: Write the failing tests**

Create `test/phoenix_ai/ai_stream_test.exs`:

```elixir
defmodule AIStreamTest do
  use ExUnit.Case

  alias PhoenixAI.{Message, MockProvider, Response, StreamChunk}

  import Mox

  setup :verify_on_exit!

  describe "stream/2" do
    test "returns error when api_key is missing" do
      assert {:error, {:missing_api_key, :openai}} =
               AI.stream(
                 [%Message{role: :user, content: "Hi"}],
                 provider: :openai
               )
    end

    test "returns error for unknown provider" do
      assert {:error, {:unknown_provider, :fake}} =
               AI.stream(
                 [%Message{role: :user, content: "Hi"}],
                 provider: :fake
               )
    end

    test "build_callback uses on_chunk when provided" do
      callback = fn _chunk -> :ok end
      result = AI.build_callback(on_chunk: callback)
      assert result == callback
    end

    test "build_callback sends to PID when :to provided" do
      callback = AI.build_callback(to: self())
      chunk = %StreamChunk{delta: "test"}
      callback.(chunk)
      assert_received {:phoenix_ai, {:chunk, ^chunk}}
    end

    test "build_callback defaults to self()" do
      callback = AI.build_callback([])
      chunk = %StreamChunk{delta: "test"}
      callback.(chunk)
      assert_received {:phoenix_ai, {:chunk, ^chunk}}
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/ai_stream_test.exs --trace`
Expected: FAIL — `AI.stream/2` and `AI.build_callback/1` not defined.

- [ ] **Step 3: Implement AI.stream/2 and build_callback/1**

In `lib/ai.ex`, add after the `chat/2` function:

```elixir
  @spec stream([PhoenixAI.Message.t()], keyword()) ::
          {:ok, PhoenixAI.Response.t()} | {:error, term()}
  def stream(messages, opts \\ []) do
    provider_atom = opts[:provider] || default_provider()

    case resolve_provider(provider_atom) do
      {:ok, provider_mod} ->
        merged_opts = Config.resolve(provider_atom, Keyword.delete(opts, :provider))
        dispatch_stream(provider_mod, messages, merged_opts, provider_atom)

      {:error, _} = error ->
        error
    end
  end

  defp dispatch_stream(provider_mod, messages, opts, provider_atom) do
    case Keyword.get(opts, :api_key) do
      nil ->
        {:error, {:missing_api_key, provider_atom}}

      _key ->
        callback = build_callback(opts)
        stream_opts = Keyword.drop(opts, [:on_chunk, :to, :schema])
        PhoenixAI.Stream.run(provider_mod, messages, callback, stream_opts)
    end
  end

  @doc false
  def build_callback(opts) do
    cond do
      fun = Keyword.get(opts, :on_chunk) -> fun
      pid = Keyword.get(opts, :to) -> fn chunk -> send(pid, {:phoenix_ai, {:chunk, chunk}}) end
      true -> fn chunk -> send(self(), {:phoenix_ai, {:chunk, chunk}}) end
    end
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/ai_stream_test.exs --trace`
Expected: All tests PASS.

- [ ] **Step 5: Run full test suite for regressions**

Run: `mix test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/ai.ex test/phoenix_ai/ai_stream_test.exs
git commit -m "feat(06): add AI.stream/2 public API with callback/PID delivery"
```

---

### Task 7: SSE fragmentation fixtures and integration tests

**Files:**
- Create: `test/fixtures/sse/openai_simple.sse`
- Create: `test/fixtures/sse/openai_fragmented.sse`
- Create: `test/fixtures/sse/anthropic_simple.sse`
- Modify: `test/phoenix_ai/stream_test.exs`

- [ ] **Step 1: Create SSE fixture files**

Create `test/fixtures/sse/openai_simple.sse`:

```
event: message
data: {"choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}

event: message
data: {"choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}

event: message
data: {"choices":[{"index":0,"delta":{"content":" world"},"finish_reason":null}]}

event: message
data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":8,"completion_tokens":2,"total_tokens":10}}

event: message
data: [DONE]

```

Create `test/fixtures/sse/anthropic_simple.sse`:

```
event: message_start
data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":10,"output_tokens":1}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" world"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":2}}

event: message_stop
data: {}

```

Create `test/fixtures/sse/openai_fragmented.sse` — this is the full stream, but tests will split it at arbitrary byte positions to simulate TCP fragmentation:

```
event: message
data: {"choices":[{"index":0,"delta":{"content":"Frag"},"finish_reason":null}]}

event: message
data: {"choices":[{"index":0,"delta":{"content":"mented"},"finish_reason":null}]}

event: message
data: [DONE]

```

- [ ] **Step 2: Add fixture-based tests to stream_test.exs**

Add to `test/phoenix_ai/stream_test.exs`:

```elixir
  describe "SSE fixture integration" do
    test "parses complete OpenAI SSE fixture" do
      raw = File.read!("test/fixtures/sse/openai_simple.sse")

      callback = fn chunk -> send(self(), {:chunk, chunk}) end
      acc = %{
        remainder: "",
        provider_mod: FakeOpenAIProvider,
        callback: callback,
        content: "",
        usage: nil,
        finished: false
      }

      result = Stream.process_sse_events(raw, acc)

      assert result.content == "Hello world"
      assert result.finished == true
      assert_received {:chunk, %StreamChunk{delta: "Hello"}}
      assert_received {:chunk, %StreamChunk{delta: " world"}}
    end

    test "handles OpenAI SSE fragmented at arbitrary byte positions" do
      raw = File.read!("test/fixtures/sse/openai_fragmented.sse")

      callback = fn chunk -> send(self(), {:chunk, chunk}) end

      # Split at multiple positions to test fragment reassembly
      for split_pos <- [10, 30, 50, div(byte_size(raw), 2)] do
        {frag1, frag2} = String.split_at(raw, split_pos)

        acc = %{
          remainder: "",
          provider_mod: FakeOpenAIProvider,
          callback: callback,
          content: "",
          usage: nil,
          finished: false
        }

        acc = Stream.process_sse_events(frag1, acc)
        result = Stream.process_sse_events(frag2, %{acc | remainder: acc.remainder})

        assert result.content == "Fragmented",
               "Failed at split_pos=#{split_pos}: got #{inspect(result.content)}"

        assert result.finished == true
      end
    end

    test "parses complete Anthropic SSE fixture" do
      raw = File.read!("test/fixtures/sse/anthropic_simple.sse")

      defmodule FakeAnthropicProvider do
        alias PhoenixAI.StreamChunk

        def parse_chunk(%{event: "content_block_delta", data: data}) do
          json = Jason.decode!(data)
          %StreamChunk{delta: get_in(json, ["delta", "text"])}
        end

        def parse_chunk(%{event: "message_delta", data: data}) do
          json = Jason.decode!(data)
          %StreamChunk{
            finish_reason: get_in(json, ["delta", "stop_reason"]),
            usage: Map.get(json, "usage")
          }
        end

        def parse_chunk(%{event: "message_stop", data: _}), do: %StreamChunk{finish_reason: "stop"}
        def parse_chunk(_), do: nil
      end

      callback = fn chunk -> send(self(), {:chunk, chunk}) end
      acc = %{
        remainder: "",
        provider_mod: FakeAnthropicProvider,
        callback: callback,
        content: "",
        usage: nil,
        finished: false
      }

      result = Stream.process_sse_events(raw, acc)

      assert result.content == "Hello world"
      assert result.finished == true
      assert result.usage == %{"output_tokens" => 2}
      assert_received {:chunk, %StreamChunk{delta: "Hello"}}
      assert_received {:chunk, %StreamChunk{delta: " world"}}
    end
  end
```

- [ ] **Step 3: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/stream_test.exs --trace`
Expected: All tests PASS (fixtures exist and parse correctly).

- [ ] **Step 4: Run full test suite**

Run: `mix test`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add test/fixtures/sse/ test/phoenix_ai/stream_test.exs
git commit -m "test(06): add SSE fixtures and fragmentation integration tests"
```

---

### Task 8: Error handling and final polish

**Files:**
- Modify: `test/phoenix_ai/stream_test.exs`
- Modify: `lib/phoenix_ai/stream.ex`

- [ ] **Step 1: Write error handling tests**

Add to `test/phoenix_ai/stream_test.exs`:

```elixir
  describe "error handling" do
    test "process_sse_events handles JSON decode errors gracefully" do
      # Malformed JSON should not crash — chunk is skipped
      sse_data = "event: message\ndata: {invalid json}\n\n"

      callback = fn _chunk -> :ok end
      acc = %{
        remainder: "",
        provider_mod: FakeOpenAIProvider,
        callback: callback,
        content: "",
        usage: nil,
        finished: false
      }

      # Should not raise — malformed chunks are skipped
      result = Stream.process_sse_events(sse_data, acc)
      assert result.content == ""
    end

    test "non-200 status accumulates error body" do
      acc = %{
        remainder: "",
        provider_mod: FakeOpenAIProvider,
        callback: fn _ -> :ok end,
        content: "",
        usage: nil,
        finished: false,
        status: 429
      }

      result = Stream.handle_stream_event_public({:data, "rate limited"}, acc)
      assert result.remainder == "rate limited"
      assert result.content == ""
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/stream_test.exs --trace`
Expected: FAIL — JSON decode error crashes, `handle_stream_event_public` not defined.

- [ ] **Step 3: Add JSON error resilience and test helper**

In `lib/phoenix_ai/stream.ex`, wrap the parse_chunk call to rescue JSON errors:

Update `process_sse_events` — replace the `case` block inside `Enum.reduce`:

```elixir
    Enum.reduce(events, acc, fn event, acc ->
      event_type = Map.get(event, :event)
      event_data = Map.get(event, :data, "")

      chunk =
        try do
          acc.provider_mod.parse_chunk(%{event: event_type, data: event_data})
        rescue
          _ -> nil
        end

      case chunk do
        nil ->
          acc

        %StreamChunk{} = chunk ->
          if chunk.delta, do: acc.callback.(chunk)

          new_content =
            if chunk.delta,
              do: acc.content <> chunk.delta,
              else: acc.content

          new_usage = chunk.usage || acc.usage
          new_finished = acc.finished or (chunk.finish_reason != nil)

          %{acc | content: new_content, usage: new_usage, finished: new_finished}
      end
    end)
```

Add a test helper function at the bottom of the module:

```elixir
  @doc false
  def handle_stream_event_public(event, acc), do: handle_stream_event(event, acc)
```

Also in `run/4`, handle non-200 status after streaming completes. Update the success path:

```elixir
    case Finch.stream(request, finch_name, acc, &handle_stream_event/2) do
      {:ok, %{status: status} = final_acc} when status != 200 ->
        {:error, %Error{status: status, message: final_acc.remainder, provider: nil}}

      {:ok, final_acc} ->
        {:ok, build_response(final_acc)}

      {:error, exception} ->
        {:error, %Error{status: nil, message: Exception.message(exception), provider: nil}}
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/stream_test.exs --trace`
Expected: All tests PASS.

- [ ] **Step 5: Run full test suite and Credo**

Run: `mix test && mix credo --strict`
Expected: All tests pass, no Credo issues.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/stream.ex test/phoenix_ai/stream_test.exs
git commit -m "fix(06): add JSON error resilience and non-200 status handling in Stream"
```

---

## Self-Review Checklist

**Spec coverage:**
- ✅ STREAM-01: SSE streaming uses Finch directly → Task 5 (`Finch.build` + `Finch.stream`)
- ✅ STREAM-02: SSE parser with stateful buffer + `\n\n` detection → Task 5 (`ServerSentEvents.parse`)
- ✅ STREAM-03: Each provider adapter implements `parse_chunk/1` → Tasks 2, 3, 4
- ✅ STREAM-04: One Task per streaming session → Task 5 (synchronous `run/4`, caller owns concurrency)
- ✅ `server_sent_events` dependency → Task 1
- ✅ `AI.stream/2` with `:on_chunk` / `:to` / default self() → Task 6
- ✅ `{:ok, %Response{}}` with accumulated content → Task 5 (`build_response`)
- ✅ SSE fragmentation fixtures → Task 7
- ✅ Error handling (non-200, connection error, JSON decode) → Task 8
- ✅ OpenRouter delegates to OpenAI → Task 4
- ✅ `StreamChunk.usage` field added → Task 2

**Placeholder scan:** No TBD, TODO, or "fill in later" entries.

**Type consistency:**
- `parse_chunk/1` receives `%{event: _, data: _}` in all tasks ✓
- `build_stream_body` is /3 for OpenAI/OpenRouter, /4 for Anthropic — `Stream.run` dispatches via `function_exported?/3` ✓
- `StreamChunk` has `usage` field added in Task 2, referenced in Tasks 3, 5, 7 ✓
- `build_callback/1` in Task 6 matches usage in test ✓
