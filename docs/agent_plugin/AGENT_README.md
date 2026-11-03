# AFDX 智能体插件

基于已训练的三个小模型，实现“诊断—选择工具—查看证据—主动实验—复核—策略建议—报告”的有界闭环。规划器是可审查的状态机：模型提供先验，独立证据会改变调查焦点和下一步动作；不需要语言模型、GPU或云API。

原AFDX架构、网安插件与三个模型权重均未修改。智能体运行在电脑上，读取观测窗口和证据，在自己的实验目录执行软件注入及真实安全RTL重放，输出建议给既有可信配置流程。

| 功能 | 本包实际执行 |
|---|---|
| 故障诊断 | 调用分类、异常检测、时延预测三个模型，核对加载、时间、双网及计数器证据 |
| 证据追溯 | 解析FCS/IPv4/UDP、比较逻辑副本、检索日志行号、解析160位事件及快照，保留文件哈希 |
| 主动验证 | 生成合法校验的内容篡改与坏CRC负对照；重放捕获帧；运行六类固定RTL实验；进行负载反事实并重新调用模型 |
| 策略建议 | 根据正常逻辑流量预算生成速率窗口/帧配额候选，核对修改范围并在隔离RTL中比较原值与候选 |
| 自动报告 | 输出Markdown、结构化JSON、逐工具结果、原始实验日志与哈希链；区分候选、局部事实、实验复现及待验证事项 |

## 直接运行

需要Python 3.12或兼容版本，推理仅需NumPy。真实RTL实验需要本机安装Icarus Verilog 11或兼容版本的 `iverilog`、`vvp`。

```sh
python -m pip install -r requirements.txt
python -m afdx_agent run --case cases/ab_conflict --out runs/ab_demo --rtl required
python -m afdx_agent verify --run runs/ab_demo
```

打开 `runs/ab_demo/report.md` 查看完整报告，`trace.jsonl` 保留调用序列，`tools/` 为每次工具的结构化回执，`experiments/` 为实际注入、重放和RTL日志。

只用CPU、不启动HDL仿真时：

```sh
python -m afdx_agent run --case cases/model_disagreement --out runs/software_demo --rtl off
```

此模式仍执行模型、报文比较、受控软件注入和报告；RTL项明确标为unavailable，报告不会写成已经通过。默认 `--rtl auto` 会在Icarus可用时执行；要求完整RTL证据时使用required。

工具不在PATH时，可增加 `--iverilog /path/to/iverilog --vvp /path/to/vvp`；可重定位安装需要时再增加 `--ivl-base /path/to/ivl`。仅接受可信用户通过CLI/环境提供的程序路径，不从报文、日志或案例文件执行程序指令。

## 十个演示案例

| 案例 | 展示重点 |
|---|---|
| normal | 常规模型及原始帧检查、基线实验 |
| ab_conflict | 双网内容差异、受控注入、捕获帧实际RTL重放 |
| model_disagreement | 模型初判正常，原始帧证据改变调查方向 |
| compound | 同时发现双网分歧和时间交换异常，不强行压成唯一根因 |
| congestion | 负载实验、计数器核对、模型复核及速率候选对照 |
| loader_stall | 加载无进展超时证据与阶段/TID实验 |
| time_anomaly | Q32.32时间计算及NTP异常/恢复实验 |
| fragment_pressure | 重组预算、孤儿分片、预算释放的RTL实验 |
| missing_measurements | 不补零、不把独立回归夹具当成当前窗口事实 |
| fcs_error | 独立CRC核对及格式拒绝/恢复机制 |

案例是明确标注的合成实验或既有RTL回归夹具；不是十台真实设备，也不是重新评测模型准确率。三个模型原来的合成训练与局限完整保留在 `docs/UPSTREAM_MODEL_CARD.md`。

## 接入现有工程

```python
from afdx_agent.agent import Agent

report = Agent(rtl_mode='auto').run('my_case', 'runs/my_investigation')
```

案例格式、测量单位和证据绑定见 [接口](docs/INTERFACES.md)。已有160位安全事件、计数器寄存器和观测窗口通过外部只读适配接入；模型输入不包含原因码，证据工具单独核对原因码。

安全RTL实验使用 `security_lab/` 中与原网安包逐字节相同的八个模块及原通用测试台，验证完整帧准入/重放和相关状态；**不等同于原AFDX完整业务系统的联合仿真或板级测试**。模型时延与抽象队列实验也不构成最坏时序保证。

## 策略如何交付

`report.json` 的policy字段包含建议、允许字段的old/new、影子寄存器位置、expected_epoch及原规则哈希。限流候选只改window/max_frames，并保留地址、协议阶段、签名授权与其他规则属性。需要配置方复制完整活动策略到影子表、重查epoch/原值、运行正常流量影子试验，再通过原有可信流程原子应用。智能体只在隔离仿真中写入测试配置，不写设备，不生成可直接覆盖全部策略的残缺事务。

工具步数默认16，最大24。缺数据、超预算、工具失败、不适用捕获或缺少仿真器都会保留为报告限制；不会把未执行实验变成PASS。哈希链用于可追溯和意外改动检测，不是数字签名或来源认证。

## 验证

```sh
python scripts/validate.py --out reports/my_validation --rtl required
```

选择新输出目录。脚本运行测试、十案例闭环及六类固定 RTL 实验，逐事件和逐字节核对转发结果，并验证源码、模型及案例哈希。上游历史 `reports/release_agent_final_20261015/` 未随当前工程交付；本目录 `VALIDATION.md` 仅保留历史摘要，当前源码清单和新运行入口见 `PINS_README.md`。
