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

torchrun_check_binary() {
  if command -v torchrun >/dev/null 2>&1; then
    result_pass "torchrun_binary" "torchrun found"
  else
    result_skip "torchrun_binary" "TODO: torchrun binary check; torchrun not found in PATH"
  fi
}

torchrun_check_import_torch() {
  result_skip "torch_import" "TODO: python -c 'import torch'"
}

torchrun_check_cuda() {
  result_skip "torch_cuda" "TODO: torch.cuda availability check"
}

torchrun_check_single_node_launch() {
  result_skip "torchrun_single_node" "TODO: single-node torchrun launch smoke test"
}

capability_torchrun_check() {
  section "torchrun capability check"
  torchrun_check_binary
  torchrun_check_import_torch
  torchrun_check_cuda
  torchrun_check_single_node_launch
}

capability_torchrun_main() {
  local config="${1:-}"
  local provided_run_dir="${2:-}"

  if [ -z "${config}" ]; then
    log_error "usage: bash capabilities/torchrun.sh <config> [run_dir]"
    return 2
  fi

  load_config "${config}" || return 1
  TARGET="torchrun"
  export TARGET
  init_run_dir "torchrun" "${provided_run_dir}"
  result_init
  write_env_snapshot "${RUN_DIR}/env.snapshot"
  capability_torchrun_check
  print_summary
  final_exit_code
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  capability_torchrun_main "$@"
  exit $?
fi
