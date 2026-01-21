# Hook File Rules

> Pattern: `**/hooks/**/*.rb`, `**/*_hook.rb`, `**/*_validator.rb`

---

## Requirements

1. **Exit 0 to allow** - Tool call proceeds
2. **Exit 2 to BLOCK** - Tool call is prevented (Claude Code standard)
3. **Exit 1 = warning only** - Shows warning but tool proceeds
3. **Warn for messages** - User sees stderr output
4. **Handle errors gracefully** - Don't block on unexpected errors

## Right

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'

# Read from stdin (Claude Code standard)
begin
  input = JSON.parse($stdin.read)
rescue JSON::ParserError, Errno::ENOENT
  exit 0  # Don't block on parse errors
end

tool_name = input['tool_name']
tool_input = input['tool_input'] || input

begin
  if should_block?(tool_input)
    warn '🔴 BLOCKED: [Rule Name]'
    warn '   Reason: [explanation]'
    exit 2  # Exit 2 = BLOCK in Claude Code
  end

  exit 0  # Allow the call
rescue StandardError => e
  warn "⚠️  Hook error: #{e.message}"
  exit 0  # Don't block on unexpected errors
end
```

## Hook Types

| Type | Runs | Purpose |
|------|------|---------|
| PreToolUse | Before tool executes | Block dangerous operations |
| PostToolUse | After tool completes | Track failures, log decisions |
| SessionStart | When session begins | Bootstrap environment |
| SessionEnd | When session ends | Capture learnings |

## Wrong

```ruby
# Missing error handling - will crash and block unexpectedly
data = JSON.parse($stdin.read)

# Using exit 1 for warnings - will block the tool
if file_too_large?(data)
  puts "Warning: file is large"
  exit 1  # Should warn and exit 0 for warnings
end
```
