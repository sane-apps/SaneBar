# SaneBar AGENTS

Speak in plain English. Keep it short and direct.

Use these docs first:
- `DEVELOPMENT.md`
- `docs/DEBUGGING_MENU_BAR_INTERACTIONS.md`
- `ROADMAP.md` as needed; bugs tracked in GitHub Issues

Core enforcement (SaneProcess):
- If a hook or prompt fires, read it first and follow it exactly.
- Verify APIs before use; stop after 2 failures and investigate.
- Research gate uses all 4: docs (apple-docs/context7), web search, GitHub MCP, local codebase.
- Tests must pass before saying “done.”
- If errors repeat, check breaker status and reset only after investigation.

Build/test (use SaneMaster, not raw xcodebuild):
- `./scripts/SaneMaster.rb verify`
- `./scripts/SaneMaster.rb test_mode`
- `./scripts/SaneMaster.rb logs --follow`
- `./scripts/SaneMaster.rb verify_api ...` before using Accessibility APIs

Menu bar UI testing:
- Use `macos-automator` for real UI. SaneBar is a macOS app (no simulator).

NSStatusItem positioning:
- Use the Ice pattern (seed positions before creating items; use ordinal 0/1/2).

Memory:
- Use mcp-search with `project: "SaneBar"` and the 3-step flow: search → timeline → get_observations.

Session end:
- Add SOP self-rating to `SESSION_HANDOFF.md` and append to `/Users/sj/SaneApps/infra/SaneProcess/outputs/sop_ratings.csv`.
