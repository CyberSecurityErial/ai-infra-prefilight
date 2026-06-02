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
. "${ROOT_DIR}/lib/bash/cleanup.sh"
# shellcheck disable=SC1090
. "${ROOT_DIR}/lib/bash/summary.sh"

nccl_defaults() {
  default_var COMMAND_TIMEOUT "20"
  default_var NCCL_TIMEOUT "60"
  default_var NCCL_DEBUG "INFO"
  default_var NCCL_MIN_BYTES "8M"
  default_var NCCL_MAX_BYTES "128M"
  default_var NCCL_STEP_FACTOR "2"
  default_var NCCL_GPUS_PER_PROCESS "1"
}

nccl_check_binary() {
  local log_file="${RUN_DIR}/nccl_binary.log"
  {
    printf 'NCCL_TEST_BIN=%s\n' "${NCCL_TEST_BIN:-}"
    if [ -n "${NCCL_TEST_BIN:-}" ]; then
      ls -l "${NCCL_TEST_BIN}" 2>/dev/null || true
    fi
  } > "${log_file}" 2>&1

  if [ -z "${NCCL_TEST_BIN:-}" ]; then
    result_skip "nccl_binary" "NCCL_TEST_BIN is not set"
    return 0
  fi

  if [ -x "${NCCL_TEST_BIN}" ]; then
    result_pass "nccl_binary" "executable: ${NCCL_TEST_BIN}"
  else
    result_skip "nccl_binary" "NCCL_TEST_BIN not executable: ${NCCL_TEST_BIN}"
  fi
}

nccl_check_env() {
  local log_file="${RUN_DIR}/nccl_env.log"
  env | sort | grep '^NCCL_' > "${log_file}" 2>&1 || true

  if [ -z "${NCCL_SOCKET_IFNAME:-}" ]; then
    result_warn "nccl_env" "NCCL_SOCKET_IFNAME is empty; NCCL may choose an unexpected interface"
  else
    result_pass "nccl_env" "NCCL_SOCKET_IFNAME=${NCCL_SOCKET_IFNAME}"
  fi
}

nccl_print_env() {
  local log_file="${RUN_DIR}/nccl_env_all.log"
  {
    printf 'NCCL_DEBUG=%s\n' "${NCCL_DEBUG:-}"
    printf 'NCCL_SOCKET_IFNAME=%s\n' "${NCCL_SOCKET_IFNAME:-}"
    printf 'NCCL_MIN_BYTES=%s\n' "${NCCL_MIN_BYTES:-}"
    printf 'NCCL_MAX_BYTES=%s\n' "${NCCL_MAX_BYTES:-}"
    printf 'NCCL_STEP_FACTOR=%s\n' "${NCCL_STEP_FACTOR:-}"
    printf 'NCCL_GPUS_PER_PROCESS=%s\n' "${NCCL_GPUS_PER_PROCESS:-}"
    env | sort | grep '^NCCL_' || true
  } > "${log_file}" 2>&1
}

nccl_check_ldconfig() {
  local log_file="${RUN_DIR}/nccl_ldconfig.log"

  if ! command -v ldconfig >/dev/null 2>&1; then
    result_skip "nccl_ldconfig" "ldconfig not found"
    return 0
  fi

  run_cmd "nccl_ldconfig" "${COMMAND_TIMEOUT}" "${log_file}" -- \
    bash -lc 'ldconfig -p 2>/dev/null | grep -i libnccl'
  local rc=$?

  if [ "${rc}" -eq 0 ]; then
    result_pass "nccl_ldconfig" "libnccl visible via ldconfig"
  else
    result_warn "nccl_ldconfig" "libnccl not visible via ldconfig; see ${log_file}"
  fi
}

nccl_check_gpu_info() {
  local log_file="${RUN_DIR}/nccl_gpu_info.log"

  if ! command -v nvidia-smi >/dev/null 2>&1; then
    result_skip "nccl_gpu_info" "nvidia-smi not found"
    return 0
  fi

  run_cmd "nccl_gpu_info" "${COMMAND_TIMEOUT}" "${log_file}" -- \
    nvidia-smi
  local rc=$?

  if [ "${rc}" -eq 0 ]; then
    result_pass "nccl_gpu_info" "nvidia-smi succeeded"
  else
    result_warn "nccl_gpu_info" "nvidia-smi exit=${rc}; see ${log_file}"
  fi
}

nccl_check_standalone_single_process() {
  local log_file="${RUN_DIR}/nccl_single_process.log"

  if [ -z "${NCCL_TEST_BIN:-}" ] || [ ! -x "${NCCL_TEST_BIN:-}" ]; then
    result_skip "nccl_single_process" "NCCL_TEST_BIN not executable"
    return 0
  fi

  clean_nccl

  local env_args
  env_args=(env "NCCL_DEBUG=${NCCL_DEBUG:-INFO}")
  if [ -n "${NCCL_SOCKET_IFNAME:-}" ]; then
    env_args+=("NCCL_SOCKET_IFNAME=${NCCL_SOCKET_IFNAME}")
  fi

  run_cmd "nccl_single_process" "${NCCL_TIMEOUT}" "${log_file}" -- \
    "${env_args[@]}" \
    "${NCCL_TEST_BIN}" \
    -b "${NCCL_MIN_BYTES}" \
    -e "${NCCL_MIN_BYTES}" \
    -f 2 \
    -g "${NCCL_GPUS_PER_PROCESS}"
  local rc=$?

  if [ "${rc}" -eq 0 ]; then
    result_pass "nccl_single_process" "single-process all_reduce_perf passed"
  elif [ "${rc}" -eq 124 ]; then
    result_fail "nccl_single_process" "timeout, possible hang; see ${log_file}"
  else
    result_fail "nccl_single_process" "exit=${rc}; see ${log_file}"
  fi

  clean_nccl
}

capability_nccl_check() {
  section "NCCL capability check"
  nccl_defaults
  nccl_print_env
  nccl_check_binary
  nccl_check_env
  nccl_check_ldconfig
  nccl_check_gpu_info
  nccl_check_standalone_single_process
}

capability_nccl_main() {
  local config="${1:-}"
  local provided_run_dir="${2:-}"

  if [ -z "${config}" ]; then
    log_error "usage: bash capabilities/nccl.sh <config> [run_dir]"
    return 2
  fi

  load_config "${config}" || return 1
  TARGET="nccl"
  export TARGET
  init_run_dir "nccl" "${provided_run_dir}"
  result_init
  write_env_snapshot "${RUN_DIR}/env.snapshot"
  capability_nccl_check
  print_summary
  final_exit_code
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  capability_nccl_main "$@"
  exit $?
fi
