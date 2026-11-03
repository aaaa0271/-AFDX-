# 当前实现状态（2026-11-03）

当前正式顶层为 AFDX_defense_top。新增真实615A有界加卸载：
操作员选择LNO/LNL/LNA、媒体指定LND/LNR、目标文件回传及LNS状态。
支持最多4个已提交文件、每文件4096字节；加载与卸载互斥。
详细范围及复现见 [DOWNLOAD_615A.md](DOWNLOAD_615A.md)。

打包路径、采集连续性、合法策略更新、验证入口和证据清单已修订，
见 [REVIEW_20261103.md](REVIEW_20261103.md) 和 ../evidence/INDEX.md。
127为注册用例数量；实际通过数量以本次原始acceptance.json、修订验证记录为准。

本机ModelSim许可正常；eLinx兼容编译器提示许可证与机器标识不匹配，
尚不能确认兼容分析展开、目标EQ6HL130综合或时序完成。
组委会允许仿真验证，无硬件板卡不列为本次未完成条件。
完整标准认证、SNMPv3认证/加密、615A全部选项等仍未声明完成。

以下保留历史实现记录。历史“本轮”“顶层”“通过数量”均指当时版本，
不能代替上述当前入口及本次交付证据。

---

# 实现状态（2026-10-19 审查修复版）

本文件是 AFDX 竞赛交付件的可读实现状态入口。结论以可复现的 ModelSim 回归与 eLinx 分析/综合为准；本文不是标准认证声明。

本轮修复、顶层选择及新测试见 `REVIEW_FIXES_20261019.md`、`DEMO_TOP.md`。本文后续插件章节中的旧测试数字是历史记录，不能代替本轮新源码验收；拟态和 agent 的上游历史冻结目录不在本工程，无法由本交付件独立核验。

**2026-10-20 更新**：按用户要求，安全、AI 和拟态现通过 `AFDX_defense_top` 与可信宿主运行时接入同一实际准入/测量路径，工程默认顶层已切换。完整连接、寄存器、缺测规则、异构进程、时限及协同仿真边界以 `DEFENSE_INTEGRATION.md` 为准。下方早期“独立插件/未接入”描述是集成前历史，不代表当前状态。本轮明确不执行上板和单域/双域展开。

## 1. 顶层结构

| 模块 | 角色 |
|---|---|
| `AFDX_top`（`rtl/AFDX_top.v`） | 题目建议接口的八端口自主演示：复位后配置并封存四个业务 VL，真实业务源、主动 RTC、合法 SIM 硬件 ID、接收与镜像状态报文。内部例化单域可配置顶层，外部字节流同时送 A/B，输出取 A。不是独立双物理网络演示。 |
| `AFDX_competition_top`（`rtl/AFDX_competition_top.v`） | 正式可配置验收入口，`SERVICE_DOMAINS` 参数化，是工程顶层实体；默认不启用安全包装、AI 核或拟态裁决器。 |
| `AFDX_basic_top` / `AFDX_legacy_top` | M6F 集成路径的精简/遗留封装，仅供 legacy ModelSim 回归（`tb_contest_top` 等）使用，不用于赛题接口。 |

## 2. 已实现并验证的功能

