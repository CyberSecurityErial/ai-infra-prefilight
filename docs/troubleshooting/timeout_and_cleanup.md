# Timeout and Cleanup

Distributed preflight checks should assume commands can hang. Every risky
command must run through:

```bash
run_cmd <check_name> <timeout_sec> <log_file> -- <command...>
```

The function writes stdout and stderr to the log file and returns the command
exit code. Exit code `124` means timeout.

## Process Cleanup

The current MPI and NCCL cleanup targets are:

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
