# Human Usage Guide / 人工使用手册

这份文档说明在没有 Codex 的情况下，如何手动使用 AI Infra Preflight。

This guide explains how to use AI Infra Preflight without Codex.

## What This Tool Does / 这个工具做什么

AI Infra Preflight 用于在启动分布式 AI 任务之前做环境自检，提前发现缺少二进制、SSH 不通、网卡选择错误、OpenMPI OOB 路由异常、NCCL smoke test 失败、命令可能 hang 等问题。

AI Infra Preflight runs environment checks before launching distributed AI jobs.
It helps catch missing binaries, broken SSH, wrong network interfaces, OpenMPI
OOB routing issues, NCCL smoke failures, and commands that would otherwise hang.

检查分两层：

The tool has two layers:

```text
Capability check / 能力检查:
  Validate one component, such as NCCL or MPI.
  单独验证一个组件，例如 NCCL 或 MPI。

Integration check / 联调检查:
  Validate that components work together, such as NCCL over MPI.
  验证多个组件能否一起工作，例如 NCCL over MPI。
```

## Before You Run It / 运行前确认

联调检查请从 nodes 文件第一行对应的节点运行。该节点会被视为 master。

Run integration checks from the first node listed in your nodes file. That node
is treated as the master.

运行前确认：

Confirm these prerequisites:

```text
1. Bash 可用 / Bash is available.
2. master 可以 SSH 到所有 workers / SSH from master to all workers is configured.
3. SSH 端口配置正确 / The configured SSH port is correct.
4. 运行 MPI 检查时 mpirun 已安装 / mpirun is installed when running MPI checks.
5. 运行 NCCL smoke 时 all_reduce_perf 存在 / all_reduce_perf exists when running NCCL smoke tests.
6. 运行 NCCL 检查时 GPU 驱动和 CUDA/NCCL runtime 已安装 / GPU driver and CUDA/NCCL runtime are installed.
7. 明确是否要开启 UPDATE_ETC_HOSTS / You understand whether UPDATE_ETC_HOSTS should be enabled.
```

## Configure Nodes / 配置节点

创建或编辑 nodes 文件：

Create or edit a nodes file:

```text
configs/examples/nodes/two_nodes.nodes
```

格式：

Format:

```text
hostname ip slots
```

示例：

Example:

```text
host0 10.0.0.1 8
host1 10.0.0.2 8
```

规则：

Rules:

```text
1. 第一行有效节点是 master / The first valid line is the master.
2. 后续节点是 workers / Later lines are workers.
3. 空行和注释会被忽略 / Empty lines and comments are ignored.
4. MPI_NP 为空时，slots 会用于推导进程数 / slots controls MPI process count when MPI_NP is empty.
```

## Configure a Scenario / 配置场景

可以从这个示例开始：

Start from this example:

```text
configs/examples/nccl_mpi_smoke.env
```

至少需要按你的环境修改：

Edit at least these values for your environment:

```bash
NODES_FILE=configs/examples/nodes/two_nodes.nodes
SSH_PORT=22
UPDATE_ETC_HOSTS=0
NCCL_TEST_BIN=/opt/nccl-tests/build/all_reduce_perf
NCCL_SOCKET_IFNAME=bond0
CONTROL_IF_CIDR=10.0.0.0/24
```

只有在你希望工具在所有节点的 `/etc/hosts` 写入 managed block 时，才开启：

Enable this only when you want the tool to write a managed block into
`/etc/hosts` on all nodes:

```bash
UPDATE_ETC_HOSTS=1
```

该操作可能需要 root 或免密 sudo。

This may require root or passwordless sudo.

## Recommended Check Order / 推荐检查顺序

先跑小检查，再跑完整联调：

Run smaller checks before full integration:

```bash
bin/preflight nccl configs/examples/nccl_mpi_smoke.env
bin/preflight mpi configs/examples/nccl_mpi_smoke.env
bin/preflight nccl_mpi configs/examples/nccl_mpi_smoke.env
```

含义：

Meaning:

```text
nccl:
  检查本地 NCCL 相关能力。
  Checks local NCCL-related capability.

mpi:
  检查 mpirun、hostfile、本地 hostname launch、多机 hostname launch。
  Checks mpirun, hostfile, local hostname launch, and multinode hostname launch.

nccl_mpi:
  运行 SSH/network 检查、NCCL 检查、MPI 检查，然后运行 mpirun-launched NCCL。
  Runs SSH/network checks, NCCL checks, MPI checks, then mpirun-launched NCCL.
```