- **ARINC 664 Part7 通信**：datagram 收发、VL/Sub-VL、通信端口/SAP、BAG 调度、LMAX（64..1518）、IP 分片/重组、A/B 双冗余、采样/队列端口。
- **完整性与通道**：以太网 FCS、IP/UDP 校验和、序号完整性（PSN 连续性检查）、冗余去重、SkewMax 超时复位、错误隔离与统计。
- **SNMP 网络管理**：生产 MAC 路径支持 SNMPv1/v2c community 与 SNMPv3 USM `noAuthNoPriv` 明文 ScopedPDU；engine discovery/REPORT、GET/GETNEXT/GETBULK、只读 SET 错误响应；25 个项目私有遥测对象。`authNoPriv`/`authPriv` 及加密请求一律拒绝：可报告消息回 `usmStatsUnsupportedSecLevels` REPORT，不可报告消息静默丢弃，安全级别计数器在 engine/user 发现检查之后统一判定。认证（HMAC）与隐私加密（DES/AES）未实现，也不作此宣称。
- **ARINC 615A 数据加载**：A4/RFC1350 有界子集，RRQ/WRQ、DATA/ACK、重复包、重试、零长末块、DALLY、WAIT、ABORT、有界超时恢复；LUI/LUR/LUS bounded upload、真实 package loader、双 bank 原子提交。生产路径每个 LUR 仅一个 LUH（`MAX_HEADERS(1)`），一个 LUH 可含多个 data/support 文件；独立控制模块的多 header 计数/准入测试不等于生产多 LUH 原子提交。
- **ARINC 665**：0x8003（665-2）与 0x8004（665-3/4/5）LUH 解析，data/support/UDD/load type、CRC16/CRC32、指针、重复名、路径边界检查；support 文件接入 package loader；文件数上限 4、单文件 4096 字节（`MAX_FILES`/`MAX_FILE_BYTES` 参数，头解析与 loader 一致）。
- **RTC 时钟同步**：NTPv4 客户端，每 lane 一个服务器，holdover 与恢复，UTC 可步进、单调计数不回退。正式 MAC 路径采用最终物理 TX 的 T1 和随帧保留的原始 RX T4，并补偿外层安全重放延迟；无 MAC 的独立模块以 datagram 握手为边界。
- **服务域扩展**：`SERVICE_DOMAINS` 参数化 lane/mux，运行时 shadow IP/clock/enable 配置，空闲后原子提交；已验证 1/2/4/5/8/9 域结构与 1/2/5/9 域运行时配置。

## 3. 2026-10-14 修复记录

依据独立验证报告 `VERIFICATION_REPORT_20261014.md`：

1. 提供赛题 8 端口 `AFDX_top`；旧 M6F 封装改名 `AFDX_legacy_top`，工程文件（`ARINC.epr`/`ARINC.qsf`）同步。
2. 修复两个测试侧缺陷：`tb_integration_multi_services` 的 `loaded/locked` 位宽与双域 DUT 对齐；`tb_665_grammar_focused` 例化补 `.MAX_FILES(4)` 对齐生产配置。
3. 冗余管理：增加 SN=0 复位标记双网丢失后"孤儿迟到副本"判据（逻辑已前进到非零序号且副本来自未见网络时判跨网重复），防止逻辑序号回滚导致同一 payload 重复投递；定向序列已加入 `tb_m5_integrity_rules`。
4. `RX_SKEW_MAX_CYCLES` 默认值由 2,000,000 收敛为 1,500,000（12.5MHz 下 120ms），严格小于 128 × 最小 BAG（1ms ×128 = 1,600,000 周期）。
5. SNMPv3 安全级别判定统一到 PRIV 字段、engine/user 检查之后；保留编码（10）静默但计入 `usmStatsUnsupportedSecLevels`，不再漏计。
6. `afdx_timebase` 改为余数累加（Bresenham）微秒分频，消除 12.5MHz 下 -4.2% 的取整误差，并支持低于 1MHz 的时钟。
7. 665 package loader 单文件长度上限改为 `MAX_FILE_BYTES` 参数并透传给 header；控制侧 TFTP 对未知 TID 回 ERROR 5 且不干扰在途会话。
8. 文档/工程：重写本状态文件；README 结果引用改为运行时生成口径；更新 SNMP MIB sidecar 的版本状态；`ARINC.qsf` 加器件说明注释；`run_all.py` 自动探测 C:/D: 盘 eLinx 安装路径；消除验证框架两处恒空检查并将子横幅改为错误门控。

## 4. 配置能力边界

