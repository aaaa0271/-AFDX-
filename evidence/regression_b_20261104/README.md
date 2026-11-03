# B 重构回归（2026-11-04 00:18 批次）

- 源码树：`AFDX_SOURCE_20261026` 的临时副本，仅把 `rtl/afdx_615a_download.v`
  替换为存储器化重构版（见 `../final_elinx_download_b_20261104_PASS/`），
  其余文件与最新源码逐字节一致。
- 驱动：`python -B -u scripts/run_all.py --hdl-only --workers 4`
- 结果：**127 项全部通过，失败 0 项**。
  - 生产实现 122 项 + 实验模型 5 项；
  - 含 `tb_615a_roundtrip` / `tb_615a_download_faults` /
    `tb_615a_download_security` 三个新增 615A 卸载用例；
  - 含正式顶层宿主联动 `tb_defense_live`。
- 原始判词：`FUNCTIONAL PASS FULL_FUNCTIONAL_RUN False COMPETITION_PROTOTYPE INCOMPLETE`
  （原工程验收器仍按“全部完整工具链”判 INCOMPLETE；本次批次的 RTL/联动
  127 项逐项结果以 `results.csv` 为准）。

本目录保存 `results.csv`（127 项逐项判词与日志路径）和 `acceptance.json`
（验收器原始记录）。
