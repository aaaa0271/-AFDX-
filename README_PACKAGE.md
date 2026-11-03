# AFDX 航电网络安全端系统源码交付

源码修订：2026-11-03。实际文件数量与SHA-256以根MANIFEST.sha256为准。

- rtl/：120个Verilog文件；aihw_plugin/rtl/另含TCN核心。
- tb/：171个文件，其中124个Verilog文件，包含116个测试台和8个辅助模型/替身。
- scripts/tests.json：127个注册用例；注册数量不等于本次已通过数量。
- host/、afdx_ai/、afdx_agent/、mimic_plugin/：宿主控制、诊断和真实异构执行器。
- vendor/：内置部分协议依赖；NumPy、cryptography仍须安装，见requirements.txt。
- docs/screenshots/：已有截图；版本与证据对应关系见evidence/INDEX.md。
- report_tools/：路径按当前工程定位；打包必须指定工程外的新ZIP，不覆盖原文件。
- poster/poster.html：海报源文件。
- ARINC.epr：EQ6HL130目标工程；ARINC.qsf：Quartus兼容分析，不代表器件综合通过。
- evidence/：验证汇总、原始日志及选定波形；results/为运行生成目录，不入源码包。

## 环境与命令

Python 3.12+、有许可的ModelSim SE-64 2020.4、GCC/G++（C11/C++17）。
已有pyc允许保留，但复现以.py源码为准。

    python -m pip install -r requirements.txt
    python -B -m unittest discover -s tests -v
    python -B -u scripts/run_all.py --hdl-only --workers 4
    python -B -u scripts/run_all.py --elinx-only --elinx "实际quartus_map.exe路径"
    python -B report_tools/build_source_package.py --output "工程以外/AFDX_SOURCE_reviewed.zip" --folder-name AFDX_SOURCE_20261026

若gcc/g++不在PATH，先用当前终端环境指定编译器bin目录；
或运行scripts/verify_defense_live.py --out NEW_DIR --cc GCC --cxx GXX --modelsim VSIM。
AI插件独立Icarus脚本需要iverilog/vvp；ModelSim集成路径不依赖Icarus。

## 功能范围

当前支持有界上传加载及操作员/媒体指定卸载；详见 docs/DOWNLOAD_615A.md。
不宣称information/find、所有选项或全标准认证。
功能仿真通过不证明完整ARINC664条款、物理链路、目标时序或板级验证完成。
修订说明及尚未闭合项见docs/REVIEW_20261103.md，实测见evidence/。

本次处理结果和提交包说明见根目录“本次核查与提交说明.md”。
