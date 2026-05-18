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

## Public Repo Hygiene

- Do not track `.build-logs`, `DerivedData`, `.claude`, `.agent`, `.gemini`, `SESSION_HANDOFF.md`, generated outputs, or local screenshots.
- Keep dependency versions reproducible. Do not track internal packages from a moving branch when a revision or tag is available.
- Use source-available wording for SaneBar. The repo is licensed under PolyForm Shield, not a permissive open-source license.
