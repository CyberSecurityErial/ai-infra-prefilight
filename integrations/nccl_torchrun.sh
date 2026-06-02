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
. "${ROOT_DIR}/lib/bash/summary.sh"
# shellcheck disable=SC1090
. "${ROOT_DIR}/capabilities/nccl.sh"
# shellcheck disable=SC1090
. "${ROOT_DIR}/capabilities/torchrun.sh"

nccl_torchrun_integration_check() {
  section "NCCL over torchrun integration check"
  result_skip "nccl_torchrun_allreduce" "TODO: torchrun init_process_group('nccl') and all_reduce smoke test"
}

integration_nccl_torchrun_main() {
  local config="${1:-}"
  local provided_run_dir="${2:-}"

  if [ -z "${config}" ]; then
    log_error "usage: bash integrations/nccl_torchrun.sh <config> [run_dir]"
    return 2
  fi

  load_config "${config}" || return 1
  TARGET="nccl_torchrun"
  export TARGET
  init_run_dir "nccl_torchrun" "${provided_run_dir}"
  result_init
  write_env_snapshot "${RUN_DIR}/env.snapshot"
  capability_nccl_check
  capability_torchrun_check
  nccl_torchrun_integration_check
  print_summary
  final_exit_code
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  integration_nccl_torchrun_main "$@"
  exit $?
fi
