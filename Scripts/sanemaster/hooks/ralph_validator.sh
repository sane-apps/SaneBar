#!/bin/bash
# Ralph Loop Validator - Enforces exit conditions
# Called by wrapper before ralph-loop starts

set -euo pipefail

HAS_MAX_ITER=false
HAS_PROMISE=false
MAX_ITER_VALUE=0

# Parse arguments to check for required flags
while [[ $# -gt 0 ]]; do
  case $1 in
    --max-iterations)
      HAS_MAX_ITER=true
      if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
        MAX_ITER_VALUE="$2"
      fi
      shift 2 2>/dev/null || shift
      ;;
    --completion-promise)
      if [[ -n "${2:-}" ]]; then
        HAS_PROMISE=true
      fi
      shift 2 2>/dev/null || shift
      ;;
    *)
      shift
      ;;
  esac
done

# Enforce: Must have at least one real exit condition
if [[ "$HAS_MAX_ITER" == "false" ]] && [[ "$HAS_PROMISE" == "false" ]]; then
  echo "❌ BLOCKED: Ralph loop requires an exit condition!" >&2
  echo "" >&2
  echo "   You must provide at least ONE of:" >&2
  echo "     --max-iterations N    (where N > 0)" >&2
  echo "     --completion-promise 'TEXT'" >&2
  echo "" >&2
  echo "   Example:" >&2
  echo "     /ralph-loop \"Fix bug\" --max-iterations 15 --completion-promise \"BUG-FIXED\"" >&2
  echo "" >&2
  echo "   This prevents infinite loops (learned from 700+ iteration failure)." >&2
  exit 1
fi

# Enforce: max-iterations 0 is not allowed without a promise
if [[ "$HAS_MAX_ITER" == "true" ]] && [[ "$MAX_ITER_VALUE" == "0" ]] && [[ "$HAS_PROMISE" == "false" ]]; then
  echo "❌ BLOCKED: --max-iterations 0 (unlimited) requires --completion-promise!" >&2
  echo "" >&2
  echo "   Either:" >&2
  echo "     1. Set --max-iterations to a positive number (10-20 recommended)" >&2
  echo "     2. Add --completion-promise 'TEXT' as exit condition" >&2
  echo "" >&2
  exit 1
fi

# Warn if max-iterations is very high
if [[ "$MAX_ITER_VALUE" -gt 30 ]]; then
  echo "⚠️  WARNING: --max-iterations $MAX_ITER_VALUE is high. 10-20 is recommended." >&2
fi

echo "✅ Ralph loop validated: exit conditions present"
exit 0
