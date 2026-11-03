# 615A/665 侧车审查说明

## 目的

本目录是 `D:\elinx\ARINC` 的独立 615A/665 侧车，不改变竞赛基础路径、生产顶层或原有 `scripts/tests.json`。它把新增的 `afdx_615a_process_engine`、`afdx_665_format_engine` 与原有的 615A 控制/TFTP、665 header/package loader 放在同一份可复现实验证据中审查。

## 运行边界

- 工具：ModelSim + Python；不需要上板。
- 选定审查基线：`ARINC615A-4`、`ARINC665-5`。
- 公开网页只登记标准目录元数据；本项目没有保留受控的完整标准正文，因此逐条条款闭合仍为 `OPEN`。
- `PASS_MODEL` 只表示本项目声明的有限数字行为在 ModelSim 中通过；它不表示 ARINC/SAE 正式认证。
- 任何未覆盖的格式、文件、版次差异和规范条款均保持 `OPEN_NORMATIVE` 或 `NOT_CLAIMED`。

## 已审查的实现关系

| 层 | 文件 | 侧车结论 |
|---|---|---|
| 过程抽象 | `rtl/afdx_615a_process_engine.v` | 覆盖 information/download/abort/wait/error 的有限状态转移、计数边界、busy 冲突；不等于完整 615A wire/file codec。 |
| 控制/TFTP | `rtl/afdx_615a_control_tftp.v` | 真实 TFTP 字节级 LUI/LUR 控制窗口和异常拒绝，范围受当前接口约束。 |
| 上传控制 | `rtl/afdx_615a_upload_control.v` | A4 受限 LUR -> data fetch -> validation -> status 的项目流程，含 transport/validation/timeout failure。 |
| 格式准入 | `rtl/afdx_665_format_engine.v` | 仅对 edition=4/5、0x8002/0x8004、计数/CRC/保留字段/名称/重复项进行有限准入。 |
| Header parser | `rtl/afdx_665_header.v` | 受限 header grammar；`MAX_FILES=4`、`MAX_HEADER=2048`，当前 profile 明确拒绝 support/UDD 区域。 |
| Package loader | `rtl/afdx_665_package_loader.v` | 真实 TFTP header/data 拉取，CRC16/CRC32、双 bank 原子提交、失败不切 bank。 |

## 过程矩阵

详细机器可读矩阵在 `docs/615A_665_PROCESS_FORMAT_MATRIX.json`。侧车 ModelSim testbench 的每个 case 都打印 `CASE_PASS` 或 `CASE_FAIL`，并输出 `SIDECAR_CASES` 与总错误数。覆盖：

- information accepted/completed；
- download complete；
- deferred/wait；
- error reason；
- busy 时新命令不被接受；
- abort；
- unsupported operation 与 header/target/part cardinality rejection；
- LUI/LUR/LUS 控制和 transport/validation failure 的原有测试重放；
- 多文件真实 TFTP/CRC/双 bank 回滚的原有测试重放。

## 格式/跨版次矩阵

本侧车将 `edition` 作为模型输入维度，重放 edition 3/4/5/6 和 format ID 0x8002/0x8004/未知值，另测 support/UDD、计数边界、CRC16/file CRC/load CRC、reserved、名称和 duplicate rejection。

这只证明当前模型的接受/拒绝矩阵是可重复的，不证明 edition 4/5 的全部 ARINC 语义。`afdx_665_header` 与 package loader 的已知答案文件继续作为实际字节级证据，但不扩展成“全格式”结论。

## 证据输出

运行后在 `sidecar_615a665/results/<timestamp>/` 生成：

- 每个 ModelSim 测试目录的 `run.do`、`console.log`、`result.log`；
- `evidence.json`：测试、marker、错误计数、源文件哈希；
- `traceability_report.json`：矩阵行与测试证据的绑定；
- `summary.json`：总体 PASS/OPEN 边界。

建议把一次完整结果目录作为交付证据，不覆盖此前 R1 竞赛结果。
