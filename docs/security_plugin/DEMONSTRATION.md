# 不上板演示与使用

## 一次回归演示

在根目录运行 `python scripts/run_tests.py --out results/demo_run`，结果必须是 `SECURITY_REGRESSION_PASS`。查看 `summary.json` 及各子目录日志。以下均来自实际DUT输出，不是预先绘制的界面数值。

| 展示 | 向量/日志位置 | 可观察结果 |
|---|---|---|
| 双网内容篡改 | `tb/scenarios.json` 的 `AB_valid_checksums_content_conflict` | FCS/IP/UDP均合法，后到报文flags=4且ENFORCE不转发；冻结两份帧、差异位置；后续冲突增加证据lost |
| 阶段/TID | `LUR_before_LUI`、`out_of_order_file_block`、`legal_retransmission` | 非法操作被拒，合法重传允许；相同块号改变内容被拒 |
| VL/服务域资源 | `second_unfinished_message_quota`、`other_flow_has_independent_quota` | 超额消息拒绝，另一规则仍可接收；完成/超时释放；正常小帧恢复通过 |
| 原子更新 | 测试命令中的 `core_safe=0`、会话中commit、rollback | 活动模式保持旧值，pending置位；空闲后整表切换，floor不降，授权撤销 |
| 签名/内容 | `tests/test_authorizer.py` 与 `authorized_DATA_*`、`valid_crc_but_sha_mismatch` | 真Ed25519验签；错误签名/版本回退/nonce复用拒绝；RTL SHA对替换内容拒绝末块 |
| 授时攻击 | `NTP_wrong_origin`、`NTP_excess_round_trip`、`established_NTP_jump_rejected` | 异常回复拒绝，正常恢复允许；UTC跳变/倒退/失锁计数增加 |
| 双加载器与双授时 | `core_multi/result.log`、`multi_services_wire.txt`、`core_security_events.txt` | 两个独立加载器全部完成已签名文件；两时钟锁定并完成恢复；独立线上审计 |
| 不破坏原接口 | `bypass/result.log` 及两套 `*_shared_wire.txt` | 原核心与封装的39项输出逐周期比对；两份完整线上日志连时间戳一致 |

`plugin/forwarded_wire.txt` 为「场景号 通道 结束周期 原始完整帧hex」，`plugin/security_events.txt` 为「场景号 事件消费周期 160位事件hex」。事件中的到达周期与消费周期不同；前者用于流量间隔和A/B关联。压力注入使用场景号0，不与逐条握手场景混计。

## 实际配置流程

1. 预置公钥和设备ID，可信主机从受保护存储读取版本下限。`initialize_state()` 仅用于首次可信制造/试验置备，不应在每次启动把floor设为0。
2. 上级授权方签名的是 `DOMAIN + canonical_JSON`，DOMAIN为 `AFDX-SEC-MANIFEST-v1` 加一个NUL，JSON为键排序、无多余空格、ASCII转义、禁止NaN。字段和大小见 `authorizer.py`；包内有可验证的测试清单/公钥/签名。
3. 调用 `authorize()`，传入预期target、硬件ID、可信当前时间和本次随机nonce。主机先验签和所有约束，再原子记下已用nonce并生成授权写入。不要接收网络发来的预制寄存器收据。
4. 用 `Rule` 构造地址/资源策略，调用 `control.transaction({规则号:规则}, receipts, mode=1)` 做冲突检查及多加载器合并。每项写入前等待cfg_ready，写后检查cfg_error；末项为commit。等待epoch增加、pending清除并读回关键活动值。
5. 重放正常/异常流量，根据事件检查影子误拦；确认后生成完整mode=2事务并在维护安全边界提交。模式切换会清空会话和A/B状态，只能在无活动会话时生效。
6. 实际发布后，可信主机调用 `confirm_publication(state_path, target=..., version=..., generation=...)`，持久提高floor并同步RTL。该generation必须严格大于持久状态中的已确认代数，来源由可信控制器在核实服务域及核心发布状态后提供；断电恢复时必须保持单调。

可以先运行 `python examples/prepare_demo.py --out results/demo_config` 生成两域测试配置。它使用冻结清单的模拟时间150验证[100,200]有效期，不会把过期试验清单当作生产授权。该示例不是生产密钥置备程序。

## 原始证据导出

可信控制器向 `host/evidence.snapshot(read32)` 提供本地总线读函数；返回两份完整线上帧及全部差异。调用 `evidence.save(record, output_dir)` 保存 `.bin` 和JSON后，再由控制器写 `0x2000=0x41434b31`。导出期间证据保持冻结。ACK前检查并记录evidence_lost；非零表示存在未保留下来的后续冲突。

## 工程接入文件表

新增RTL全部列于 `plugin_files.f`；将基线 `reference_core/rtl/*.v` 一并加入工程即可。现有QSF/SDC属于原核心，本包没有自动替换目标器件或声称新插件已达到12.5MHz时序收敛。物理MAC、电源复位、可信总线及日志/NVM连接应在板级工程完成。

为了让原测试模型能在Icarus的Verilog-2001模式运行，`tb/model_security_rx_filter.v`、两个 `model_security_*.v` 在外围兼容副本中把端口声明初始化移到初始块。原模型和原RTL未修改；39项周期比较和线上日志审计用于检验这种适配没有改变可观测流程。
