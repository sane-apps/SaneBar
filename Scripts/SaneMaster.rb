#!/bin/bash
# Unified SaneMaster wrapper (single source of truth in infra/SaneProcess)

set -e

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "${PROJECT_ROOT}"
exec "${ROOT_DIR}/infra/SaneProcess/scripts/SaneMaster.rb" "$@"
