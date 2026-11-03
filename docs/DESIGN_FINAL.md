# 竞赛基础框架设计与验收说明

版本：AFDX-COMPETITION-FINAL-20261012。

## 对应赛题

| 赛题项 | 实现位置/路径 | 验证入口 |
|---|---|---|
| ARINC 664 Part 7 通信功能 | `AFDX_competition_top`、datagram TX/RX、VL/端口配置及共享 MAC | `tb_datagram_mac_joint`、`tb_integration_subvl_mac` |
| 高完整性数据通信 | A/B 校验、过滤、序号、冗余去重、错误隔离、缓冲和恢复 | `tb_foundation_shared_degraded`、`tb_m5_integrity_rules` |
| SNMP 网络管理 | `afdx_snmp_mac` / `afdx_snmp_extended`，实际 UDP/MAC v2c 请求响应 | `tb_foundation_snmp_bulk_mac`、PySNMP 审计 |
| 615A 数据加载 | control TFTP、A4 upload、LUH parser、package loader、最终 LUS ACK | `tb_completion_package_network`、`tb_integration_multi_services` |
| RTC 时钟同步 | NTPv4 packet client，独立 UTC/单调计数、holdover/恢复 | `tb_contest_rtc_convergence`、`tb_integration_multi_services` |

这是对赛题五个功能目标的本地实现验收矩阵。标准相关语义和实现限制另有明确记录，不用矩阵的 PASS 代替完整规范条款认证。

## 统一数据流

应用写入经 SAP/端口权限和封存配置映射到完整消息存储。轮询选择 VL 与 Sub-VL，BAG 与序号在 VL 层共享；每次发送一个完整帧或 IP 分片。业务、管理、加载/时钟在帧边界进行仲裁，输出冗余 A/B MAC 字节流。

输入验证帧结构、FCS、IPv4/UDP、地址和长度后，完成序号完整性和冗余处理，再按端口进行重组和应用交付。无效或未完成数据不会当作完成消息提交。应用读取可背压，使用条件须遵守 `PORT_API.md`；持续不读取会填满有限缓冲。

## 端口和状态

四 VL，每 VL 四 Sub-VL，共十六端口。端口索引 `{subvl,vl}`。基本四端口容量8192字节，扩展十二端口默认2048字节，排队深度两个完整消息。采样使用独立存储槽，保护当前活动读写。SAP 和分区访问受封存表约束。配置写入与封存冲突、重复绑定和未知 SAP 都有明确异常路径。

## 服务扩展

默认 `SERVICE_DOMAINS=1` 保留基本单域路径。`SERVICE_DOMAINS=2` 是已经纳入验收的扩展配置。两套加载器、两台时钟服务器在统一 A/B MAC 上通信，各自保存传输状态、包 bank、时钟状态。Loader/clock 的接收与发送 VL、SN 历史分开。外层发送 BAG 仍限制共享服务流量。`service_app_domain` 选择应用 bank 和时钟视图。

测试对一台时钟服务器的输出进行阻断，再恢复并重新轮询，验证另一域不受影响。对两套加载器分别检查完整文件及最终状态。相关地址表在 `afdx_multi_loader_client_plane.v` 和 `competition_profile.json` 中声明；其他规模未经此次验收。

## 数据加载和管理边界

加载是有界 A4 上传路径，支持多个数据文件、header/file CRC16、load CRC32、非活动 bank 准备、最终 LUS 确认后的原子发布。错误、超时或 CRC 失败保留旧 bank。665 字节测试覆盖当前支持的0x8002/0x8004子集及异常拒绝，完整 information/download、support/UDD、batch/media和所有版次不在完成声明中。

SNMP采用v2c，最多16个VarBind、512字节BER消息、GET/GETNEXT/GETBULK，私有25对象只读遥测，SET返回只读错误。标准对象清单是附加研究，不是全部生产对象实现。5个抽象模型实验独立列项。

## 验证构成

最终回归必须运行52项历史兼容、15项竞赛专项、5项completion、8项foundation、7项datagram、2项integration，共89项实现相关HDL用例，另有5项独立模型实验。独立审计由MAC字节文本和第三方ASN.1解析重建结果。两种顶层配置分别在eLinx安装目录的分析后端展开。源代码哈希在运行前后相同才允许最终验收通过。

外部回归记录包含原始日志、输入快照、抓包及接受/失败状态；桌面源码交付只保留复现所需源文件、项目、向量、说明和附加审查。生成后的根目录 `DELIVERY.md` 汇总本次具体结果及外部位置。