# 2026-11-04 完整最新核心（含重构版 615A download）eLinx 展开 PASS

## 一、结论

对 **2026-11-03 最新源码** 的 `AFDX_competition_top`（121 源：120 个
`rtl/*.v` + AI TCN），其中 `afdx_615a_download.v` 为存储器化重构版（B 方案），
执行 eLinx Analysis & Elaboration：

| 项目 | 值 |
|---|---:|
| 顶层 | `AFDX_competition_top`（单域，含 615A download） |
| 源文件 | 121 |
| 结果 | **PASS** |
| errors / warnings | **0 / 171** |
| 峰值虚拟内存 | **18,866 MB（18.9 GB）** |
| 耗时 | 22 分 47 秒 |
| 成功行 | `Analysis & Elaboration was successful. 0 errors, 171 warnings` |

对照：

| 运行 | 结果 | 峰值内存 |
|---|---|---:|
| 2026-10-24 旧 120 源基线 | PASS，0/159 | 16.9 GB |
| 2026-11-03 原版 121 源（变址 part-select） | FAIL/OOM | 105,262 MB |
| 2026-11-04 重构版 121 源（本次） | **PASS，0/171** | **18.9 GB** |

## 二、前提

- 重构只改 `afdx_615a_download.v` 内部实现载体（宽向量变址 part-select →
  字节存储器索引），端口与行为不变。
- 重构版替换进源码树后 **127 项 RTL/联动回归全部通过、0 失败**
  （`../regression_b_20261104/`），含三个 615A 卸载用例和 `tb_defense_live`。
- 重构版单独展开亦 PASS（`../final_elinx_download_b_20261104_PASS/`，
  0/23，10.8 GB）。

## 三、边界（重要）

- 本次是 **EP1S80F1508C6 占位器件**上的 analysis/elaboration，**不是**
  EQ6HL130 综合映射、布局布线或时序收敛。
- warnings 由旧基线的 159 变为 171：新增 12 条来自最新 615A 下载与相关
  接线（截断、连接性等类别），0 error；告警清单见 `elaboration.log`。
- 统一防御 `AFDX_defense_top` 与网安整体顶层仍未展开（历史 OOM >110 GB），
  本 PASS 不覆盖它们。

## 四、复现

工程（`ARINC.qpf` / `ARINC.qsf`，VERILOG_FILE 清单指向源码树）与原始日志
随本目录保存；`afdx_615a_download.v` 重构版亦随目录保存。在 eLinx 3.0
（有效许可安装）中执行：

```text
quartus_map --read_settings_files=on --write_settings_files=off --analysis_and_elaboration ARINC
```
