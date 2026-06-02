# Timeout and Cleanup

Distributed preflight checks should assume commands can hang. Every risky
command must run through:

```bash
run_cmd <check_name> <timeout_sec> <log_file> -- <command...>
```

The function writes stdout and stderr to the log file and returns the command
exit code. Exit code `124` means timeout.

## Process Cleanup

Every command launched through `run_cmd` receives marker environment variables:

```text
AI_INFRA_PREFLIGHT=1
PREFLIGHT_RUN_ID=<run directory timestamp>
```

MPI-based checks also export those markers through `mpirun -x` so remote ranks
can be identified. Cleanup normally removes only marked preflight processes.

Cleanup scope is controlled by:

```bash
PREFLIGHT_CLEAN_SCOPE=all_preflight
```

Supported values:

```text
all_preflight  clean any AI_INFRA_PREFLIGHT=1 process left by this tool
current_run    clean only processes with this run's PREFLIGHT_RUN_ID
```

Legacy name-based cleanup is disabled by default. Enable it only for incident
recovery or for cleaning processes left by older preflight versions that did not
carry markers:

```bash
PREFLIGHT_CLEAN_LEGACY_PATTERNS=1
```

When legacy cleanup is explicitly enabled, the MPI and NCCL name-based cleanup
targets are:

```text
mpirun
orted
prted
all_reduce_perf
```

`pmix` is not cleaned by default because that pattern can be too broad on some
systems. If a specific environment needs PMIx cleanup for preflight-only
residuals, enable it explicitly:

```bash
PREFLIGHT_CLEAN_PMIX=1
```

OpenMPI and PMIx temp directories are also not removed by default. During
incident recovery, after confirming no unrelated MPI jobs are running for the
same user, enable:

```bash
PREFLIGHT_CLEAN_MPI_TMP=1
```

This removes:

```text
/tmp/openmpi-sessions-*
/tmp/ompi.*
/tmp/pmix-*
```

Cleanup functions:

```text
clean_mpi
clean_nccl
clean_all
show_residual_all_nodes
```

`clean_ray_temp` is intentionally limited to preflight temporary Ray patterns.
It does not kill a user's existing Ray head or worker by default.

## Why Cleanup Matters

Residual MPI daemons or NCCL test processes can make later checks fail or pass
for the wrong reason. The expected pattern is:

```text
clean
run distributed check with timeout
extract important log lines
clean
record result
```
