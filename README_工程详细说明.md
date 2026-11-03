# AFDX_Competition_Final

AFDX 竞赛端系统的 RTL、ModelSim 回归、独立报文审计和 eLinx 分析工程。当前修复范围和复现入口见 `docs/REVIEW_FIXES_20261019.md`。功能回归通过不等于完整 ARINC 符合性、板级验证或无缺陷证明。

## 正式入口

| 入口 | 用途与实际接入范围 |
|---|---|
| `AFDX_defense_top` | 当前工程统一入口。安全 ENFORCE、真实宿主异构执行器/RTL 拟态裁决、真实指标到 TCN 硬件推理、告警及可选限时 RX 阻断已接在同一系统中。详见 `docs/DEFENSE_INTEGRATION.md`。 |
| `AFDX_competition_top` | 保留的基础端系统入口，业务、SNMP、615A/665、RTC 共用 A/B MAC；用于基线回归，不再作为集成防御工程的默认顶层。 |
| `AFDX_top` | 八端口自主演示入口。接口来自题目设计建议，不冒称强制评测接口。复位后配置并封存四个业务 VL，发送状态报文、接收业务、主动轮询 RTC，使用合法硬件标识加载 LUH。外部输入同时送 A/B，输出取 A；不能据此演示两条独立物理链路。 |
| `AFDX_security_plugin_top` | 可配置安全包装，默认 ENFORCE，保留可信控制和事件接口；使用该顶层才会启用安全保护。 |
| `AFDX_security_8port_top` | 自主演示的安全 BYPASS 对照入口，不是默认安全防护入口。 |
| `AFDX_basic_top` / `AFDX_legacy_top` | 精简或遗留回归入口，不替代正式验收。 |

八端口预置配置、参数、时序和状态报文格式见 `docs/DEMO_TOP.md`。两个八端口版本都有自身的加载、校时、业务回环测试及独立抓包审计，不再只检查编译和接口签名。

## 实现范围

- **AFDX**：业务 datagram、A/B 冗余、VL/Sub-VL、通信端口/SAP、BAG、LMAX、完整帧调度、分片/重组及完整性检查。
- **SNMP**：v1/v2c community、v3 USM `noAuthNoPriv`、discovery/REPORT、GET/GETNEXT/GETBULK、只读 SET 错误响应。未实现 HMAC、DES/AES 或其他认证/隐私加密。
- **615A/TFTP**：RRQ/WRQ、DATA/ACK、重试、重复包、最终零块、DALLY、WAIT、ABORT、有界超时恢复；A4 LUI/LUR/LUS bounded upload，以及LNO/LNL/LNA、LND/LNR、LNS有界卸载，见 docs/DOWNLOAD_615A.md。生产集成路径每个 LUR 只接受 **一个 LUH**，即 `MAX_HEADERS(1)`；一个 LUH 可描述多个 data/support 文件，不等于多 LUH 聚合事务。
- **665**：0x8003/0x8004 LUH、data/support/UDD/load type、CRC、指针、重复名、路径边界检查；非活动 bank 准备、最终 LUS 确认后的原子发布。完整版次标准认证不在声明内。
- **RTC**：NTPv4 客户端，UTC 可步进、单调计数不回退。正式 MAC 路径从最终发送口记录 T1，原始接收口记录 T4，接收时间戳随帧穿过缓存和去重；请求中的时间戳用作不可变 origin 匹配标识。独立 datagram 模块以其握手接口为观测边界。
- **服务域**：`SERVICE_DOMAINS` 参数化独立加载/时钟 lane，运行时 shadow IP/clock/enable 配置，空闲后原子提交。
- **安全插件**：A/B 内容一致性、证据冻结、加载授权、配额、策略切换、可信主机 Ed25519 验签与 RTL SHA-256、时间可信度监测。防回退版本下限复位后需由可信控制器恢复，详见 `docs/security_plugin/SECURITY_SCOPE.md`。

## 扩展边界

| 扩展 | 已交付 | 未接入或未证明 |
|---|---|---|
| AI 智能防御体 | 通过 `DefenseRuntime.investigate()` 读取实际窗口、真实报文及硬件 AI/拟态结果，生成可审计报告 | 智能体建议不直接写策略；训练指标不等于真实设备准确率。 |
| AI 硬件推理 | 统一顶层实例化原 TCN 核；实际测量快照经宿主预处理形成8窗口，真实 CSR 推理连接告警和可选限时 RX 阻断 | 缺测/越界/饱和不触发处置；候选不是确认根因。未宣称目标时序或板测。 |
| 拟态防御 | 安全准入后的整帧队列接入三活一备异构进程、完整语义 SHA-256 RTL 裁决、隔离轮换和完整帧重放 | 是**宿主协同集成**，不是四套 FPGA 硬核；宿主缺失、无一致结果或截止超时均丢帧。未证明 Windows 宿主线速吞吐。 |

