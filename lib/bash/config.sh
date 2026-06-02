#!/usr/bin/env bash

resolve_repo_path() {
  local path="$1"

  if [ -z "${path}" ]; then
    return 1
  fi

  if [ "${path#/}" != "${path}" ]; then
    printf '%s\n' "${path}"
    return 0
  fi

  if [ -f "${path}" ] || [ -d "${path}" ]; then
    (cd "$(dirname "${path}")" 2>/dev/null && printf '%s/%s\n' "$(pwd)" "$(basename "${path}")")
    return 0
  fi

  if [ -n "${CONFIG_DIR:-}" ] && { [ -f "${CONFIG_DIR}/${path}" ] || [ -d "${CONFIG_DIR}/${path}" ]; }; then
    (cd "$(dirname "${CONFIG_DIR}/${path}")" 2>/dev/null && printf '%s/%s\n' "$(pwd)" "$(basename "${CONFIG_DIR}/${path}")")
    return 0
  fi

  if [ -n "${ROOT_DIR:-}" ] && { [ -f "${ROOT_DIR}/${path}" ] || [ -d "${ROOT_DIR}/${path}" ]; }; then
    (cd "$(dirname "${ROOT_DIR}/${path}")" 2>/dev/null && printf '%s/%s\n' "$(pwd)" "$(basename "${ROOT_DIR}/${path}")")
    return 0
  fi

  printf '%s\n' "${path}"
}

load_config() {
  local env_file="$1"

  if [ -z "${env_file}" ]; then
    log_error "config file is required"
    return 1
  fi

  env_file="$(resolve_repo_path "${env_file}")"
  if [ ! -f "${env_file}" ]; then
    log_error "config file not found: ${env_file}"
    return 1
  fi

  CONFIG_FILE="${env_file}"
  CONFIG_DIR="$(cd "$(dirname "${env_file}")" && pwd)"
  export CONFIG_FILE CONFIG_DIR

  set -a
  # shellcheck disable=SC1090
  . "${env_file}"
  set +a

  default_var LOG_ROOT "logs"
  default_var COMMAND_TIMEOUT "20"
  default_var SSH_TIMEOUT "5"
  default_var SSH_PORT "22"
  default_var UPDATE_ETC_HOSTS "0"
  default_var PREFLIGHT_DEBUG "0"
  default_var PREFLIGHT_CLEAN_LEGACY_PATTERNS "0"
  default_var PREFLIGHT_CLEAN_SCOPE "all_preflight"

  log_info "loaded config: ${env_file}"
}

require_var() {
  local name="$1"
  local value
  eval "value=\"\${${name}:-}\""

  if [ -z "${value}" ]; then
    log_error "required config variable is empty: ${name}"
    return 1
  fi
}

default_var() {
  local name="$1"
  local default_value="$2"
  local value
  eval "value=\"\${${name}:-}\""

  if [ -z "${value}" ]; then
    eval "${name}=\"\${default_value}\""
    export "${name}"
  fi
}

init_run_dir() {
  local target="$1"
  local provided="${2:-}"
  local log_root

  if [ -n "${provided}" ]; then
    RUN_DIR="$(resolve_repo_path "${provided}")"
  else
    log_root="${LOG_ROOT:-logs}"
    if [ "${log_root#/}" = "${log_root}" ] && [ -n "${ROOT_DIR:-}" ]; then
      log_root="${ROOT_DIR}/${log_root}"
    fi
    RUN_DIR="${log_root}/${target}/$(date '+%Y%m%d_%H%M%S')"
  fi

  mkdir -p "${RUN_DIR}"
  PREFLIGHT_RUN_ID="${PREFLIGHT_RUN_ID:-$(basename "${RUN_DIR}")}"
  export RUN_DIR
  export PREFLIGHT_RUN_ID
  log_info "run_dir: ${RUN_DIR}"
}

write_env_snapshot() {
  local output_file="$1"
  mkdir -p "$(dirname "${output_file}")"
  env | sort > "${output_file}"
}
