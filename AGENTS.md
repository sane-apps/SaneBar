# SaneBar Agent Instructions

This repository is public. Keep agent instructions public-safe and do not commit local handoffs, private memory, generated agent state, local machine paths, support transcripts, or release secrets.

## Source Of Truth

- Product behavior and setup: `README.md`
- Development workflow: `DEVELOPMENT.md`
- Architecture and known fragilities: `ARCHITECTURE.md`
- Privacy and security claims: `PRIVACY.md`, `SECURITY.md`
- Release history: `CHANGELOG.md`

## Workflow

- Prefer the project wrappers in `scripts/SaneMaster.rb` for build, test, release, preflight, launch, and QA workflows.
- Do not run raw release steps manually; use the shared `release.sh` flow documented in `DEVELOPMENT.md`.
- For SaneApps maintainers, use the Mac Mini build server and private local handoff/memory files when available, but keep those files out of the public repository.
- Before claiming release readiness, run code verification, release preflight, and customer-facing runtime/visual checks for touched surfaces.
- Settings and right-click menu items must be ordered from the customer's most likely/common need to the least likely/most advanced need.
- Settings text, helper text, highlights, badges, status messages, and subsection text must stay bright white, high contrast, and at least `13pt`.
- Settings sections should use plain language, balanced spacing, and visual symmetry.

## Public Repo Hygiene

- Do not track `.build-logs`, `DerivedData`, `.claude`, `.agent`, `.gemini`, `SESSION_HANDOFF.md`, generated outputs, or local screenshots.
- Keep dependency versions reproducible. Do not track internal packages from a moving branch when a revision or tag is available.
- SaneBar is free and fully open source under the MIT License (relicensed June 2026 as part of the sunset). Use open-source/MIT wording; the old "source-available / PolyForm Shield" framing is retired.
