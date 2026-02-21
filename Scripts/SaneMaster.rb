#!/bin/bash
# SaneMaster wrapper — delegates to SaneProcess infra if available,
# otherwise runs standalone for external contributors.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(cd "${PROJECT_ROOT}/../.." 2>/dev/null && pwd 2>/dev/null || echo "")"
INFRA="${ROOT_DIR}/infra/SaneProcess/scripts/SaneMaster.rb"
LOGIN_KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

cd "${PROJECT_ROOT}"

prepare_signing_keychain() {
  local keychain password identities identity

  keychain="${SANEBAR_KEYCHAIN_PATH:-${LOGIN_KEYCHAIN}}"
  [ -f "${keychain}" ] || return 0

  # Keep lookup deterministic in SSH/headless shells.
  security default-keychain -d user -s "${keychain}" >/dev/null 2>&1 || true

  if [[ "${OTHER_CODE_SIGN_FLAGS:-}" != *"--keychain"* ]]; then
    export OTHER_CODE_SIGN_FLAGS="--keychain ${keychain}${OTHER_CODE_SIGN_FLAGS:+ ${OTHER_CODE_SIGN_FLAGS}}"
  fi

  password="${SANEBAR_KEYCHAIN_PASSWORD:-${KEYCHAIN_PASSWORD:-${KEYCHAIN_PASS:-}}}"
  [ -n "${password}" ] || return 0

  # Only modify session/search behavior when explicit credentials are supplied.
  security list-keychains -d user -s "${keychain}" /Library/Keychains/System.keychain >/dev/null 2>&1 || true
  security set-keychain-settings -lut 21600 "${keychain}" >/dev/null 2>&1 || true
  security unlock-keychain -p "${password}" "${keychain}" >/dev/null 2>&1 || true

  identities="$(
    security find-identity -v -p codesigning "${keychain}" 2>/dev/null |
      sed -n 's/^[[:space:]]*[0-9][0-9]*) [0-9A-F]\{40\} "\(.*\)"$/\1/p'
  )"

  [ -n "${identities}" ] || return 0

  while IFS= read -r identity; do
    [ -n "${identity}" ] || continue
    security set-key-partition-list \
      -S apple-tool:,apple:,codesign: \
      -s \
      -k "${password}" \
      -D "${identity}" \
      -t private \
      "${keychain}" >/dev/null 2>&1 || true
  done <<< "${identities}"
}

resolved_sanebar_build_config() {
  local command arg requested
  command="${1:-}"
  shift || true

  for arg in "$@"; do
    case "${arg}" in
    --proddebug)
      echo "ProdDebug"
      return 0
      ;;
    --release)
      echo "Release"
      return 0
      ;;
    esac
  done

  requested="${SANEMASTER_BUILD_CONFIG:-${SANEBAR_BUILD_CONFIG:-}}"
  case "${requested}" in
  ProdDebug | Release)
    echo "${requested}"
    return 0
    ;;
  esac

  case "${command}" in
  test_mode | tm | launch)
    # Mirrors SaneProcess default for SaneBar local runtime testing.
    echo "ProdDebug"
    ;;
  *)
    echo "Debug"
    ;;
  esac
}

requires_signed_build() {
  local command config
  command="${1:-}"
  shift || true

  case "${command}" in
  test_mode | tm | launch | build)
    config="$(resolved_sanebar_build_config "${command}" "$@")"
    [[ "${config}" == "ProdDebug" || "${config}" == "Release" ]]
    ;;
  *)
    return 1
    ;;
  esac
}

headless_keychain_blocking() {
  local keychain info
  keychain="${SANEBAR_KEYCHAIN_PATH:-${LOGIN_KEYCHAIN}}"
  [ -f "${keychain}" ] || return 1

  info="$(security show-keychain-info "${keychain}" 2>&1 || true)"
  [[ "${info}" == *"User interaction is not allowed"* ]]
}

enforce_signing_preflight() {
  local keychain password command
  command="${1:-}"
  shift || true

  requires_signed_build "${command}" "$@" || return 0

  keychain="${SANEBAR_KEYCHAIN_PATH:-${LOGIN_KEYCHAIN}}"
  password="${SANEBAR_KEYCHAIN_PASSWORD:-${KEYCHAIN_PASSWORD:-${KEYCHAIN_PASS:-}}}"

  if headless_keychain_blocking && [ -z "${password}" ]; then
    cat <<EOF
❌ Signed ${command} build blocked: login keychain is not accessible in this headless session.
   Keychain: ${keychain}

   Provide one of these before rerunning:
   1) export SANEBAR_KEYCHAIN_PASSWORD='***'   (or KEYCHAIN_PASSWORD / KEYCHAIN_PASS)
   2) Run from an interactive GUI login session on the mini.

EOF
    return 1
  fi
}

requires_codesign_prep() {
  case "${1:-}" in
  test_mode | tm | launch | build | verify)
    return 0
    ;;
  *)
    return 1
    ;;
  esac
}

if requires_codesign_prep "${1:-}"; then
  prepare_signing_keychain
fi

enforce_signing_preflight "${1:-}" "${@:2}"

# If SaneProcess infra exists, delegate to it (internal development)
if [ -f "${INFRA}" ]; then
  exec "${INFRA}" "$@"
fi

# Standalone mode for external contributors
exec ruby "${SCRIPT_DIR}/SaneMaster_standalone.rb" "$@"
