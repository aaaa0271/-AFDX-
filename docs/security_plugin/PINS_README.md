# 交付件 pin 清单说明（网安创新拓展 / security_plugin）

本文件说明本目录下的 pin 清单，**不计入任何 pin，仅供阅读**；清单 JSON 本身保持
原样、未注入说明键，以免通用"逐键校验"工具把说明误判为缺失文件。

| 清单 | 条目 | 合并后布局实测 |
| --- | --- | --- |
| `DELIVERY_SHA256.json` | 650 | 40 匹配 / 5 不匹配 / 605 缺失 |
| `BASELINE_HASHES.json` | — | 其结构由该文件自身定义 |

## `DELIVERY_SHA256.json` 差异原因

- **5 处不匹配**（`README.md`、`VERSION.txt`、`scripts/run_tests.py`、
  `tb/tb_security_core_multi.v`、`rtl/afdx_sec_engine.v`）：上游清单按**上游插件根**
  计算相对路径；合并后 `README.md`/`VERSION.txt` 解析为本工程根的同名文件，
  `scripts/`、`tb/`、`rtl/` 解析为工程级目录。其中：
  - `tb/tb_security_core_multi.v` 的差异来自合并时的位宽/接口适配修复（上游 10-14 版
    审查指出、本工程已修）；
  - `rtl/afdx_sec_engine.v` 的差异来自 **2026-10-17 的两项缺陷修复**（见下节），
    属**已知且有意的**源码变更。两者另见 `docs/COMPLETE_IMPLEMENTATION_STATUS.md`。
- **605 处缺失**：指向未随本工程复制的上游冻结结果与用例目录（属声明的边界）。

## 2026-10-17 安全引擎两项缺陷修复（`rtl/afdx_sec_engine.v`）

依第三方验证报告"代码审查发现·网安插件"条目修复，均按**描述**定位（报告行号对应
另一修订版，与本工程行号不一致）：

1. **A/B 逻辑键补入 UDP 端口**：`match_key` 原只比对 VL、IP 地址、IPv4 ID/分片与 AFDX
   SN，未比对 UDP 源/目的端口，导致"同 VL/SN、不同端口"的第二路流被误判为内容冲突而
   丢弃。现补 `q=42..45`（端口字节）入键。
2. **DF 位护栏**：分片分支原只在 `(fragment&0x3fff)!=0`（MF 或偏移非零）时进入。DF=1
   的帧依 RFC 791 不得再带 MF 或非零偏移；原实现会把这种非法组合当作首片并为它开一个
   分片上下文，直至超时才回收。现对 `(fragment&0x4000)!=0` 直接判 `F_FORMAT`，不再开槽。

**回归证据**：定向 `py -3 scripts/run_all.py --hdl-only --tests tb_security_sha
tb_security_plugin tb_security_core_multi tb_security_bypass` 四个用例全 PASS；随后全量
`py -3 scripts/run_all.py --hdl-only --workers 8` → `FUNCTIONAL PASS`，
`results\run_20261017_102614_850302` 下 **116/116 PASS**、`changed_inputs []`。

**副作用（如实记录）**：该 RTL 变更使 `rtl/afdx_sec_engine.v` 脱离上游 pin（上表第 5 条）；
同时此前记录的 eLinx 单/双域分析综合证据（约 58 分钟一轮）因源码变更而失效，需在具备
eLinx 环境时重跑方可重新宣称。

## 口径澄清：插件场景数

插件报文测试为 **111** 个逐条握手场景（见 `docs/security_plugin/VALIDATION.md`：
"111 个逐条握手场景通过"），**不是 112**。工程 `README.md` 已按 111 修正。

## 本机可复跑的部分

插件 RTL 由工程 ModelSim `security` 套件 4 个用例回归覆盖；主机侧审计脚本
（`verify_plugin_wire.py`、`verify_multi_service_wire.py`、`verify_shared.py`）与
`tests/` 下 27 个主机端单元测试可在本机运行。
