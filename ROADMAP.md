# SaneBar Roadmap

> High-level feature status. For details, see linked documents.

---

## Feature Status Overview

| Feature | Status | Details |
|---------|--------|---------|
| Hide/Show menu bar icons | ✅ Shipped v1.0.0 | Core functionality |
| AppleScript support | ✅ Shipped v1.0.0 | `tell app "SaneBar" to toggle` |
| Per-icon keyboard shortcuts | ✅ Shipped v1.0.0 | Settings → Shortcuts |
| Profiles/presets | ✅ Shipped v1.0.0 | Save/load configurations |
| Show on hover | ✅ Shipped v1.0.0 | Settings → General |
| Menu bar spacing control | ✅ Shipped v1.0.3 | Settings → Advanced |
| Visual zones (dividers) | ✅ Shipped v1.0.3 | Settings → Advanced |
| Find Icon search | ✅ Shipped v1.0.3 | Option-click or ⌘⇧Space |
| Find Icon move | ✅ Shipped v1.0.5 | Right-click → Move to Hidden/Visible |
| Sparkle auto-updates | ✅ Shipped v1.0.6 | Automatic update checks |
| Menu bar tint (M4 fix) | 🔧 In Progress | [BUG-020](BUG_TRACKING.md) |
| Intel (x86_64) support | 📌 Backlog | No test hardware |
| Second menu bar row | ❌ Not Planned | macOS limitation |

---

## Detailed Documentation

| Document | Purpose |
|----------|---------|
| [FEATURE_PLAN.md](FEATURE_PLAN.md) | Implementation details, API research, phase planning |
| [marketing/feature-requests.md](marketing/feature-requests.md) | User requests, priority assessment, testimonials |
| [BUG_TRACKING.md](BUG_TRACKING.md) | All bugs with GitHub issue links |
| [CHANGELOG.md](CHANGELOG.md) | Version history |

---

## How to Request Features

1. **GitHub Issue**: https://github.com/stephanjoseph/SaneBar/issues/new
2. **Reddit**: r/macapps or r/MacOS threads
3. **Include**: What you want, why you need it, how many others might benefit

---

## Decision Criteria

Features are evaluated on:
1. **User impact**: How many people does this help?
2. **Alignment**: Does it fit SaneBar's "clean menu bar" vision?
3. **Complexity**: Engineering effort vs. benefit
4. **Risk**: Could it break existing functionality?

---

## Not Planned (with reasons)

| Request | Reason |
|---------|--------|
| Second menu bar row | macOS doesn't support multiple NSStatusItem bars |
| Intel/Hackintosh support | No test hardware, shrinking user base |
| "Reveal to front" positioning | Edge case for notch overlay apps, high complexity |
| Icon click-through | High complexity, cursor hijacking risk |

See [marketing/feature-requests.md](marketing/feature-requests.md) for full cost-benefit analysis.