- per-VL 关闭完整性检查（IC）/冗余管理（RM）当前仅有**编译期参数** `IC_ENABLE`/`RM_ENABLE`，配置表无运行时控制位。本版本不提供运行时逐 VL 关闭能力，特此声明。
- 665 存储几何为 2 bank × 4 文件 × 4096 字节；放大 `MAX_FILE_BYTES` 需同步扩展存储数组与槽位位宽。

## 5. 遗留代码

M4 时代发送路径文件（`afdx_tx_engine*`、`multi_vl_*`、`vl_scheduler_*`、`per_vl_*`、`vl_fifo.v`、`m4_*`、`bag_regulator.v` 等）不被 `AFDX_competition_top`/`AFDX_top` 实例化，保留在 `rtl/` 仅供 legacy ModelSim 回归编译，文件头有 LEGACY 标记；新工作不得依赖它们。

## 6. 验证证据与复现

- ModelSim 功能回归：111 个 testbench，修复后 **111 PASS / 0 FAIL**；失败判定为 fail-closed（PASS marker + 仿真内错误计数为 0 + 编译 0 error）。
- 独立审计：7 个 `scripts/verify_*.py`（Python 重算 FCS/CRC16/CRC32/IP/UDP 校验和、pysnmp 独立 BER 解码并与 DUT 快照交叉核对），抓包来自 DUT 实际输出。
- eLinx 分析/综合：单域 `AFDX_competition_top` 为 0 error；双域由同一入口执行。分析综合不是器件布局布线、时序收敛或硬件认证。
- 结果目录在运行时生成，默认 `results/`，或用 `--output-root` 指定工程外目录；交付件本身不携带历史结果，任何新运行都无法用旧日志充数。

```powershell
.\run_all.ps1 -ModelsimOnly -Workers 3
.\run_all.ps1 -ModelsimOnly -ResultsRoot D:\AFDX_Results -Workers 3
```

## 7. 网安创新拓展插件（AFDX Security Plugin 1.0，2026-10-15 接入）

插件以**外部封装**方式集成，不修改原核心任何源码；正式顶层 `AFDX_security_plugin_top` 逐一保留原 106 端口与 22 参数，新增独立 `sec_cfg_*`/`sec_event_*`/`sec_*` 统计口与 `SECURITY_BOOT_MODE` 参数。`AFDX_security_8port_top` 是旧 8 口签名的 BYPASS 对比件，不代表安全功能启用。

