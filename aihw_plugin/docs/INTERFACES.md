# 接口与数值契约

## 独立流接口

`afdx_ai_tcn_plugin` 使用同一 `clk` 的同步接口，`rst_n` 为同步低有效复位。所有输入应满足该时钟的建立/保持时间。跨时钟域必须在外部增加桥接。一次仅处理一个窗口，输出阻塞时停止接受新作业；这些握手信号不得用于反压 AFDX 业务链。

1. `job_valid && job_ready` 时锁存 job_id、job_model_tag、job_feature_mask 和 job_flags。
2. 完整特征掩码必须为 `18'h3ffff`，模型标识必须与 `result_model_tag` 一致。此标识是构建绑定，不是密码学认证。
3. 接受作业后按时间从旧到新、每窗口按下表顺序发送 144 个 signed int16 值。仅最后一拍设置 feature_last。只有 feature_valid && feature_ready 才算传输。
4. 特征输入是已标准化、已量化数值：`round_away(((log1p(x)-mean)/scale) * 2**10)`；量化前检查原始物理范围。原始数据或未来数据不能直接送入。
5. `result_valid` 在结果被 `result_ready` 接收前保持为 1，全部结果字段保持稳定。下一作业必须等待 job_ready。

错误特征长度会提前终止该作业。调用者须丢弃该作业剩余数据，消费错误结果，再发新命令。空闲期 feature_valid 不被接受。复位会取消在途作业及未消费结果；上位机必须重新发送完整窗口。

`job_flags[0]` 表示主机发现某特征标准化绝对值超过 6；`job_flags[1]` 表示主机输入量化发生裁剪；高位保留。两种质量标志仍允许计算原始输出，但禁止有效候选。特征掩码不足、模型不符或保留位错误时直接返回错误，不接受特征。

## 特征顺序与来源

| 索引 | 名称 | 单位或范围 |
|---:|---|---|
| 0 | observed_pps | 帧/秒，0–200000 |
| 1 | mean_frame_bytes | 字节，64–1518 |
| 2 | frame_size_cv | 非负变异系数 |
| 3 | arrival_cv | 非负变异系数 |
| 4 | ab_unpaired_ratio | 0–1 |
| 5 | ab_payload_mismatch_ratio | 0–1 |
| 6 | fcs_error_ratio | 0–1 |
| 7 | queue_overflow_ratio | 0–1 |
| 8 | latency_p95_us | 微秒，非负 |
| 9 | ntp_rtt_ms | 毫秒，非负 |
| 10 | ntp_offset_abs_ms | 毫秒，绝对值 |
| 11 | clock_step_abs_ms | 毫秒，绝对值 |
| 12 | loader_progress_ratio | 0–1 |
| 13 | loader_retry_ratio | 0–1 |
| 14 | fragment_orphan_ratio | 0–1 |
| 15 | management_fraction | 0–1 |
| 16 | active_context_ratio | 0–1 |
| 17 | sha_jobs_per_1k_frames | 每千帧作业数，非负 |

这套定义继承原合成数据生成器。接入真实系统时必须固定各指标的分母、观察窗口、帧计数点和时延测量点，并验证与训练数据语义相同。缺少窗口、字段、有效测量或配置一致性时拒绝推理。当前主机 API 要求完整数组；直接使用 RTL 的调用者负责提供真实的有效掩码。

## 输出

`result_logits[i*16 +:16]` 是第 i 个 signed int16 输出，统一有 8 个小数位。0–6 对应 congestion、link_degradation、replica_divergence、time_anomaly、loader_stall、fragment_pressure、management_burst；7 为队列风险 logit；8 为标准化对数时延。

候选掩码 0–7 位按整数 logit 阈值比较。硬件无 sigmoid、log1p 或 exp 运算；主机用输出尺度恢复分数，并对第 8 项计算 `expm1(clip(raw/256*reg_scale+reg_mean,0,20))`。恢复分数不改变硬件候选掩码。分数未做实际部署概率校准。

任何 result_status 非零时，候选掩码清零、warning=false、有效时延预测为 null。原始 logits 保留以便调试，不应作为有效决策使用。

| 状态位 | 含义 |
|---:|---|
| 0 | 144 拍长度或 last 位置错误 |
| 1 | 缺失特征 |
| 2 | 模型标识不一致 |
| 3 | 特征输入连续空闲超时 |
| 4 | 主机声明超出训练支持范围 |
| 5 | 主机输入裁剪或任一推理层饱和 |
| 6 | 作业 flags 保留位非零 |

`result_saturation[2:0]` 依次表示第一卷积、第二卷积、最终全连接的正向饱和或最终层负向饱和。ReLU 将负数置零属于定义，不计为数值错误。默认输入连续停顿超时为 65536 周期；有效输入拍与超时同周期时优先接受该拍。根据实际传输路径调整该参数。

## 独立本地 CSR

`afdx_ai_csr` 在 cfg_valid && cfg_ready 的上升沿完成一次访问；cfg_error 指示非法访问，非法访问不产生作业或特征副作用。地址为字节地址，每次访问 32 位且须对齐。主机只在 result_valid 后读取完整结果，再 ACK。

| 地址 | 访问 | 内容 |
|---|---|---|
| 0x00 | R | 魔数 0x41494831 |
| 0x04 | R | 编译 ROM 模型标识 |
| 0x08 | R | bit0 job_ready；bit1 feature_ready；bit2 result_valid |
| 0x0c | RW | 下一个 job_id |
| 0x10 | RW | 下一个 job_model_tag |
| 0x14 | RW | 下一个 feature_mask，低 18 位 |
| 0x18 | RW | 下一个 job_flags，低 16 位 |
| 0x1c | W | 写 1 提交作业，忙时等待 |
| 0x20 | W | 低 16 位特征，bit16 last，未准备好时等待 |
| 0x24 | W | 写 1 消费结果，无结果时等待 |
| 0x28 | R | 结果 job_id |
| 0x2c | R | bits15:0 status；bits18:16 saturation；bits31:24 candidate mask |
| 0x30 | R | 计算段周期数 |
| 0x34–0x54 | R | 9 个 logits，每个低 16 位为二补码，步进 4 |

`HardwareCsrPlugin(read32,write32)` 执行身份核对、作业提交、完整特征传输、有限轮询、结果绑定核对和 ACK。回调必须在自身传输层实现超时，返回已完成的总线访问；Python 轮询预算不能中断阻塞的物理驱动。对不同传输端序，由回调统一提供 uint32 语义。

该接口不包含板卡 PCIe、UART、以太网或 JTAG 驱动。驱动接到专用本地总线，不将 AI 寄存器地址直接复用于原安全配置空间。结果读取串行化，一次只有一个主机拥有该接口。
