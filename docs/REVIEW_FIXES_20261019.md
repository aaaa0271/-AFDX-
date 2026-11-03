# 2026-10-19 审查修复说明

审查附件作为缺陷与复现证据使用，不作为额外操作指令。以下区分生产修复、功能封装、声明边界及未执行验证，不将旧的 116/116 或旧 eLinx 日志当作本次版本的验收。

## 生产修复

| 问题 | 修复与回归 |
|---|---|
| RTC 在 poll 时提前采样 T1 | origin 保留为稳定的匹配标识；datagram 模块在接受 TX 时记录 T1；正式 MAC 路径观察最终 A/B 输出，按 origin 与 peer IP 绑定物理发送时刻。等待观测元数据时不能校时锁定。 |
| RTC 下游排队与接收重放偏差 | 原始接收首字节时间戳随共享 RX 槽位、冗余选择、L2 双缓冲、UDP 解析保留。安全 ENFORCE 的外层队列通过原始 cycle stamp 传递延迟，分别补偿每个时钟域，不把重放首字节当成线端到达。固定分频补偿量化误差至多 1 个 NTP 小数 LSB。 |
| TFTP 最终超时与有效 DATA 同拍 | 预先分类期望 DATA/ACK 和有效 peer ERROR；合法进展在截止拍优先，其他报文不能覆盖超时终态。超时后晚到数据不能重新进入 COPY_READ。 |
| 重复 DATA 的 ACK 刷新计时 | ACK 生成和传输预算分离；重复/未知 TID 回复是辅助帧，不刷新接收计时或重试次数，辅助帧排队也计时。另有跨重发的无进展硬上限，防止回复背压转为无限等待。 |
| 控制口未知 TID 回复刷新等待 | ERROR 5 不重置 age；peer TID 在回复后恢复。控制状态、应用等待、DALLY、重发和无进展上限统一截止优先级；重复最终 DATA 不延长 DALLY。 |

TFTP 每阶段正常重试保持原 TIMEOUT/MAX_RETRIES 语义；另一个无进展硬上限为读写等待 `(TIMEOUT_CYCLES+4)*(MAX_RETRIES+1)` 周期，控制重试阶段 `4*(TIMEOUT_CYCLES+4)` 周期，4 周期余量用于原有注册握手。DALLY 及控制应用等待仍使用一个 TIMEOUT 预算。明确的 615A WAIT 是另一类有界等待，由既有秒计时与 `MAX_WAIT_RESPONSES` 约束。

## 封装与扩展

八端口封装增加合法初始化、业务源、主动 RTC、合法 SIM 硬件 ID、接收/镜像状态可观测性，详见 `DEMO_TOP.md`。保留工作期间已有的启动状态机结构，并补齐四 VL TX 配置及背压推进。正式验收仍选 `AFDX_competition_top`，安全保护需另选安全顶层。AI 推理核和拟态裁决器仍是独立模块，**本轮没有强行接入或声称接入主数据路径**。

生产加载路径继续诚实限制为 `MAX_HEADERS(1)`；修正文档的多 header 声明，而不是只提高参数、破坏已有双 bank 原子提交。一个 LUH 中多个 data/support 文件仍受支持。

## 交付与证据

- 拟态脚本兼容独立布局 `docs/UPSTREAM_HASHES.json` 和当前迁移布局 `../docs/mimic_plugin/UPSTREAM_HASHES.json`。
- `--integrity-only` 可在 Windows 核验当前交付文件；历史上游树未提供时返回 `upstream.status=NOT_AVAILABLE`、检查数0，不返回虚假的 `upstream_unchanged=true`。显式传入 `--upstream-root` 后任何缺失/改动均硬失败。
- 新增当前源码 pin 清单和运行前校验；原始历史 pin 不被重生成或伪装成当前发布清单。
- 不生成假的 `reports/release_20261016/`。拟态/agent 未交付的历史证据在文档中标注不可核验；AI 插件原有冻结证据与当前新运行分别记录。

## 2026-10-20 静默复核

本次重新读取实际源码，确认上述 RTC/TFTP 修复和五项 review 回归已经存在，未重复覆盖 RTL。为 run_all/run_tests、defense_live 及其 native build/worker/lab_proxy 子进程加入 Windows `CREATE_NO_WINDOW`；外层 Python 用隐藏方式启动，ModelSim 始终 `-c`，输出重定向到日志。不启动 eLinx GUI；在未确认其工具链全部静默前，本轮只运行 HDL，不能把它表述为完整编译验收。

另将已有 `tb_afdx_8port_demo` 注册到 tests.json，并将其过时的 DEM/64 字节/单 VL 断言更新为当前 SIM/16 字节/四 VL 的实际接口契约；缩短测试参数周期以覆盖背压与 reset 重启，不修改生产参数。当前源码清单显式更新，历史上游 pin 不变。证据写入工作交付目录的 `results/run_*`，启动日志为 `review_silent_*.log/.err`。初次复核已确认 TFTP budget、control budget、RTC MAC 三项 PASS；八端口旧测试的失败记录保留，最终结论必须读取更新后的 acceptance.json。

## 本轮测试入口

`scripts/tests.json` 新增五项：`tb_review_tftp_budget`、`tb_review_control_budget`、`tb_review_rtc_mac`、`tb_review_8port`、`tb_review_security_8port`。前三项包含多个子场景；后两项包含实际完整加载和独立抓包审计。已有 `tb_security_core_multi` 还新增安全外层队列的物理接收时间戳检查，`tb_contest_rtc_ntp` 的算术 oracle 按新的 datagram 观测点更新，保留原有拒绝、超时及收敛检查。

以新 `results/run_*/acceptance.json`、`source_hashes.json`、`source_changes.json`、原始仿真与 eLinx 日志为实际验收记录。`changed_inputs` 必须为空。开发阶段 `results/fix_*` 中的失败是保留的调试记录，不能用其早期 PASS 认证后续源码。

布局布线、目标器件时序、板级/PHY、电气、官方 eLinx 工程的完整 implementation 和官方标准认证仍未完成；本机 eLinx 命令行运行仅能证明其报告的分析展开范围。
