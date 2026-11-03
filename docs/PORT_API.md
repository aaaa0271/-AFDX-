# Sub-VL / SAP / 端口 API（R1）

## 端口编号

`port = 4 * subvl + vl`，`vl=0..3`，`subvl=0..3`。默认仅 0..3 启用。`EXTENDED_PORTS=1` 是顶层默认值；配置后可启用另外十二个端口。

## 端口表项 64 位

| 位 | 含义 |
|---|---|
| 0 | enabled |
| 1 | sampling；0 为排队 |
| 2 | SAP 绑定；R1 的 SAP 为排队方式 |
| 3 | 覆盖 VL 默认 UDP 源/目的端口 |
| 7:4 | 保留，必须为 0 |
| 23:8 | 本地 SAP ID（仅 bit2=1 时使用） |
| 39:24 | UDP 源端口 |
| 55:40 | UDP 目的端口 |
| 63:56 | 本地读/写分区允许位图，bit0 对应分区 0 |

`cfg_port_write/index/entry` 在配置阶段写入。`cfg_rx_seal` 同时封存 VL 表与端口表。不同端口不能使用重复 SAP ID，同一 VL 上不能使用完全相同的 UDP 绑定。新增端口必须显式指定 UDP 绑定，避免与默认端口混淆。

例如 port4（VL0/Sub-VL1）的采样端口、允许分区0和1、UDP 10004→20004：

```verilog
cfg_port_index = 4;
cfg_port_entry = {8'h03, 16'd20004, 16'd10004, 16'h9004, 8'h0b};
```

port8（VL0/Sub-VL2）的 SAP 排队绑定、仅分区0：

```verilog
cfg_port_index = 8;
cfg_port_entry = {8'h01, 16'd20008, 16'd10008, 16'h9008, 8'h0d};
```

这些编号是本原型本地 API 配置示例，不是 ARINC 规定的全局固定 SAP 编码。

## 写入

普通端口：提供 `app_wr_vl_id` 和 `app_wr_subvl`。SAP 调用：置 `app_wr_use_sap`，提供 `app_wr_sap`，由表项解析出实际端口。分区由 `app_wr_partition` 给出。

沿用字节流的 `app_wr_data/len/sof/eof/en/ready/accept`；只有 accept 才提交一个字节。未知 SAP/无权限分区产生 `app_access_error`，格式或容量错误产生 `app_len_error`。队列满时 ready 拉低。元数据须在同一消息期间保持不变。

## 读取

设置 `EXPLICIT_PORT_READ=1` 后，用 `app_read_port`（VL）、`app_read_subvl`、`app_read_partition` 和 `app_read_request` 发起读取；只有 `app_read_ready` 才能接受请求。

返回：`payload_port` 为完整四位端口索引，`payload_vl` 为兼容的低两位 VL，`payload_sap` 为 SAP 绑定 ID 或 0，另有长度、SOF/EOF、网络来源和 freshness。暂停 `payload_ready` 不得改变当前有效数据及事务元数据。

采样端口允许重复读取同一最新值、允许位图中的多个读取者；接口串行化，一次仅一个读事务。排队端口成功读完后消费一个消息。R1 不主张多条独立同时读取总线或通用多分区操作系统 API。

## 容量与边界

排队深度固定为两个完整消息；0..3 默认 8192 字节，4..15 默认 2048 字节（参数 `SUBVL_MAX_MESSAGE`）。采样必须不超过该 VL 的 LMAX−47。配置容量不是规范上限。

接收首片建立 IPv4 ID→端口上下文后，可按该上下文接续分片。多端口/VL 时无法区分端口的首片前孤儿分片不会投递到猜测的端口。该已知边界见机器可读 profile，不算作完整重组规范已关闭。

## 原子封存与启动边界

封存当周期必须没有 VL、TX 策略或端口表写入。任一写入与封存同周期时，统一拒绝本次事务并报错：两张表都不写入、都不封存，不能出现一张已锁、另一张仍可改的状态。业务收发在配置封存前关闭；若封存发生在接收帧中途，该网络先等待下一次空闲再开始接收。管理/加载服务的固定配置路径不受这个业务端口启动门槛阻断。
