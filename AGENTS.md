# SaneBar Agent Instructions

This repository is public. Keep agent instructions public-safe and do not commit local handoffs, private memory, generated agent state, local machine paths, support transcripts, or release secrets.

## Source Of Truth

- Product behavior and setup: `README.md`
- Development workflow: `DEVELOPMENT.md`
- Architecture and known fragilities: `ARCHITECTURE.md`
- Privacy and security claims: `PRIVACY.md`, `SECURITY.md`
- Release history: `CHANGELOG.md`

## Workflow

- Prefer the project wrappers in `Scripts/SaneMaster.rb` for build, test, launch, and QA workflows.
- Releases are signed and published by the repo owner. Pull requests must never touch `docs/appcast.xml`, `docs/_redirects`, or release artifacts.
- Before claiming a change works, build and test it, and runtime-verify any customer-facing surface you touched.
- Settings and right-click menu items must be ordered from the customer's most likely/common need to the least likely/most advanced need.
- Settings text, helper text, highlights, badges, status messages, and subsection text must stay bright white, high contrast, and at least `13pt`.
- Settings sections should use plain language, balanced spacing, and visual symmetry.

## Public Repo Hygiene

- Do not track `.build-logs`, `DerivedData`, `.claude`, `.agent`, `.gemini`, `SESSION_HANDOFF.md`, generated outputs, or local screenshots.
- Keep dependency versions reproducible. Do not track internal packages from a moving branch when a revision or tag is available.
- SaneBar is free and fully open source under the MIT License (relicensed June 2026 as part of the sunset). Use open-source/MIT wording; the old "source-available / PolyForm Shield" framing is retired.
