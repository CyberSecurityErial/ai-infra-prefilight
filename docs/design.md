# Design

AI Infra Preflight uses two layers.

This document is the design contract for the repository. Read it before changing
module boundaries, adding new capability modules, or adding new integration
paths.

## Non-Negotiable Boundaries

Keep these rules intact:

```text
1. A capability module checks one component in isolation.
2. An integration module combines capability modules and adds cross-component tests.
3. A lower-level capability must not source or depend on an integration module.
4. NCCL standalone checks belong in capabilities/nccl.sh.
5. MPI standalone checks belong in capabilities/mpi.sh.
6. Launcher-specific NCCL tests belong in integrations/<path>.sh.
7. Every possibly hanging command must use run_cmd or preflight_with_timeout.
8. Distributed checks must clean residual processes before and after the check.
9. Every check must append one result row to summary.tsv.
10. Node count must come from NODES_FILE, not from script names or hard-coded paths.
11. Integration-only tests should not run when a required capability already failed.
12. Cleanup patterns must be narrow and must not kill shared cluster services by default.
```

The most important example:

```text
Correct:
  nccl_mpi.sh = nccl.sh + mpi.sh + nccl over mpi test

Incorrect:
  nccl_mpi.sh contains a private copy of NCCL standalone checks
```

## Capability Layer

Capability modules answer one question: can this component work by itself?

```text
capabilities:
  nccl.sh        independent
  mpi.sh         independent
  ray.sh         independent
  torchrun.sh    independent
  slurm.sh       independent
  ssh.sh         independent
  network.sh     independent
```

Examples:

```text
nccl.sh:
  - checks the nccl-tests binary
  - checks NCCL environment variables
  - checks libnccl visibility when ldconfig exists
  - runs a single-process NCCL smoke test when possible

mpi.sh:
  - checks mpirun
  - checks MPI daemon visibility
  - generates a hostfile from NODES_FILE
  - runs local and multinode hostname tests
```

## Integration Layer

Integration modules combine capability modules and add only cross-component
tests.

```text
integrations:
  nccl_mpi.sh
    depends on: nccl.sh, mpi.sh, ssh.sh, network.sh

  nccl_ray.sh
    depends on: nccl.sh, ray.sh

  nccl_torchrun.sh
    depends on: nccl.sh, torchrun.sh

  nccl_srun.sh
    depends on: nccl.sh, slurm.sh
```

The important boundary is that NCCL standalone logic belongs in
`capabilities/nccl.sh`, not in `integrations/nccl_mpi.sh`. That lets future
paths such as NCCL over Ray and NCCL over torchrun reuse the same NCCL checks.

## Capability Module Contract

Each capability module must support direct execution:

```bash
bash capabilities/<name>.sh <config> [run_dir]
```

Each capability module should expose:

```text
capability_<name>_main
capability_<name>_check
```

The `main` function handles CLI-style setup. The `check` function assumes common
libraries, config, `RUN_DIR`, and summary initialization are already available.
Integration modules call only the `check` function.

Capability modules may use shared libraries from `lib/bash`. They should not
source other capability modules unless the component is genuinely a sub-part of
the same capability. Prefer keeping modules independent.

## Integration Module Contract

Each integration module must support direct execution:

```bash
bash integrations/<name>.sh <config> [run_dir]
```

An integration module may:

```text
1. Initialize config, run_dir, nodes, logs, and summary.
2. Run shared pre-checks such as ssh and network checks.
3. Call capability_<name>_check functions.
4. Run integration-only commands that prove components work together.
5. Print summary and return the final exit code.
```

An integration module must not duplicate reusable checks from capability modules.
If a check would be useful for another launcher or integration path, move it into
the relevant capability module.

Integration modules should gate expensive or hang-prone cross-component tests on
their required capability checks. For example, `nccl_mpi.sh` records
`nccl_mpi_allreduce` as `SKIP` when any previous `mpi_*` check has already
failed. That keeps the first failure as the useful diagnostic signal and avoids
running the same broken launcher path twice.

## Execution Model

Each target creates a run directory:

```text
logs/<target>/<timestamp>/
```

Every check writes logs into that directory and appends a row to:

```text
summary.tsv
```

The summary format is:

```text
check_name<TAB>status<TAB>message
```

Statuses are `PASS`, `FAIL`, `WARN`, and `SKIP`. Any `FAIL` makes the overall
exit code `1`; otherwise the exit code is `0`.

## Result Semantics

Use statuses consistently:

```text
PASS  The check ran and proved the expected capability.
FAIL  The check ran or was required, and the result indicates a real problem.
WARN  The check found a suspicious condition but not a hard blocker.
SKIP  The check is intentionally not applicable or lacks optional tooling.
```

Examples:

```text
NCCL_TEST_BIN missing       SKIP for nccl_binary, because framework NCCL may still be checked later.
mpirun missing              FAIL for mpi_binary_local, because MPI capability cannot run.
ldconfig missing            SKIP for nccl_ldconfig, because ldconfig is optional.
command timeout exit 124    FAIL for required smoke tests, because it indicates a possible hang.
```

## Extension Checklist

Before adding a new check, decide where it belongs:

```text
Question: Does it validate one component by itself?
Answer:   Put it in capabilities/<component>.sh.

Question: Does it validate two or more components working together?
Answer:   Put it in integrations/<path>.sh.

Question: Is it generic logging, config, timeout, remote, cleanup, nodes, or summary behavior?
Answer:   Put it in lib/bash/<area>.sh.

Question: Is it only a troubleshooting note?
Answer:   Put it in docs/troubleshooting/.
```

When adding a new integration, prefer this shape:

```text
1. source shared libraries
2. source required capability modules
3. load config
4. init run_dir and result summary
5. load nodes when needed
6. clean before distributed work
7. run independent capability checks
8. run integration-specific smoke test
9. extract important log lines
10. clean after distributed work
11. print summary and final exit code
```

## Anti-Patterns

Avoid these changes:

```text
1. Copying NCCL checks into nccl_mpi.sh, nccl_ray.sh, or nccl_torchrun.sh.
2. Making nccl.sh source mpi.sh, ray.sh, torchrun.sh, or slurm.sh.
3. Making mpi.sh know about NCCL_TEST_BIN or NCCL_* variables.
4. Running mpirun, nccl-tests, ssh, route, or remote commands without timeout.
5. Adding a distributed test without pre-clean and post-clean.
6. Recording logs but not summary rows.
7. Hard-coding two nodes in code.
8. Requiring YAML, JSON, jq, Python, or other optional tools for core Bash flow.
9. Killing user-owned long-running services such as Ray head/worker by default.
10. Killing broad shared runtime processes such as all `pmix` processes by default.
11. Treating debug-only verbose output as a required pass condition.
```

## Compatibility Bias

The scripts are intentionally plain Bash. Prefer common POSIX-ish tools and
feature checks. If a tool may not exist, detect it and return `SKIP` or `WARN`
instead of making it a hard dependency.

Use Bash arrays for command arguments that may contain spaces. This is especially
important for OpenMPI SSH arguments.
