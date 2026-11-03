# AFDX 智能体诊断报告：live_defense

调查状态：completed；停止原因：complete；工具调用：6。

## 现象与模型候选

模型状态：out_of_support。森林投票份额不是校准概率；当前调查焦点为 `link_degradation`。

| 候选 | 投票份额 |
|---|---:|
| 链路质量下降 | 0.3602 |
| 授时异常 | 0.2585 |
| 正常 | 0.1654 |

## 已核对的局部证据

本次没有足以形成局部确定事实的捕获证据。

## 主动验证过程

| 工具/实验 | 状态 | 证据域 | 输出 |
|---|---|---|---|
| rtl_experiment | unavailable | model_counterfactual | [JSON](tools/05_rtl_experiment.json) |

## 策略建议

核对链路、线缆与副本缺失；保持CRC及双网检查。


候选需要完整影子表复制、epoch/原值重查、正常流量影子试运行及既有可信配置流程应用。本智能体未写入设备配置。

## 结论与待验证事项

本次结果区分模型候选、局部捕获事实、受控注入与隔离RTL机制实验；尚未确认为真实设备物理根因。

- 本次未运行全部RTL实验；缺少工具或已关闭。
- 模型低把握或超出支持范围，保留候选。
- 真实设备根因仍需现场测量确认。
- 三个模型来自合成数据，异常召回及复合故障识别仍有限。

## 可追溯调用

| 序号 | 工具 | 选择原因 | 状态 |
|---|---|---|---|
| 1 | [inventory](tools/01_inventory.json) | 先固定证据清单、来源和测量覆盖。 | ok |
| 2 | [diagnose](tools/02_diagnose.json) | 调用三个固定模型，建立候选与时延/异常参考。 | ok |
| 3 | [parse_frames](tools/03_parse_frames.json) | 按当前候选和可用证据选择独立检查：link_degradation | ok |
| 4 | [search_logs](tools/04_search_logs.json) | 定位日志原文、文件哈希和行号。 | ok |
| 5 | [rtl_experiment](tools/05_rtl_experiment.json) | 针对当前焦点执行固定RTL机制实验及正常恢复对照。 | unavailable |
| 6 | [propose_policy](tools/06_propose_policy.json) | 根据证据及实验生成可审查建议，并校验允许修改范围。 | advice_only |
