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
. "${ROOT_DIR}/lib/bash/cleanup.sh"
# shellcheck disable=SC1090
. "${ROOT_DIR}/lib/bash/summary.sh"

MPI_COMMON_ARGS=()
MPI_NETWORK_ARGS=()
MPI_VERBOSE_ARGS=()
MPI_RUN_ARGS=()
MPI_PREFLIGHT_ENV_ARGS=()

mpi_defaults() {
  default_var COMMAND_TIMEOUT "20"
  default_var MPI_TIMEOUT "25"
  default_var MPI_BIN "mpirun"
  default_var MPI_LOCAL_NP "2"
  default_var MPI_ALLOW_RUN_AS_ROOT "1"
  default_var MPI_DISABLE_OPENIB_BTL "1"
  default_var MPI_NO_TREE_SPAWN "1"
  default_var MPI_VERBOSE "0"
  default_var MPI_HOSTFILE "/tmp/preflight_mpi_hostfile"

  if [ -z "${MPI_NP:-}" ] || [ "${MPI_NP:-0}" = "0" ]; then
    if [ "${#NODE_HOSTS[@]}" -gt 0 ]; then
      MPI_NP="$(get_total_slots)"
    else
      MPI_NP="${MPI_LOCAL_NP}"
    fi
    export MPI_NP
  fi
}

mpi_common_args_array() {
  MPI_COMMON_ARGS=()

  if [ "${MPI_ALLOW_RUN_AS_ROOT:-1}" = "1" ]; then
    MPI_COMMON_ARGS+=(--allow-run-as-root)
  fi

  MPI_COMMON_ARGS+=(-np "${MPI_NP}")

  if [ -n "${MPI_HOSTFILE:-}" ]; then
    MPI_COMMON_ARGS+=(--hostfile "${MPI_HOSTFILE}")
  fi

  if [ "${MPI_NO_TREE_SPAWN:-1}" = "1" ]; then
    MPI_COMMON_ARGS+=(--mca plm_rsh_no_tree_spawn 1)
  fi

  MPI_COMMON_ARGS+=(--mca plm_rsh_agent ssh)
  MPI_COMMON_ARGS+=(
    --mca
    plm_rsh_args
    "-p ${SSH_PORT:-22} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=${SSH_TIMEOUT:-5} -o BatchMode=yes"
  )
}

mpi_network_args_array() {
  MPI_NETWORK_ARGS=()

  if [ -n "${CONTROL_IF_NAME:-}" ]; then
    MPI_NETWORK_ARGS+=(--mca oob_tcp_if_include "${CONTROL_IF_NAME}")
    MPI_NETWORK_ARGS+=(--mca btl_tcp_if_include "${CONTROL_IF_NAME}")
  elif [ -n "${CONTROL_IF_CIDR:-}" ]; then
    MPI_NETWORK_ARGS+=(--mca oob_tcp_if_include "${CONTROL_IF_CIDR}")
    MPI_NETWORK_ARGS+=(--mca btl_tcp_if_include "${CONTROL_IF_CIDR}")
  fi

  if [ "${MPI_DISABLE_OPENIB_BTL:-1}" = "1" ]; then
    MPI_NETWORK_ARGS+=(--mca btl "^openib")
  fi
}

mpi_verbose_args_array() {
  MPI_VERBOSE_ARGS=()

  if [ "${MPI_VERBOSE:-0}" = "1" ]; then
    MPI_VERBOSE_ARGS+=(--mca plm_base_verbose 100)
    MPI_VERBOSE_ARGS+=(--mca plm_rsh_verbose 100)
    MPI_VERBOSE_ARGS+=(--mca oob_base_verbose 100)
  fi
}

mpi_build_run_args() {
  mpi_common_args_array
  mpi_verbose_args_array
  mpi_network_args_array
  MPI_RUN_ARGS=("${MPI_BIN}" "${MPI_COMMON_ARGS[@]}" "${MPI_VERBOSE_ARGS[@]}" "${MPI_NETWORK_ARGS[@]}")
}

