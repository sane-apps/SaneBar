# SaneBar Development Guide (SOP)

**Version 1.0** | Last updated: 2026-01-01

> **SINGLE SOURCE OF TRUTH** for all Developers and AI Agents.
>
> **SOP = Standard Operating Procedure = This File (DEVELOPMENT.md)**
>
> When you see "SOP", "use our SOP", or "follow the SOP", this is the document.
>
> **Read this entirely before touching code.**

---

## 🚀 Quick Start for AI Agents

**New to this project? Start here:**

1. **Bootstrap runs automatically** - `./Scripts/SaneMaster.rb bootstrap`
2. **Read Rule #0 first** (Section 1)
3. **Know the Self-Rating requirement**
4. **Use SaneMaster.rb**: All tools are in `./Scripts/SaneMaster.rb`

**Key Commands:**

```bash
./Scripts/SaneMaster.rb bootstrap  # Environment check + auto-update
./Scripts/SaneMaster.rb verify     # Build + unit tests
```

---

## 0. Critical System Context: macOS 26.2 (Tahoe)

- **OS**: macOS 26.2 (Tahoe). APIs differ from older versions.
- **Hardware**: Apple Silicon (M1+) ONLY.
- **Ruby**: Homebrew Ruby 3.4+ required.

---

## 1. The Golden Rules (CRITICAL)


### Rule #0: INTERNALIZE, DON'T SKIM (META)

Before coding, explicitly map rules to your task.

### Tier 1: Anti-Hallucination

1. **SDK IS THE SOURCE OF TRUTH (CRITICAL)**:
   - **NEVER trust web search for API existence**.
   - **ALWAYS query the SDK directly** (`grep "API" ...swiftinterface`).

2. **TWO-FIX RULE (CRITICAL)**: If you fail twice in a row, **STOP GUESSING**.
3. **VERIFY BEFORE SHIP (NO OVERRIDE)**.

### Tier 2: Core Workflow

1. **USE SaneMaster.rb**: Never use raw `xcodebuild`.
2. **AUTOMATIC BUILD & LAUNCH**: After changes, `verify` and if needed `launch`.
3. **VERIFY LOGS ALWAYS**: Run `./Scripts/SaneMaster.rb diagnose --dump` after tests.

### Tier 3: Code Quality

1. **FILE CREATION = XCODEGEN**: New file? Run `xcodegen generate`.
2. **FILE SIZE LIMITS**: Soft limit **500 lines**.


---

## 2. Directory Structure

```text
SaneBar/
├── Core/                  # Foundation types, Managers
├── UI/                    # SwiftUI views
├── SaneBarApp.swift       # Entry point
└── Scripts/               # SaneMaster automation
```

---

## 3. Style Guide & Best Practices

- **Line Length**: 120 chars max.
- **Indent**: 4 spaces.
- **Linting**: Enforced by `swiftlint`.

---

## 4. Troubleshooting

- **Ghost Beeps / No Launch**: Run `xcodegen generate`.
- **Phantom Errors**: Run `./Scripts/SaneMaster.rb clean --nuclear`.
