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

# shellcheck disable=SC1090
. "${ROOT_DIR}/capabilities/ssh.sh"
# shellcheck disable=SC1090
. "${ROOT_DIR}/capabilities/network.sh"
# shellcheck disable=SC1090
. "${ROOT_DIR}/capabilities/nccl.sh"
# shellcheck disable=SC1090
. "${ROOT_DIR}/capabilities/mpi.sh"

nccl_mpi_defaults() {
  nccl_defaults
  mpi_defaults
  network_defaults
  default_var RUN_SSH_CHECK "1"
  default_var RUN_ROUTE_CHECK "1"
  default_var RUN_TCP_CHECK "1"
  default_var RUN_NCCL_STANDALONE_CHECK "1"
  default_var RUN_MPI_STANDALONE_CHECK "1"
  default_var RUN_INTEGRATION_CHECK "1"
}

nccl_mpi_skip_if_mpi_prerequisite_failed() {
  local failed_checks

  if ! result_has_fail_by_prefix "mpi_"; then
    return 1
  fi

  section "NCCL over MPI integration check"
  failed_checks="$(result_failed_checks_by_prefix "mpi_" | tr '\n' ',' | sed 's/,$//')"
  result_skip "nccl_mpi_allreduce" "skipped because MPI prerequisite failed: ${failed_checks}"
  return 0
}

nccl_mpi_integration_check() {
  section "NCCL over MPI integration check"

  if [ -z "${NCCL_TEST_BIN:-}" ] || [ ! -x "${NCCL_TEST_BIN:-}" ]; then
    result_skip "nccl_mpi_allreduce" "NCCL_TEST_BIN not executable: ${NCCL_TEST_BIN:-unset}"
    return 0
  fi

  if [ "${#NODE_HOSTS[@]}" -lt 2 ]; then
    result_skip "nccl_mpi_allreduce" "less than two nodes"
    return 0
  fi

  if [ ! -f "${MPI_HOSTFILE}" ]; then
    generate_mpi_hostfile "${MPI_HOSTFILE}"
  fi

  mpi_build_run_args
  mpi_preflight_env_args_array

  local log_file="${RUN_DIR}/nccl_mpi_allreduce.log"
  local env_args
  env_args=(-x "NCCL_DEBUG=${NCCL_DEBUG:-INFO}")
  if [ -n "${NCCL_SOCKET_IFNAME:-}" ]; then
    env_args+=(-x "NCCL_SOCKET_IFNAME=${NCCL_SOCKET_IFNAME}")
  fi

  clean_mpi
  clean_nccl

  run_cmd "nccl_mpi_allreduce" "${NCCL_TIMEOUT}" "${log_file}" -- \
    "${MPI_RUN_ARGS[@]}" \
    "${MPI_PREFLIGHT_ENV_ARGS[@]}" \
    "${env_args[@]}" \
    "${NCCL_TEST_BIN}" \
    -b "${NCCL_MIN_BYTES}" \
    -e "${NCCL_MAX_BYTES}" \
    -f "${NCCL_STEP_FACTOR}" \
    -g "${NCCL_GPUS_PER_PROCESS}"
  local rc=$?

  if [ "${rc}" -eq 0 ]; then
    result_pass "nccl_mpi_allreduce" "mpirun + NCCL all_reduce_perf passed"
  elif [ "${rc}" -eq 124 ]; then
    result_fail "nccl_mpi_allreduce" "timeout, possible hang; see ${log_file}"
  else
    result_fail "nccl_mpi_allreduce" "exit=${rc}; see ${log_file}"
  fi

  mpi_extract_important_lines "${log_file}" > "${RUN_DIR}/nccl_mpi_allreduce.important.log" || true

  clean_mpi
  clean_nccl
}

integration_nccl_mpi_main() {
  local config="${1:-}"
  local provided_run_dir="${2:-}"

  if [ -z "${config}" ]; then
    log_error "usage: bash integrations/nccl_mpi.sh <config> [run_dir]"
    return 2
  fi

  load_config "${config}" || return 1
  TARGET="nccl_mpi"
  export TARGET
  init_run_dir "nccl_mpi" "${provided_run_dir}"
  result_init
  require_var NODES_FILE || return 1
  load_nodes "${NODES_FILE}" || return 1
  nccl_mpi_defaults

  write_env_snapshot "${RUN_DIR}/env.snapshot"
  write_nodes_snapshot "${RUN_DIR}/nodes.snapshot"

  clean_all

  if [ "${UPDATE_ETC_HOSTS:-0}" = "1" ]; then
    update_etc_hosts_all_nodes
  else
    result_skip "update_etc_hosts" "UPDATE_ETC_HOSTS is disabled"
  fi

  generate_mpi_hostfile "${MPI_HOSTFILE}"
  cp "${MPI_HOSTFILE}" "${RUN_DIR}/hostfile"

  if [ "${RUN_SSH_CHECK:-1}" = "1" ]; then
    capability_ssh_check
  else
    result_skip "ssh_check" "RUN_SSH_CHECK is disabled"
  fi

  if [ "${RUN_ROUTE_CHECK:-1}" = "1" ]; then
    capability_network_check
  else
    result_skip "network_check" "RUN_ROUTE_CHECK is disabled"
  fi

  if [ "${RUN_NCCL_STANDALONE_CHECK:-1}" = "1" ]; then
    capability_nccl_check
  else
    result_skip "nccl_standalone_check" "RUN_NCCL_STANDALONE_CHECK is disabled"
  fi

  if [ "${RUN_MPI_STANDALONE_CHECK:-1}" = "1" ]; then
    capability_mpi_check
  else
    result_skip "mpi_standalone_check" "RUN_MPI_STANDALONE_CHECK is disabled"
  fi

  if [ "${RUN_INTEGRATION_CHECK:-1}" = "1" ]; then
    if ! nccl_mpi_skip_if_mpi_prerequisite_failed; then
      nccl_mpi_integration_check
    fi
  else
    result_skip "nccl_mpi_allreduce" "RUN_INTEGRATION_CHECK is disabled"
  fi

  clean_all
  print_summary
  final_exit_code
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  integration_nccl_mpi_main "$@"
  exit $?
fi
