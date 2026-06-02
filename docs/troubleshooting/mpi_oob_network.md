# OpenMPI OOB Network Selection

OpenMPI has an OOB control channel separate from the data path. On multi-NIC
machines it may automatically choose an unreachable interface.

Example failure mode:

```text
OpenMPI puts a 10.105.x.x address into orte_hnp_uri.
The worker-side orted cannot register back to the master.
mpirun appears to hang.
```

Important log keywords:

```text
orte_hnp_uri
adding 10.
post no route
tcp:no route
final template argv
orted
prted
oob
btl
```

Useful include parameters:

```bash
--mca oob_tcp_if_include 10.104.144.0/21
--mca btl_tcp_if_include 10.104.144.0/21
--mca btl ^openib
```

If include does not take effect, try excludes:

```bash
--mca oob_tcp_if_exclude 10.105.0.0/16,127.0.0.0/8
--mca btl_tcp_if_exclude 10.105.0.0/16,127.0.0.0/8
```

In this repository, set one of:

```bash
CONTROL_IF_NAME=bond0
CONTROL_IF_CIDR=10.104.144.0/21
```

`CONTROL_IF_NAME` has priority. These values are converted into OpenMPI MCA
arguments by `capabilities/mpi.sh`.
