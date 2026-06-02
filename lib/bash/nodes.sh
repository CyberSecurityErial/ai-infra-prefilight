#!/usr/bin/env bash

NODE_HOSTS=()
NODE_IPS=()
NODE_SLOTS=()

load_nodes() {
  local nodes_file="$1"
  local line
  local host
  local ip
  local slots

  nodes_file="$(resolve_repo_path "${nodes_file}")"
  if [ ! -f "${nodes_file}" ]; then
    log_error "nodes file not found: ${nodes_file}"
    return 1
  fi

  NODE_HOSTS=()
  NODE_IPS=()
  NODE_SLOTS=()

  while IFS= read -r line || [ -n "${line}" ]; do
    line="${line%%#*}"
    if [ -z "$(printf '%s' "${line}" | tr -d '[:space:]')" ]; then
      continue
    fi

    set -- ${line}
    host="${1:-}"
    ip="${2:-}"
    slots="${3:-}"

    if [ -z "${host}" ] || [ -z "${ip}" ] || [ -z "${slots}" ]; then
      log_warn "skip invalid node line: ${line}"
      continue
    fi

    NODE_HOSTS+=("${host}")
    NODE_IPS+=("${ip}")
    NODE_SLOTS+=("${slots}")
  done < "${nodes_file}"

  if [ "${#NODE_HOSTS[@]}" -eq 0 ]; then
    log_error "no valid nodes found in ${nodes_file}"
    return 1
  fi

  NODES_FILE="${nodes_file}"
  export NODES_FILE
  log_info "loaded ${#NODE_HOSTS[@]} node(s) from ${nodes_file}"
}

get_master_host() {
  printf '%s\n' "${NODE_HOSTS[0]}"
}

get_master_ip() {
  printf '%s\n' "${NODE_IPS[0]}"
}

get_worker_hosts() {
  local i
  for ((i = 1; i < ${#NODE_HOSTS[@]}; i++)); do
    printf '%s\n' "${NODE_HOSTS[$i]}"
  done
}

get_worker_ips() {
  local i
  for ((i = 1; i < ${#NODE_IPS[@]}; i++)); do
    printf '%s\n' "${NODE_IPS[$i]}"
  done
}

get_all_hosts() {
  printf '%s\n' "${NODE_HOSTS[@]}"
}

get_all_ips() {
  printf '%s\n' "${NODE_IPS[@]}"
}

get_total_slots() {
  local total=0
  local slots
  for slots in "${NODE_SLOTS[@]}"; do
    total=$((total + slots))
  done
  printf '%s\n' "${total}"
}

generate_etc_hosts_entries() {
  local i
  for ((i = 0; i < ${#NODE_HOSTS[@]}; i++)); do
    printf '%s %s\n' "${NODE_IPS[$i]}" "${NODE_HOSTS[$i]}"
  done
}

generate_mpi_hostfile() {
  local hostfile="$1"
  local i

  mkdir -p "$(dirname "${hostfile}")"
  : > "${hostfile}"

  for ((i = 0; i < ${#NODE_HOSTS[@]}; i++)); do
    printf '%s slots=%s\n' "${NODE_HOSTS[$i]}" "${NODE_SLOTS[$i]}" >> "${hostfile}"
  done
}

write_nodes_snapshot() {
  local output_file="$1"
  mkdir -p "$(dirname "${output_file}")"
  {
    printf 'hostname\tip\tslots\n'
    local i
    for ((i = 0; i < ${#NODE_HOSTS[@]}; i++)); do
      printf '%s\t%s\t%s\n' "${NODE_HOSTS[$i]}" "${NODE_IPS[$i]}" "${NODE_SLOTS[$i]}"
    done
  } > "${output_file}"
}
