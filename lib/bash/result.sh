#!/usr/bin/env bash

result_init() {
  if [ -z "${RUN_DIR:-}" ]; then
    log_error "RUN_DIR is not set"
    return 1
  fi

  mkdir -p "${RUN_DIR}"
  SUMMARY_FILE="${RUN_DIR}/summary.tsv"
  export SUMMARY_FILE
  : > "${SUMMARY_FILE}"
}

_result_sanitize() {
  printf '%s' "$*" | tr '\t\r\n' '   '
}

_result_record() {
  local name="$1"
  local status="$2"
  shift 2
  local message
  message="$(_result_sanitize "$@")"

  if [ -z "${SUMMARY_FILE:-}" ]; then
    SUMMARY_FILE="${RUN_DIR}/summary.tsv"
    export SUMMARY_FILE
  fi

  mkdir -p "$(dirname "${SUMMARY_FILE}")"
  printf '%s\t%s\t%s\n' "${name}" "${status}" "${message}" >> "${SUMMARY_FILE}"

  case "${status}" in
    PASS) log_info "${name}: PASS ${message}" ;;
    FAIL) log_error "${name}: FAIL ${message}" ;;
    WARN) log_warn "${name}: WARN ${message}" ;;
    SKIP) log_info "${name}: SKIP ${message}" ;;
    *) log_warn "${name}: ${status} ${message}" ;;
  esac
}

result_pass() {
  _result_record "$1" "PASS" "${2:-}"
}

result_fail() {
  _result_record "$1" "FAIL" "${2:-}"
}

result_skip() {
  _result_record "$1" "SKIP" "${2:-}"
}

result_warn() {
  _result_record "$1" "WARN" "${2:-}"
}
