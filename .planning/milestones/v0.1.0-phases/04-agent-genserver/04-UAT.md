---
status: complete
phase: 04-agent-genserver
source: [BRAINSTORM.md, ROADMAP.md success criteria]
started: 2026-03-29T23:38:00.000Z
updated: 2026-03-29T23:40:00.000Z
---

## Current Test

[testing complete]

## Tests

### 1. Agent starts with valid opts
expected: Agent.start_link with provider, model, api_key returns {:ok, pid} and process is alive.
result: pass

### 2. Agent accepts :name opt
expected: Agent.start_link with name: :test_agent registers the process. GenServer.whereis(:test_agent) returns the PID.
result: pass

### 3. prompt/2 returns response from provider
expected: Agent.prompt(pid, "Hello") returns {:ok, %Response{content: "Hi there!"}}.
result: pass

### 4. System prompt prepended in every call
expected: When system: "You are helpful." is set, provider receives [system_msg, user_msg] in every call.
result: pass

### 5. History accumulates across multiple prompts
expected: After two prompts, get_messages returns 4 messages (user, assistant, user, assistant). Second provider call receives full history.
result: pass

### 6. Provider error propagated
expected: When provider returns {:error, _}, Agent.prompt returns the same error. Messages do NOT accumulate on error.
result: pass

### 7. Consumer-managed history (manage_history: false)
expected: Agent does not accumulate messages. get_messages returns []. Each prompt starts fresh.
result: pass

### 8. Consumer passes messages: opt
expected: With manage_history: false, consumer passes messages: in prompt/3. Provider receives history + new user msg.
result: pass

### 9. Tools delegation to ToolLoop
expected: With tools: [WeatherTool], Agent invokes format_tools then ToolLoop. Returns final response.
result: pass

### 10. get_messages/1 returns accumulated messages
expected: After prompt, returns [user_msg, assistant_msg].
result: pass

### 11. reset/1 clears history
expected: After reset, get_messages returns []. Next prompt starts fresh conversation.
result: pass

### 12. Busy detection
expected: Second prompt while first is running returns {:error, :agent_busy}.
result: pass

### 13. Task crash handled
expected: When spawned Task crashes (exit(:boom)), Agent returns {:error, {:agent_task_failed, :boom}} and stays alive.
result: pass

### 14. Process isolation
expected: Killing agent1 with Process.exit does not affect agent2. agent2 still responds to prompts.
result: pass

### 15. DynamicSupervisor compatibility
expected: DynamicSupervisor.start_child with {Agent, opts} starts the agent successfully.
result: pass

## Summary

total: 15
passed: 15
issues: 0
pending: 0
skipped: 0

## Gaps

[none]