mpi_preflight_env_args_array() {
  MPI_PREFLIGHT_ENV_ARGS=()
  MPI_PREFLIGHT_ENV_ARGS+=(-x AI_INFRA_PREFLIGHT=1)
  MPI_PREFLIGHT_ENV_ARGS+=(-x "PREFLIGHT_RUN_ID=${PREFLIGHT_RUN_ID:-unknown}")
}

mpi_common_args() {
  mpi_common_args_array
  printf '%s\n' "${MPI_COMMON_ARGS[@]}"
}

mpi_network_args() {
  mpi_network_args_array
  printf '%s\n' "${MPI_NETWORK_ARGS[@]}"
}

mpi_verbose_args() {
  mpi_verbose_args_array
  printf '%s\n' "${MPI_VERBOSE_ARGS[@]}"
}

mpi_rsh_args() {
  printf '%s\n' "-p ${SSH_PORT:-22} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=${SSH_TIMEOUT:-5} -o BatchMode=yes"
}

mpi_check_binary() {
  local log_file="${RUN_DIR}/mpi_binary_local.log"
  {
    printf 'MPI_BIN=%s\n' "${MPI_BIN}"
    command -v "${MPI_BIN}" || true
    if command -v orted >/dev/null 2>&1; then command -v orted; fi
    if command -v prted >/dev/null 2>&1; then command -v prted; fi
  } > "${log_file}" 2>&1

  if command -v "${MPI_BIN}" >/dev/null 2>&1; then
    result_pass "mpi_binary_local" "${MPI_BIN} found"
  else
    result_fail "mpi_binary_local" "${MPI_BIN} not found"
  fi
}

mpi_check_version_local() {
  local log_file="${RUN_DIR}/mpi_version_local.log"

  if ! command -v "${MPI_BIN}" >/dev/null 2>&1; then
    result_skip "mpi_version_local" "${MPI_BIN} not found"
    return 0
  fi

  run_cmd "mpi_version_local" "${COMMAND_TIMEOUT}" "${log_file}" -- "${MPI_BIN}" --version
  local rc=$?
  if [ "${rc}" -eq 0 ]; then
    result_pass "mpi_version_local" "version command succeeded"
  else
    result_warn "mpi_version_local" "exit=${rc}; see ${log_file}"
  fi
}

mpi_check_version_all_nodes() {
  if [ "${#NODE_HOSTS[@]}" -eq 0 ]; then
    result_skip "mpi_binary_remote" "no nodes loaded"
    return 0
  fi

  local failures=0
  local daemon_warnings=0
  local host

  for host in "${NODE_HOSTS[@]}"; do
    local log_file="${RUN_DIR}/mpi_binary_${host}.log"
    local cmd="command -v ${MPI_BIN} && (${MPI_BIN} --version | head -n 5) && (command -v orted || command -v prted || command -v prte || true)"
    local rc

    if is_local_host "${host}"; then
      run_cmd "mpi_binary_${host}" "${COMMAND_TIMEOUT}" "${log_file}" -- bash -lc "${cmd}"
      rc=$?
    else
      remote_exec_timeout "${COMMAND_TIMEOUT}" "${host}" "${cmd}" "${log_file}"
      rc=$?
    fi

    if [ "${rc}" -ne 0 ]; then
      failures=$((failures + 1))
    elif ! grep -E '(/orted|/prted|/prte)$' "${log_file}" >/dev/null 2>&1; then
      daemon_warnings=$((daemon_warnings + 1))
    fi
  done

  if [ "${failures}" -gt 0 ]; then
    result_fail "mpi_binary_remote" "${failures} node(s) failed MPI binary/version check"
  elif [ "${daemon_warnings}" -gt 0 ]; then
    result_warn "mpi_binary_remote" "MPI binary found; daemon command not detected on ${daemon_warnings} node(s)"
  else
    result_pass "mpi_binary_remote" "MPI binary and daemon visible on all nodes"
  fi
}

mpi_generate_hostfile() {
  if [ "${#NODE_HOSTS[@]}" -eq 0 ]; then
    result_skip "mpi_hostfile" "no nodes loaded"
    return 0
  fi

  generate_mpi_hostfile "${MPI_HOSTFILE}"
  cp "${MPI_HOSTFILE}" "${RUN_DIR}/hostfile"
  result_pass "mpi_hostfile" "generated ${MPI_HOSTFILE} with MPI_NP=${MPI_NP}"
}

