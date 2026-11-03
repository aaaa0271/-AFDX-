# 交付证据索引

- historical_20261030/：2026-10-30在这台电脑实际运行的五类截图目标证据，包括WLF、
  原始日志、独立审计、智能体报告、源码哈希和版本标记。保留原日志不改写。
  这部分是修订前的历史运行，不能冒充2026-11-03宿主采集修复后的新运行。
- review_20261103/：本次修复后的实际测试摘要、主机测试、HDL和eLinx原始结果。
  eLinx授权报错、未执行的器件阶段均保留原状态。
- final_elinx_baseline_20261024/：2026-10-24/25 在 120 源基线快照上的 eLinx
  Analysis & Elaboration **PASS** 记录（AFDX_competition_top 与 AFDX_top，
  0 error / 159 warning，1122/1137 s）；报告中的 eLinx PASS 引用此目录。
  2026-11-03 新增的 615A 下载功能由 127 项 RTL/联动回归覆盖，不把该日志
  冒充为 2026-11-03 的重新展开。
- final_elinx_baseline_20261103_FAIL_OOM/：2026-11-03 对含 615A 下载的 121 源
  `AFDX_competition_top` 重跑的真实结果，`Out of memory in module
  quartus_map.exe (105262 megabytes used)`；这是内存边界，不是许可证问题。
  最新 615A 增量只有 127 项仿真覆盖，不写成 eLinx PASS。
- final_elinx_core_stub_20261104_PASS/：**A 实验**——最新核心把 615A download
  临时 stub 掉后的 eLinx 展开，**PASS，0 error / 161 warning，17.25 GB，
  21.6 min**。证明最新代码里唯一爆内存的是 download 模块，其余核心 0 error。
  生产 RTL 未改动；详见该目录 README.md。
- final_elinx_download_b_20261104_PASS/：**B 方案**——存储器化重构后的
  `afdx_615a_download` 单独 eLinx 展开 **PASS，0 error / 23 warning，
  10.8 GB，4.6 min**（原版 106 GB OOM）；重构文件与复现工程随目录保存。
- regression_b_20261104/：重构版替换进源码树后的 **127 项回归全部通过、
  0 失败**（results.csv + acceptance.json）。
- final_elinx_core_b_20261104_PASS/：**完整最新核心（含重构版 615A
  download）eLinx 展开 PASS，0 error / 171 warning，18.9 GB，22.8 min**。
  重构版 `afdx_615a_download.v` 与复现工程随目录保存；这是最新代码首个
  完整核心 eLinx PASS。
- screenshot_mapping.json：团队现有五张PNG的文件名和哈希。现有PNG未携带可证明生成批次的
  元数据，暂不能逐张确认来自哪一次原始运行。上传前应使用相应版本WLF回放重新截图并标注批次。

## 回放历史波形

在新打开的ModelSim会话中执行以下任意相对入口（从本文件夹所在目录起）：

    source historical_20261030/overview/open_overview.do
    source historical_20261030/captures/tb_datagram_mac_joint/open_wave.do
    source historical_20261030/captures/tb_security_plugin/open_wave.do
    source historical_20261030/captures/tb_mimic_quorum/open_wave.do
    source historical_20261030/tcn/open_wave.do

请使用Tcl的source命令（不要将此处的source换成do），以便正确定位脚本自身目录。\n脚本内部按自身位置解析WLF与日志路径，移到其他电脑后无需编辑旧电脑绝对路径。
系统全貌属于宿主协同仿真；TCN阳性处置分支采用明确标注的合成验证向量。
题目附带说明允许无硬件平台；未上板本身不作为本次必须整改项。

## 本次最终验收

review_20261103/final_validation.json为最终汇总。
final_run/内保留127项实际结果、独立审计、eLinx许可证失败日志和源码指纹。
早期开发中间记录已清理；最终验收以final_run和final_validation.json为准。
新增卸载波形可执行：

    source review_20261103/download_waveform/open_wave.do
