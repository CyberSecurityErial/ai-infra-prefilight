#!/usr/bin/env bash

preflight_timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

_preflight_log_emit() {
  local level="$1"
  shift
  local message="$*"
  local line
  line="[$(preflight_timestamp)] [${level}] ${message}"
  printf '%s\n' "${line}"

  if [ -n "${RUN_DIR:-}" ] && [ -d "${RUN_DIR:-}" ]; then
    printf '%s\n' "${line}" >> "${RUN_DIR}/preflight.log"
  fi
}

log_info() {
  _preflight_log_emit "INFO" "$@"
}

log_warn() {
  _preflight_log_emit "WARN" "$@"
}

log_error() {
  _preflight_log_emit "ERROR" "$@"
}

log_debug() {
  if [ "${PREFLIGHT_DEBUG:-0}" = "1" ] || [ "${TEST_LEVEL:-}" = "debug" ]; then
    _preflight_log_emit "DEBUG" "$@"
  fi
}

section() {
  local title="$*"
  printf '\n========== %s ==========\n' "${title}"
  if [ -n "${RUN_DIR:-}" ] && [ -d "${RUN_DIR:-}" ]; then
    printf '\n========== %s ==========\n' "${title}" >> "${RUN_DIR}/preflight.log"
  fi
}
