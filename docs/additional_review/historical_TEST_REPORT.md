# 竞赛基础 AFDX 原型 R1 — 最终验收报告

冻结时间：2026-10-10T22:51:11.387761+08:00。

## 最终结论

**R1 在 `docs/competition_profile.json` 声明的仿真实现范围内完成竞赛基础 AFDX 原型验收。**

本结论不是完整 ARINC 全条款认证，也不是比赛主办方颁发的证书。完整标准范围状态仍为 `INCOMPLETE`，因为标准全文逐条审查、所有适用 SNMP/MIB、完整 615A/665 过程、跨版次和全部最坏工况证明尚未关闭。

## 竞赛五项

| 功能 | 结论 | 真实联合证据 |
|---|---|---|
| COMP-F01 AFDX通信 | PASS | 四 VL、A/B、BAG、序号、IPv4/UDP、16端口/四Sub-VL、Sub-VL MAC字节审计 |
| COMP-F02 高完整性 | PASS | FCS/IP/UDP、错误隔离、冗余去重、序号/丢包/恢复和缓冲压力 |
| COMP-F03 SNMP | PASS（v2c/私有MIB声明范围） | 真实管理MAC、GET/NEXT/BULK、长BER、PySNMP |
| COMP-F04 615A加载 | PASS（A4基础上传声明范围） | LUI/LUR、LUH/LUP、多文件CRC、双bank、LUS/ACK、失败回滚 |
| COMP-F05 RTC | PASS（单时钟服务器NTP报文声明范围） | 联合MAC锁定、独立参考时钟、漂移/失步/恢复 |

矩阵机器文件：`results/run_20261010_222628_350469/competition_acceptance.json`。

## 回归和工具

- 52 legacy PASS
- 15 contest PASS
- 3 completion PASS
- 8 foundation PASS
- 7 datagram PASS
- 1 native Sub-VL/SAP/MAC integration PASS
- **86/86 生产实现相关 HDL 用例 PASS**
- 独立 SAP 覆盖测试 `tb_integration_sap_override` PASS
- 所有源输入哈希未变，运行前后和快照逐项一致
- eLinx `AFDX_competition_top`：**0 errors，120 warnings**

eLinx warning 分类：`{'10230': 115, '10240': 2, '10036': 2, '10270': 1}`。warning 没有被隐去，也没有声称实现了器件时序收敛或板级资格。

## 统一顶层 MAC 联合结果

```text
SHARED_FINAL mode=1 business=4 bytes=32768 snmp=8 snapshots=8
load=1 rtc=1 a_frames=49 b_frames=49 drops=0 overflows=0 errors=0
```

APP.LUH、A.LUP、B.LUP 通过真实服务 MAC 字节抓取与恢复；最终状态 ACK 前不发布，CRC 和失败恢复均有证据。

## Sub-VL/SAP 结果

实际生产顶层 `tb_integration_subvl_mac`：

- 4 VL × 4 Sub-VL = 16 端口；
- 21 个逻辑 UDP 数据报、58 个物理 A/B 帧；
- VL 级 BAG/序号、帧级 Sub-VL 轮询；
- 采样最新值、排队 FIFO、背压保持、同周期入/出队；
- SAP 路由覆盖：原始 VL/Sub-VL 参数故意错误时，以配置 SAP 绑定为准；
- 重复 UDP 绑定、未知 SAP、未授权分区、超容量、同周期写/封存均拒绝；
- 独立 `verify_subvl_wire.py` 字节审计通过。

相关证据：`D:\elinx\ARINC\results\run_20261010_222628_350469\tb_integration_subvl_mac\subvl_audit.json`、`D:/elinx/ARINC/results/sap_override_audit_20261010_sealfix/audit.json`。

## 数字指标

| 工况 | 实测 |
|---|---:|
| RX 双网 1200 个最小帧、12字节IFG、80ns/字节 | 最大缓冲可用延迟 3520 ns |
| RX 双网 32 个最大帧、12字节IFG、80ns/字节 | 最大缓冲可用延迟 119840 ns |
| RTC 独立参考、+20ppm | 21 次同步，最大误差 4998 ns |
| 原生Sub-VL预填充轮询 | 58物理帧 / 42线数据报，配置BAG与序号按VL共享 |

这些是声明工况的数字行为指标，不能外推成全部合法配置、所有相位偏移、无限负载或真实PHY的最坏界限。完整指标原样在 `docs/metrics.json`。

## 封存物

- `RELEASE.json`：R1 frozen competition profile 状态。
- `DELIVERY.json`：交付机器状态。
- `VERSION.txt`：版本标识。
- `MANIFEST.csv`：当前工作树文件哈希。
- `ARINC_Competition_Prototype_R1.zip`：独立压缩包及旁边的 `.sha256.json`。
- `results/run_20261010_222628_350469/`：完整运行、日志、快照和独立审计。

## 明确边界

本 R1 不宣称：完整标准 MIB-II/IF-MIB/全部 SNMP 版本、多个任意 Loader/时钟服务域、完整 615A information/download/abort/wait/error 过程、665 全格式/跨版次、所有规范条款、全部最坏负载数学证明、PHY/电气/板级认证或任何正式 ARINC 证书。对应状态在 `docs/SEVEN_AREA_REVIEW.json` 中继续为 OPEN。
