#!/bin/bash
# Live SaneBar log capture for Air UI testing (code evidence alongside visual).
# Run via a script FILE, never inline — the agent shell evals inline commands
# and mangles the predicate's nested quotes ("too many arguments"). Background
# inline `log stream` also fails; this script form works.
#
# Usage:
#   bash Scripts/sanebar_logwatch.sh > /tmp/sanebar_live.log 2>&1 &
#   tail -40 /tmp/sanebar_live.log | grep -iE "moveIcon task|Move complete|notch-unsafe|separator"
#
# --level info is required: the move workflow logs at .info. --level debug was
# observed to fail; log show does NOT reliably surface .info/.debug.
exec log stream --level info --predicate 'subsystem == "com.sanebar.app"' --style compact