## 复现

```powershell
# 运行 HDL 与宿主联动（不执行兼容分析展开）：
python -B -u scripts/run_all.py --workers 8 --hdl-only

# 仅 HDL，或仅新增反例及八端口验收。
python -B -u scripts/run_all.py --workers 8 --hdl-only
python -B -u scripts/run_all.py --workers 4 --hdl-only --tests tb_review_tftp_budget tb_review_control_budget tb_review_rtc_mac tb_review_8port tb_review_security_8port
python -B -u scripts/run_all.py --hdl-only --tests tb_defense_live tb_defense_boundary

# 当前交付源码完整性；不改写上游历史清单。
python -B scripts/freeze_plugin_manifests.py
python -B mimic_plugin/scripts/validate.py --integrity-only
```

测试清单在 `scripts/tests.json`，目前实际注册127项。`tb_defense_live` 实际启动 ModelSim、四个独立宿主进程与原 TCN，不是只编译顶层。实际 PASS/FAIL 以新运行目录为准，旧版116/116和旧eLinx日志不认证本版。执行前后校验源码哈希，失败的开发中间记录不是验收证据。

`--modelsim` / `AFDX_MODELSIM`、`--elinx` / `AFDX_ELINX` 可显式指定工具。`--output-root` 或 PowerShell 的 `-ResultsRoot` 可指定工程外结果目录。生成的结果不应手动改写成 PASS。

当前源码清单分别为 `docs/agent_plugin/CURRENT_DELIVERY_SHA256.json`、`docs/mimic_plugin/CURRENT_DELIVERY_SHA256.json` 和 `mimic_plugin/RELEASE_MANIFEST.json`。原 `DELIVERY_SHA256.json` / `UPSTREAM_HASHES.json` 仅保留历史来源。拟态 `reports/release_20261016/` 和 agent 历史冻结树 **未随本工程交付**，不声称它们存在或已复验；详见各插件 `PINS_README.md`。

完整拟态宿主链现支持 Windows Job 或 POSIX 进程限制，需 GCC/G++。本机集成脚本可探测已有 RedPanda MinGW，不会自动安装工具。主链联动使用 ModelSim，不依赖 Icarus；原插件的 Icarus 专用脚本仍需其实际工具，缺工具不能用参考推理冒充 RTL。宿主实时预算与协同仿真的区别详见集成文档。此命令范围不包含上板；兼容分析入口及器件阶段边界见下文。

## 未完成范围

SNMPv3 authNoPriv/authPriv；615A 完整 information/find、所有下载选项及全部版次语法；多 LUH 原子聚合；665-1/0x8002 完整 parser、batch/media 等全语法；官方标准认证；FPGA fitting、布局布线、时序收敛、PHY/电气及板级验证。详细边界见 `docs/competition_profile.json` 和 `docs/COMPLETE_IMPLEMENTATION_STATUS.md`。


## 可移植复现与依赖（2026-11-03修订）

Python 3.12及以上。先执行 python -m pip install -r requirements.txt。
NumPy和cryptography需要额外安装；vendor只内置pysnmp/pyasn1等协议依赖。
ModelSim需要有效许可；统一联动还需要可在PATH发现的gcc/g++（或直接驱动的--cc/--cxx）。
工具路径可用AFDX_MODELSIM、AFDX_ELINX环境变量指定。不要改写证据为PASS。

    python -B -m unittest discover -s tests -v
    Push-Location aihw_plugin; python -B -m unittest discover -s tests -v; Pop-Location
    python -B -u scripts/run_all.py --hdl-only --workers 4
    python -B -u scripts/run_all.py --elinx-only --elinx "你的quartus_map.exe路径"
    python -B report_tools/build_source_package.py --output "工程目录以外/新文件名.zip"

--elinx-only分别运行正式防御顶层与基础顶层的单/双服务域兼容分析。
输出逐项区分analysis_elaboration、target_synthesis、place_route、timing。
QSF的EP1S80是兼容分析占位器件，不能代替EPR中EQ6HL130目标器件综合。
本交付不声称已经完成EQ6HL130综合、布局布线或时序收敛。

采集API DefenseRuntime.acknowledge_policy(policy) 只供可信控制器在RTL策略已提交、
待处理帧排空后调用；不会凭读取到的epoch自动信任一份未知策略。
缺测、无字节帧窗口或采样边界会清空旧历史及旧推理，重新收集连续8个有效窗口。
运行证据及截图对应关系见 docs/REVIEW_20261103.md 和 evidence/INDEX.md。
保留已有pyc文件；复现以.py为准。根清单覆盖发布文件，排除results等生成目录。
