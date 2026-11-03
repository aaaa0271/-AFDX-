# 2026-11-04 重构版 afdx_615a_download 单独展开 PASS —— B 方案说明

## 一、结论

把 `afdx_615a_download.v` 里**运行时变址的宽向量 part-select** 改成
**存储器索引访问**后，该模块单独做 eLinx Analysis & Elaboration：

| 项目 | 原版 | 重构版 |
|---|---:|---:|
| 结果 | OOM（106,389 MB） | **PASS** |
| errors / warnings | — | **0 / 23** |
| 峰值虚拟内存 | >106 GB | **10.8 GB** |
| 耗时 | 未完成（手动停） | **4 分 36 秒** |

重构版模块已随本目录保存（`afdx_615a_download.v`），配套的独立展开顶层
（`elab_615a_download_top.v`）、工程（`615a.qpf`/`615a.qsf`）和原始日志
（`elaboration.log`）一起提供，可复现。

## 二、改了什么（行为不变）

- `protocol_file`（4096-bit reg + 运行时 cursor 变址写）→ `pf_mem[0:511]`
  字节存储器；`put_data` 从存储器按地址读。
- `names[0:3]`（256-bit reg + 变址 part-select）→ `names_mem[0:3][0:31]`
  二维字节存储器。
- LNA/LNR 组合解析块：`rx_bytes` 上的运行时变址切片 → 先展开成
  `pbyte[0:515]` 字节数组再逐字节比较；`candidate` 同样改为 `cand[0:31]`
  字节存储器。
- `envelope` / `make_status` / `LIST` 里的 cursor/z 变址写 → 存储器索引写。
- `FILE` 状态的 `transfer_name` 赋值 → 经 `name_pick` 字节数组按固定索引
  搬移，避免变址 part-select。

端口列表、状态机、时序行为与原版一致；差别只在实现载体（存储器 vs 宽向量
变址切片）。

## 三、行为验证

同一份重构文件替换进源码树后，**127 项 RTL/联动回归全部通过、0 失败**，
包括：

- 新增的三个 615A 卸载用例：`tb_615a_roundtrip`、
  `tb_615a_download_faults`、`tb_615a_download_security`；
- 正式顶层联动 `tb_defense_live`（A.LUP/B.LUP 加载+卸载审计一致）。

回归汇总（`results.csv`、`acceptance.json`）在
`evidence/regression_b_20261104/`。

## 四、边界

- 该 PASS 是 **EP1S80F1508C6 占位器件**上的 analysis/elaboration，不是
  EQ6HL130 综合映射、布局布线或时序收敛。
- 完整核心（含重构版 download）的展开结果见
  `final_elinx_core_b_20261104/`（若存在）。

## 五、复现

在 eLinx 3.0（有效许可安装）中对本目录工程执行：

```text
quartus_map --read_settings_files=on --write_settings_files=off --analysis_and_elaboration 615a
```
