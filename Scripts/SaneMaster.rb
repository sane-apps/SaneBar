#!/bin/bash
# SaneMaster wrapper — delegates to SaneProcess infra if available,
# otherwise runs standalone for external contributors.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(cd "${PROJECT_ROOT}/../.." 2>/dev/null && pwd 2>/dev/null || echo "")"
INFRA="${ROOT_DIR}/infra/SaneProcess/scripts/SaneMaster.rb"

cd "${PROJECT_ROOT}"

# If SaneProcess infra exists, delegate to it (internal development)
if [ -f "${INFRA}" ]; then
  exec "${INFRA}" "$@"
fi

# Standalone mode for external contributors
exec ruby "${SCRIPT_DIR}/SaneMaster_standalone.rb" "$@"
