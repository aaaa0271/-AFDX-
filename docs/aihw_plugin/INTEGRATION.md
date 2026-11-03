# AFDX AI 硬件推理插件 R1 — 接入说明（INTEGRATION）

**2026-10-20 集成更新**：原 TCN 现已由 `AFDX_defense_top` 实例化，真实测量经 `host/defense_runtime.py` 预处理送入硬件 CSR，结果连接告警与可选限时 RX 阻断；原有智能体也能消费同一实际窗口。完整接口与验证见 `../DEFENSE_INTEGRATION.md`。下文保留的是早期独立交付记录，“未接线/零改动”等描述不再代表当前工程。未做上板和新增 eLinx 展开。

本文件记录 AFDX AI 硬件推理插件（`AFDX_AI_Hardware_Plugin_R1`）接入本竞赛工程的
落点、边界与验证情况。接入遵循一条硬规则：**不改动原有架构**——不动三层顶层、
不动工程文件集、不动回归清单、不动既有源码。

## 1. 落点布局

插件整树放入工程根新目录 `aihw_plugin/`，忠实保留其内部相对路径（插件脚本用
`Path(__file__).resolve().parents[1]` 定位插件根，恰好指向 `aihw_plugin/`）：

```
aihw_plugin/
    afdx_ai_hw/        主机驱动与整数/CSR 运行时（6 文件）
    rtl/               独立 RTL 核与固定 ROM
                       afdx_ai_tcn_plugin.v / afdx_ai_csr.v
                       ai_model_params.vh / weights.mem / biases.mem
                       thresholds.mem / shifts.mem
    tests/             tb_tcn_plugin.v / tb_csr.v / tb_arithmetic.v
                       tb_hw_infer.v / test_host.py / test_csr_driver.py
    scripts/           run_all.py / validate_rtl.py / make_vectors.py
                       export_model.py / verify_export.py / verify_release.py
                       evaluate_quantization.py / make_hardware_holdout.py
                       reproduce_training.py
    models/            model.json / quantized.npz
    source_model/      原训练程序、训练/验证/OOD/留出数据与权重
    examples/          history.json / run_extension_agent.py
    integration/       files.f / ai_clock_example.sdc
    docs/              随包文档（INTERFACES / MODEL_CARD / VALIDATION /
                       INTEGRATION / UPSTREAM_MODEL_PROVENANCE，见第 6 节）
    evidence/          冻结交付证据 release_20261016/
    reports/           运行时输出目录（仅占位文件 .gitkeep，见第 2 节）
    README.md  RELEASE_MANIFEST.json  requirements.txt  requirements-train.txt
```

采用独立根目录而非展开到工程根，是因为插件自带的 `docs/`、`examples/`、`models/`、
`rtl/`、`scripts/` 五个目录与工程根**同名**；展开会与工程既有目录发生路径碰撞。
`aihw_plugin/` 不参与工程 ModelSim 编译文件集，也不在 `scripts/run_all.py` 的
`inputs()` 哈希范围（该函数只覆盖 `rtl,tb,scripts,vendor,docs` 与根级清单文件），
故不影响既有回归与工程设置一致性判定。

随包文档**保留在 `aihw_plugin/docs/` 原位**，未按 `docs/security_plugin/`、
`docs/agent_plugin/`、`docs/mimic_plugin/` 的加前缀约定迁至工程 `docs/`。原因是插件
自带 `scripts/verify_release.py` 按 `RELEASE_MANIFEST.json` 的**相对路径**逐条校验
完整性，迁移文档会使该清单的 5 条 `docs/*` pin 变为"缺失"，从而破坏插件自带的
完整性验证。本工程因此选择**保真优先**，仅在工程 `docs/aihw_plugin/` 放置本文件作为
项目侧入口。

## 2. 原有架构零改动（含报告目录处理）