- **六项能力**：A/B 整帧内容一致性（逻辑键配对、逐字节比较、排除接口位/FCS、证据冻结/ACK）；615A 阶段/会话/TID/乱序/重复块授权；帧长/最小间隔/窗口/分片/文件上下文资源配额；活动-影子-上一版规则离线冲突预检与空闲原子提交；可信主机 Ed25519 真实验签（目标/nonce/时效/版本/防回退）+ RTL 真实 SHA-256 末块扣留；NTP 请求来源/原始时间/模式/层级/RTT/跳变与 UTC/单调交叉监测。
- **文件**：10 个 RTL（`rtl/afdx_sec_*.v`、`rtl/afdx_security_plugin.v`、两个封装顶层），7 个 TB（4 个测试 + 3 个模型），`scripts/run_tests.py`/`generate_*.py`/`verify_plugin_wire.py`，主机工具在 `host/`，单元测试在 `tests/`，原始插件文档与基线哈希清单在 `docs/security_plugin/`。
- **工程接线**：`ARINC.epr`/`ARINC.qsf` 的 DesignSrcs 已登记全部 10 个新 RTL（三方一致性 114=114=114），sim_1 仿真集加入 4 个 TB 和 3 个模型；`scripts/tests.json` 新增 security 套件 4 用例。
- **验证**：ModelSim 全量 115/115 PASS（插件 4 用例均由错误计数门控并附独立 Python 审计：报文重放、FCS/校验和重算、BYPASS 基线字节等价）；主机端 27/27 单元测试 PASS（cryptography 50.0.2）；114 个 RTL `vlog` 0 error。一处 TB 重复声明已为 ModelSim 严格性修正（`tb_security_core_multi.v` 声明前移），`verify_shared.py` 增加 harness 直跑时的 `plugin_*_wire.txt` 回退。
- **边界**：ENFORCE 为整帧存储转发，有延迟与吞吐成本；可信主机/配置总线/预置公钥/可信 NVM 必须由部署环境保证；FPGA 内未实现 Ed25519，未做目标器件综合时序、板级互通与密钥烧录；插件交付包自带 iverilog 证据，本机主工具链为 ModelSim。
- **2026-10-17 缺陷修复（依第三方验证报告「代码审查发现·网安插件」）**：`rtl/afdx_sec_engine.v` 两处已修——① `match_key` 补比对 UDP 源/目的端口（`q=42..45`），避免「同 VL/SN、不同端口」的第二路流被判内容冲突而误丢；② 分片分支新增 DF 护栏，对 `(fragment&16'h4000)!=0` 直接判 `F_FORMAT`，不再为非法 DF+MF/偏移组合开分片上下文以致泄漏至超时。**回归**：定向 4 个 security 用例全 PASS；全量 `--hdl-only --workers 8` → `FUNCTIONAL PASS`、**116/116 PASS**、`changed_inputs []`。**代价（如实记录）**：该文件因此脱离上游 pin（见 `docs/security_plugin/PINS_README.md`），且此前 eLinx 单/双域分析综合证据因源码变更失效，需在具备 eLinx 环境时重跑方可重新宣称。其余 4 项中等级条目（replay 核心错误透传、`ab_window` 与 `RX_SKEW_MAX_CYCLES` 派生、策略位 7 构造性强制、`afdx_sec_sha256` 长度护栏）与 2 项低级条目经评估**本轮未改动**，维持文档化边界。报告给出行号对应另一修订版，本工程按**描述**而非行号定位。

## 8. AI 智能防御体插件（AFDX Agent Plugin 1.0，2026-10-16 接入）

电脑端有界工具智能体，与 RTL 完全解耦：规划器是可审查状态机，三个冻结 NumPy 小模型（诊断/异常/时延，权重在 `models/`）只提供先验，独立证据工具可以推翻模型首选（`model_disagreement` 案例即证据改写调查方向），不需要 LLM、GPU 或云 API。

- **闭环能力**：故障诊断（三模型 + 加载/时间/双网/计数器证据核对）、证据追溯（FCS/IPv4/UDP 重算、逻辑副本比对与差异偏移、日志行号、160 位事件/快照解析、文件哈希）、主动验证（合法校验内容篡改与坏 CRC 负对照、捕获帧重放、六类固定 RTL 实验、负载反事实后重调模型）、策略建议（仅 window/max_frames 候选 + 影子寄存器/epoch/原规则哈希，隔离 RTL 对照，状态 `lab_checked_candidate`）、自动报告（Markdown/JSON + 逐工具回执 + 哈希链，区分候选/局部事实/实验复现/待验证）。
- **目录**：`afdx_agent/`（agent/tools/rtl/audit/case/packets，8 文件）、`afdx_ai/`（模型推理与桥接，7 文件）、`cases/`（10 个冻结演示案例）、`models/`（3 权重 + registry）、`security_lab/`（与网安插件逐字节相同的 8 个 RTL + 通用 TB + `policy.py`，仅供智能体在自己的实验目录编译，**不并入工程 `rtl/`**）、`reference_evidence/`（带溯源的参考夹具）、`scripts/validate.py`+`generate_cases.py`、`tests/test_agent.py`（50 测试），文档在 `docs/agent_plugin/`。
- **安全边界**：只读观测适配；iverilog/vvp 路径只接受可信 CLI/环境变量提供，不从报文/日志/案例执行指令；日志指令当纯数据（有测试）；案例符号链接/路径穿越/重复键/证据篡改/哈希链篡改均拒绝；**不写设备配置、不生成可覆盖全策略的事务、不规避反作弊**；哈希链用于可追溯与篡改检测，不是数字签名。
- **本机验证（Python 3.14 + NumPy 2.3.5）**：77/77 单元集成测试通过（2 项平台相关跳过）；`validate.py --rtl off` 十案例全部正常结束、70 次工具调用、模型分歧被证据纠正、compound 保留双根因、缺测量不补零、源码运行前后哈希不变；`--rtl auto` 在无 Icarus 时 RTL 项如实标 `unavailable`、报告明确写出，不冒充 PASS。三处跨平台适配：案例生成器改字节写入保持 LF；符号链接测试在无特权平台跳过；逐字节案例重生成门控到上游钉版 CPython 3.12（3.14 下某合成指标 numpy 归约漂移 2 ULP）。
- **边界**：模型为合成数据训练，十个案例不是真实设备准确率评测；上游 iverilog required 的冻结证据（6 类实验/80 项固定检查/22 次含案例 RTL 运行/216 项逐报文检查）保留在插件交付包 `reports/release_agent_final_20261015/`；时延模型与抽象队列实验不构成最坏时序保证；现场接入需宿主采集真实测量并经原可信配置流程落地建议。

