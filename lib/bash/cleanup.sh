#!/usr/bin/env bash

clean_process_pattern_local() {
  local pattern="$1"
  local log_file="${RUN_DIR:-/tmp}/cleanup_local.log"

  {
    printf '[%s] clean local pattern: %s\n' "$(preflight_timestamp)" "${pattern}"
    pgrep -af "${pattern}" || true
    pkill -9 -f "${pattern}" || true
  } >> "${log_file}" 2>&1
}

marked_preflight_cleanup_command() {
  cat <<'CLEAN_MARKED_PREFLIGHT'
if [ ! -d /proc ]; then
  exit 0
fi

for envfile in /proc/[0-9]*/environ; do
  [ -r "${envfile}" ] || continue
  pid="${envfile#/proc/}"
  pid="${pid%/environ}"
  [ "${pid}" = "$$" ] && continue

  env_text="$(tr '\000' '\n' < "${envfile}" 2>/dev/null || true)"
  printf '%s\n' "${env_text}" | grep -Fxq 'AI_INFRA_PREFLIGHT=1' || continue

  if [ -n "${PREFLIGHT_CLEAN_RUN_ID:-}" ]; then
    printf '%s\n' "${env_text}" | grep -Fxq "PREFLIGHT_RUN_ID=${PREFLIGHT_CLEAN_RUN_ID}" || continue
  fi

  cmdline="$(tr '\000' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true)"
  printf '%s %s\n' "${pid}" "${cmdline}"
  kill -9 "${pid}" 2>/dev/null || true
done
CLEAN_MARKED_PREFLIGHT
}

clean_marked_preflight_local() {
  local log_file="${RUN_DIR:-/tmp}/cleanup_marked_local.log"
  local clean_run_id=""

  if [ "${PREFLIGHT_CLEAN_SCOPE:-all_preflight}" = "current_run" ]; then
    clean_run_id="${PREFLIGHT_RUN_ID:-}"
  fi

  {
    printf '[%s] clean marked preflight processes: scope=%s run_id=%s\n' "$(preflight_timestamp)" "${PREFLIGHT_CLEAN_SCOPE:-all_preflight}" "${clean_run_id}"
    PREFLIGHT_CLEAN_RUN_ID="${clean_run_id}" bash -lc "$(marked_preflight_cleanup_command)"
  } >> "${log_file}" 2>&1
}

clean_marked_preflight_all_nodes() {
  local host
  local script
  local script_q
  local clean_run_id=""
  local run_id_q

  if [ "${PREFLIGHT_CLEAN_SCOPE:-all_preflight}" = "current_run" ]; then
    clean_run_id="${PREFLIGHT_RUN_ID:-}"
  fi

  script="$(marked_preflight_cleanup_command)"
  printf -v script_q '%q' "${script}"
  printf -v run_id_q '%q' "${clean_run_id}"

  if [ "$(_cleanup_node_count)" -eq 0 ]; then
    clean_marked_preflight_local
    return 0
  fi

  for host in "${NODE_HOSTS[@]}"; do
    local log_file="${RUN_DIR:-/tmp}/cleanup_marked_${host}.log"
    if declare -F is_local_host >/dev/null 2>&1 && is_local_host "${host}"; then
      clean_marked_preflight_local
    elif declare -F remote_exec_timeout >/dev/null 2>&1; then
      remote_exec_timeout "${COMMAND_TIMEOUT:-10}" "${host}" "PREFLIGHT_CLEAN_RUN_ID=${run_id_q} bash -lc ${script_q}" "${log_file}" || true
    fi
  done
}

_cleanup_node_count() {
  if declare -p NODE_HOSTS >/dev/null 2>&1; then
    printf '%s\n' "${#NODE_HOSTS[@]}"
  else
    printf '0\n'
  fi
}

clean_process_pattern_all_nodes() {
  local pattern="$1"
  local host

  if [ "$(_cleanup_node_count)" -eq 0 ]; then
    clean_process_pattern_local "${pattern}"
    return 0
  fi

  for host in "${NODE_HOSTS[@]}"; do
    local log_file="${RUN_DIR:-/tmp}/cleanup_${host}.log"
    if declare -F is_local_host >/dev/null 2>&1 && is_local_host "${host}"; then
      clean_process_pattern_local "${pattern}"
    elif declare -F remote_exec_timeout >/dev/null 2>&1; then
      remote_exec_timeout "${COMMAND_TIMEOUT:-10}" "${host}" "pgrep -af '${pattern}' || true; pkill -9 -f '${pattern}' || true" "${log_file}" || true
    fi
  done
}