如果前面的 `mpi_*` 检查已经出现 `FAIL`，`nccl_mpi` 不会继续运行 NCCL over MPI 联调，而是把 `nccl_mpi_allreduce` 记录为 `SKIP`。这样可以保留第一次 MPI 失败作为主要诊断信息，避免同一个 MPI hang 再 timeout 一次。

If an earlier `mpi_*` check already recorded `FAIL`, `nccl_mpi` will not run the
NCCL over MPI integration test. It records `nccl_mpi_allreduce` as `SKIP` so the
first MPI failure remains the main diagnostic signal and the same MPI hang is
not timed out twice.

## Logs and Summary / 日志和 Summary

每次运行都会创建：

Each run creates:

```text
logs/<target>/<timestamp>/
```

重要文件：

Important files:

```text
preflight.log
summary.tsv
*.log
*.important.log
env.snapshot
nodes.snapshot
hostfile
```

最终 summary 会打印这些状态：

The final summary prints these statuses:

```text
PASS  检查成功 / The check succeeded.
FAIL  发现阻塞问题 / The check found a blocker.
WARN  可疑但不一定阻塞 / Suspicious but not always fatal.
SKIP  可选或不适用 / Optional or not applicable.
```

整体退出码：

Overall exit code:

```text
0  没有 FAIL / no FAIL rows
1  存在至少一个 FAIL / one or more FAIL rows
```

## Timeout Meaning / Timeout 含义

退出码 `124` 表示命令被 timeout 杀掉。对 `mpirun` 和 NCCL 来说，这通常意味着可能 hang。

Exit code `124` means timeout. For `mpirun` and NCCL, this usually means a
possible hang.

请查看对应的日志和 `*.important.log`：

Inspect the matching log file and any `*.important.log` file.

MPI hang 重点搜索：

For MPI hangs, look for:

```text
orte_hnp_uri
post no route
tcp:no route
final template argv
orted
prted
oob
```

然后阅读：

Then read:

```text
docs/troubleshooting/mpi_oob_network.md
docs/troubleshooting/nccl_mpi_hang.md
```

## Safe Cleanup / 安全清理

分布式检查会在运行前后清理带有 preflight 标记的进程。脚本启动的命令会带上：

Distributed checks clean processes marked by preflight. Commands launched by the
script carry:

```text
AI_INFRA_PREFLIGHT=1
PREFLIGHT_RUN_ID=<run_id>
```

默认不会按通用进程名杀 `mpirun`、`orted`、`prted`、`all_reduce_perf` 或 `pmix`。只有事故恢复时显式开启：

By default, cleanup does not kill generic `mpirun`, `orted`, `prted`,
`all_reduce_perf`, or `pmix` processes by name. Enable this only for incident
recovery:

```bash
PREFLIGHT_CLEAN_LEGACY_PATTERNS=1
```

legacy name-based cleanup targets:

```text
mpirun
orted
prted
pmix
all_reduce_perf
```

第一版不会默认杀用户已有的 Ray head 或 worker。

The first version does not kill a user's normal Ray head or worker by default.

默认 cleanup 不删除 `/tmp` 下的 OpenMPI/PMIx 临时目录。排障恢复时，如果确认当前用户没有其他 MPI 作业，可以在配置里设置：

By default, cleanup does not delete OpenMPI/PMIx temp directories under `/tmp`.
During incident recovery, after confirming there are no other MPI jobs for the
current user, set:

```bash
PREFLIGHT_CLEAN_MPI_TMP=1
```

## Common Runs / 常用命令

使用 smoke 配置：

Use the smoke config:

```bash
bin/preflight nccl_mpi configs/examples/nccl_mpi_smoke.env
```

使用 debug 配置，打开更详细的 MPI 日志：

Use the debug config with verbose MPI logging:

```bash
bin/preflight nccl_mpi configs/examples/nccl_mpi_debug.env
```

只运行 NCCL 单项检查：

Run only NCCL standalone checks:

```bash
bin/preflight capability:nccl configs/examples/nccl_mpi_smoke.env
```

只运行 MPI 检查：

Run only MPI checks:

```bash
bin/preflight capability:mpi configs/examples/nccl_mpi_smoke.env
```

## When a Check Fails / 检查失败时

按这个顺序处理：

Use this order:

```text
1. 先读最终 summary / Read the final summary.
2. 打开 FAIL message 里提到的日志 / Open the log file named in the FAIL message.
3. 如果有对应的 *.important.log，也打开 / Open the matching *.important.log if it exists.
4. 查 docs/troubleshooting/ 下的对应排障文档 / Check docs/troubleshooting/ for the failure type.
5. 修正配置或环境 / Fix config or environment.
6. 先重新跑最小失败目标 / Re-run the smallest failed target first.
```
