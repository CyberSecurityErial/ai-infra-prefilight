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
. "${ROOT_DIR}/lib/bash/remote.sh"
# shellcheck disable=SC1090
. "${ROOT_DIR}/lib/bash/nodes.sh"
# shellcheck disable=SC1090
. "${ROOT_DIR}/lib/bash/summary.sh"

network_defaults() {
  default_var COMMAND_TIMEOUT "20"
  default_var TCP_CALLBACK_PORT "29500"
}

_network_route_cmd() {
  local ip="$1"
  printf 'if command -v ip >/dev/null 2>&1; then ip route get %s; elif command -v route >/dev/null 2>&1; then route -n get %s 2>/dev/null || route get %s; else echo "no route tool"; exit 127; fi' "${ip}" "${ip}" "${ip}"
}

network_check_route_all_nodes() {
  if [ "${#NODE_HOSTS[@]}" -lt 2 ]; then
    result_skip "route_all_nodes" "less than two nodes"
    return 0
  fi

  local failures=0
  local master_host
  local master_ip
  local i

  master_host="$(get_master_host)"
  master_ip="$(get_master_ip)"

  for ((i = 1; i < ${#NODE_HOSTS[@]}; i++)); do
    local worker_host="${NODE_HOSTS[$i]}"
    local worker_ip="${NODE_IPS[$i]}"
    local log_file="${RUN_DIR}/route_master_to_${worker_host}.log"

    run_cmd "route_master_to_${worker_host}" "${COMMAND_TIMEOUT}" "${log_file}" -- \
      bash -lc "$(_network_route_cmd "${worker_ip}")"
    local rc=$?
    if [ "${rc}" -ne 0 ]; then
      failures=$((failures + 1))
    fi

    log_file="${RUN_DIR}/route_${worker_host}_to_master.log"
    if is_local_host "${worker_host}"; then
      run_cmd "route_${worker_host}_to_master" "${COMMAND_TIMEOUT}" "${log_file}" -- \
        bash -lc "$(_network_route_cmd "${master_ip}")"
      rc=$?
    else
      remote_exec_timeout "${COMMAND_TIMEOUT}" "${worker_host}" "$(_network_route_cmd "${master_ip}")" "${log_file}"
      rc=$?
    fi
    if [ "${rc}" -ne 0 ]; then
      failures=$((failures + 1))
    fi
  done

  if [ "${failures}" -eq 0 ]; then
    result_pass "route_all_nodes" "routes are available in both directions"
  else
    result_fail "route_all_nodes" "${failures} route check(s) failed"
  fi
}

network_check_ping_optional() {
  if [ "${RUN_PING_CHECK:-0}" != "1" ]; then
    result_skip "ping_all_nodes" "RUN_PING_CHECK is not enabled"
    return 0
  fi

  if [ "${#NODE_HOSTS[@]}" -lt 2 ]; then
    result_skip "ping_all_nodes" "less than two nodes"
    return 0
  fi

  local failures=0
  local i
  for ((i = 1; i < ${#NODE_IPS[@]}; i++)); do
    local ip="${NODE_IPS[$i]}"
    local log_file="${RUN_DIR}/ping_${NODE_HOSTS[$i]}.log"
    run_cmd "ping_${NODE_HOSTS[$i]}" "${COMMAND_TIMEOUT}" "${log_file}" -- \
      ping -c 1 "${ip}"
    local rc=$?
    if [ "${rc}" -ne 0 ]; then
      failures=$((failures + 1))
    fi
  done

  if [ "${failures}" -eq 0 ]; then
    result_pass "ping_all_nodes" "ping succeeded"
  else
    result_warn "ping_all_nodes" "${failures} ping check(s) failed; ICMP may be blocked"
  fi
}

_network_remote_has_cmd() {
  local host="$1"
  local cmd="$2"
  local log_file="${RUN_DIR}/has_${cmd}_${host}.log"

  if is_local_host "${host}"; then
    run_cmd "has_${cmd}_${host}" "${COMMAND_TIMEOUT}" "${log_file}" -- bash -lc "command -v ${cmd}"
  else
    remote_exec_timeout "${COMMAND_TIMEOUT}" "${host}" "command -v ${cmd}" "${log_file}"
  fi
}

_network_tcp_python_server() {
  local bind_ip="$1"
  local port="$2"
  local timeout_sec="$3"

  python3 -u -c '
import socket
import sys
bind_ip = sys.argv[1]
port = int(sys.argv[2])
timeout = int(sys.argv[3])
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.settimeout(timeout)
s.bind((bind_ip, port))
s.listen(1)
conn, addr = s.accept()
print("accepted %s:%s" % addr)
conn.sendall(b"preflight-ok\n")
conn.close()
s.close()
' "${bind_ip}" "${port}" "${timeout_sec}"
}

network_check_tcp_callback() {
  if [ "${#NODE_HOSTS[@]}" -lt 2 ]; then
    result_skip "tcp_callback" "less than two nodes"
    return 0
  fi

  local master_ip
  local port
  local worker
  local log_file
  local server_pid=""
  local failures=0

  master_ip="$(get_master_ip)"
  port="${TCP_CALLBACK_PORT:-29500}"
  worker="${NODE_HOSTS[1]}"
  log_file="${RUN_DIR}/tcp_callback.log"
  : > "${log_file}"

  if command -v python3 >/dev/null 2>&1; then
    _network_tcp_python_server "0.0.0.0" "${port}" "${COMMAND_TIMEOUT}" >> "${log_file}" 2>&1 &
    server_pid=$!
    sleep 1

    if _network_remote_has_cmd "${worker}" python3 >/dev/null 2>&1; then
      if is_local_host "${worker}"; then
        run_cmd "tcp_callback_client" "${COMMAND_TIMEOUT}" "${RUN_DIR}/tcp_callback_client.log" -- \
          python3 -c 'import socket, sys; s=socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=int(sys.argv[3])); print(s.recv(128).decode().strip()); s.close()' "${master_ip}" "${port}" "${COMMAND_TIMEOUT}"
      else
        remote_exec_timeout "${COMMAND_TIMEOUT}" "${worker}" "python3 -c 'import socket, sys; s=socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=int(sys.argv[3])); print(s.recv(128).decode().strip()); s.close()' ${master_ip} ${port} ${COMMAND_TIMEOUT}" "${RUN_DIR}/tcp_callback_client_${worker}.log"
      fi
    elif _network_remote_has_cmd "${worker}" nc >/dev/null 2>&1; then
      if is_local_host "${worker}"; then
        run_cmd "tcp_callback_client" "${COMMAND_TIMEOUT}" "${RUN_DIR}/tcp_callback_client.log" -- \
          nc -z -w "${COMMAND_TIMEOUT}" "${master_ip}" "${port}"
      else
        remote_exec_timeout "${COMMAND_TIMEOUT}" "${worker}" "nc -z -w ${COMMAND_TIMEOUT} ${master_ip} ${port}" "${RUN_DIR}/tcp_callback_client_${worker}.log"
      fi
    else
      kill "${server_pid}" >/dev/null 2>&1 || true
      wait "${server_pid}" >/dev/null 2>&1 || true
      result_skip "tcp_callback" "worker ${worker} has neither python3 nor nc"
      return 0
    fi

    local client_rc=$?
    wait "${server_pid}" >/dev/null 2>&1
    local server_rc=$?
    if [ "${client_rc}" -ne 0 ] || [ "${server_rc}" -ne 0 ]; then
      failures=1
    fi
  elif command -v nc >/dev/null 2>&1; then
    preflight_with_timeout "${COMMAND_TIMEOUT}" nc -l "${port}" >> "${log_file}" 2>&1 &
    server_pid=$!
    sleep 1

    if _network_remote_has_cmd "${worker}" nc >/dev/null 2>&1; then
      if is_local_host "${worker}"; then
        run_cmd "tcp_callback_client" "${COMMAND_TIMEOUT}" "${RUN_DIR}/tcp_callback_client.log" -- \
          nc -z -w "${COMMAND_TIMEOUT}" "${master_ip}" "${port}"
      else
        remote_exec_timeout "${COMMAND_TIMEOUT}" "${worker}" "nc -z -w ${COMMAND_TIMEOUT} ${master_ip} ${port}" "${RUN_DIR}/tcp_callback_client_${worker}.log"
      fi
      local client_rc=$?
      wait "${server_pid}" >/dev/null 2>&1 || true
      if [ "${client_rc}" -ne 0 ]; then
        failures=1
      fi
    else
      kill "${server_pid}" >/dev/null 2>&1 || true
      wait "${server_pid}" >/dev/null 2>&1 || true
      result_skip "tcp_callback" "worker ${worker} has no nc"
      return 0
    fi
  else
    result_skip "tcp_callback" "local node has neither python3 nor nc"
    return 0
  fi

  if [ "${failures}" -eq 0 ]; then
    result_pass "tcp_callback" "worker ${worker} can connect back to master ${master_ip}:${port}"
  else
    result_fail "tcp_callback" "callback failed; see ${log_file}"
  fi
}

capability_network_check() {
  section "Network capability check"
  network_defaults
  network_check_route_all_nodes
  network_check_ping_optional
  if [ "${RUN_TCP_CHECK:-1}" = "1" ]; then
    network_check_tcp_callback
  else
    result_skip "tcp_callback" "RUN_TCP_CHECK is disabled"
  fi
}

capability_network_main() {
  local config="${1:-}"
  local provided_run_dir="${2:-}"

  if [ -z "${config}" ]; then
    log_error "usage: bash capabilities/network.sh <config> [run_dir]"
    return 2
  fi

  load_config "${config}" || return 1
  TARGET="network"
  export TARGET
  init_run_dir "network" "${provided_run_dir}"
  result_init
  write_env_snapshot "${RUN_DIR}/env.snapshot"
  require_var NODES_FILE || return 1
  load_nodes "${NODES_FILE}" || return 1
  write_nodes_snapshot "${RUN_DIR}/nodes.snapshot"
  capability_network_check
  print_summary
  final_exit_code
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  capability_network_main "$@"
  exit $?
fi
