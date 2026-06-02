# NCCL over MPI Hang Troubleshooting

Do not start by running nccl-tests. Check the stack from the bottom up:

```text
1. /etc/hosts and hostname resolution
2. ssh master self
3. ssh worker
4. route master -> worker
5. route worker -> master
6. tcp callback worker -> master
7. mpirun local hostname
8. mpirun multinode hostname
9. mpirun-launched nccl-tests
```

This order separates launcher problems from NCCL problems. If `mpirun hostname`
hangs, NCCL is not the first thing to debug.

## Timeout Semantics

Exit code `124` means the timeout killed the command. For `mpirun` and NCCL,
`124` usually means a possible hang.

Look at:

```text
logs/<target>/<timestamp>/*.log
logs/<target>/<timestamp>/*.important.log
```

## Cleanup Rules

Run cleanup before and after distributed tests:

```bash
pkill -9 -f "mpirun|orted|prted|pmix|all_reduce_perf"
```

The implementation uses safer bracketed patterns such as `[m]pirun` so the
cleanup command is less likely to match itself.

Cleanup must run on workers as well as the master. Residual `orted`, `prted`,
`pmix`, or `all_reduce_perf` processes can make the next check misleading.

## Common Split Point

If these pass:

```text
ssh_workers
route_all_nodes
tcp_callback
mpi_local_hostname
```

but this times out:

```text
mpi_multinode_hostname
```

inspect MPI OOB control channel selection before debugging NCCL.

If `mpi_multinode_hostname` passes and only this fails:

```text
nccl_mpi_allreduce
```

then focus on NCCL interface selection, GPU visibility, driver/runtime
compatibility, and `NCCL_SOCKET_IFNAME`.
