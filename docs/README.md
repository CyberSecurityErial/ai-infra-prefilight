# Documentation Index / 文档索引

这个页面是人和 Codex 的文档入口。请按任务只阅读需要的文档，不要默认把所有文档都读进上下文。

This page is the documentation entry for humans and Codex. Read only the
document that matches the task. Do not load every document into context by
default.

## Start Here / 从这里开始

```text
需要理解仓库边界再改代码 / Understand boundaries before editing:
  docs/design.md

需要手动在集群上使用 / Use the tool manually on a cluster:
  docs/human_usage.md

需要 Codex 运行或扩展工具 / Ask Codex to run or extend the tool:
  docs/codex_usage.md

需要调整配置 / Tune config values:
  docs/config.md

需要理解 capability 模块 / Understand capability modules:
  docs/capability_modules.md

需要理解 integration 模块 / Understand integration modules:
  docs/integration_modules.md

需要排查 NCCL over MPI hang / Debug NCCL over MPI hangs:
  docs/troubleshooting/nccl_mpi_hang.md
  docs/troubleshooting/mpi_oob_network.md
  docs/troubleshooting/timeout_and_cleanup.md
```

## Reading Strategy / 阅读策略

普通人工使用：

For normal manual runs:

```text
1. README.md
2. docs/human_usage.md
3. 修改配置时再看 docs/config.md
4. 失败时再看 troubleshooting 文档
```

Codex 扩展任务：

For Codex extension tasks:

```text
1. docs/codex_usage.md
2. docs/design.md
3. 只读相关 module 文档
4. 只读相关 troubleshooting 文档
```

代码审查：

For code review:

```text
1. docs/design.md
2. changed capability or integration module
3. docs/codex_usage.md extension checklist
```

## Document Purposes / 文档用途

`docs/design.md`

中文：设计边界契约，说明哪些逻辑必须保持独立、新逻辑应该放在哪里、哪些反模式要避免。

English: The design contract. It defines module boundaries, placement rules, and
anti-patterns.

`docs/codex_usage.md`

中文：Codex 操作指南，说明如何运行工具、如何按边界扩展、如何验证和汇报结果。

English: The Codex operating guide. It explains how to run, extend, verify, and
report results.

`docs/human_usage.md`

中文：人工使用手册，说明前置条件、配置、运行顺序、日志解读和常见安全注意事项。

English: The manual runbook. It explains prerequisites, config, execution order,
log interpretation, and safety notes.

`docs/config.md`

中文：配置文件和 nodes 文件说明。

English: Env file and nodes file reference.

`docs/capability_modules.md`

中文：单项能力检查模块说明。

English: Component-level capability module reference.

`docs/integration_modules.md`

中文：组合联调模块说明，例如 NCCL over MPI。

English: Integration module reference, such as NCCL over MPI.

`docs/troubleshooting/`

中文：排障经验沉淀。

English: Incident-shaped troubleshooting knowledge.

## Bilingual Policy / 双语策略

面向人直接使用的入口文档保持中英文双语，包括 `README.md`、`docs/README.md` 和 `docs/human_usage.md`。

Human-facing entry documents are bilingual: `README.md`, `docs/README.md`, and
`docs/human_usage.md`.

Codex 专用或工程细节文档可以偏英文，但新增面向用户的 runbook、FAQ、排障说明时，建议中英文双语。

Codex-specific and engineering-detail documents may stay primarily English, but
new user-facing runbooks, FAQs, and troubleshooting docs should be bilingual.