本插件与先前的网安、智能体、拟态插件不同：其 RTL 与测试台**依赖外部数据文件**，
由 `$readmemh` 在运行时加载——固定 ROM（`rtl/weights.mem`、`biases.mem`、
`thresholds.mem`、`shifts.mem`）与生成向量（`reports/vectors/*.mem`），并依赖
`ai_model_params.vh` 头文件包含。工程既有 `run_hdl`（`scripts/run_all.py`）只把
`tb/*.hex` 复制进每用例的仿真目录、且 `vlog` 的 `+incdir` 只指向 `tb/`。若把这些
RTL/TB 挂进工程文件集与回归清单，将连带要求：修改运行器（增补 `.mem`/`.vh` 复制）、
为合成流程补 `ai_model_params.vh` 搜索路径、并把两个带运行时文件依赖的模块并入**评委
编译文件集**；同时 `test_packaging.py::test_test_resources` 会拒绝非裸文件名的
`$readmemh` 路径。以上均构成对原有架构的改动。

按既定约束（不改动原有架构），本工程对以下对象保持**零改动**，已复核：

| 对象 | 状态 |
| --- | --- |
| 三层顶层（`AFDX_top` / `AFDX_competition_top` / `AFDX_legacy_top`） | AI 插件未接入；八端口是建议接口的演示封装，2026-10-19 核心修复另见 `../REVIEW_FIXES_20261019.md` |
| 工程 RTL 文件集 `rtl/*.v` | 115 个，未增未减 |
| 工程 TB `tb/*.v` | 未增未减 |
| `ARINC.qsf` / `ARINC.epr` | 未修改（`VERILOG_FILE` 计数 115 与 `rtl/*.v` 一致） |
| `scripts/tests.json` | 116 条，未增未减 |
| `scripts/run_all.py` 及其余 `scripts/*` | 未修改 |

因此该插件的 RTL 与测试台**不进入**竞赛编译与回归流程，仅以独立模块形态随工程交付，
并在需要时由系统外层包装单独实例化（见第 5 节）。

`reports/` 为插件的可写运行时输出目录。经核对，`RELEASE_MANIFEST.json` 的 87 条 pin
**不包含** `reports/` 下任何文件，故按"交付件不携带历史结果"约定排除其内容不破坏
完整性校验；仅保留 `reports/.gitkeep` 占位，以维持插件脚本对 `ROOT/'reports'` 的
写入前提。

## 3. 本机已执行的验证（Windows）

在 `aihw_plugin/` 下、`PYTHONDONTWRITEBYTECODE=1` 环境中实测：

- **拷贝保真度**：对 `RELEASE_MANIFEST.json` 的 87 条 pin 全量逐字节比对——
  **87 匹配 / 0 不匹配 / 0 缺失**。
- **插件自带完整性校验**：`py -3 scripts/verify_release.py` →
  **`RELEASE_INTEGRITY_PASS 87`**，退出码 0。
- **宿主侧单元测试**：`py -3 -m unittest discover -s tests -p "test_*.py" -v` →
  **`Ran 34 tests ... OK`**，退出码 0（含浮点/整数舍入、NaN/无穷/重复键 JSON 拒绝、
  越界与量化范围拒绝、CSR 操作序列、参考溯源等）。
- **参考模型推理路径**（不依赖 Icarus）：
  `py -3 -m afdx_ai_hw infer --history examples/history.json --backend reference` →
  **`INFER_PASS`**，退出码 0，输出标注来源为 reference。

## 4. 平台门控（如实标注，未伪装通过）

插件的 RTL 回放与整套编排以 **Icarus Verilog** 为前提。本机（Windows，PowerShell 5）
经实测不可用，此处如实记录，未以任何方式伪装为 PASS：

