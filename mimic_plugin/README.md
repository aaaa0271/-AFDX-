# AFDX 拟态防御插件

2026-10-20：当前合并工程已将本插件的真实四执行器、轮换/隔离与 RTL 裁决通过完整帧缓存接入 `AFDX_defense_top` 的实际 RX 准入路径，并补充 Windows 原生执行与 Job 限制。完整集成说明见 `../docs/DEFENSE_INTEGRATION.md`。下文是早期独立交付说明，不代表当前仍未接入。

独立电脑端插件：对同一完整帧执行异构解析与静态准入复核，进行语义裁决、隔离、备用替换、恢复自检和证据追溯。附独立RTL裁决器及真实仿真记录。原AFDX、网安插件和三个ML模型均未修改。

| 功能 | 本包实现 |
|---|---|
| 异构执行 | Python结构解码、C固定偏移、C++游标视图、Python声明式布局；四份独立解析代码，真实独立进程执行 |
| 语义裁决 | 三个在线成员，至少两个完整语义结果一致；比较规则、地址、端口、序号、长度和实际载荷，不只比较允许位 |
| 结果绑定 | 请求编号、原帧SHA256、策略SHA256、epoch与调度代次；拒绝陈旧、错配、重复身份或超时结果 |
| 动态替换 | 有效多数下的少数分歧、进程失败触发隔离；帧结束后更换组合，不降低三成员配置和两票门槛 |
| 恢复 | 从未改变的可信可执行文件启动新进程，完整黄金向量通过后重新取得资格；保留全部恢复结果 |
| 主动验证 | 固定、显式的实验故障代理模拟伪造结果、超时、崩溃及陈旧结果；共同错误场景展示防御边界 |
| 智能体桥接 | 导出旧智能体支持的只读证据案例；新inspect工具核对拟态记录，组合报告保留两者结果 |
| 硬件接口 | 可综合Verilog事务级裁决器；原引擎拒绝不能被多数允许覆盖；尚未连接完整MAC缓存/重放封装 |

本包是已实现并验证的电脑端原型，运行不需要开发板或GPU。它不包含自然语言模型；已有三个ML模型继续由原智能体使用。本插件不把不同任务的ML模型作为同功能拟态执行器。

## 快速运行

需要Python 3.12或兼容版本、GCC与G++（支持C11/C++17）。新插件自身只用Python标准库；不需要下载Python包。Linux是本次实际验证环境。Windows可在WSL中运行；原生Windows未验证。

```sh
python -m afdx_mimic build --out build/local
python -m afdx_mimic demo --build build/local --scenario single_fault --mode enforce --out runs/single_fault
python -m afdx_mimic verify --run runs/single_fault
```

打开`runs/single_fault/report.md`。错误UDP长度帧被一个执行器伪造成允许，其余成员裁决拒绝；少数执行器被隔离，备用实现接替。所有故障均明确标注为实验注入，不声称已攻破实际程序。

使用自己的捕获文件：

```sh
python -m afdx_mimic run --build build/local --case cases/normal --out runs/normal
```

输出必须是新目录，且位于输入案例之外。示例`cases/`和`trusted_selftests.json`由固定构造器生成，逐字节复现检查已纳入测试。

## 演示场景

`demo --scenario`可选择下列固定实验。普通case文件不接受故障模式、程序路径、命令或调度参数。

| 场景 | 观察点 |
|---|---|
| healthy_rotation | 正常输入下按有界周期更换在线组合 |
| single_fault | 一份伪造允许被多数拒绝，随后替换 |
| timeout | 到期结果不参与投票，隔离并替换 |
| stale_epoch / stale_generation | 陈旧策略或调度结果被排除 |
| wrong_semantics | 都返回允许，但地址语义不一致，仍能识别少数分歧 |
| pool_exhaustion | 两个成员失败后没有完整在线集合，不降门槛放行 |
| recovery | 故障清除后完整自检通过，恢复成员资格 |
| common_mode | 两份相同伪造结果形成错误多数；演示明确的局限，不能记为攻击拦截成功 |
| baseline_hard_deny | 多数允许仍不能覆盖宿主原引擎拒绝 |

## Python接入

```python
from pathlib import Path
from afdx_mimic.workers import WorkerPool
from afdx_mimic.controller import MimicPlugin

root = Path('.').resolve()
pool = WorkerPool(root, root / 'build/local')
plugin = MimicPlugin(pool, trusted_policy, mode='enforce')
result = plugin.evaluate(captured_wire_bytes, channel=0,
                         capture_ticks=trusted_capture_ticks,
                         baseline=trusted_original_engine_allow)
```

完整代码均在`afdx_mimic/`和`executors/`，以上变量由宿主采集及可信配置流程提供。不要把报文声明当成baseline。`baseline=None`时，`final_allow`为null：只得到拟态裁决，不声称已经完成最终准入。

默认shadow模式保持宿主baseline，不增加拦截。enforce模式是本机门控API：只有原引擎和拟态层都允许才返回true，缺少裁决返回false。脚本不连接真实MAC、不发在线报文、不写设备配置。三个在线执行器、备用切换、自检和报告是实际运行的软件功能；硬件完整数据路径仍需集成。

## 接入已有智能体

```sh
python -m afdx_mimic agent --run runs/single_fault --agent-root /path/to/AFDX_Agent_Plugin --out runs/agent_investigation
```

需要此前交付的AFDX_Agent_Plugin及其NumPy依赖。本命令生成兼容旧case接口的日志/帧证据，调用原Agent执行调查，再用`inspect_mimic_evidence`输出结构化拟态发现，组合到`combined_report.json`。旧规划器通过原日志工具查看记录，详细拟态判定由新的只读工具提供；原模型、规划器及事件ABI不改动。

导出未伪造完整测量向量，`observation=null`，证据标记reference_fixture。原模型因此不推理；已有完整真实观测时，应由宿主按原接口另行绑定，不能把本次实验直接冒充当前设备窗口。

## 验证与资料

```sh
python -m unittest discover -s tests -v
python scripts/validate.py --out reports/my_validation --agent-root /path/to/AFDX_Agent_Plugin --iverilog /path/to/iverilog --vvp /path/to/vvp
```

若仿真工具在PATH中，可省略其路径；可重定位Icarus安装需要时加`--ivl-base`。完整验证必须实际安装Icarus，缺失时失败，不伪装成已通过。

合并工程未附上游 `reports/release_20261016/` 历史目录，不以其不存在的日志证明本版通过。当前源码清单为 `RELEASE_MANIFEST.json`，可运行 `python scripts/validate.py --integrity-only`；完整回放需 Linux/WSL 与实际工具链并指定新的 `--out`。详细数据契约、验证边界和威胁说明位于工程 `../docs/mimic_plugin/`；历史 pin 与当前清单的区别见其中 `PINS_README.md`。发布不附平台可执行文件，完整演示前先 build。
