# AI Infra Preflight

AI Infra Preflight 用来沉淀分布式 AI 基础设施的环境自检流程。它把检查分成两层：

1. 能力检查：单独验证一个组件，例如 NCCL、MPI、Ray、torchrun、SSH 或网络路由。
2. 联调检查：验证多个组件能否一起工作，例如 NCCL over MPI、NCCL over Ray、NCCL over torchrun。

AI Infra Preflight records reusable environment checks for distributed AI
runtime stacks. It separates checks into two layers:

1. Capability checks validate one component in isolation, such as NCCL, MPI,
   Ray, torchrun, SSH, or network routing.
2. Integration checks validate that two or more components work together, such
   as NCCL over MPI, NCCL over Ray, or NCCL over torchrun.

核心模型：

```text
nccl_mpi.sh      = nccl.sh + mpi.sh + nccl over mpi integration
nccl_ray.sh      = nccl.sh + ray.sh + nccl over ray integration
nccl_torchrun.sh = nccl.sh + torchrun.sh + nccl over torchrun integration
nccl_srun.sh     = nccl.sh + slurm.sh + nccl over srun integration
```

The key model is that integration scripts reuse independent capability modules
and add only the cross-component smoke test.

## Quick Start / 快速开始

联调检查建议从 `NODES_FILE` 第一行对应的节点运行；该节点会被视为 master。单项能力检查，例如 `nccl`，可以在本地直接运行。

Run integration checks from the first node in `NODES_FILE`, which is treated as
the master. Single capability checks such as `nccl` can be run locally.

```bash
bin/preflight nccl configs/examples/nccl_mpi_smoke.env
bin/preflight mpi configs/examples/nccl_mpi_smoke.env
bin/preflight nccl_mpi configs/examples/nccl_mpi_smoke.env
```

也支持显式目标写法：

Explicit target names are also supported:

```bash
bin/preflight capability:nccl configs/examples/nccl_mpi_smoke.env
bin/preflight capability:mpi configs/examples/nccl_mpi_smoke.env
bin/preflight integration:nccl_mpi configs/examples/nccl_mpi_smoke.env
```

## Documentation / 文档

先看总索引：[docs/README.md](docs/README.md)。

Start from the documentation index: [docs/README.md](docs/README.md).

常用入口：

Common entry points:

```text
人手动使用 / Manual usage:
  docs/human_usage.md

Codex 使用和扩展 / Codex usage and extension:
  docs/codex_usage.md

设计边界 / Design boundaries:
  docs/design.md

配置说明 / Configuration:
  docs/config.md

NCCL over MPI hang 排查 / NCCL over MPI hang troubleshooting:
  docs/troubleshooting/nccl_mpi_hang.md
  docs/troubleshooting/mpi_oob_network.md
```

## Repository Layout / 仓库结构

```text
bin/preflight                  CLI dispatcher / CLI 分发入口
capabilities/                  Single-component checks / 单项能力检查
integrations/                  Cross-component checks / 组合联调检查
lib/bash/                      Shared Bash libraries / Bash 公共库
configs/templates/             Config templates / 配置模板
configs/examples/              Example configs and node files / 示例配置和节点文件
docs/                          Design, usage, and troubleshooting docs / 文档
logs/                          Runtime logs and summaries / 运行日志和 summary
```

## Current Coverage / 当前覆盖范围

第一版已完整实现：

Complete in the first version:

```text
capabilities/nccl.sh
capabilities/mpi.sh
capabilities/ssh.sh
capabilities/network.sh
integrations/nccl_mpi.sh
```

第一版只做结构 stub：

Stubbed for future implementation:

```text
capabilities/ray.sh
capabilities/torchrun.sh
capabilities/slurm.sh
integrations/nccl_ray.sh
integrations/nccl_torchrun.sh
integrations/nccl_srun.sh
```

## Safety Rules / 安全规则

所有可能 hang 的命令都必须带 timeout。分布式测试前后会清理 preflight 可能拉起的 MPI/NCCL 残留进程。每个检查都会写日志，并在 `summary.tsv` 中记录结果。

All commands that can hang must run with a timeout. Distributed tests clean
preflight-related MPI/NCCL residual processes before and after each run. Every
check writes logs and records a result row in `summary.tsv`.

`124` 表示命令被 timeout 杀掉。对 `mpirun` 和 NCCL 来说，这通常意味着可能 hang，需要查看对应的 `*.log` 和 `*.important.log`。

Exit code `124` means the timeout killed the command. For `mpirun` and NCCL
tests, this usually means a possible hang. Inspect the matching `*.log` and
`*.important.log` files.

## Nodes File / 节点文件

节点文件独立于场景配置，格式如下：

Nodes are configured separately from scenario env files:

```text
hostname ip slots
```

规则：

Rules:

```text
1. 空行和注释会被忽略 / Empty lines and comments are ignored.
2. 第一行有效节点是 master / The first valid node is the master.
3. 后续节点是 workers / Remaining nodes are workers.
4. slots 用于推导默认 MPI_NP / slots are used to derive MPI_NP when MPI_NP is empty.
```

示例：

Example:

```text
yj-arsenalk8sgpu-191 10.104.148.227 1
yj-arsenalk8sgpu-223 10.104.149.18 1
```

## Boundary Rule / 边界规则

`nccl.sh` 不能依赖 `mpi.sh`。`mpi.sh` 不能依赖 `nccl.sh`。只有 integration 模块可以组合 capability 模块。

`nccl.sh` must not depend on `mpi.sh`. `mpi.sh` must not depend on `nccl.sh`.
Only integration modules combine capability modules.
