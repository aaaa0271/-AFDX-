# 2026-11-03 最新核心 eLinx 重跑：OOM

- 顶层：`AFDX_competition_top`（单域，121 个源文件：120 个 `rtl/*.v` + AI TCN）
- 工具：`D:\Program Files (x86)\eLinx3.0\bin\Passkey\bin\quartus_map.exe`（本机有效许可）
- 命令：`quartus_map --read_settings_files=on --write_settings_files=off --analysis_and_elaboration ARINC`
- 结果：**FAIL / OOM**，`exit=1`
- 关键日志：`Out of memory in module quartus_map.exe (105262 megabytes used)`
- 耗时：约 14 分钟（2026-11-03 23:05—23:19）
- `status.json` 中 `analysis_elaboration=FAIL`，`target_synthesis/place_route/timing=NOT_RUN`。

## 判读

- 该版本相对 2026-10-24 的 120 源基线，新增 `afdx_615a_download.v`（224 行）并修改 `afdx_665_package_loader.v`、`afdx_package_network_services.v`、`afdx_sec_engine.v`。新增 615A 下载路径使核心展开从约 16.9 GB 上升到 **105 GB 以上**，本机 24 GB RAM + D: 64 GB 页面文件无法完成。
- 因此 **2026-10-24 的 PASS 不能写成“最新代码核心重新跑 PASS”**；它只对应 120 源基线。最新 615A 下载功能由 `evidence/review_20261103/final_run/` 的 127 项 RTL/联动回归覆盖，不是 eLinx PASS。
- 这不是许可证问题；许可证和最小探针均正常，是真实的内存边界。统一防御/网安整体顶层历史上同样 OOM（>110 GB），本次未重跑。
