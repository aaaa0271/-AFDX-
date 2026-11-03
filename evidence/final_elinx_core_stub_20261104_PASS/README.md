# 2026-11-04 最新核心（去掉 615A download）eLinx 展开 PASS —— A 实验说明

## 一、这是什么

**A 实验**：对 **2026-11-03 最新源码**的 `AFDX_competition_top` 做 eLinx
Analysis & Elaboration，但把 `afdx_615a_download` 这一个实例**临时 stub 掉**，
用来确认“最新代码里让展开爆内存的只有 615A download 这一个模块”。

- **生产 RTL 没有改动**。只在一份临时副本里把
  `afdx_package_network_services.v` 中的 download 实例换成悬空/常值的 stub
  接线（该副本已随本目录保存为 `afdx_package_network_services_stub.v`，仅供
  复现，不参与生产工程）。
- 其余 119 个 rtl/*.v 全部使用最新版本，含 `afdx_665_package_loader.v` 和
  `afdx_package_network_services.v` 的其他最新改动。
- 工具为本机有效安装 `D:\Program Files (x86)\eLinx3.0\bin\Passkey\bin\quartus_map.exe`。

## 二、结果

| 项目 | 值 |
|---|---:|
| 顶层 | `AFDX_competition_top`（单域） |
| 源文件 | 120（119 个最新 rtl/*.v + AI TCN） |
| 结果 | **PASS** |
| errors / warnings | **0 / 161** |
| 峰值虚拟内存 | **17,252 MB**（约 17.3 GB） |
| 耗时 | 21 分 35 秒 |
| 成功行 | `Analysis & Elaboration was successful. 0 errors, 161 warnings` |

原始日志在 `elaboration.log`，判词在 `status.json`。

## 三、和另外两次运行的关系

| 运行 | 对象 | 结果 | 峰值内存 |
|---|---|---|---|
| 2026-10-24 旧基线 | 120 源旧快照核心（无 download） | PASS，0/159 | 16.9 GB |
| 2026-11-03 完整最新核心 | 121 源（含 615A download） | **FAIL/OOM** | 105,262 MB |
| **本次 A** | **最新核心去掉 download** | **PASS，0/161** | **17.25 GB** |

由此可以确认：

1. 最新代码里 **唯一** 把展开内存推到 100 GB 以上的就是
   `afdx_615a_download` 模块（含其 4128-bit 宽总线上的运行时变址 part-select）。
2. 最新核心的其余全部内容（修改后的 665 package loader、package network
   services、SNMP/RTC/业务路径）展开 **0 error**，警告数由旧基线的 159 变为
   161（增加 2 条，来自最新代码，见日志）。
3. 615A download 的功能正确性由 127 项 RTL/联动回归覆盖
   （`evidence/review_20261103/final_run/`），但不是 eLinx PASS。

## 四、边界（重要）

- 本次 A 是 **EP1S80F1508C6 占位器件**上的 analysis/elaboration，不是 EQ6HL130
  综合映射、布局布线或时序收敛。
- A 的 PASS **不是**“最新完整核心 PASS”；它明确排除了 615A download。
- 要拿到“最新完整核心 PASS”，需要对 `afdx_615a_download.v` 做存储器化重构
  （B 方案），重构后先过 127 项回归，再重跑本实验。

## 五、复现

`elaboration.log` 与 `ARINC.qsf`（含 stub 后的 VERILOG_FILE 清单）已随本目录保存；
在 eLinx 3.0（有效许可安装）中对该工程执行：

```text
quartus_map --read_settings_files=on --write_settings_files=off --analysis_and_elaboration ARINC
```

即可复核。
