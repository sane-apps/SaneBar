# Script File Rules

> Pattern: `**/scripts/**/*.rb`, `**/*.rb`, `**/hooks/**/*.rb`

---

## Requirements

1. **frozen_string_literal** - Always add pragma at top
2. **Exit codes matter** - 0 = success, 1 = blocked/error
3. **Warn, don't puts** - Use `warn` for messages (goes to stderr)
4. **Handle missing input** - Read from stdin, handle empty gracefully

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

# Process the input
tool_input = input['tool_input'] || input
# ... do work
```

## Wrong

```ruby
# Missing frozen_string_literal pragma
require 'json'

# Using puts instead of warn
puts "Processing..."  # Goes to stdout, may interfere with hook output

# Not handling empty stdin
data = JSON.parse($stdin.read)  # Will crash on empty input
```
