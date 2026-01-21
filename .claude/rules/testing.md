# Testing Rules

> Pattern: When user says "test", "verify", "check if works", "ship", "release"

---

## MANDATORY: Before Claiming Anything Works

**YOU MUST RUN THESE TOOLS:**

### 1. Button Map (See All Controls)
```bash
./scripts/button_map.rb
```
Shows every UI toggle/button and what it triggers.

### 2. Trace Flow (Debug Specific Function)
```bash
./scripts/trace_flow.rb <function_name>
```
Example: `./scripts/trace_flow.rb toggleHiddenItems`

### 3. E2E Checklist
Read and follow: `docs/E2E_TESTING_CHECKLIST.md`

---

## Testing Flow

1. **Build & Launch**: `./scripts/SaneMaster.rb test_mode`
2. **Run button_map.rb** to see all controls
3. **Test each setting** by toggling and observing
4. **Verify visually** in the menu bar
5. **Check logs** for errors: `./scripts/SaneMaster.rb logs --follow`

---

## Visual Verification Required

For ANY visual feature (spacers, dividers, appearance):
1. **Open Settings** → Navigate to the control
2. **Change the value**
3. **LOOK AT THE MENU BAR** - verify change is visible
4. **Report what you see** - not just "it works"

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Said "it works" without testing | Run the actual app |
| Didn't check menu bar visually | Look at the screen |
| Assumed toggle worked | Verify state changed |
| Skipped auth check | Test with password enabled |

---

## When User Says "Test X"

1. Find X in button_map.rb output
2. Trace the flow with trace_flow.rb
3. Build and launch the app
4. Toggle/click the control
5. Observe the result
6. Report: "I toggled X, and Y happened in the menu bar"
