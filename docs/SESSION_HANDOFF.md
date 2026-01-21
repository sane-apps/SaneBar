# Session Handoff: SaneBar Marketing & Maintenance

> **Next Session**: Refactor `sanetools.rb` and continue marketing execution.

---

## What's Done (Jan 21, 2026)

### Infrastructure ✅
- **Gemini CLI**: Successfully transitioned from Claude.
- **Refactoring**:
    - `scripts/hooks/sanetrack.rb` → Split into modular `lib/sanetrack/*.rb`. Verified with self-test.
    - `scripts/hooks/test/tier_tests.rb` → Split into `tiers/*.rb`. Verified (most tests passed, some `sanetools` failures unrelated to refactor).
- **Environment**: Added `GEMINI.md` context. Symlinked `.gemini -> .claude`.

### Marketing ✅
- **9to5Mac**: Email draft prepared.
- **AlternativeTo**: Submission prepared.
- **GitHub Outreach**: Checked opportunities. "Hidden Bar" issue #339 has activity.
- **Website**: Updated `index.html` to hide "SaneApps" family links until other sites are ready. Verified local preview.

### Testing ✅
- **Fixed Tests**: Updated `AppleScriptCommandsTests.swift` to support intermediate `SaneBarScriptCommand` class.
- **Verification**: `SaneMaster.rb verify` passed 206/206 tests.

---

## Next Session: Execute This

### Immediate Actions
1. **Push Changes**: Run `git push origin main` (Authentication failed in session).
2. **Fix Sanetools Tests**: Investigate why `sanetools.rb` blocked valid reads in the test suite (Exit 1 vs 0).
3. **Continue Refactoring**: Split `sanetools.rb` (738 lines) using the same pattern as `sanetrack.rb`.

### Marketing (Week 2)
4. **Product Hunt Teaser**: Create "Coming Soon" page.
5. **BetaList**: Consider expedited listing ($129).

---

## Budget Remaining

| Spent | Remaining |
|-------|-----------|
| $0 | $200 |

Plan: $129 BetaList + $71 reserve