## 9. 拟态防御插件（AFDX Mimic Plugin 1.0.0，2026-10-16 接入）

电脑端**语义动态异构冗余（DHR）**原型：四个异构执行器（Python 结构解码
`python_struct.py`、C 固定偏移 `c_offsets.c`、C++ 游标视图 `cpp_cursor.cpp`、
Python 声明式布局 `python_table.py`）独立解析同一报文并给出结构化语义，按
**2-of-3 语义裁决**（比较语义哈希而非仅比较 allow/deny）判定，支持单点故障
隔离、动态轮换、恢复自检与共同模式反例。拟态层另有独立 RTL 事务级裁决器。

- **目录**：整体落在新根目录 `mimic_plugin/`（`afdx_mimic/`、`executors/`、
  `cases/{boundary_suite,normal,udp_length}`、`scripts/`、`tests/`、`rtl/`、
  `security_lab/`、`reports/`（仅占位文件 `.gitkeep`）、`trusted_selftests.json`、
  `DELIVERY_SHA256.json`、
  `README.md`、`VERSION.txt`、`requirements.txt`，共 74 文件）。采用独立根目录
  是因为插件自带的 `cases/`、`scripts/`、`tests/`、`rtl/`、`security_lab/`
  五个目录与工程根同名，展开会产生路径碰撞。原始交付件逐字节保留，未改写源码。
- **工程接线**：`rtl/afdx_mimic_quorum_gate.v`（事务级裁决器）与
  `tb/tb_mimic_quorum.v`（13 项用例）复制进工程，前者登记进 `ARINC.qsf`/
  `ARINC.epr` 的 `DesignSrcs`（三处一致 **115=115=115**），TB 同时登记进
  `ARINC.epr` 的 `sim_1` 仿真集；`scripts/tests.json`
  新增 `mimic` 套件 1 用例（共 116 用例），门控为 `failures==0` 且精确终行标记
  `MIMIC_RTL_PASS cases=13 done=13`。TB 刻意不以 `afdx_` 前缀命名，以满足
  `test_packaging.py` 的"`tb/afdx_*.v` 必须为空"门控。
- **验证（本机 Windows / ModelSim）**：`py -3 scripts\run_all.py --hdl-only
  --tests tb_mimic_quorum` → `mimic tb_mimic_quorum PASS`、
  `MIMIC_RTL_PASS cases=13 done=13`、`REGRESSION_FINAL_ERRORS=0`、`vlog`
  `Errors: 0`；7 个预检门全部 PASS（含新增文件后的 `test_packaging.py` 6 项
  文件集/覆盖/命名门控）。纯 Python 契约层在本机可运行的 8 项
  （重复键 JSON/ NaN / 策略未知字段与重复 id / 布尔整数 / 策略稳定排序 /
  请求边界 / 请求 id 布尔）实测 `Ran 8 tests ... OK`。
