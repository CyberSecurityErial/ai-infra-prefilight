# Integration Modules

Integration modules combine capability modules and then run cross-component
smoke tests.

## NCCL over MPI

`integrations/nccl_mpi.sh` runs:

```text
1. cleanup
2. optional /etc/hosts update
3. SSH capability checks
4. network capability checks
5. NCCL capability checks
6. MPI capability checks
7. mpirun-launched nccl-tests all_reduce_perf
8. cleanup
9. summary
```

The integration command is:

```bash
bin/preflight nccl_mpi configs/examples/nccl_mpi_smoke.env
```

The NCCL over MPI test uses:

```text
mpirun <mpi args> -x NCCL_DEBUG=... -x NCCL_SOCKET_IFNAME=... all_reduce_perf ...
```

If any previous `mpi_*` check records `FAIL`, the integration allreduce is not
run. The script records:

```text
nccl_mpi_allreduce  SKIP  skipped because MPI prerequisite failed: ...
```

This avoids timing out the same broken MPI launcher path twice.

## Future Integrations

`nccl_ray.sh`, `nccl_torchrun.sh`, and `nccl_srun.sh` are stubs in the first
version. Their structure already reflects the intended reuse:

```text
nccl_ray.sh      = capabilities/nccl.sh + capabilities/ray.sh + Ray NCCL smoke
nccl_torchrun.sh = capabilities/nccl.sh + capabilities/torchrun.sh + torchrun NCCL smoke
nccl_srun.sh     = capabilities/nccl.sh + capabilities/slurm.sh + srun NCCL smoke
```
