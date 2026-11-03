# 插件接入与数据契约

## 运行位置和依赖

本插件是电脑端Python插件，不占用AFDX实时转发通路。三个原模型通过NumPy推理；有界状态机根据模型候选、原始证据与工具结果选择下一步动作。它不包含语言模型、自然语言规划器或任意代码执行工具。

直接调用：

```python
from afdx_agent.agent import Agent

agent = Agent(rtl_mode='auto', max_steps=16)
report = agent.run('my_case', 'runs/my_case_001')
```

输出目录必须是新目录，且位于输入案例目录之外。输出目录名不能复用。Agent实例保存本次调查状态；并发调查应使用不同实例与输出目录。命令行例子见根目录README。

`rtl_mode`可为auto、off、required。程序路径仅由可信调用方提供；可用参数`iverilog`、`vvp`、`ivl_base`。每次仿真先校验`security_lab/manifest.json`中的源文件哈希。仿真器不随本ZIP附带，请本机安装Icarus Verilog。

## 输入目录

`case.json`只允许下列字段，未知字段会被拒绝。完整样例见`cases/congestion/`与`cases/ab_conflict/`。

```json
{
  "schema": 1,
  "case_id": "my_case",
  "observation": "observation.json",
  "artifacts": [
    {
      "id": "pair",
      "type": "frame_pair",
      "paths": ["A.bin", "B.bin"],
      "source": "external_capture",
      "binding": "same_window",
      "window_id": "capture-0001"
    }
  ],
  "expected_flow": {
    "peer_ip": 167772161,
    "local_ip": 167772176,
    "rx_mac": 3298534883344,
    "peer_mac": 2199023255554,
    "tx_mac": 3298534883346,
    "source_port": 100,
    "destination_port": 200
  }
}
```

`expected_flow`来自可信实验配置，整数分别代表IPv4、48位MAC与16位端口。它用于隔离RTL规则和捕获重放匹配，不会发包到实际MAC。不要让收到的报文自行改写这份可信配置。

`observation`可以为null：智能体仍检查证据，但不调用缺少测量的模型。案例id与证据id允许字母、数字、下划线、连字符，最长64字符。文件路径必须为案例根目录内的相对路径，不允许绝对路径、上级路径或符号链接逃逸。最多24个证据项、50个输入文件、每文件8MiB；运行前后核对输入哈希。JSON拒绝重复键及非有限数值。

证据来源可为synthetic_lab、rtl_fixture、external_capture、hardware_capture。来源是采集方声明，哈希不能认证真实来源。`binding=same_window`要求window_id与观测一致；`reference_fixture`表示独立参考实验，其发现不会提高当前窗口的调查优先级。实际采集方还须确保时间范围、VL/服务域及设备身份一致；字符串绑定本身不构成这一保证。

## 观测窗口和三个模型

`observation.json`恰有六个字段：schema=1、source、window_id、window_duration_s、scope、metrics。source取synthetic、rtl_capture或hardware，时长单位秒且必须为正。冻结模型只接受以下工作剖面：

```json
{"clock_hz":12500000,"link_mbps":100,"security_mode":2}
```

metrics必须完整提供18项，不允许用事件原因码、标签或补零值代替真实测量。每项的统计口径应与原模型卡一致。换链路速率、时钟、模式或统计定义需要重新校准模型，并使用新的模型注册版本。

| 字段 | 含义/单位 |
|---|---|
| observed_pps | 每秒输入逻辑帧数；范围0–200000 |
| mean_frame_bytes | 平均MAC帧长，包含FCS，不含前导码；64–1518字节 |
| frame_size_cv、arrival_cv | 帧长、到达间隔变异系数 |
| ab_unpaired_ratio、ab_payload_mismatch_ratio | 双网未配对比例、同逻辑消息内容不同比例 |
| fcs_error_ratio、queue_overflow_ratio | FCS错误比例、输入队列丢弃比例 |
| latency_p95_us | 测量窗口时延95分位，微秒 |
| ntp_rtt_ms、ntp_offset_abs_ms、clock_step_abs_ms | NTP往返、偏移绝对值、时钟跳变量，毫秒 |
| loader_progress_ratio、loader_retry_ratio | 加载进度、重试比例 |
| fragment_orphan_ratio | 孤儿分片比例 |
| management_fraction、active_context_ratio | 管理流量比例、活动上下文占用比例 |
| sha_jobs_per_1k_frames | 每千帧SHA任务数 |

所有比例取0–1，其余精确边界见`afdx_ai/schema.py`。三个模型分别输出故障候选、异常分数、条件时延预测。森林投票份额不是经过校准的概率。直接同窗口证据可改变工具调查顺序，增加的优先级分数也不是后验概率。合成训练和异常召回限制见`UPSTREAM_MODEL_CARD.md`。

## 原始证据类型

