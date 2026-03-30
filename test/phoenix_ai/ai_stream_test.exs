defmodule AIStreamTest do
  use ExUnit.Case

  alias PhoenixAI.{Message, StreamChunk}

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
  end

  describe "build_callback/1" do
    test "uses on_chunk when provided" do
      callback = fn _chunk -> :ok end
      result = AI.build_callback(on_chunk: callback)
      assert result == callback
    end

    test "sends to PID when :to provided" do
      callback = AI.build_callback(to: self())
      chunk = %StreamChunk{delta: "test"}
      callback.(chunk)
      assert_received {:phoenix_ai, {:chunk, ^chunk}}
    end

    test "defaults to self()" do
      callback = AI.build_callback([])
      chunk = %StreamChunk{delta: "test"}
      callback.(chunk)
      assert_received {:phoenix_ai, {:chunk, ^chunk}}
    end
  end
end
