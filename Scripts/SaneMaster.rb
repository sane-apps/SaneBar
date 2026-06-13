#!/bin/bash
# SaneMaster wrapper - delegates to SaneProcess infra if available,
# otherwise runs standalone for external contributors.

set -e

# Hook/launchd shells often run with a C locale, which makes Ruby default to
# US-ASCII and crash on UTF-8 Swift sources and xcodebuild output.
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export LANG="${LANG:-en_US.UTF-8}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

find_saneprocess_infra() {
  local dir="${PROJECT_ROOT}"
  while [ "${dir}" != "/" ]; do
    if [ -f "${dir}/infra/SaneProcess/scripts/SaneMaster.rb" ]; then
      printf '%s\n' "${dir}/infra/SaneProcess/scripts/SaneMaster.rb"
      return 0
    fi
    dir="$(dirname "${dir}")"
  done

  if [ -f "${HOME}/SaneApps/infra/SaneProcess/scripts/SaneMaster.rb" ]; then
    printf '%s\n' "${HOME}/SaneApps/infra/SaneProcess/scripts/SaneMaster.rb"
    return 0
  fi

  return 1
}

INFRA="$(find_saneprocess_infra || true)"

cd "${PROJECT_ROOT}"

if [ -f "${INFRA}" ]; then
  PRELUDE="$(dirname "${INFRA}")/sanemaster-wrapper-prelude.sh"
  if [ -f "${PRELUDE}" ]; then
    # shellcheck disable=SC1090
    . "${PRELUDE}"
    saneprocess_prepare_project_wrapper "$@"
  fi
  exec "${INFRA}" "$@"
fi

if [ -f "${SCRIPT_DIR}/SaneMaster_standalone.rb" ]; then
  exec ruby "${SCRIPT_DIR}/SaneMaster_standalone.rb" "$@"
fi

echo "SaneMaster: No SaneProcess infra found and no standalone version available." >&2
echo "" >&2
echo "  For internal development: Clone the full SaneApps monorepo." >&2
echo "  For external contributors: Run xcodebuild directly:" >&2
echo "    xcodebuild -scheme SaneBar -configuration Debug build" >&2
exit 1
