#!/usr/bin/env bash

_preflight_timeout_bin() {
  if command -v timeout >/dev/null 2>&1; then
    command -v timeout
    return 0
  fi

  if command -v gtimeout >/dev/null 2>&1; then
    command -v gtimeout
    return 0
  fi

  return 1
}

preflight_with_timeout() {
  local timeout_sec="$1"
  shift
  local timeout_bin

  if [ -z "${timeout_sec}" ] || [ "${timeout_sec}" = "0" ]; then
    "$@"
    return $?
  fi

  timeout_bin="$(_preflight_timeout_bin || true)"
  if [ -n "${timeout_bin}" ]; then
    "${timeout_bin}" "${timeout_sec}s" "$@"
    return $?
  fi

  if command -v perl >/dev/null 2>&1; then
    perl -e '
      my $timeout = shift;
      my $pid = fork();
      if (!defined $pid) { exit 125; }
      if ($pid == 0) {
        setpgrp(0, 0);
        exec @ARGV;
        exit 127;
      }
      setpgrp($pid, $pid);
      local $SIG{ALRM} = sub {
        kill "TERM", -$pid;
        sleep 1;
        kill "KILL", -$pid;
        exit 124;
      };
      alarm $timeout;
      waitpid($pid, 0);
      my $status = $?;
      alarm 0;
      if ($status & 127) { exit 128 + ($status & 127); }
      exit(($status >> 8) & 255);
    ' "${timeout_sec}" "$@"
    return $?
  fi

  log_warn "timeout command is unavailable; running without timeout: $*"
  "$@"
}

run_cmd() {
  local check_name="$1"
  local timeout_sec="$2"
  local log_file="$3"
  shift 3

  if [ "${1:-}" = "--" ]; then
    shift
  fi

  mkdir -p "$(dirname "${log_file}")"
  {
    printf '[%s] check=%s timeout=%ss\n' "$(preflight_timestamp)" "${check_name}" "${timeout_sec}"
    printf '[%s] command:' "$(preflight_timestamp)"
    printf ' %q' "$@"
    printf '\n'
  } >> "${log_file}"

  AI_INFRA_PREFLIGHT=1 PREFLIGHT_RUN_ID="${PREFLIGHT_RUN_ID:-unknown}" \
    preflight_with_timeout "${timeout_sec}" "$@" >> "${log_file}" 2>&1
  local rc=$?

  {
    printf '[%s] exit=%s\n' "$(preflight_timestamp)" "${rc}"
    if [ "${rc}" -eq 124 ]; then
      printf '[%s] timeout: command exceeded %ss\n' "$(preflight_timestamp)" "${timeout_sec}"
    fi
  } >> "${log_file}"

  return "${rc}"
}