mpi_tmp_cleanup_command() {
  cat <<'CLEAN_MPI_TMP'
rm -rf /tmp/openmpi-sessions-* /tmp/ompi.* /tmp/pmix-* 2>/dev/null || true
CLEAN_MPI_TMP
}

clean_mpi_tmp_local() {
  local log_file="${RUN_DIR:-/tmp}/cleanup_mpi_tmp_local.log"

  if [ "${PREFLIGHT_CLEAN_MPI_TMP:-0}" != "1" ]; then
    return 0
  fi

  {
    printf '[%s] clean local MPI temp dirs\n' "$(preflight_timestamp)"
    find /tmp -maxdepth 1 \( -name 'openmpi-sessions-*' -o -name 'ompi.*' -o -name 'pmix-*' \) -print 2>/dev/null || true
    bash -lc "$(mpi_tmp_cleanup_command)"
  } >> "${log_file}" 2>&1
}

clean_mpi_tmp_all_nodes() {
  local host

  if [ "${PREFLIGHT_CLEAN_MPI_TMP:-0}" != "1" ]; then
    return 0
  fi

  if [ "$(_cleanup_node_count)" -eq 0 ]; then
    clean_mpi_tmp_local
    return 0
  fi

  for host in "${NODE_HOSTS[@]}"; do
    local log_file="${RUN_DIR:-/tmp}/cleanup_mpi_tmp_${host}.log"
    if declare -F is_local_host >/dev/null 2>&1 && is_local_host "${host}"; then
      clean_mpi_tmp_local
    elif declare -F remote_exec_timeout >/dev/null 2>&1; then
      remote_exec_timeout "${COMMAND_TIMEOUT:-10}" "${host}" "$(mpi_tmp_cleanup_command)" "${log_file}" || true
    fi
  done
}

mpi_cleanup_pattern() {
  local pattern="[m]pirun|[o]rted|[p]rted"

  if [ "${PREFLIGHT_CLEAN_PMIX:-0}" = "1" ]; then
    pattern="${pattern}|[p]mix|p[m]ix"
  fi

  printf '%s\n' "${pattern}"
}

clean_mpi() {
  clean_marked_preflight_all_nodes
  if [ "${PREFLIGHT_CLEAN_LEGACY_PATTERNS:-0}" = "1" ]; then
    clean_process_pattern_all_nodes "$(mpi_cleanup_pattern)"
  fi
  clean_mpi_tmp_all_nodes
}

clean_nccl() {
  clean_marked_preflight_all_nodes
  if [ "${PREFLIGHT_CLEAN_LEGACY_PATTERNS:-0}" = "1" ]; then
    clean_process_pattern_all_nodes "[a]ll_reduce_perf"
  fi
}

clean_ray_temp() {
  clean_marked_preflight_all_nodes
  if [ "${PREFLIGHT_CLEAN_LEGACY_PATTERNS:-0}" = "1" ]; then
    clean_process_pattern_all_nodes "[r]ay::Preflight|[p]reflight_ray_temp"
  fi
}

clean_all() {
  section "Cleanup preflight residual processes"
  clean_mpi
  clean_nccl
  clean_ray_temp
}

show_residual_all_nodes() {
  local pattern="${1:-$(mpi_cleanup_pattern)|[a]ll_reduce_perf}"
  local host

  if [ "$(_cleanup_node_count)" -eq 0 ]; then
    pgrep -af "${pattern}" || true
    return 0
  fi

  for host in "${NODE_HOSTS[@]}"; do
    if declare -F is_local_host >/dev/null 2>&1 && is_local_host "${host}"; then
      printf '## %s\n' "${host}"
      pgrep -af "${pattern}" || true
    elif declare -F remote_exec_timeout >/dev/null 2>&1; then
      printf '## %s\n' "${host}"
      remote_exec_timeout "${COMMAND_TIMEOUT:-10}" "${host}" "pgrep -af '${pattern}' || true" "${RUN_DIR}/residual_${host}.log" || true
      cat "${RUN_DIR}/residual_${host}.log" 2>/dev/null || true
    fi
  done
}
