# Codex Usage Guide

This document tells Codex how to use and extend AI Infra Preflight without
breaking the repository design.

## Context Loading Rule

Do not read all docs by default. Start with:

```text
docs/README.md
```

Then read only what the task needs:

```text
Run existing check:
  docs/codex_usage.md
  docs/human_usage.md if command behavior is unclear

Change module boundaries or add a module:
  docs/design.md
  docs/capability_modules.md or docs/integration_modules.md

Debug NCCL over MPI:
  docs/troubleshooting/nccl_mpi_hang.md
  docs/troubleshooting/mpi_oob_network.md
  docs/troubleshooting/timeout_and_cleanup.md
```

## Running Existing Checks

Prefer the CLI:

```bash
bin/preflight nccl configs/examples/nccl_mpi_smoke.env
bin/preflight mpi configs/examples/nccl_mpi_smoke.env
bin/preflight nccl_mpi configs/examples/nccl_mpi_smoke.env
```

Use explicit forms when clarity matters:

```bash
bin/preflight capability:nccl configs/examples/nccl_mpi_smoke.env
bin/preflight integration:nccl_mpi configs/examples/nccl_mpi_smoke.env
```

Do not run integration checks casually on a local development machine. They may
SSH nodes, update `/etc/hosts` when enabled, start distributed processes, and
kill residual preflight MPI/NCCL processes.

## Before Running Cluster Checks

Check the config first:

```bash
sed -n '1,220p' configs/examples/nccl_mpi_smoke.env
sed -n '1,120p' configs/examples/nodes/two_nodes.nodes
```

Confirm:

```text
1. The command is being run from the master node.
2. NODES_FILE points to the intended hosts.
3. SSH_PORT and SSH_TIMEOUT are correct.
4. UPDATE_ETC_HOSTS is intentionally enabled or disabled.
5. NCCL_TEST_BIN points to the real all_reduce_perf binary.
6. NCCL_SOCKET_IFNAME and CONTROL_IF_* match reachable interfaces.
7. Timeouts are long enough for the environment.
```

## Extension Boundary Rules

When implementing a new request, classify it first:

```text
Single component check:
  capabilities/<component>.sh

Cross-component launch or communication check:
  integrations/<path>.sh

Generic helper:
  lib/bash/<area>.sh

Config example:
  configs/examples/<scenario>.env

Troubleshooting knowledge:
  docs/troubleshooting/<topic>.md
```

Do not put reusable standalone checks inside an integration module. For example,
NCCL binary, NCCL env, and single-process NCCL checks belong in
`capabilities/nccl.sh`, even if the incident was found while debugging
`nccl_mpi`.

## Required Shape for New Capability Modules

A capability module should support:

```bash
bash capabilities/<name>.sh <config> [run_dir]
```

It should expose:

```text
capability_<name>_main
capability_<name>_check
```

Each concrete check should:

```text
1. write a dedicated log file under RUN_DIR
2. use run_cmd or preflight_with_timeout when it can hang
3. record exactly one result row with result_pass/fail/warn/skip
4. avoid exiting the whole script on individual check failure
```

## Required Shape for New Integration Modules

An integration module should:

```text
1. source shared libraries
2. source only the needed capability modules
3. load config and initialize RUN_DIR
4. load nodes when topology is needed
5. run clean_all or targeted cleanup before distributed tests
6. call capability checks
7. run only integration-specific tests
8. extract important log lines when useful
9. clean again after distributed tests
10. print summary and return final_exit_code
```

## Verification After Edits

Always run syntax checks after changing Bash:

```bash
bash -lc 'for f in bin/preflight lib/bash/*.sh capabilities/*.sh integrations/*.sh; do bash -n "$f" || exit 1; done'
```

For low-risk local validation, prefer checks that do not mutate remote state:

```bash
bin/preflight nccl configs/examples/nccl_mpi_smoke.env
```

Run MPI or integration checks only when the user expects cluster-side actions:

```bash
bin/preflight mpi configs/examples/nccl_mpi_smoke.env
bin/preflight nccl_mpi configs/examples/nccl_mpi_smoke.env
```

## Reporting Results

When reporting to the user, include:

```text
1. what changed
2. which files matter
3. which verification commands ran
4. which commands were not run and why
5. where logs are written when runtime checks were executed
```

If a check fails with exit code `124`, say it timed out and point to the relevant
log file. For OpenMPI hangs, point to `*.important.log` and the OOB docs.
