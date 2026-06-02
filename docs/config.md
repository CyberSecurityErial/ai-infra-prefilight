# Configuration

Configuration files are Bash env files. YAML and JSON are intentionally avoided
so the scripts can run in minimal cluster environments.

## Scenario Fields

```bash
TARGET=nccl_mpi
TEST_LEVEL=smoke
LOG_ROOT=logs
```

`TARGET` documents the intended scenario. The CLI target controls what actually
runs.

## Nodes

```bash
NODES_FILE=configs/examples/nodes/two_nodes.nodes
UPDATE_ETC_HOSTS=1
```

Nodes files use:

```text
hostname ip slots
```

The first valid node is the master. Remaining nodes are workers.

Integration checks assume the script is launched from the master node unless a
future integration explicitly documents a different launch model.

## Timeouts

```bash
COMMAND_TIMEOUT=20
MPI_TIMEOUT=25
NCCL_TIMEOUT=60
SSH_TIMEOUT=5
```

Commands that can hang must use a timeout. Exit code `124` means the timeout
killed the command.

## MPI Network Selection

```bash
CONTROL_IF_CIDR=10.104.144.0/21
CONTROL_IF_NAME=
MPI_DISABLE_OPENIB_BTL=1
MPI_NO_TREE_SPAWN=1
```

`CONTROL_IF_NAME` takes precedence over `CONTROL_IF_CIDR`. These values are used
to generate OpenMPI MCA parameters for OOB and TCP BTL interface selection.

## NCCL

```bash
NCCL_TEST_BIN=/opt/nccl-tests/build/all_reduce_perf
NCCL_DEBUG=INFO
NCCL_SOCKET_IFNAME=bond0
NCCL_MIN_BYTES=8M
NCCL_MAX_BYTES=128M
NCCL_STEP_FACTOR=2
NCCL_GPUS_PER_PROCESS=1
```

If `NCCL_TEST_BIN` is missing or not executable, binary and smoke checks are
reported as `SKIP` instead of `FAIL`. This allows framework-internal NCCL checks
to be added later without requiring nccl-tests.
