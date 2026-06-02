#!/usr/bin/env bash

ssh_base_args() {
  SSH_BASE_ARGS=(
    -p "${SSH_PORT:-22}"
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
    -o ConnectTimeout="${SSH_TIMEOUT:-5}"
    -o BatchMode=yes
  )
}

is_local_host() {
  local host="$1"
  local short
  local full

  short="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
  full="$(hostname 2>/dev/null || true)"

  [ "${host}" = "localhost" ] ||
    [ "${host}" = "127.0.0.1" ] ||
    [ "${host}" = "${short}" ] ||
    [ "${host}" = "${full}" ]
}

remote_exec() {
  local host_or_ip="$1"
  shift
  local command="$*"

  ssh_base_args
  ssh "${SSH_BASE_ARGS[@]}" "${host_or_ip}" "${command}"
}

remote_exec_timeout() {
  local timeout_sec="$1"
  local host_or_ip="$2"
  local command="$3"
  local log_file="${4:-}"

  if [ -z "${log_file}" ]; then
    log_file="${RUN_DIR:-/tmp}/remote_${host_or_ip}.log"
  fi

  ssh_base_args
  run_cmd "remote_exec_${host_or_ip}" "${timeout_sec}" "${log_file}" -- \
    ssh "${SSH_BASE_ARGS[@]}" "${host_or_ip}" "${command}"
}

_apply_etc_hosts_from_file_local() {
  local entries_file="$1"
  local tmp_file
  tmp_file="$(mktemp /tmp/preflight_hosts.XXXXXX)"

  awk '
    BEGIN { skip = 0 }
    /^# BEGIN AI_INFRA_PREFLIGHT$/ { skip = 1; next }
    /^# END AI_INFRA_PREFLIGHT$/ { skip = 0; next }
    skip == 0 { print }
  ' /etc/hosts > "${tmp_file}"

  {
    printf '# BEGIN AI_INFRA_PREFLIGHT\n'
    cat "${entries_file}"
    printf '# END AI_INFRA_PREFLIGHT\n'
  } >> "${tmp_file}"

  if [ "$(id -u)" -eq 0 ]; then
    cp "${tmp_file}" /etc/hosts
  elif command -v sudo >/dev/null 2>&1; then
    sudo -n cp "${tmp_file}" /etc/hosts
  else
    rm -f "${tmp_file}"
    return 1
  fi

  rm -f "${tmp_file}"
}

update_etc_hosts_all_nodes() {
  section "Update /etc/hosts"

  if [ "${#NODE_HOSTS[@]}" -eq 0 ]; then
    result_skip "update_etc_hosts" "no nodes loaded"
    return 0
  fi

  local entries_file="${RUN_DIR}/etc_hosts.entries"
  generate_etc_hosts_entries > "${entries_file}"

  local failures=0
  local host
  for host in "${NODE_HOSTS[@]}"; do
    local log_file="${RUN_DIR}/update_etc_hosts_${host}.log"

    if is_local_host "${host}"; then
      _apply_etc_hosts_from_file_local "${entries_file}" > "${log_file}" 2>&1
    else
      ssh_base_args
      local remote_script
      remote_script='tmp=$(mktemp /tmp/preflight_hosts.XXXXXX); cat > "$tmp"; out=$(mktemp /tmp/preflight_hosts_out.XXXXXX); awk '\''BEGIN { skip = 0 } /^# BEGIN AI_INFRA_PREFLIGHT$/ { skip = 1; next } /^# END AI_INFRA_PREFLIGHT$/ { skip = 0; next } skip == 0 { print }'\'' /etc/hosts > "$out"; { printf "%s\n" "# BEGIN AI_INFRA_PREFLIGHT"; cat "$tmp"; printf "%s\n" "# END AI_INFRA_PREFLIGHT"; } >> "$out"; if [ "$(id -u)" -eq 0 ]; then cp "$out" /etc/hosts; elif command -v sudo >/dev/null 2>&1; then sudo -n cp "$out" /etc/hosts; else rm -f "$tmp" "$out"; exit 1; fi; rm -f "$tmp" "$out"'
      run_cmd "update_etc_hosts_${host}" "${COMMAND_TIMEOUT:-20}" "${log_file}" -- \
        bash -c 'entries_file="$1"; shift; ssh "$@" < "${entries_file}"' \
        _ "${entries_file}" "${SSH_BASE_ARGS[@]}" "${host}" "${remote_script}"
    fi

    local rc=$?
    if [ "${rc}" -ne 0 ]; then
      failures=$((failures + 1))
      log_warn "failed to update /etc/hosts on ${host}; see ${log_file}"
    fi
  done

  if [ "${failures}" -eq 0 ]; then
    result_pass "update_etc_hosts" "managed block updated on ${#NODE_HOSTS[@]} node(s)"
  else
    result_warn "update_etc_hosts" "${failures} node(s) failed; see update_etc_hosts_*.log"
  fi
}
