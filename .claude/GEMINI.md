# Gemini Project Context for SaneBar

> **PRIMARY INSTRUCTION**: This project uses a shared configuration with Claude.
> **SOURCE OF TRUTH**: Read `CLAUDE.md` and `DEVELOPMENT.md` for all project rules, architectural patterns, and workflows.

---

## 🚀 Quick Start for Gemini

1.  **Shared State**: You are sharing the `.claude` directory via a symlink (`.gemini -> .claude`). This means you share memory, circuit breaker state, and logs with Claude. **Respect this state.**
2.  **Scripts**: Use `scripts/SaneMaster.rb` for build, test, and verification.
    *   Verify: `./scripts/SaneMaster.rb verify`
    *   Test Mode: `./scripts/SaneMaster.rb test_mode`
3.  **Refactoring Note**: On Jan 21, 2026, `scripts/hooks/sanetrack.rb` and `scripts/hooks/test/tier_tests.rb` were refactored to be modular. This was done to improve maintainability and is compatible with the existing automation.

## ⚠️ Critical Rules (from CLAUDE.md)

*   **No Sandbox**: The app requires Accessibility APIs and cannot be sandboxed.
*   **Position Pre-Seeding**: Follow the position pre-seeding pattern for NSStatusItem positioning (see `docs/DEBUGGING_MENU_BAR_INTERACTIONS.md`).
*   **Verify APIs**: Always use `./scripts/SaneMaster.rb verify_api` before using new Apple APIs.

## 🔗 Key Links

*   **Rules**: `CLAUDE.md`
*   **SOP**: `DEVELOPMENT.md`
*   **Status**: `docs/SESSION_HANDOFF.md`
*   **Bugs**: `BUG_TRACKING.md`

---
*Created by Gemini CLI on Jan 21, 2026*
