# AFDX AI 硬件推理插件 R1

这是已经实现并运行 RTL 仿真的小型时序神经网络推理插件。电脑负责训练和特征预处理，FPGA 逻辑负责两层因果卷积、池化、全连接与候选判定；上位机智能体读取结果开展证据分析。现有 AFDX、安全和拟态插件源码不需要改写。

交付范围是独立 RTL 核、独立本地寄存器包装、实际训练权重、整数参考模型、主机驱动、智能体适配示例和可复现测试。尚未执行 EQ6HL130 器件综合、布局布线、时序收敛或板级测试；包中没有可直接烧录的 bitstream。

## 已实现

- 保留前一版真实训练的 TCN：8×18 输入，两层 16 通道因果卷积，膨胀率分别为 1、2，末时刻与全窗口均值拼接后输出 9 个值。
- 七类故障候选、未来三个窗口的队列风险、未来三个窗口各自 p95 时延最大值的回归输出。候选不等于已确认物理根因。
- 按输出通道量化的 INT16 权重、INT16 激活、INT32 偏置和 INT48 累加；共用一条乘加数据通路。
- 输入和输出 ready/valid、完整特征掩码、模型标识、错误状态、数值饱和、输入停顿超时和复位恢复。
- 独立 AI CSR 总线及 `HardwareCsrPlugin` 驱动；与原 `sec_cfg_*` 总线没有隐式地址共用。
- 实际调用 Icarus RTL 的 Python 接口；缺少仿真器会明确失败，不退回参考模型冒充 RTL。

## 运行

需要 Python、NumPy 和 Icarus Verilog。普通推理不需要 PyTorch 或 scikit-learn；重新训练才需要 scikit-learn。安装依赖后，在本目录运行：

```bash
python3 -m pip install -r requirements.txt
python3 scripts/run_all.py
python3 -m afdx_ai_hw infer --history examples/history.json --job-id 42 --out reports/my_rtl_result.json
python3 -m afdx_ai_hw emit-csr --history examples/history.json --job-id 42 --out reports/my_csr_operations.json
```

`infer` 默认执行真实 RTL 仿真。只计算整数参考模型时，显式加 `--backend reference`，输出会标明来源。Icarus 不在 PATH 时，可设置 `IVERILOG`、`VVP`，必要时设置 `IVL_BASE`。不要把示例输入当成实际采集记录。

复现原浮点模型训练和定点导出：

```bash
python3 -m pip install -r requirements-train.txt
python3 scripts/reproduce_training.py
python3 scripts/verify_export.py
```

上述两个命令在隔离临时目录运行并比较结果，不覆盖发布权重。`source_model/scripts/train_temporal.py` 保留了原训练程序；若要改模型，请复制整个项目另建版本。直接重新导出会改变 ROM、模型标识和发布哈希，需要重新验证。

## 对接现有智能体

将本插件与上一版 `AFDX_AI_Extensions_R2` 并排解压。以下示例实际把 Assistant 的时序工具实例换为硬件推理适配器，其他工具保持原实现：

```bash
python3 examples/run_extension_agent.py --extensions-root ../AFDX_AI_Extensions_R2 --case ../AFDX_AI_Extensions_R2/cases/compound --out reports/my_agent_report
```

该命令默认执行 RTL。需要单独准备上一版扩展包；本包没有重复嵌入全部智能体依赖。特征越界或数值错误会停止该调查，避免把无效分数用于后续实验排序。

## 接入和证据

- [接口与寄存器](docs/INTERFACES.md)：端口、地址表、错误语义和主机契约。
- [模型与精度](docs/MODEL_CARD.md)：量化选择、合成数据评估及适用边界。
- [器件接入](docs/INTEGRATION.md)：EQ6HL130 工程接入、时钟和特征来源。
- [验证记录](docs/VALIDATION.md)：可复现结果、周期推导和仍待验证事项。
- `evidence/release_20261016/`：本次交付冻结的实际运行结果；`reports/` 是重新运行时的可写输出。

现有模型需要完整 18 维窗口。原计数器桥仅能推导部分指标，缺失指标不能补零伪装为实测。本版预处理在主机执行，尚未实现原始 MAC 到全部特征的 FPGA 在线提取。模型 ROM 在构建时固定；模型更新走重新构建与可信发布流程。
