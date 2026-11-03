# AFDX 外挂网安插件

本包针对随附的 `AFDX_Competition_Final (2).zip` 基线设计，提供六项可运行的安全扩展：双网内容一致性、阶段/会话授权、资源配额、原子策略切换、签名加载授权/防回退、时间可信度监测。原核心保存在 `reference_core/`，未修改其架构或源码；`docs/BASELINE_HASHES.json` 可逐文件验证。

**正式接入顶层是 `AFDX_security_plugin_top`。默认 ENFORCE，未配置时拒绝 RX。** 原 106 个端口和 22 个参数保留，另加独立安全控制及事件口。发送路径只做观测，接收路径按整帧检查和重放。八口兼容顶层显式处于 BYPASS，仅供旧接口对比。

## 内容

| 路径 | 用途 |
|---|---|
| `rtl/` | 独立安全 RTL、SHA-256、帧队列、证据保留、原子策略表、封装顶层 |
| `host/authorizer.py` | 真实 Ed25519 验签、目标/时效/nonce/版本检查、持久主机状态、授权寄存器生成 |
| `host/control.py` | 规则冲突预检，多加载器授权合并成一次完整提交 |
| `host/evidence.py` | 冻结证据读取、原始帧及差异位置导出 |
| `tb/`、`tests/` | 冻结的有效签名、报文、RTL/主机测试及基线集成适配模型 |
| `scripts/run_tests.py` | 一次运行主机、RTL、原核心联测和独立报文审计 |
| `results/release_final_20261015/` | 本次实际执行的回归日志、原始线上帧、源文件哈希和汇总 |
| `docs/` | 接口、寄存器、可信边界、验证范围及演示步骤 |

## 运行

需要 Python 3.12 或兼容版本、`requirements.txt` 中的 cryptography、Icarus Verilog 11 或兼容版本。仿真使用 Verilog-2001；基线有 `priority` 等标识符，不应直接切换为 SystemVerilog 关键字模式。

```sh
python -m pip install -r requirements.txt
python scripts/run_tests.py --out results/my_run
```

需要指定本机工具时：

```sh
python scripts/run_tests.py --iverilog /path/to/iverilog --vvp /path/to/vvp --out results/my_run
```

特殊可重定位安装可再指定 `--ivl-base /path/to/ivl`。每次选择新输出目录，失败会以非零退出码结束。脚本不会重签清单或重生成测试向量。日志中的绝对路径是本次执行位置，移到其他电脑后由脚本重新生成。

```sh
python scripts/generate_wrapper.py
```

上面命令仅重新生成外围封装；不会改 `reference_core/`。`generate_vectors.py`、`generate_integration.py` 属于开发工具，会产生新的测试密钥和测试签名，交付后复现验证不需要运行。私钥仅存在于生成过程内存，包内公钥是测试公钥。

## 接入次序

1. 编译 `reference_core/rtl/*.v` 与 `rtl/*.v`，选择完整封装顶层，按 [接口对照](docs/INTERFACES.md) 连接。
2. 可信主机恢复持久版本下限，验证外部签名授权清单，构造完整规则、授权表与模式事务。
3. 先用 SHADOW 模式评估事件和误拦；确认规则冲突预检通过、正常流量可通过后，提交 ENFORCE。提交只在安全边界原子生效。
4. 日志消费者持续读取事件；双网冲突时通过寄存器导出冻结的两份完整帧，再明确 ACK 释放证据。
5. 只有原核心实际发布新包、可信控制器核实对应 `package_generation`/服务域后，才调用 `confirm_publication()` 提高主机版本下限，并同步 RTL floor。验签通过或开始传输不等于发布成功。

详细内容见 [寄存器](docs/REGISTERS.md)、[安全边界](docs/SECURITY_SCOPE.md)、[演示](docs/DEMONSTRATION.md)、[验证报告](docs/VALIDATION.md)。

本包的交付结论是软件/RTL 原型及所列仿真证据。板级互通、目标 FPGA 资源及时序收敛、可信 NVM、密钥烧录和正式标准/认证审查需在目标环境完成，未在本包中宣称通过。
