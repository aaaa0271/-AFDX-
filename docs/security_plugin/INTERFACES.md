# 顶层接口对照

`AFDX_security_plugin_top` 通过命名端口逐一转接原 `AFDX_competition_top`。原来的 106 个端口、22 个参数全部保留；新增一个 `SECURITY_BOOT_MODE` 参数及下列 `sec_*` 控制/观测端口。原核心源码逐字节保留。

## 原端口与新增端口

| 名称 | 方向 | 位宽表达式 |
|---|---|---|
| `cfg_port_write` | input | `1` |
| `cfg_port_index` | input | `[3:0]` |
| `cfg_port_entry` | input | `[63:0]` |
| `app_wr_subvl` | input | `[1:0]` |
| `app_read_subvl` | input | `[1:0]` |
| `app_wr_use_sap` | input | `1` |
| `app_wr_sap` | input | `[15:0]` |
| `app_wr_partition` | input | `[2:0]` |
| `app_read_partition` | input | `[2:0]` |
| `payload_port` | output | `[3:0]` |
| `payload_sap` | output | `[15:0]` |
| `app_access_error` | output | `1` |
| `cfg_rx_write` | input | `1` |
| `cfg_rx_seal` | input | `1` |
| `cfg_rx_index` | input | `[1:0]` |
| `cfg_rx_entry` | input | `[167:0]` |
| `cfg_rx_ready` | output | `1` |
| `cfg_rx_error` | output | `1` |
| `clk` | input | `1` |
| `rst` | input | `1` |
| `tx_enable` | input | `1` |
| `network_a_enable` | input | `1` |
| `network_b_enable` | input | `1` |
| `cfg_we` | input | `1` |
| `cfg_vl_id` | input | `[1:0]` |
| `cfg_bag` | input | `[31:0]` |
| `cfg_destination` | input | `[7:0]` |
| `app_wr_en` | input | `1` |
| `app_wr_vl_id` | input | `[1:0]` |
| `app_wr_data` | input | `[7:0]` |
| `app_wr_len` | input | `[15:0]` |
| `app_wr_sof` | input | `1` |
| `app_wr_eof` | input | `1` |
| `cfg_lmax` | input | `[15:0]` |
| `app_wr_ready` | output | `1` |
| `app_len_error` | output | `1` |
| `app_wr_accept` | output | `1` |
| `fault_enable` | input | `1` |
| `data_a_txd` | output | `[7:0]` |
| `data_b_txd` | output | `[7:0]` |
| `data_a_tx_en` | output | `1` |
| `data_b_tx_en` | output | `1` |
| `data_a_tx_er` | output | `1` |
| `data_b_tx_er` | output | `1` |
| `data_a_done` | output | `1` |
| `data_b_done` | output | `1` |
| `data_a_rxd` | input | `[7:0]` |
| `data_b_rxd` | input | `[7:0]` |
| `data_a_rx_dv` | input | `1` |
| `data_b_rx_dv` | input | `1` |
| `data_a_rx_er` | input | `1` |
| `data_b_rx_er` | input | `1` |
| `payload_data` | output | `[7:0]` |
| `payload_valid` | output | `1` |
| `payload_sof` | output | `1` |
| `payload_eof` | output | `1` |
| `payload_network` | output | `1` |
| `payload_ready` | input | `1` |
| `app_read_request` | input | `1` |
| `app_read_port` | input | `[1:0]` |
| `app_read_ready` | output | `1` |
| `payload_length` | output | `[15:0]` |
| `payload_vl` | output | `[1:0]` |
| `payload_fresh` | output | `1` |
| `management_busy` | output | `1` |
| `snmp_snapshots` | output | `[31:0]` |
| `snmp_busy_drops` | output | `[31:0]` |
| `shared_rx_accepted` | output | `[31:0]` |
| `shared_rx_duplicates` | output | `[31:0]` |
| `shared_rx_dropped` | output | `[31:0]` |
| `shared_tx_overflows` | output | `[31:0]` |
| `physical_a_frames` | output | `[31:0]` |
| `physical_b_frames` | output | `[31:0]` |
| `loader_ip` | input | `[31:0]` |
| `time_server_ip` | input | `[31:0]` |
| `hardware_length` | input | `[5:0]` |
| `hardware_id` | input | `[255:0]` |
| `app_file` | input | `[1:0]` |
| `rtc_poll` | input | `1` |
| `rtc_locked` | output | `1` |
| `utc_ntp` | output | `[63:0]` |
| `monotonic_ticks` | output | `[63:0]` |
| `image_valid` | output | `1` |
| `image_length` | output | `[15:0]` |
| `image_crc` | output | `[31:0]` |
| `package_generation` | output | `[31:0]` |
| `package_file_count` | output | `[2:0]` |
| `image_read_address` | input | `[15:0]` |
| `image_read_data` | output | `[7:0]` |
| `loading` | output | `1` |
| `load_complete` | output | `1` |
| `load_failed` | output | `1` |
| `service_app_domain` | input | `[SERVICE_DOMAIN_WIDTH-1:0]` |
| `service_loaded` | output | `[SERVICE_DOMAINS-1:0]` |
| `service_clock_locked` | output | `[SERVICE_DOMAINS-1:0]` |
| `service_cfg_we` | input | `1` |
| `service_cfg_domain` | input | `[SERVICE_DOMAIN_WIDTH-1:0]` |
| `service_cfg_loader_ip` | input | `[31:0]` |
| `service_cfg_clock_ip` | input | `[31:0]` |
| `service_cfg_enable` | input | `1` |
| `service_cfg_commit` | input | `1` |
| `service_cfg_ready` | output | `1` |
| `service_cfg_error` | output | `1` |
| `service_cfg_pending` | output | `1` |
| `service_cfg_commit_pulse` | output | `1` |
| `service_enabled` | output | `[SERVICE_DOMAINS-1:0]` |
| `sec_cfg_write` | input | `1` |
| `sec_cfg_read` | input | `1` |
| `sec_cfg_address` | input | `[15:0]` |
| `sec_cfg_wdata` | input | `[31:0]` |
| `sec_cfg_ready` | output | `1` |
| `sec_cfg_error` | output | `1` |
| `sec_cfg_pending` | output | `1` |
| `sec_cfg_commit_pulse` | output | `1` |
| `sec_cfg_rdata` | output | `[31:0]` |
| `sec_mode` | output | `[1:0]` |
| `sec_epoch` | output | `[31:0]` |
| `sec_event_valid` | output | `1` |
| `sec_event_ready` | input | `1` |
| `sec_event_record` | output | `[159:0]` |
| `sec_alarm` | output | `1` |
| `sec_time_flags` | output | `[3:0]` |
| `sec_time_alarms` | output | `[31:0]` |
| `sec_would_allow` | output | `[31:0]` |
| `sec_would_block` | output | `[31:0]` |
| `sec_queue_overflows` | output | `[31:0]` |
| `sec_event_overflows` | output | `[31:0]` |
| `sec_ab_conflicts` | output | `[31:0]` |
| `sec_hash_failures` | output | `[31:0]` |

