# AFDX Mimic Plugin 1.0 — 接入说明（INTEGRATION）

**2026-10-20 集成更新**：当前统一顶层已把完整帧缓存、原四执行器的三活一备宿主运行时、RTL 语义裁决和整帧重放连接到实际 RX 准入路径；Windows 二进制执行和 Job 资源限制已适配。完整接口与实测范围见 `../DEFENSE_INTEGRATION.md`，下文“未接入/仅独立裁决”等为早期历史记录。它是宿主协同系统，不是四套 FPGA 硬核，也未证明实时线速。

本文件记录 AFDX 拟态防御插件（`AFDX_Mimic_Plugin 1.0.0`）接入本竞赛工程的
方式、落点、接线与验证边界。原始交付件逐字节保留，未做源码改写。

## 1. 落点布局

插件整树放入工程根新目录 `mimic_plugin/`，忠实保留其内部相对路径，使得
包内脚本的 `Path(__file__).resolve().parents[1]`（即插件根）继续指向
`mimic_plugin/`：

```
mimic_plugin/
    afdx_mimic/            契约、控制、执行器编排、证据与桥接（10 文件）
    executors/             四个异构执行器源码
                           python_struct.py / c_offsets.c / cpp_cursor.cpp / python_table.py
    cases/                 冻结用例：boundary_suite / normal / udp_length
    scripts/               validate.py / fixtures.py / compare_modes.py
                           native_sanitize.py / rtl_checks.py
    tests/                 test_mimic.py
    rtl/                   afdx_mimic_quorum_gate.v / tb_mimic_quorum.v
    security_lab/          同包内的隔离安全实验目录（12 文件）
    reports/               运行时暂存目录（仅保留占位文件 .gitkeep，见第 6 节）
    trusted_selftests.json
    DELIVERY_SHA256.json   README.md   VERSION.txt   requirements.txt
docs/mimic_plugin/         随包文档（见第 5 节）
```

采用独立根目录而非展开到工程根，是因为插件自带 `cases/`、`scripts/`、
`tests/`、`rtl/`、`security_lab/` 五个与工程根**同名**的目录；展开会与工程
既有目录发生路径碰撞。`mimic_plugin/` 不参与工程 ModelSim 编译的文件集，
也不在 `scripts/run_all.py` 的 `inputs()` 哈希范围（该函数只覆盖
`rtl,tb,scripts,vendor,docs` 与根级清单文件），因此不影响既有回归与工程
设置一致性判定。

## 2. 与工程 HDL 流程的接线

拟态层唯一的可综合 RTL 是事务级裁决器 `afdx_mimic_quorum_gate`。为让它进入
工程 `vlog`/eLinx 流程并接受独立编译：

- `rtl/afdx_mimic_quorum_gate.v` —— 由 `mimic_plugin/rtl/` 复制而来，登记进
  `ARINC.qsf`、`ARINC.epr` 的 `DesignSrcs` 文件集（按字母序落在
  `rtl/afdx_mib_register_bank.v` 与 `rtl/afdx_multi_loader_client_plane.v`
  之间）。三处（`rtl/*.v` 实际集合、qsf、epr）保持完全一致。
- `tb/tb_mimic_quorum.v` —— 由 `mimic_plugin/rtl/` 复制而来。命名刻意避开
  `afdx_*` 前缀，以满足 `test_packaging.py` 中"`tb/afdx_*.v` 必须为空"的
  门控（该门控用于排除生产模块被测试台重复定义）。该 TB 同时登记进
  `ARINC.epr` 的 `sim_1`（`SimulationSrcs`）仿真集，与网安插件 TB 的既有做法
  保持一致，便于 GUI 仿真使用。
- `scripts/tests.json` —— 新增 `mimic` 套件一条用例：

  ```json
  {
    "name": "tb_mimic_quorum",
    "file": "tb/tb_mimic_quorum.v",
    "suite": "mimic",
    "marker": "MIMIC_RTL_PASS cases=13 done=13",
    "error_counter": "failures",
    "run_ms": 5,
    "auditors": [],
    "timeout_seconds": 300
  }
  ```

  判定同时受 `failures`（错误计数须为 0）与精确终行 PASS 标记双重约束。

## 3. 本机已执行的验证（Windows / ModelSim）

```powershell
py -3 scripts\run_all.py --hdl-only --tests tb_mimic_quorum
```

结果（证据目录 `results/run_20261016_223447_697036`）：

- `mimic tb_mimic_quorum PASS`，`MIMIC_RTL_PASS cases=13 done=13`，
  `REGRESSION_FINAL_ERRORS=0`，`vlog` `Errors: 0`。
- 7 个预检门（`test_verdict.py`、`test_conformance_gate.py`、
  `test_packaging.py`、`test_competition_gate.py`、
  `verify_standard_mib_inventory.py`、`test_worst_case_envelope.py`、
  `test_release_paths.py`）全部 PASS，其中 `test_packaging.py` 的 6 项
  文件集/覆盖/命名门控在新增文件后仍通过。

纯 Python 契约层在 Windows 上单独可运行的部分亦已实测通过：

```powershell
# 工作目录 mimic_plugin/
py -3 -m unittest -v tests.test_mimic.ContractTests.<不依赖 WorkerPool 的 8 项>
```

结果 `Ran 8 tests ... OK`（重复键 JSON 拒绝、NaN 拒绝、策略未知字段/重复
id/布尔整数、策略稳定排序、请求边界、请求 id 布尔拒绝共 8 项）。