- **平台门控（如实标注，未伪装 PASS）**：插件原始验证环境为 Linux + GCC(C11)
  + G++(C++17) + Icarus Verilog。编译器可通过 MinGW 等安装提供，不能把 PATH
  查找失败写成整机不存在；`afdx_mimic/launch.py` 依赖 POSIX `resource` 模块（Windows 导入即
  失败）。故依赖原生执行器与 Icarus 的整体编排（`scripts/validate.py`、四执行
  器 2-of-3 回放、`MIMIC_VALIDATION_PASS` 终态标记）**未在本机运行**；其原始
  冻结证据目录 `reports/release_20261016/` 未随本工程提供，不能独立核验。
  `build.py` 在缺工具链时**硬失败**而非静默省略执行器。拟态层唯一可
  综合 RTL 则通过工程 ModelSim 流程独立复算，不依赖上述 Linux 工具链。
- **文档**：随包文档落在 `docs/mimic_plugin/`（10 文件：`MIMIC_README.md`、
  `MIMIC_VERSION.txt`、`MIMIC_requirements.txt`、`INTERFACES.md`、
  `THREAT_MODEL.md`、`VALIDATION.md`、`UPSTREAM_HASHES.json`、
  `UPSTREAM_VERIFICATION.json`、`DELIVERY_SHA256.json`、`INTEGRATION.md`），
  命名遵循工程既有 `security_plugin/`、`agent_plugin/` 加前缀约定。
- **边界**：裁决器 RTL 为事务级，**尚未连接完整 MAC 缓存/重放封装**，本工程
  仅使其通过独立编译与 13 项用例回归，不宣称已接入数据面；拟态层最终放行同时
  取决于宿主 baseline 与拟态层裁决（`baseline=None` 时 `final_allow` 为
  `null`，不冒充放行），本工程不修改该语义；集成布局下
  `mimic_plugin/scripts/validate.py` 的上游 698 条 pin 中部分相对路径假定插件
  根同级存在原始同级交付包，端到端复现需在原始同级包环境并具备上述工具链；
  `mimic_plugin/reports/` 仅保留占位文件 `.gitkeep`，以维持
  `tests/test_mimic.py` 的临时构建父目录，不携带任何历史结果。

## 10. AI 硬件推理插件（AFDX AI Hardware Plugin R1，2026-10-17 接入）

电脑端训练、FPGA 推理的小型时序神经网络诊断插件：8×18 因果卷积窗口，两层 16 通道
因果卷积（膨胀率 1、2）+ 池化 + 全连接，末时刻与窗口均值拼接后输出 9 个值——7 类故障
候选、未来三窗口队列风险、未来三窗口各自 p95 时延最大值。**候选不等于已确认物理
根因**。本次接入遵循一条硬规则：**不改动原有架构**。

- **目录**：整体落在新根目录 `aihw_plugin/`（`afdx_ai_hw/`、`rtl/`、`tests/`、
  `scripts/`、`models/`、`source_model/`、`examples/`、`integration/`、`docs/`、
  `evidence/`、`reports/`（仅占位文件 `.gitkeep`）、`README.md`、
  `RELEASE_MANIFEST.json`、`requirements.txt`、`requirements-train.txt`，共 90 文件）。
  采用独立根目录是因为插件自带的 `docs/`、`examples/`、`models/`、`rtl/`、`scripts/`
  五个目录与工程根同名，展开会产生路径碰撞。插件自带文档**保真保留在
  `aihw_plugin/docs/` 原位**（不迁至工程 `docs/` 加前缀），原因是插件自带
  `scripts/verify_release.py` 按 `RELEASE_MANIFEST.json` 相对路径逐条校验完整性，
  迁移会使清单 5 条 `docs/*` pin 变为"缺失"。