## 接入规则

- 工程编译同时加入 `reference_core/rtl/*.v` 和 `rtl/*.v`，将顶层改为 `AFDX_security_plugin_top`。只接收方向经过完整帧准入与重放；原发送方向保持直连，另有旁路观测。
- A/B 必须分别接入各自原始 MAC 字节流，不能先做冗余消除再接本插件。时钟仍为原工程 `clk`，默认 12.5 MHz，每拍一个 100 Mb/s 线上字节模型；不是 125 MHz 的物理 GMII 转换器。
- 原配置口全部保留。新 `sec_cfg_*` 是独立、可信的本地寄存器口，不经 SNMP/业务 UDP 自动暴露。需由集成方映射至现有可信 CPU/配置控制器。
- 未使用 `sec_cfg_write`/`sec_cfg_read` 时明确接 0；`sec_event_ready` 建议接持续消费的日志接收器。忽略事件时接 1，但将失去应用侧审计记录。
- 默认 `SECURITY_BOOT_MODE=2`，复位后没有允许规则，会拒绝所有 RX。可信配置器安装完整规则和授权，提交成功后再开始加载/业务。
- 原八口兼容顶层另命名为 `AFDX_security_8port_top`，显式选择 BYPASS=0，仅用于旧竞赛接口比对；八口无法承载独立 A/B、策略写入和证据导出，不能当作已启用安全功能的交付接口。
- 需要直接复用已有顶层时，可实例化 `afdx_security_plugin` 并按生成封装连接，不必改原核心内部模块。
- `hardware_id` 按原核心的小端字节向量连接；授权清单用 64 位十六进制字符表示同一 256 位整数。签名清单内的 `target` 是主机配置的设备类别字符串，两者都检查。
- 策略提交安全条件是所有采集队列、接收重放器、检测引擎空闲，且没有活动加载/分片/NTP 等待上下文，同时原核心没有 `loading`、`management_busy` 或 TX 活动。持续异常流量可阻止提交，控制器应先停流/维护切换；不存在保证任意流量下立即更新的承诺。
- `service_app_domain` 改变时仅重新锚定该选择口的 UTC 监测。每个时间服务的报文检查按自己的规则执行。
