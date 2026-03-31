# Cookbook: Streaming to LiveView

Stream AI responses in real-time to a Phoenix LiveView, updating the UI as text arrives.

## Pattern Overview

```
LiveView → AI.stream(..., to: self()) → handle_info({:phoenix_ai, {:chunk, _}}, socket)
```

## Basic LiveView Integration

```elixir
defmodule MyAppWeb.ChatLive do
  use MyAppWeb, :live_view

  alias PhoenixAI.Message

  def mount(_params, _session, socket) do
    {:ok, assign(socket, messages: [], streaming: false, current_response: "")}
  end

  def handle_event("send_message", %{"text" => text}, socket) do
    # Don't allow concurrent streams
    if socket.assigns.streaming do
      {:noreply, socket}
    else
      user_msg = %{role: :user, content: text}
      messages = socket.assigns.messages ++ [user_msg]

      # Start streaming in a Task, sending chunks to this LiveView process
      lv_pid = self()

      Task.start(fn ->
        ai_messages = Enum.map(messages, &%Message{role: &1.role, content: &1.content})

        AI.stream(ai_messages,
          provider: :openai,
          model: "gpt-4o",
          to: lv_pid
        )

        # Signal stream completion
        send(lv_pid, {:phoenix_ai, :done})
      end)

      {:noreply,
       assign(socket,
         messages: messages,
         streaming: true,
         current_response: ""
       )}
    end
  end

  # Receive each text chunk
  def handle_info({:phoenix_ai, {:chunk, %PhoenixAI.StreamChunk{delta: delta}}}, socket)
      when is_binary(delta) do
    {:noreply, assign(socket, current_response: socket.assigns.current_response <> delta)}
  end

  # Ignore non-text chunks (tool call deltas, usage, etc.)
  def handle_info({:phoenix_ai, {:chunk, _chunk}}, socket) do
    {:noreply, socket}
  end

  # Stream complete — finalize the message
  def handle_info({:phoenix_ai, :done}, socket) do
    assistant_msg = %{role: :assistant, content: socket.assigns.current_response}

    {:noreply,
     assign(socket,
       messages: socket.assigns.messages ++ [assistant_msg],
       streaming: false,
       current_response: ""
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="chat-container">
      <div :for={msg <- @messages} class={"message #{msg.role}"}>
        <strong><%= msg.role %>:</strong> <%= msg.content %>
      </div>

      <div :if={@streaming} class="message assistant streaming">
        <strong>assistant:</strong> <%= @current_response %><span class="cursor">▌</span>
      </div>

      <form phx-submit="send_message">
        <input type="text" name="text" disabled={@streaming} />
        <button type="submit" disabled={@streaming}>Send</button>
      </form>
    </div>
    """
  end
end
```

## PubSub Alternative with on_chunk:

For broadcasting to multiple subscribers (e.g., collaborative chat), use `on_chunk:`
with PubSub:

```elixir
defmodule MyApp.AIStreamer do
  alias PhoenixAI.Message

  def stream_to_topic(messages, topic) do
    Task.start(fn ->
      AI.stream(messages,
        provider: :openai,
        on_chunk: fn chunk ->
          if chunk.delta do
            Phoenix.PubSub.broadcast(
              MyApp.PubSub,
              topic,
              {:ai_chunk, chunk.delta}
            )
          end
        end
      )

      Phoenix.PubSub.broadcast(MyApp.PubSub, topic, :ai_done)
    end)
  end
end
```

Subscribe in your LiveView:

```elixir
def mount(%{"room_id" => room_id}, _session, socket) do
  topic = "chat:#{room_id}"
  Phoenix.PubSub.subscribe(MyApp.PubSub, topic)
  {:ok, assign(socket, topic: topic, current_response: "", streaming: false)}
end

def handle_info({:ai_chunk, delta}, socket) do
  {:noreply, assign(socket, current_response: socket.assigns.current_response <> delta)}
end

def handle_info(:ai_done, socket) do
  {:noreply, assign(socket, streaming: false)}
end
```

## Streaming with Tools

When streaming with tool calling, the model may pause to call tools. PhoenixAI handles
the tool loop automatically — your LiveView just receives text chunks:

```elixir
Task.start(fn ->
  AI.stream(messages,
    provider: :openai,
    tools: [MyApp.WeatherTool, MyApp.CalendarTool],
    to: lv_pid
  )

  send(lv_pid, {:phoenix_ai, :done})
end)
```

During tool calls, there may be a pause before text resumes — consider showing
a "thinking..." indicator:

```elixir
def handle_info({:phoenix_ai, {:chunk, %PhoenixAI.StreamChunk{tool_call_delta: delta}}}, socket)
    when is_map(delta) do
  # Tool call in progress — show thinking indicator
  {:noreply, assign(socket, thinking: true)}
end

def handle_info({:phoenix_ai, {:chunk, %PhoenixAI.StreamChunk{delta: delta}}}, socket)
    when is_binary(delta) do
  # Text resumed — hide thinking indicator
  {:noreply,
   assign(socket,
     thinking: false,
     current_response: socket.assigns.current_response <> delta
   )}
end
```

## Timeout Handling

Always handle the case where streaming takes too long:

```elixir
def handle_event("send_message", %{"text" => text}, socket) do
  lv_pid = self()

  Task.start(fn ->
    result = AI.stream(messages, provider: :openai, to: lv_pid)

    case result do
      {:ok, _} -> send(lv_pid, {:phoenix_ai, :done})
      {:error, reason} -> send(lv_pid, {:phoenix_ai, {:error, reason}})
    end
  end)

  {:noreply, assign(socket, streaming: true)}
end

def handle_info({:phoenix_ai, {:error, reason}}, socket) do
  {:noreply,
   assign(socket,
     streaming: false,
     error: "AI request failed: #{inspect(reason)}"
   )}
end
```
