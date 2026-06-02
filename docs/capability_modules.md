# Capability Modules

Capability modules can be run directly:

```bash
bash capabilities/nccl.sh configs/examples/nccl_mpi_smoke.env
bash capabilities/mpi.sh configs/examples/nccl_mpi_smoke.env
```

They can also be sourced by integration modules. Each module provides:

```text
capability_<name>_main
capability_<name>_check
```

## NCCL

`capabilities/nccl.sh` checks:

```text
nccl_binary
nccl_env
nccl_ldconfig
nccl_gpu_info
nccl_single_process
```

It does not depend on MPI, Ray, torchrun, Slurm, SSH, or a launcher.

## MPI

`capabilities/mpi.sh` checks:

```text
mpi_binary_local
mpi_version_local
mpi_binary_remote
mpi_hostfile
mpi_local_hostname
mpi_multinode_hostname
```

It does not depend on NCCL. OpenMPI arguments are generated from config values
and kept in Bash arrays so SSH argument strings remain intact.

## SSH

`capabilities/ssh.sh` checks local hostname resolution, SSH to the master, and
SSH to workers.

## Network

`capabilities/network.sh` checks route visibility and an optional worker to
master TCP callback. The callback uses `python3` when available, falls back to
`nc`, and reports `SKIP` when neither tool is available.
