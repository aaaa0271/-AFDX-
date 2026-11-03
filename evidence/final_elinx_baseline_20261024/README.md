# 2026-10-24/25 eLinx 基线 PASS 证据

本目录保存 2026-10-24/25 在 120 源基线快照上实际完成的 eLinx Analysis & Elaboration 成功记录，供报告引用：

| 子目录 | 顶层 | 结果 | errors | warnings | 耗时 |
|---|---|---|---:|---:|---:|
| `AFDX_competition_top/` | `AFDX_competition_top` | PASS | 0 | 159 | 1122.0 s（18.7 min） |
| `AFDX_top/` | `AFDX_top`（八端口） | PASS | 0 | 159 | 1137.0 s（18.9 min） |

- 成功行：`Analysis & Elaboration was successful. 0 errors, 159 warnings`，原始日志在各自 `elaboration.log`，判词在 `status.json`，逐文件哈希在 `EVIDENCE.md`。
- 该结果是 **EP1S80F1508C6 占位器件的 analysis/elaboration**，不是 EQ6HL130 综合映射、布局布线或时序收敛。
- 2026-11-03 最新源码相对该基线新增 `afdx_615a_download.v`（224 行）并修改 `afdx_665_package_loader.v`、`afdx_package_network_services.v`、`afdx_sec_engine.v`；新增 615A 下载功能由 127 项 RTL/联动回归覆盖，本目录不把旧日志冒充为 2026-11-03 的重新展开。
- `evidence/review_20261103/final_run/elinx*` 的四份记录是核查时误用 `D:\eLinx3.0` 第二套安装产生的许可失败（Error 292028），本目录保留它们作为历史失败记录，但不作为 PASS 依据。本机有效安装为 `D:\Program Files (x86)\eLinx3.0`。
