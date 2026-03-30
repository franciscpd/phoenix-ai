defmodule PhoenixAI.AgentTest do
  use ExUnit.Case, async: false

  import Mox

  alias PhoenixAI.{Agent, Message, Response}

  setup :set_mox_global
  setup :verify_on_exit!

  @base_opts [
    provider: PhoenixAI.MockProvider,
    api_key: "test-key",
    model: "test-model"
  ]

  describe "start_link/1" do
    test "starts agent with valid opts" do
      assert {:ok, pid} = Agent.start_link(@base_opts)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "accepts :name opt" do
      assert {:ok, pid} = Agent.start_link(@base_opts ++ [name: :test_agent])
      assert Process.alive?(pid)
      assert GenServer.whereis(:test_agent) == pid
      GenServer.stop(pid)
    end

    test "defaults manage_history to true" do
      {:ok, pid} = Agent.start_link(@base_opts)
      assert Agent.get_messages(pid) == []
      GenServer.stop(pid)
    end
  end

  describe "prompt/2 with managed history" do
    test "returns response from provider" do
      expect(PhoenixAI.MockProvider, :chat, fn messages, _opts ->
        assert [%Message{role: :user, content: "Hello"}] = messages
        {:ok, %Response{content: "Hi there!", tool_calls: [], finish_reason: "stop"}}
      end)

      {:ok, pid} = Agent.start_link(@base_opts)

      assert {:ok, %Response{content: "Hi there!"}} = Agent.prompt(pid, "Hello")

      GenServer.stop(pid)
    end

    test "prepends system prompt to messages" do
      expect(PhoenixAI.MockProvider, :chat, fn messages, _opts ->
        assert [
                 %Message{role: :system, content: "You are helpful."},
                 %Message{role: :user, content: "Hi"}
               ] = messages

        {:ok, %Response{content: "Hello!", tool_calls: [], finish_reason: "stop"}}
      end)

      {:ok, pid} = Agent.start_link(@base_opts ++ [system: "You are helpful."])

      assert {:ok, _} = Agent.prompt(pid, "Hi")

      GenServer.stop(pid)
    end

    test "accumulates messages across multiple prompts" do
      PhoenixAI.MockProvider
      |> expect(:chat, fn messages, _opts ->
        assert [%Message{role: :user, content: "My name is João"}] = messages

        {:ok,
         %Response{content: "Nice to meet you, João!", tool_calls: [], finish_reason: "stop"}}
      end)
      |> expect(:chat, fn messages, _opts ->
        assert [
                 %Message{role: :user, content: "My name is João"},
                 %Message{role: :assistant, content: "Nice to meet you, João!"},
                 %Message{role: :user, content: "What is my name?"}
               ] = messages

        {:ok, %Response{content: "Your name is João!", tool_calls: [], finish_reason: "stop"}}
      end)

      {:ok, pid} = Agent.start_link(@base_opts)

      assert {:ok, _} = Agent.prompt(pid, "My name is João")

      assert {:ok, %Response{content: "Your name is João!"}} =
               Agent.prompt(pid, "What is my name?")

      messages = Agent.get_messages(pid)
      assert length(messages) == 4

      GenServer.stop(pid)
    end

    test "propagates provider error" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, _opts ->
        {:error, %PhoenixAI.Error{status: 500, message: "Server error", provider: :mock}}
      end)

      {:ok, pid} = Agent.start_link(@base_opts)

      assert {:error, %PhoenixAI.Error{status: 500}} = Agent.prompt(pid, "Hello")

      assert Agent.get_messages(pid) == []

      GenServer.stop(pid)
    end
  end

  describe "prompt/3 with consumer-managed history" do
    test "does not accumulate messages when manage_history: false" do
      PhoenixAI.MockProvider
      |> expect(:chat, fn messages, _opts ->
        assert [%Message{role: :user, content: "Hello"}] = messages
        {:ok, %Response{content: "Hi!", tool_calls: [], finish_reason: "stop"}}
      end)
      |> expect(:chat, fn messages, _opts ->
        assert [%Message{role: :user, content: "Again"}] = messages
        {:ok, %Response{content: "Hi again!", tool_calls: [], finish_reason: "stop"}}
      end)

      {:ok, pid} = Agent.start_link(@base_opts ++ [manage_history: false])

      assert {:ok, _} = Agent.prompt(pid, "Hello")
      assert {:ok, _} = Agent.prompt(pid, "Again")
      assert Agent.get_messages(pid) == []

      GenServer.stop(pid)
    end

    test "accepts messages: opt for consumer-managed history" do
      expect(PhoenixAI.MockProvider, :chat, fn messages, _opts ->
        assert [
                 %Message{role: :user, content: "Previous"},
                 %Message{role: :assistant, content: "I remember"},
                 %Message{role: :user, content: "Continue"}
               ] = messages

        {:ok, %Response{content: "Continuing!", tool_calls: [], finish_reason: "stop"}}
      end)

      history = [
        %Message{role: :user, content: "Previous"},
        %Message{role: :assistant, content: "I remember"}
      ]

      {:ok, pid} = Agent.start_link(@base_opts ++ [manage_history: false])

      assert {:ok, _} = Agent.prompt(pid, "Continue", messages: history)

      GenServer.stop(pid)
    end
  end

  describe "prompt/2 with tools" do
    test "delegates to ToolLoop when tools configured" do
      PhoenixAI.MockProvider
      |> expect(:format_tools, fn tools ->
        assert [PhoenixAI.TestTools.WeatherTool] = tools
        [%{"type" => "function", "function" => %{"name" => "get_weather"}}]
      end)
      |> expect(:chat, fn _messages, opts ->
        assert opts[:tools_json] != nil
        {:ok, %Response{content: "It's sunny!", tool_calls: [], finish_reason: "stop"}}
      end)

      {:ok, pid} = Agent.start_link(@base_opts ++ [tools: [PhoenixAI.TestTools.WeatherTool]])

      assert {:ok, %Response{content: "It's sunny!"}} = Agent.prompt(pid, "Weather?")

      GenServer.stop(pid)
    end
  end

  describe "get_messages/1" do
    test "returns accumulated messages" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, _opts ->
        {:ok, %Response{content: "Hi!", tool_calls: [], finish_reason: "stop"}}
      end)

      {:ok, pid} = Agent.start_link(@base_opts)
      Agent.prompt(pid, "Hello")

      messages = Agent.get_messages(pid)

      assert [%Message{role: :user, content: "Hello"}, %Message{role: :assistant, content: "Hi!"}] =
               messages

      GenServer.stop(pid)
    end

    test "returns empty list when manage_history: false" do
      {:ok, pid} = Agent.start_link(@base_opts ++ [manage_history: false])
      assert Agent.get_messages(pid) == []
      GenServer.stop(pid)
    end
  end

  describe "reset/1" do
    test "clears messages but keeps config" do
      PhoenixAI.MockProvider
      |> expect(:chat, fn _messages, _opts ->
        {:ok, %Response{content: "First", tool_calls: [], finish_reason: "stop"}}
      end)
      |> expect(:chat, fn messages, _opts ->
        assert [%Message{role: :user, content: "After reset"}] = messages
        {:ok, %Response{content: "Fresh start!", tool_calls: [], finish_reason: "stop"}}
      end)

      {:ok, pid} = Agent.start_link(@base_opts)
      Agent.prompt(pid, "Before reset")
      assert length(Agent.get_messages(pid)) == 2

      assert :ok = Agent.reset(pid)
      assert Agent.get_messages(pid) == []

      assert {:ok, %Response{content: "Fresh start!"}} = Agent.prompt(pid, "After reset")

      GenServer.stop(pid)
    end
  end

  describe "busy detection" do
    test "returns error when prompt is already in progress" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, _opts ->
        Process.sleep(200)
        {:ok, %Response{content: "Done", tool_calls: [], finish_reason: "stop"}}
      end)

      {:ok, pid} = Agent.start_link(@base_opts)

      task = Task.async(fn -> Agent.prompt(pid, "Slow request") end)
      Process.sleep(50)

      assert {:error, :agent_busy} = Agent.prompt(pid, "Impatient request")

      assert {:ok, %Response{content: "Done"}} = Task.await(task)

      GenServer.stop(pid)
    end
  end

  describe "isolation" do
    test "killing one agent does not affect another" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, _opts ->
        {:ok, %Response{content: "Still alive!", tool_calls: [], finish_reason: "stop"}}
      end)

      {:ok, pid1} = Agent.start_link(@base_opts)
      {:ok, pid2} = Agent.start_link(@base_opts)

      Process.unlink(pid1)
      Process.exit(pid1, :kill)
      Process.sleep(50)

      refute Process.alive?(pid1)
      assert Process.alive?(pid2)
      assert {:ok, %Response{content: "Still alive!"}} = Agent.prompt(pid2, "Are you there?")

      GenServer.stop(pid2)
    end
  end

  describe "DynamicSupervisor" do
    test "starts agent via DynamicSupervisor with child_spec" do
      {:ok, sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

      {:ok, pid} =
        DynamicSupervisor.start_child(sup, {Agent, @base_opts})

      assert Process.alive?(pid)

      GenServer.stop(pid)
      Supervisor.stop(sup)
    end
  end
end
