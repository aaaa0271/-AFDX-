# AFDX 竞赛工程最终基础状态 R2（2026-10-11，历史件）

> 归档说明：本文件原中文内容因编码损坏全部变为 `?`，于 2026-10-14 依据文件中
> 仍可读的数字、路径与条目骨架重建，以恢复可读性为准；事实口径保持 2026-10-11
> R2 时点（91/91 用例、SNMP 当时范围等），不代表 2026-10-14 之后的最新状态。
> 当前状态见 `docs/COMPLETE_IMPLEMENTATION_STATUS.md`。

## 摘要

本交付件为 AFDX 竞赛端系统工程，已通过 eLinx 分析/综合与 ModelSim 回归验证；不含 PHY/电气、板级硬件与 AI 相关内容。

**关键结论**

- 顶层为 `AFDX_competition_top`。
- 91/91 个 HDL 用例回归通过。
- eLinx 分析/综合：0 errors，120 warnings。
- AFDX MAC/IPv4/UDP、A/B 冗余、VL/Sub-VL/SAP/端口/分片重组，以及 SNMPv2c、615A/665 加载、NTPv4/RTC，均在 ModelSim 中验证通过。
- 与 Loader/时钟扩展 profile（615A 有界加载、665 头解析、私有 MIB 遥测、SNMP 只读管理）完成 R2 收口。
- 615A/665 为有界实现，完整标准范围未宣称闭合。

## 未闭合项（对照完整 ARINC 标准）

1. 完整 ARINC 标准条款的 SHALL/SHOULD/OPTIONAL 逐条盘点仍为 OPEN。
2. 标准 MIB 未逐对象实现：MAC 代理仅提供私有 MIB，MIB-II/IF-MIB/IP-MIB/UDP-MIB 未实现。
3. SNMP 为 v2c community 模式；SNMPv1/v3 当时仅有策略/框架层面内容，无 MAC wire engine。
4. 615A information/download/abort/wait/error 的完整标准交互未全覆盖；当前为 A4/TFTP 有界 profile，含超时/重试/恢复机制。
5. 665 0x8002/0x8004 的部分字段、CRC、双 bank 提交已实现；support/UDD/batch/list 等语法未完整。
6. 物理板级、BAG/LMAX 物理裕量等硬件相关项不在仿真验证范围内。

## 证据

- 完整回归：`results/run_20261011_131233_233608`
- 615A/665 sidecar：`sidecar_615a665/results/run_20261011_112927_185699`
- 标准 MIB 清单：`docs/STANDARD_MIB_SNMP_INVENTORY.json`
- SNMP 评审：`docs/STANDARD_MIB_SNMP_REVIEW.md`
- 一致性结果：`results/run_20261011_131233_233608/conformance.json`
- 发布记录：`RELEASE_R2.json` / `docs/RELEASE_R2.json`

本报告为阶段性状态记录，不是标准认证结论。