## 4. 平台门控（如实标注，未伪装通过）

插件原始验证环境为 **Linux + GCC(C11) + G++(C++17) + Icarus Verilog**。本
机（Windows，PowerShell 5）经实测存在以下不可用项，此处如实记录，未以任何
方式伪装为 PASS：

| 能力 | 依赖 | 本机状态（实测） |
| --- | --- | --- |
| 四执行器异构编译 | `gcc`、`g++` | 可通过 MinGW 或其他安装提供；是否在 PATH 须运行时探测，不能由 PATH 未找到推断整机不存在。完整执行器仍要求 POSIX 平台。缺编译器时硬失败，不静默省略执行器。 |
| 原生 RTL 检查 `scripts/rtl_checks.py` | `iverilog`、`vvp` | 不存在 → 抛 `RuntimeError('actual RTL checks require Icarus')` |
| 子进程隔离启动 `afdx_mimic/launch.py` | POSIX `resource` 模块 | 导入即 `ModuleNotFoundError: No module named 'resource'`（POSIX-only） |
| 进程组处置 `afdx_mimic/workers.py` | POSIX `os.killpg`、`signal.SIGKILL` | 模块可导入（相关调用仅在方法体内引用），但进程池的实际执行路径在本机不可用 |

因此，**依赖原生执行器与 Icarus 的整体编排（`scripts/validate.py`、四执行器
2-of-3 语义裁决回放、`MIMIC_VALIDATION_PASS` 终态标记）未在本机运行**。
上游历史清单引用 `reports/release_20261016/`，该目录未随本工程交付，
不能由本交付树独立核验；当前源码与迁移后的路径校验见 `PINS_README.md`。

拟态层的 **RTL 裁决器**则通过工程 ModelSim 流程独立复算（第 3 节），不依赖
上述 Linux 工具链。

## 5. 文档落点

`docs/mimic_plugin/` 保存随包文档（原文件名 → 落点名，遵循本工程既有
`security_plugin/`、`agent_plugin/` 的加前缀约定，避免与工程同名文档冲突）：

| 原文件 | 落点 |
| --- | --- |
| `README.md` | `MIMIC_README.md` |
| `VERSION.txt` | `MIMIC_VERSION.txt` |
| `requirements.txt` | `MIMIC_requirements.txt` |
| `docs/INTERFACES.md` | `INTERFACES.md` |
| `docs/THREAT_MODEL.md` | `THREAT_MODEL.md` |
| `docs/VALIDATION.md` | `VALIDATION.md` |
| `docs/UPSTREAM_HASHES.json` | `UPSTREAM_HASHES.json` |
| `docs/UPSTREAM_VERIFICATION.json` | `UPSTREAM_VERIFICATION.json` |
| `DELIVERY_SHA256.json` | `DELIVERY_SHA256.json` |
| （本文件） | `INTEGRATION.md` |

## 6. 已知限制

- 拷贝保真度实测：`mimic_plugin/DELIVERY_SHA256.json` 共 332 条 pin，落到
  `mimic_plugin/` 的 72 条**逐字节一致（0 处不匹配）**；其余 260 条按本节
  落点约定不在 `mimic_plugin/` 内——其中 `docs/` 5 条已改前缀迁至
  `docs/mimic_plugin/`（见第 5 节），`reports/` 255 条为原始冻结证据，按交付
  约定**不随工程携带**，保留在插件交付包内。因此在该集成布局下直接对
  `DELIVERY_SHA256.json` 全量校验会报告这 260 条"缺失"，属预期，非损坏。
- `reports/` 目录依赖：`mimic_plugin/tests/test_mimic.py`（`pool()` 与
  `FilesAndBridgeTests.setUp`）以 `tempfile.TemporaryDirectory(dir=R/'reports')`
  把插件根下的 `reports/` 当作临时构建父目录，`scripts/validate.py --out` 亦
  以该目录为默认输出父目录。由于本节首条的排除约定，原始 `reports/` 内容
  已不随工程携带，会出现父目录缺失。为此在 `mimic_plugin/reports/` 内仅保留
  一个占位文件 `.gitkeep`，仅用于让该目录存在，不携带任何历史结果；不影响
  `DELIVERY_SHA256.json` 的 72 条在库 pin 校验（占位文件不在 pin 列表内）。
- `mimic_plugin/scripts/validate.py` 的上游哈希校验
  （`docs/UPSTREAM_HASHES.json` 的 698 条 pin）中，部分 pin 的相对路径假定
  插件根的同级位置存在原始同级交付包（如 `AFDX_Security_Plugin/`、
  `AFDX_AI_Plugin/`、`AFDX_Agent_Plugin/`）。在集成布局下该同级关系不再成
  立，故该脚本的端到端编排需在原始同级包环境中、并具备第 4 节所列工具链时
  才能复现。此为**未改写 vendor 脚本**的既有约束，本工程如实说明，不改动其
  逻辑。
- 裁决器 RTL 为事务级，尚未连接完整 MAC 缓存/重放封装（与 `MIMIC_README.md`
  一致）；本工程仅使其通过独立编译与 13 项用例回归，不宣称已接入数据面。
- 拟态层运行时的最终放行同时取决于宿主 baseline 与拟态层裁决
  （`baseline=None` 时 `final_allow` 为 `null`，不冒充放行）。本工程不修改该
  语义。
