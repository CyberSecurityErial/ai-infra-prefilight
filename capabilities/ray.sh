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

ray_check_binary() {
  if command -v ray >/dev/null 2>&1; then
    result_pass "ray_binary" "ray found"
  else
    result_skip "ray_binary" "TODO: ray binary check; ray not found in PATH"
  fi
}

ray_check_status() {
  result_skip "ray_status" "TODO: check ray cluster status"
}

ray_check_nodes() {
  result_skip "ray_nodes" "TODO: verify ray worker membership"
}

ray_check_gpu_actor() {
  result_skip "ray_gpu_actor" "TODO: schedule a GPU actor smoke test"
}

capability_ray_check() {
  section "Ray capability check"
  ray_check_binary
  ray_check_status
  ray_check_nodes
  ray_check_gpu_actor
}

capability_ray_main() {
  local config="${1:-}"
  local provided_run_dir="${2:-}"

  if [ -z "${config}" ]; then
    log_error "usage: bash capabilities/ray.sh <config> [run_dir]"
    return 2
  fi

  load_config "${config}" || return 1
  TARGET="ray"
  export TARGET
  init_run_dir "ray" "${provided_run_dir}"
  result_init
  write_env_snapshot "${RUN_DIR}/env.snapshot"
  capability_ray_check
  print_summary
  final_exit_code
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  capability_ray_main "$@"
  exit $?
fi