- **原有架构零改动（已复核）**：三层顶层、`AFDX_top` 8 端口、工程 RTL 文件集
  `rtl/*.v`（115）、`tb/*.v`、`ARINC.qsf`/`ARINC.epr`（`VERILOG_FILE` 115）、
  `scripts/tests.json`（116）、`scripts/run_all.py` 及其余脚本**均未修改**；
  7 个预检门逐个复跑全部 exit=0。
- **为何不入工程文件集**：该插件 RTL/测试台依赖 `$readmemh` 运行时加载的外部文件
  （固定 ROM `rtl/*.mem`、生成向量 `reports/vectors/*.mem`）与 `ai_model_params.vh`
  头文件，而工程 `run_hdl` 只复制 `tb/*.hex`、`vlog +incdir` 仅指向 `tb/`。挂入
  工程文件集会连带要求改运行器、补合成搜索路径、并把带运行时文件依赖的模块并入
  评委编译集，且 `test_packaging.py::test_test_resources` 会拒绝非裸名 `$readmemh`
  路径——均构成对原有架构的改动。故按约束保持零改动，插件以独立模块形态交付，
  必要时由系统外层包装单独实例化。
- **本机已执行验证（Windows）**：对 `RELEASE_MANIFEST.json` 87 条 pin 全量逐字节比对
  **87 匹配 / 0 不匹配 / 0 缺失**；`scripts/verify_release.py` →
  **`RELEASE_INTEGRITY_PASS 87`**；`py -3 -m unittest discover -s tests -p "test_*.py"`
  → **`Ran 34 tests ... OK`**；`-m afdx_ai_hw infer --backend reference` →
  **`INFER_PASS`**。默认 RTL 后端在缺 Icarus 时**硬失败**、不退回参考模型冒充 RTL。
- **平台门控（如实标注，未伪装 PASS）**：插件 RTL 回放与整套编排以 Icarus Verilog 为
  前提，本机 `iverilog`/`vvp` 不存在，故依赖它们的 RTL 三用例回放与
  `ALL_VALIDATION_PASS` 终态**未在本机运行**。其原始冻结证据随工程位于
  `aihw_plugin/evidence/release_20261016/`（7 阶段全 PASS，RTL 三用例全 PASS，
  388 向量 / 3492 logits / 111744 中间值 / 12 协议用例，固定计算周期 14035），
  本工程不复制到别处、不改写、不替代；其中 `synthesis_performed=false`、
  `target_timing_closed=false`、`board_tested=false`。
- **文档**：插件自带文档保留在 `aihw_plugin/docs/`（`INTERFACES.md`、`MODEL_CARD.md`、
  `INTEGRATION.md`、`VALIDATION.md`、`UPSTREAM_MODEL_PROVENANCE.json`）；工程侧入口为
  `docs/aihw_plugin/INTEGRATION.md`。
- **边界**：未做 EQ6HL130 综合、布局布线、时序收敛与板级测试，包中不含可烧录
  bitstream；通过 Verilog 语法检查不能推断 BRAM/DSP/LUT 用量或器件最大时钟；模型
  ROM 构建时固定，无在线写权重接口；主机预处理需完整 8×18 窗口，缺失字段**不得置零
  冒充**为实测。主业务链未新增 AI 反压依赖，AI 输出仅为带模型版本的诊断证据。

## 11. 明确未宣称完成

- SNMPv3 `authNoPriv`/`authPriv` 的 HMAC、DES/AES 隐私加密。
- ARINC 615A 完整标准 information/download 文件语法与全部版本条款；当前为可验证的 A4/RFC1350 有界 profile。
- 665-1/0x8002 完整 parser；Batch/LUB、LoadList/MediaSet/LUM、0x900x/0xA00x 全部字节 grammar；非空 ARINC 649 check value 与 THW positions 完整语义。
- 标准 MIB（MIB-II/IF-MIB/IP-MIB/UDP-MIB 等）逐对象闭合。
- FPGA fitting、布局布线、时序收敛、PHY/电气与官方标准认证。
