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
. "${ROOT_DIR}/capabilities/ray.sh"

nccl_ray_integration_check() {
  section "NCCL over Ray integration check"
  result_skip "nccl_ray_allreduce" "TODO: run NCCL init and allreduce inside Ray actors"
}

integration_nccl_ray_main() {
  local config="${1:-}"
  local provided_run_dir="${2:-}"

  if [ -z "${config}" ]; then
    log_error "usage: bash integrations/nccl_ray.sh <config> [run_dir]"
    return 2
  fi

  load_config "${config}" || return 1
  TARGET="nccl_ray"
  export TARGET
  init_run_dir "nccl_ray" "${provided_run_dir}"
  result_init
  write_env_snapshot "${RUN_DIR}/env.snapshot"
  capability_nccl_check
  capability_ray_check
  nccl_ray_integration_check
  print_summary
  final_exit_code
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  integration_nccl_ray_main "$@"
  exit $?
fi
