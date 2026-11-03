# AFDX 端系统与安全 / AI / 拟态防御扩展

2026 年 FPGA 创新设计竞赛 · 中科亿海微赛题「基于以太网 MAC 总线实现 AFDX」参赛工程。
作品名称：天穹幻盾——拟态防御与 AI 智能体护航的 AFDX 航电网络安全端系统（仿真赛道）。

## 一、功能范围

赛题五项基础功能 + 四类扩展插件：

| 功能 | 说明 |
|---|---|
| ARINC 664 Part 7 通信 | VL / Sub-VL、BAG 调度、UDP/IP、A/B 双网冗余、分片重组 |
| 高完整性 | FCS / IPv4 / UDP 校验、源标识、序号完整性、冗余去重 |
| SNMP 网络管理 | v1 / v2c / v3 noAuthNoPriv，GET / GETNEXT / GETBULK、BER 编解码 |
| 615A 数据加卸载 | 有界 LUI/LUR/LUH/LUP/LUS 加载与 LNO/LNL/LNA、LND/LNR、LNS 卸载 |
| RTC 时钟同步 | NTPv4 客户端、UTC 与单调计数、失步恢复 |
| 网安插件 | 规则 / 流量预算 / 加载内容绑定协同准入（BYPASS / MONITOR / ENFORCE） |
| 拟态防御 | 四异构宿主执行器、2-of-3 语义裁决与原安全结论联合准入 |
| 硬件 AI | 定点 TCN 推理核（388 组向量逐值一致） |
| 智能体 | 主机侧诊断状态机 + 独立字节级审计 + 哈希链 |

## 二、验证结论（2026-11-04）

- **功能回归**：127 项 RTL/联动用例全部通过、0 失败（生产实现 122 项 +
  实验模型 5 项）；主机单测 100/102（2 项按平台条件跳过）、AI 34/34、
  拟态 56/57（1 项跳过）。
- **eLinx 分析/展开**：最新完整核心 `AFDX_competition_top`
  **PASS，0 error / 171 warning，峰值 18.9 GB，22.8 min**。
  `afdx_615a_download` 经存储器化重构（宽向量变址 part-select → 字节存储器
  索引，行为不变），重构后先通过 127/127 回归再展开。
- 边界：eLinx 结果为 EP1S80 占位器件上的 analysis/elaboration，**不是**
  EQ6HL130 综合映射 / 布局布线 / 时序收敛；统一防御与网安整体顶层未展开
  （内存边界 >110 GB）。详见 [`eLinx修复与验证声明_20261104.md`](eLinx修复与验证声明_20261104.md)。

## 三、目录结构

```text
rtl/           120 个 Verilog（含重构版 afdx_615a_download.v）
tb/            124 个 Verilog（116 个测试台 + 8 个辅助模型）
scripts/       回归驱动 run_all.py、tests.json 等
host/ afdx_agent/ afdx_ai/ mimic_plugin/ aihw_plugin/   主机侧与插件
docs/          需求、接口、验证矩阵、615A 加卸载说明
evidence/      运行证据与 eLinx PASS/OOM 原始记录（INDEX.md 为入口）
poster/        海报 HTML 源文件
交付材料/       技术报告、测试报告、技术指标、海报 PDF/PNG
```

工程细节（正式入口、实现范围、复现命令）见
[`README_工程详细说明.md`](README_工程详细说明.md)。

## 四、快速开始

环境：Windows、Python 3.12+、ModelSim SE-64 2020.4、GCC/G++（联动用例）。

```bash
pip install -r requirements.txt
python -B -u scripts/run_all.py --hdl-only --workers 4
```

- ModelSim 路径默认为 `C:/modeltech64_2020.4/win64/vsim.exe`，可用环境变量
  `AFDX_MODELSIM` 覆盖。
- eLinx 复现使用本机有效安装
  `D:\Program Files (x86)\eLinx3.0\bin\Passkey\bin\quartus_map.exe`；
  `D:\eLinx3.0` 是已失效的第二套安装（Error 292028），不要使用。
- 615A 卸载波形回放：ModelSim Transcript 执行
  `source evidence/review_20261103/download_waveform/open_wave.do`。

## 五、证据索引

- 127 项回归逐项结果：`evidence/review_20261103/final_run/results.csv`、
  `evidence/review_20261103/final_validation.json`
- 最新完整核心 eLinx PASS：`evidence/final_elinx_core_b_20261104_PASS/`
- 重构版 download 单独展开：`evidence/final_elinx_download_b_20261104_PASS/`
- 重构后 127 项回归：`evidence/regression_b_20261104/`
- 历史对照（旧基线 PASS / 重构前 OOM）：`evidence/final_elinx_baseline_20261024/`、
  `evidence/final_elinx_baseline_20261103_FAIL_OOM/`

## 六、声明

- 本仓库不包含完整 ARINC 664/615A/665 标准认证；SNMPv3 为 noAuthNoPriv。
- 功能仿真通过不等同于物理链路、目标时序或板级验证完成。
- 提交用的 zip 交付包（含全量 MANIFEST 与内部排查记录）不在本仓库内，
  另以 Release 形式归档，其中内部记录仅限团队/评审范围。
