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

slurm_check_srun() {
  if command -v srun >/dev/null 2>&1; then
    result_pass "slurm_srun" "srun found"
  else
    result_skip "slurm_srun" "TODO: srun binary check; srun not found in PATH"
  fi
}

slurm_check_allocation() {
  result_skip "slurm_allocation" "TODO: verify active Slurm allocation"
}

slurm_check_env() {
  result_skip "slurm_env" "TODO: inspect SLURM_* environment"
}

capability_slurm_check() {
  section "Slurm capability check"
  slurm_check_srun
  slurm_check_allocation
  slurm_check_env
}

capability_slurm_main() {
  local config="${1:-}"
  local provided_run_dir="${2:-}"

  if [ -z "${config}" ]; then
    log_error "usage: bash capabilities/slurm.sh <config> [run_dir]"
    return 2
  fi

  load_config "${config}" || return 1
  TARGET="slurm"
  export TARGET
  init_run_dir "slurm" "${provided_run_dir}"
  result_init
  write_env_snapshot "${RUN_DIR}/env.snapshot"
  capability_slurm_check
  print_summary
  final_exit_code
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  capability_slurm_main "$@"
  exit $?
fi