| type | 内容与工具 |
|---|---|
| frame / frame_pair | 一个或两个完整二进制线路帧，含8字节前导码/SFD、MAC帧、AFDX序号及FCS；合法总长72–1526字节。独立解析FCS、IPv4头和UDP；先核对逻辑消息身份，再归一化正常A/B接口差异并比较业务内容。 |
| events | 原网安插件160位事件十六进制日志，每行两或三列，末列为事件；前列十进制。最多30000行。保留原始行号及epoch/channel/flags等ABI字段；原因码只用于证据。 |
| log | UTF-8文本日志，最多20000行；最多六个字面关键词，每词40字符，最多返回20条和原行号。日志内容不会成为程序指令。 |
| time_samples | JSON字段schema=1、offset_limit_ms、samples；每样本t1/t2/t3/t4为64位NTP Q32.32整数，最多1000条。计算偏移和往返，不验证服务器身份；当前工具不处理跨NTP纪元的采样。 |
| loader_trace | JSON字段schema=1、events；每事件恰有time_ms/kind/tid/block/data_hex，kind为request/data/ack/timeout/complete，最多1000条；核对无进展超时、TID、块序和重传内容。它不是完整615A/665文件验证器。 |
| counters | JSON字段schema=1、start、end、duration_s；两个快照各有boot_id、epoch、mode及完整九项counters。核对同一启动、策略与模式边界，再计算增量。 |
| policy | JSON字段schema=1、epoch、rule_id、rule、requirements；rule完全复用原`security_lab.policy.Rule`字段，requirements恰有max_normal_logical_pps和burst_frames。必须由可信配置方给出正常预算与当前规则。 |

实际捕获重放仅对符合冻结测试台支持范围且与expected_flow相符的完整IPv4/UDP帧执行；不支持的分片、IP选项或不匹配路径会明确返回inconclusive。软件内容注入也要求完整UDP基线，生成正常接口差异对照、重新计算UDP/FCS的内容变化和坏FCS负对照，保存在实验目录。

## 现有寄存器/事件适配

`afdx_ai.bridge.read_counters(read32, boot_id)`保留原只读适配函数。由宿主提供read32，不内置设备驱动；采集方负责取得一致快照并记录启动标识和单调时间。epoch为地址0x08，mode为0x00；九项计数器如下。

| 字段 | 地址 |
|---|---|
| accepted / blocked | 0x40 / 0x44 |
| queue_overflows / event_overflows | 0x48 / 0x4c |
| ab_conflicts / hash_failures | 0x50 / 0x54 |
| time_alarms / context_timeouts / observed | 0x58 / 0x5c / 0x60 |

同一boot_id/epoch/mode的快照可计算observed_pps和queue_overflow_ratio。只有接近32位上界到接近零的变化才接受为一次正常回绕；复位或不明确下降返回inconclusive。采样间隔必须短到不会多次回绕；静默复位须由采集方更新boot_id。九个计数器不足以生成完整18项输入，插件明确保留缺项，不据此自动补成可推理窗口。

## 工具预算和策略交付

工具白名单见`afdx_agent/tools.py`，默认16步、最大24步；同一工具/参数不重复执行。固定RTL实验为ab_integrity、loader_phase、time_response、fragment_budget、rate_baseline、rate_candidate。抽象队列反事实采用成对种子，默认12次，降低输入速率后再次调用模型；这是条件实验，不证明部署设备实际降载后的时延。

速率建议仅修改原规则window、max_frames，保留其余全部规则字。演示预算1000逻辑帧/秒加4帧突发，在12.5MHz下得到125000周期窗口、14帧上限。原策略更严格时不放宽。候选附expected_epoch、原规则哈希、允许字段old/new及影子地址；仅当原值和候选的隔离RTL对照均通过时标为lab_checked_candidate。

智能体不写在线配置。配置方须复制完整活动表到影子表、复核epoch与原值、验证所有部署流及正常流量、经既有可信流程原子提交。单条候选不能替代完整配置事务，隔离RTL实验也不能替代完整策略验收。

## 输出、审计与退出码

`report.md`用于阅读，`report.json`用于集成；`tools/`保存每次工具JSON，`experiments/`保存注入字节、真实RTL向量和日志，`trace.jsonl`串联参数、耗时、结果路径及SHA256，`completion.json`绑定两份报告及链尾。用`python -m afdx_agent verify --run <目录>`检查意外改动。链条和清单没有签名；攻击者若能重写全部文件，也能重算哈希。

report中verified_local_findings是核对后的局部事实，confirmed_physical_root_cause保持null；实验结果与模型候选分别记录。证据在调查中变化会撤销局部发现并报告integrity_failure。工具失败写入errors；缺数据不补零，关闭或缺少仿真器不会记为PASS。

CLI正常完成返回0，输入/启动失败返回2，工具或证据完整性失败返回3，预算耗尽返回4。off模式可正常返回0，但validation_status为partial；退出0仅表示调查过程正常结束，不代表板级、工业认证或全部验证完成。
