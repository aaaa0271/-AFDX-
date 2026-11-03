# 拟态源码与历史证据清单

## 当前交付

- `mimic_plugin/RELEASE_MANIFEST.json`：相对于插件根的当前源码、测试、案例与资源，不包含运行输出。
- 本目录 `CURRENT_DELIVERY_SHA256.json`：相对于工程根的当前拟态源码与迁移后的文档。
- 工程根运行 `python -B scripts/freeze_plugin_manifests.py` 只读校验，任何内容、文件增删或符号链接异常均失败。只有显式 `--write` 才重新冻结当前源码，不能将重新冻结当成历史版本比对。
- 运行 `python -B mimic_plugin/scripts/validate.py --integrity-only` 可在 Windows 做源码完整性检查，不会执行原生进程隔离，也不会打印全链 `MIMIC_VALIDATION_PASS`。

## 历史来源

`DELIVERY_SHA256.json` 和 `UPSTREAM_HASHES.json` 是上游历史 pin，保留原始字节与原始相对路径，**不是当前合并工程的源码校验清单**。历史包中的 `reports/release_20261016/`、同级上游树和其余训练/冻结证据没有随本工程交付，不声称本地存在，也不能从旧 summary 认证当前源码。

`validate.py` 支持原独立布局的 `docs/UPSTREAM_HASHES.json` 和本工程的 `../docs/mimic_plugin/UPSTREAM_HASHES.json`。未提供上游树时明确报告 `upstream.status=NOT_AVAILABLE`，不访问不存在的旧路径，不置 `upstream_unchanged=true`。显式指定 `--upstream-root <包含 AFDX_Security_Plugin 等目录的路径>` 后逐文件校验，缺失/哈希错误均硬失败。

## 平台边界

2026-10-20 已适配 Windows：显式 `.exe`、二进制 stdin/stdout、静态链接、Windows Job 限制及进程树清理；POSIX 继续用 resource/进程组。真实四执行器经 `tb_defense_live` 接入 ModelSim 主接收路径，详细范围见 `../DEFENSE_INTEGRATION.md`。宿主冷启动的墙钟预算与 RTL 截止预算分开记录，协同仿真不冒充线速性能证明。原插件的 Icarus 专用验证与 sanitizer 脚本仍有其工具要求。