mpi_check_local_hostname() {
  local log_file="${RUN_DIR}/mpi_local_hostname.log"
  local args
  args=("${MPI_BIN}")

  if [ "${MPI_ALLOW_RUN_AS_ROOT:-1}" = "1" ]; then
    args+=(--allow-run-as-root)
  fi
  args+=(-np "${MPI_LOCAL_NP}")

  if [ "${MPI_VERBOSE:-0}" = "1" ]; then
    args+=(--mca plm_base_verbose 100)
  fi

  clean_mpi
  run_cmd "mpi_local_hostname" "${MPI_TIMEOUT}" "${log_file}" -- \
    env AI_INFRA_PREFLIGHT=1 "PREFLIGHT_RUN_ID=${PREFLIGHT_RUN_ID:-unknown}" \
    "${args[@]}" hostname
  local rc=$?
  mpi_extract_important_lines "${log_file}" > "${RUN_DIR}/mpi_local_hostname.important.log" || true
  clean_mpi

  if [ "${rc}" -eq 0 ]; then
    result_pass "mpi_local_hostname" "local mpirun hostname passed"
  elif [ "${rc}" -eq 124 ]; then
    result_fail "mpi_local_hostname" "timeout, possible hang; see ${log_file}"
  else
    result_fail "mpi_local_hostname" "exit=${rc}; see ${log_file}"
  fi
}

mpi_check_multinode_hostname() {
  local log_file="${RUN_DIR}/mpi_multinode_hostname.log"

  if [ "${#NODE_HOSTS[@]}" -lt 2 ]; then
    result_skip "mpi_multinode_hostname" "less than two nodes"
    return 0
  fi

  if [ ! -f "${MPI_HOSTFILE}" ]; then
    generate_mpi_hostfile "${MPI_HOSTFILE}"
  fi

  mpi_build_run_args
  mpi_preflight_env_args_array

  clean_mpi
  run_cmd "mpi_multinode_hostname" "${MPI_TIMEOUT}" "${log_file}" -- \
    "${MPI_RUN_ARGS[@]}" "${MPI_PREFLIGHT_ENV_ARGS[@]}" hostname
  local rc=$?
  mpi_extract_important_lines "${log_file}" > "${RUN_DIR}/mpi_multinode_hostname.important.log" || true
  clean_mpi

  if [ "${rc}" -eq 0 ]; then
    result_pass "mpi_multinode_hostname" "multinode mpirun hostname passed"
  elif [ "${rc}" -eq 124 ]; then
    result_fail "mpi_multinode_hostname" "timeout, possible hang; see ${log_file}"
  else
    result_fail "mpi_multinode_hostname" "exit=${rc}; see ${log_file}"
  fi
}

mpi_extract_important_lines() {
  local log_file="$1"

  if [ ! -f "${log_file}" ]; then
    return 0
  fi

  grep -Eai 'orte_hnp_uri|post no route|tcp:no route|final template argv|orted|prted|pmix|no route|unreachable|oob|btl|failed|error|timeout' "${log_file}" || true
}

capability_mpi_check() {
  section "MPI capability check"
  mpi_defaults
  mpi_check_binary
  mpi_check_version_local
  mpi_check_version_all_nodes
  mpi_generate_hostfile
  mpi_check_local_hostname
  mpi_check_multinode_hostname
}

capability_mpi_main() {
  local config="${1:-}"
  local provided_run_dir="${2:-}"

  if [ -z "${config}" ]; then
    log_error "usage: bash capabilities/mpi.sh <config> [run_dir]"
    return 2
  fi

  load_config "${config}" || return 1
  TARGET="mpi"
  export TARGET
  init_run_dir "mpi" "${provided_run_dir}"
  result_init
  write_env_snapshot "${RUN_DIR}/env.snapshot"

  if [ -n "${NODES_FILE:-}" ]; then
    load_nodes "${NODES_FILE}" || return 1
    write_nodes_snapshot "${RUN_DIR}/nodes.snapshot"
  fi

  capability_mpi_check
  print_summary
  final_exit_code
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  capability_mpi_main "$@"
  exit $?
fi
