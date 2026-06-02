#!/usr/bin/env bash

_summary_has_fail() {
  if [ -n "${SUMMARY_FILE:-}" ] && [ -f "${SUMMARY_FILE}" ]; then
    awk -F '\t' '$2 == "FAIL" { found = 1 } END { exit found ? 0 : 1 }' "${SUMMARY_FILE}"
    return $?
  fi

  return 1
}

print_summary() {
  local overall="PASS"
  if _summary_has_fail; then
    overall="FAIL"
  fi

  printf '\n========== PREFLIGHT SUMMARY ==========\n'
  printf 'target: %s\n' "${TARGET:-unknown}"
  printf 'run_dir: %s\n\n' "${RUN_DIR:-unknown}"

  if [ -n "${SUMMARY_FILE:-}" ] && [ -f "${SUMMARY_FILE}" ]; then
    awk -F '\t' '{ printf "%-32s %-6s %s\n", $1, $2, $3 }' "${SUMMARY_FILE}"
  else
    printf '%-32s %-6s %s\n' "summary" "WARN" "summary file not found"
  fi

  printf '\n%-32s %s\n' "overall" "${overall}"

  if [ "${overall}" = "FAIL" ]; then
    printf 'hint: timeout exit code 124 means possible hang.\n'
    printf 'hint: inspect *.important.log files under the run_dir.\n'
    printf 'hint: for OpenMPI hangs, inspect orte_hnp_uri and OOB interface selection.\n'
  fi
}

final_exit_code() {
  if _summary_has_fail; then
    return 1
  fi

  return 0
}
