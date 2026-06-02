#!/usr/bin/env bash
set -u
set -o pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# shellcheck disable=SC1090
. "${ROOT_DIR}/lib/bash/log.sh"
# shellcheck disable=SC1090
. "${ROOT_DIR}/lib/bash/result.sh"
# shellcheck disable=SC1090
. "${ROOT_DIR}/lib/bash/config.sh"
# shellcheck disable=SC1090
. "${ROOT_DIR}/lib/bash/command.sh"
# shellcheck disable=SC1090
. "${ROOT_DIR}/lib/bash/remote.sh"
# shellcheck disable=SC1090
. "${ROOT_DIR}/lib/bash/nodes.sh"
# shellcheck disable=SC1090
. "${ROOT_DIR}/lib/bash/summary.sh"

_ssh_resolve_host() {
  local host="$1"

  if command -v getent >/dev/null 2>&1; then
    getent hosts "${host}"
    return $?
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import socket, sys; print(socket.gethostbyname(sys.argv[1]))' "${host}"
    return $?
  fi

  if command -v dscacheutil >/dev/null 2>&1; then
    dscacheutil -q host -a name "${host}"
    return $?
  fi

  return 127
}

ssh_check_hostname_resolution() {
  if [ "${#NODE_HOSTS[@]}" -eq 0 ]; then
    result_skip "hosts_resolution" "no nodes loaded"
    return 0
  fi

  local failures=0
  local host
  local log_file="${RUN_DIR}/hosts_resolution.log"
  : > "${log_file}"

  for host in "${NODE_HOSTS[@]}"; do
    {
      printf '## %s\n' "${host}"
      _ssh_resolve_host "${host}"
    } >> "${log_file}" 2>&1
    local rc=$?
    if [ "${rc}" -ne 0 ]; then
      failures=$((failures + 1))
    fi
  done

  if [ "${failures}" -eq 0 ]; then
    result_pass "hosts_resolution" "all node hostnames resolve locally"
  else
    result_fail "hosts_resolution" "${failures} hostname(s) failed local resolution; see ${log_file}"
  fi
}

ssh_check_master_self() {
  if [ "${#NODE_HOSTS[@]}" -eq 0 ]; then
    result_skip "ssh_master_self" "no nodes loaded"
    return 0
  fi

  local master
  local log_file="${RUN_DIR}/ssh_master_self.log"
  master="$(get_master_host)"

  ssh_base_args
  run_cmd "ssh_master_self" "${SSH_TIMEOUT}" "${log_file}" -- \
    ssh "${SSH_BASE_ARGS[@]}" "${master}" hostname
  local rc=$?

  if [ "${rc}" -eq 0 ]; then
    result_pass "ssh_master_self" "ssh to master ${master} succeeded"
  elif [ "${rc}" -eq 124 ]; then
    result_fail "ssh_master_self" "timeout connecting to ${master}; see ${log_file}"
  else
    result_fail "ssh_master_self" "exit=${rc}; see ${log_file}"
  fi
}

ssh_check_all_workers() {
  if [ "${#NODE_HOSTS[@]}" -lt 2 ]; then
    result_skip "ssh_workers" "no worker nodes"
    return 0
  fi

  local failures=0
  local host

  for host in $(get_worker_hosts); do
    local log_file="${RUN_DIR}/ssh_worker_${host}.log"
    ssh_base_args
    run_cmd "ssh_worker_${host}" "${SSH_TIMEOUT}" "${log_file}" -- \
      ssh "${SSH_BASE_ARGS[@]}" "${host}" hostname
    local rc=$?
    if [ "${rc}" -ne 0 ]; then
      failures=$((failures + 1))
    fi
  done

  if [ "${failures}" -eq 0 ]; then
    result_pass "ssh_workers" "ssh to all workers succeeded"
  else
    result_fail "ssh_workers" "${failures} worker ssh check(s) failed"
  fi
}

capability_ssh_check() {
  section "SSH capability check"
  ssh_check_hostname_resolution
  ssh_check_master_self
  ssh_check_all_workers
}

capability_ssh_main() {
  local config="${1:-}"
  local provided_run_dir="${2:-}"

  if [ -z "${config}" ]; then
    log_error "usage: bash capabilities/ssh.sh <config> [run_dir]"
    return 2
  fi

  load_config "${config}" || return 1
  TARGET="ssh"
  export TARGET
  init_run_dir "ssh" "${provided_run_dir}"
  result_init
  write_env_snapshot "${RUN_DIR}/env.snapshot"
  require_var NODES_FILE || return 1
  load_nodes "${NODES_FILE}" || return 1
  write_nodes_snapshot "${RUN_DIR}/nodes.snapshot"
  capability_ssh_check
  print_summary
  final_exit_code
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  capability_ssh_main "$@"
  exit $?
fi