| 能力 | 依赖 | 本机状态（实测） |
| --- | --- | --- |
| RTL 仿真后端 `afdx_ai_hw/runtime.py::tools` | `iverilog`、`vvp` | 不存在 → 抛 `RuntimeError('Install Icarus Verilog or set IVERILOG')`。`-m afdx_ai_hw infer`（默认 RTL 后端）**硬失败**，**不退回参考模型冒充 RTL**（实测退出码 1） |
| RTL 校验 `scripts/validate_rtl.py` | `iverilog`、`vvp` | 同上，不可用 |
| 一键编排 `scripts/run_all.py` | Icarus（`rtl_validation` 阶段） | 不可用 |
| 重新训练 `scripts/reproduce_training.py`（`--retrain`） | `requirements-train.txt`（scikit-learn 等） | 未安装，未运行 |

因此，**依赖 Icarus 的 RTL 三用例回放与 `ALL_VALIDATION_PASS` 终态未在本机运行**。
其原始冻结证据保留在插件交付包、并随本工程一起位于
`aihw_plugin/evidence/release_20261016/`（本工程不复制到别处、不改写、不替代）。
该冻结证据记录：7 个阶段全 PASS、RTL 三用例（`tb_tcn_plugin` / `tb_csr` /
`tb_arithmetic`）全 PASS、**388 条向量 / 3492 个 logits / 111744 个中间值 / 12 项
协议用例**、固定计算周期 14035（@12.5 MHz 约 1122.8 µs），且
`synthesis_performed=false`、`target_timing_closed=false`、`board_tested=false`。

## 5. 与工程的接线方式（不在本版执行）

按插件自身设计，AI 核应作为**独立诊断通道**接入：在系统外层包装中实例化
`afdx_ai_tcn_plugin` 或 `afdx_ai_csr`，接到独立可信本地数据通道。AI 输出是带模型
版本（32 位 `model_tag`）的**诊断证据**，由既有可信配置流程决定是否采纳；主业务链
**不新增 AI 反压依赖**，也没有 AI 自动改时钟、加载内容或防火墙配置的连线。

这符合本工程既有约定：扩展能力经 `AFDX_competition_top` 参数化与用例/文档验证暴露，
**不在 `AFDX_top` 上增加端口**。本版仅完成插件落点与文档化，未做器件综合、布局布线、
时序收敛或板级测试，包中**不含可烧录 bitstream**；目标工程需自行指定真实总线桥、
复位同步、时钟来源、引脚与 I/O 时序。

## 6. 文档落点

随包文档保留在 `aihw_plugin/docs/`（与原路径一致，便于 `verify_release.py` 校验）：

| 文件 | 内容 |
| --- | --- |
| `INTERFACES.md` | 端口、地址表、错误语义、主机契约 |
| `MODEL_CARD.md` | 量化选择、合成数据评估、适用边界 |
| `INTEGRATION.md` | EQ6HL130 器件接入、时钟与特征来源（插件视角） |
| `VALIDATION.md` | 可复现结果、周期推导、仍待验证事项 |
| `UPSTREAM_MODEL_PROVENANCE.json` | 上游模型溯源 |
| （本文件） | `docs/aihw_plugin/INTEGRATION.md`（工程侧入口） |

## 7. 已知限制

- RTL 与测试台未进入竞赛编译/回归流程（见第 2 节，属**有意选择**，源于不改动原有
  架构的约束）；其独立验证依赖 Icarus，本机不可用（见第 4 节）。
- 未做 EQ6HL130 综合、布局布线、时序收敛与板级测试；通过 Verilog 语法检查不能推断
  BRAM/DSP/LUT 用量，也不能推断器件最大时钟。仿真时钟周期仅为测试台激励。
- 模型 ROM 在构建时固定，无在线写权重接口；更新模型需重新导出全部 ROM 与
  `ai_model_params.vh` 并重走可信发布流程；32 位 `model_tag` 与发布清单中的 SHA-256
  用于发现误配，均不替代签名认证。
- 预处理在主机执行：需要完整 **8×18** 输入窗口。原计数器桥仅能估计
  `observed_pps`、`queue_overflow_ratio`；帧大小分布、到达离散度、双网内容差异、
  时延分位数、时间响应、加载状态与重组上下文等**仍需独立测量生产者**。缺失字段
  **不得置零冒充**为实测，否则相应调查会因特征越界/数值错误而停止。
