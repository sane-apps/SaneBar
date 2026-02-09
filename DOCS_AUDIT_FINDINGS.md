# SaneBar Documentation Audit Findings
**Date:** 2026-02-09
**Version:** v1.0.19 (pre-release)
**Pipeline:** 14 perspectives via NVIDIA models (mistral Batch 1, devstral Batch 2)

---

## Executive Summary

| # | Perspective | Score | Critical | Warnings |
|---|-------------|-------|----------|----------|
| 1 | Engineer | 8.5/10 | 3 | 4 |
| 2 | Designer | 7.5/10 | 8 | 8 |
| 3 | Marketer | 8.8/10 | 0 | 3 |
| 4 | User Advocate | 6.5/10 | 2 | 5 |
| 5 | QA | 7.5/10 | 4 | 6 |
| 6 | Hygiene | 7.5/10 | 4 | 3 |
| 7 | Security | 7/10 | 3 | 6 |
| 8 | Freshness | - | 5 | 4 |
| 9 | Completeness | - | 8 | 4 |
| 10 | Ops | - | 3 | 3 |
| 11 | Brand | 9/10 | 0 | 2 |
| 12 | Consistency | - | 3 | 3 |
| 13 | Website Standards | - | 0 | (checklist) |
| 14 | Marketing Framework | - | 3 | 2 |

**Overall:** 7.7/10 average across scored perspectives. Documentation is lagging behind code changes.

---

## Critical Issues (Merged & Deduplicated)

### Documentation Gaps (Fix Immediately)

| # | Issue | Sources | Action |
|---|-------|---------|--------|
| 1 | **README: Always-hidden still labeled "beta/experimental"** | Freshness, Consistency, Completeness, Hygiene, Ops | Remove "(beta)" label, update description to reflect always-on graduation |
| 2 | **README: Dropdown panel undocumented** | Freshness, Completeness, Hygiene, Marketer, User | Add Features section describing dropdown panel with SaneUI styling |
| 3 | **README: Onboarding wizard undocumented** | Freshness, Completeness, Hygiene | Add section describing 5-page flow with presets |
| 4 | **README: Zone management undocumented** | Completeness, Hygiene, User | Add section on right-click context menus for moving icons between zones |
| 5 | **Website: Missing dropdown panel, always-hidden, profiles** | Marketer, Website, Completeness | Update sanebar.com to match current feature set |

### Code Quality Issues

| # | Issue | Source | Severity |
|---|-------|--------|----------|
| 6 | **MenuBarSearchView.swift exceeds 1000 lines (1046)** | Engineer, Ops | High — extract zone helpers |
| 7 | **AH verification false negative when separators flush** | Engineer, QA | High — relax verification margin |
| 8 | **First drag ~20% failure rate** | Engineer, QA | High — increase delay or add retry |
| 9 | **Dropdown panel undiscoverable** | User, Designer | Critical UX — no visual cue for new users |
| 10 | **No feedback when icon move fails** | User, QA | Critical UX — silent failures |

### Security Issues

| # | Issue | Source | Severity |
|---|-------|--------|----------|
| 11 | **AppleScript inputs not sanitized** | Security | Critical — potential command injection |
| 12 | **Auth bypass: HideCommand works without auth** | Security | High — can hide sensitive icons |
| 13 | **Sensitive data in plaintext settings.json** | Security | High — WiFi SSIDs, hotkeys exposed |
| 14 | **Logging leaks bundle IDs and positions** | Security | Medium — use `privacy: .private` |

### Design Issues

| # | Issue | Source | Severity |
|---|-------|--------|----------|
| 15 | **Dropdown panel: missing keyboard navigation** | Designer | Critical — HIG violation |
| 16 | **Dropdown panel: icon spacing too tight (2pt, should be 8pt)** | Designer | High |
| 17 | **Dropdown panel: light mode low contrast** | Designer | High |
| 18 | **Dropdown panel: hover vs selected states identical** | Designer | High |
| 19 | **Onboarding: "Recommended" bias on Smart preset** | Designer | Medium |

---

## Warnings (Merged & Deduplicated)

### Documentation

| # | Warning | Sources |
|---|---------|---------|
| W1 | SESSION_HANDOFF.md has stale references from previous sessions | Freshness, Ops |
| W2 | ARCHITECTURE.md missing dropdown panel state machine | Consistency |
| W3 | ARCHITECTURE.md missing onboarding flow documentation | Hygiene |
| W4 | AppleScript section in README doesn't reflect current behavior | Freshness |
| W5 | DEVELOPMENT.md may reference always-hidden toggle in settings | Freshness |
| W6 | Screenshots may not reflect new UI | Freshness |
| W7 | "Coming soon" features may already be implemented | Completeness |

### Code Quality

| # | Warning | Source |
|---|---------|--------|
| W8 | Separator ordering violation continues with invalid state | QA |
| W9 | AX permission cached at init, never refreshed | QA, Security |
| W10 | Auth lockout not persisted across launches | QA |
| W11 | No SaneUI gradients in WelcomeView (custom gradients instead) | Brand |
| W12 | `.secondary` foreground could be teal-based neutral | Brand |
| W13 | Dropdown panel positioning doesn't account for notched screens | QA |
| W14 | isMoveInProgress is not atomic (plain Bool) | QA |

### Operations

| # | Warning | Source |
|---|---------|--------|
| W15 | No explicit dependency pinning (package-resolved) | Ops |
| W16 | Copyright notices need 2026 update | Ops |
| W17 | SaneUI not versioned/pinned as dependency | Ops |

