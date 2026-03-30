---
status: complete
phase: 03-tool-calling
source: [BRAINSTORM.md, ROADMAP.md success criteria]
started: 2026-03-29T22:30:00.000Z
updated: 2026-03-29T22:35:00.000Z
---

## Current Test

[testing complete]

## Tests

### 1. Tool behaviour implements all callbacks
expected: A module with @behaviour PhoenixAI.Tool compiles. WeatherTool.name() returns "get_weather", execute(%{"city" => "Lisbon"}, []) returns {:ok, "Sunny, 22°C in Lisbon"}.
result: pass

### 2. Schema converts atom keys to JSON Schema
expected: PhoenixAI.Tool.to_json_schema(WeatherTool) returns string-keyed map with "type" => "object", nested "properties" with string keys, and "required" => ["city"].
result: pass

### 3. OpenAI format_tools wraps in function calling envelope
expected: OpenAI.format_tools([WeatherTool]) returns list with %{"type" => "function", "function" => %{"name" => "get_weather", "parameters" => %{...}}}.
result: pass

### 4. Anthropic format_tools uses input_schema key
expected: Anthropic.format_tools([WeatherTool]) returns list with %{"name" => "get_weather", "input_schema" => %{...}} — no "type" key.
result: pass

### 5. Anthropic tool result injection uses content blocks
expected: Anthropic.format_messages with role: :tool produces %{"role" => "user", "content" => [%{"type" => "tool_result", "tool_use_id" => id}]}.
result: pass

### 6. ToolLoop completes single iteration round-trip
expected: ToolLoop.run with mock provider returning tool_call, then final response after tool execution — returns {:ok, %Response{content: "..."}}.
result: pass

### 7. ToolLoop respects max_iterations
expected: ToolLoop.run with max_iterations: 2 and provider always returning tool_calls — returns {:error, :max_iterations_reached}.
result: pass

### 8. ToolLoop handles tool errors gracefully
expected: When tool.execute returns {:error, reason}, the error is sent as tool result to provider (not aborting the loop). Provider receives the error message and responds.
result: pass

### 9. AI.chat routes to ToolLoop when tools present
expected: AI.chat(messages, provider: MockProvider, tools: [WeatherTool]) invokes format_tools and ToolLoop. Without tools, behaviour is unchanged.
result: pass

### 10. Tools are plain modules — no OTP
expected: PhoenixAI.Tool, PhoenixAI.ToolLoop, and WeatherTool contain zero GenServer, Agent, or process-related code.
result: pass

## Summary

total: 10
passed: 10
issues: 0
pending: 0
skipped: 0

## Gaps

[none]
