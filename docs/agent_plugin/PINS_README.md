# 智能体当前源码与历史 pin

`CURRENT_DELIVERY_SHA256.json` 才是当前合并工程的交付源码清单，所有键相对于工程根，包含宿主代码、模型、案例、实验资源、当前脚本、测试与本目录文档，不指向未交付的历史报告。

在工程根执行 `python -B scripts/freeze_plugin_manifests.py` 做只读校验；改动/缺失/新增文件会失败。`--write` 是显式重新冻结，不是验证旧版本。清单自身不参与自身哈希。

原 `DELIVERY_SHA256.json` / `UPSTREAM_HASHES.json`、`UPSTREAM_VERIFICATION.json`、`UPSTREAM_MODEL_EVALUATION.json` 仅保留上游历史来源。原始 pin 中的同名 README、脚本和文档已经发生布局或实现变化，不能按当前工程根直接解析，也不应在本次修复中改写历史哈希。

2026-10-20 的 `host/defense_runtime.py` 和统一顶层联动脚本属于当前源码清单：原智能体通过 `investigate()` 消费同一实际测量窗口和报文，并读取硬件推理/拟态记录。它的策略建议仍不自动修改设备授权，实际 AI 限时阻断由独立可信使能的 RTL 执行。

`reports/release_agent_final_20261015/`、`AFDX_AI_Extensions_R2` 训练树及上游冻结证据未随本工程交付，历史指标不能本机重算。当前模型推理、宿主测试、十案例闭环和可用的隔离 RTL 实验，应生成新的运行目录与原始日志；缺工具的实验必须标为不可用，不能认作通过。