### Marketing

| # | Warning | Source |
|---|---------|--------|
| W18 | Missing "Threat" (invisible problem) in marketing | Marketing |
| W19 | Missing "Barrier B" (why alternatives betray) in marketing | Marketing |
| W20 | 2 Timothy 1:7 promise not fully integrated into marketing narrative | Marketing |

---

## Issue Classification

### Auto-Fixable (Claude can fix)
- #1: Update README always-hidden from beta to always-on
- #2: Add dropdown panel section to README
- #3: Add onboarding wizard section to README
- #4: Add zone management section to README
- W1: Update SESSION_HANDOFF.md
- W4: Update AppleScript section in README
- W5: Update DEVELOPMENT.md references
- W7: Remove "coming soon" for shipped features

### User Action Required
- #5: Website update (sanebar.com deployment)
- #6: MenuBarSearchView extraction (code refactor)
- #7-#8: Icon moving reliability fixes (code changes)
- #9-#10: UX discoverability improvements (design decisions)
- #11-#14: Security hardening (architecture decisions)
- #15-#19: Design improvements (design decisions)
- W15-W17: Ops improvements (infrastructure decisions)
- W18-W20: Marketing framework (brand/content decisions)

---

## Per-Perspective Details

### 1. Engineer (8.5/10)
- AH verification false negative is the top blocking issue
- First drag ~20% failure rate needs retry mechanism
- MenuBarSearchView at 1046 lines violates 800-line limit
- Concurrency model is well-designed (MainActor, Sendable, Combine)
- 56 regression tests for icon moving is strong coverage

### 2. Designer (7.5/10)
- 8 "would not ship" items, 8 polish items
- Top issues: panel positioning, keyboard navigation, spacing
- Strengths: visual hierarchy, escape dismiss, auto-width, dark/light adaptation
- Panel described as "75% of the way to a premium macOS app"

### 3. Marketer (8.8/10)
- Strong value proposition and emotional journey
- Website underpromises (missing 3 key features)
- Feature naming is clear but "Always Hidden" could be less scary
- Conversion funnel is solid (free tier + $5 one-time)

### 4. User Advocate (6.5/10)
- Lowest score — new features are undiscoverable
- Basic hide/show: 9/10 (works perfectly)
- Advanced features: 4/10 (dropdown panel, zone management)
- Error recovery: 4/10 (silent failures throughout)
- "Grandma could hide/show icons but would give up on advanced features"

### 5. QA (7.5/10)
- Identified 7 always-hidden graduation edge cases
- 7 dropdown panel edge cases (state leak, mode mismatch, positioning)
- Permission edge cases (AX revocation, auth spam, lockout bypass)
- Rapid toggling race conditions documented

### 6. Hygiene (7.5/10)
- 6 duplicate documentation areas identified
- Terminology drift: "beta/experimental" vs graduated, "delimiter" vs "separator"
- Always-hidden, dropdown panel, zone management need consolidation
- ARCHITECTURE.md is well-maintained, README.md is lagging

### 7. Security (7/10)
- 3 critical vulns: AppleScript injection, auth bypass, plaintext settings
- 6 medium concerns: AX abuse, Sparkle TLS, force unwraps, insecure defaults
- Strong positives: no network requests, Touch ID gating, hardened runtime
- Recommended: sanitize AppleScript inputs, encrypt sensitive settings

### 8. Freshness
- 5 stale items: always-hidden beta label, missing dropdown/onboarding docs, stale AppleScript docs, stale session handoff
- 4 possibly stale: screenshots, installation steps, temporal references, DEVELOPMENT.md toggle references

### 9. Completeness
- 8 incomplete documentation areas in README
- Multiple code files flagged for "placeholder text" (likely false positive from audit model)
- Stale "coming soon" promises need updating

### 10. Ops
- 3 urgent: stale session notes, unpinned dependencies, oversized files
- 3 maintenance: stale TODOs, SaneUI drift, copyright dates
- 4 healthy: git hygiene, certificates, domains, release process

### 11. Brand (9/10)
- Excellent teal palette compliance
- SaneUI integration is strong
- Minor issues: WelcomeView uses custom gradients, `.secondary` text
- No gray-on-gray violations

### 12. Consistency
- README stale references to experimental always-hidden
- Missing documentation for dropdown panel and onboarding across docs
- File path references incomplete (new files not in all docs)

### 13. Website Standards
- Checklist format covering cross-linking, trust badges, monetization, visual consistency
- Needs verification against live site

### 14. Marketing Framework
- Missing "Threat" (invisible problem — why clutter hurts)
- Missing "Barrier B" (why Bartender/Ice betray users)
- Solution section is strong
- 2 Timothy 1:7 promise partially integrated (needs fuller connection)

---

## Recommendations (Priority Order)

1. **Update README.md** — Graduate always-hidden, add dropdown panel/onboarding/zone docs
2. **Fix UX discoverability** — Tooltip on first launch for dropdown panel, feedback for icon moves
3. **Address security items** — Sanitize AppleScript inputs, consider auth for HideCommand
4. **Extract MenuBarSearchView** — Split into +Zones.swift and +Actions.swift
5. **Update SESSION_HANDOFF.md** — Reflect current session state
6. **Update sanebar.com** — Match README feature set
7. **Address designer feedback** — Spacing, keyboard nav, contrast in dropdown panel
8. **Marketing framework** — Add Threat/Barrier narrative to website and onboarding
