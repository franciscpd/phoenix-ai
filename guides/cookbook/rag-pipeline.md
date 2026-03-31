# Cookbook: RAG Pipeline

Retrieval-Augmented Generation (RAG) fetches relevant context before generating a response.
This recipe implements a RAG pattern using `PhoenixAI.Pipeline`.

## Pattern Overview

```
User Query → [Search Step] → [Generate Step] → Response
                  ↓ error
              Pipeline Halts
```

## Implementation

```elixir
defmodule MyApp.RAGPipeline do
  use PhoenixAI.Pipeline

  alias PhoenixAI.Message

  step :search do
    fn query ->
      # Search your vector store or database
      case MyApp.VectorStore.search(query, limit: 5) do
        {:ok, []} ->
          {:error, {:no_results, query}}

        {:ok, documents} ->
          context =
            documents
            |> Enum.map_join("\n\n---\n\n", & &1.content)

          {:ok, %{query: query, context: context}}

        {:error, reason} ->
          {:error, {:search_failed, reason}}
      end
    end
  end

  step :generate do
    fn %{query: query, context: context} ->
      messages = [
        %Message{
          role: :system,
          content: """
          You are a helpful assistant. Answer the user's question using ONLY
          the provided context. If the context doesn't contain the answer,
          say so clearly.
          """
        },
        %Message{
          role: :user,
          content: """
          Context:
          #{context}

          Question: #{query}
          """
        }
      ]

      AI.chat(messages, provider: :openai, model: "gpt-4o")
    end
  end
end
```

## Usage

```elixir
case MyApp.RAGPipeline.run("What is the refund policy?") do
  {:ok, %PhoenixAI.Response{content: answer}} ->
    IO.puts(answer)

  {:error, {:no_results, query}} ->
    IO.puts("No documents found for: #{query}")

  {:error, {:search_failed, reason}} ->
    IO.inspect(reason, label: "Search error")
end
```

## Ad-hoc Version

For simpler use cases, run without a module:

```elixir
alias PhoenixAI.{Message, Pipeline}

steps = [
  fn query ->
    case MyApp.VectorStore.search(query, limit: 3) do
      {:ok, []} -> {:error, :no_results}
      {:ok, docs} -> {:ok, {query, Enum.map_join(docs, "\n", & &1.content)}}
      {:error, _} = err -> err
    end
  end,
  fn {query, context} ->
    AI.chat(
      [
        %Message{role: :system, content: "Answer using only this context: #{context}"},
        %Message{role: :user, content: query}
      ],
      provider: :openai
    )
  end
]

{:ok, response} = Pipeline.run(steps, "Tell me about the product")
```

## Streaming RAG

Combine RAG with streaming for real-time output:

```elixir
defmodule MyApp.StreamingRAG do
  alias PhoenixAI.Message

  def run(query, socket_pid) do
    with {:ok, docs} <- MyApp.VectorStore.search(query, limit: 5),
         context <- Enum.map_join(docs, "\n\n", & &1.content) do
      messages = [
        %Message{role: :system, content: "Use this context to answer: #{context}"},
        %Message{role: :user, content: query}
      ]

      AI.stream(messages,
        provider: :openai,
        to: socket_pid
      )
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
```

## Testing

```elixir
defmodule MyApp.RAGPipelineTest do
  use ExUnit.Case, async: true
  use PhoenixAI.Test

  alias PhoenixAI.Response

  setup do
    # Stub the vector store
    Mox.stub(MyApp.VectorStoreMock, :search, fn _query, _opts ->
      {:ok, [%{content: "Refunds are accepted within 30 days."}]}
    end)

    :ok
  end

  test "returns AI answer when documents are found" do
    set_responses([
      {:ok, %Response{content: "You can get a refund within 30 days."}}
    ])

    assert {:ok, %Response{content: "You can get a refund within 30 days."}} =
             MyApp.RAGPipeline.run("refund policy")
  end

  test "halts when no documents found" do
    Mox.stub(MyApp.VectorStoreMock, :search, fn _query, _opts -> {:ok, []} end)

    assert {:error, {:no_results, "refund policy"}} =
             MyApp.RAGPipeline.run("refund policy")
  end
end
```
