# 615A 数据加卸载（2026-11-03修订）

加载表示电脑向目标FPGA发送软件包；卸载表示目标将已提交的软件包文件传回电脑。
此处“卸载”不会删除或回滚FPGA内的软件。

正式 AFDX_defense_top → AFDX_competition_top → 多服务域 →
afdx_package_network_services → afdx_615a_download。
基础顶层也走同一服务模块；历史 AFDX_legacy_top 不作为本次新增功能入口。

支持的流程：
- 操作员选择：RRQ TARGET.LNO → 初始化文件 → WRQ TARGET.LNS（接受）→
  WRQ TARGET.LNL（目录）→ 电脑 WRQ TARGET.LNA（选择列表）→
  WRQ TARGET.LNS（进行中）→ 目标 WRQ 所选文件 → WRQ TARGET.LNS（完成）。
- 媒体指定：RRQ TARGET.LND → 初始化与接受状态 → 电脑 WRQ TARGET.LNR →
  所选文件与完成状态。LNR 的用户自定义数据长度必须为0。
- 控制TID 44000；目标发起的目录、状态、文件传输使用44001。
  请求端口69，octet模式、512字节分块；整块长度文件以零数据块结束。
- 每域独立，目标只接受配置的 loader_ip。最多4个文件、每个4096字节，
  文件名1～31 ASCII字节；严格匹配已提交目录，拒绝重复、不存在的文件。
  TARGET.LNS、TARGET.LNL为协议保留名称，不能作为卸载数据文件。
- 独立只读端口读取已提交bank；加载与卸载互斥。应用读端口继续工作，
  卸载不改变generation、CRC或发布状态。
- 包含重传、重包、错误TID、ERROR/ABORT和超时释放；
  最终成功仅在完成状态文件被对端确认后产生。
- 默认安全防护识别下载阶段、控制TID与ACK绑定；下载不会创建固件加载授权。

从工程根目录复现：

    python -B -u scripts/run_all.py --hdl-only --workers 3 --tests tb_615a_roundtrip tb_615a_download_faults tb_615a_download_security
    python -B -m unittest discover -s tests -p test_download615a.py -v

tb_615a_roundtrip 通过实际UDP接口先加载665包，再卸载700字节A.LUP、
1024字节B.LUP以及一个文件子集。独立Python审计重组目标发出的报文，
与原始文件逐字节比对，检查LNL/LNS、重传和错误TID。
原始报文为download_wire.csv，审计为download_audit.json。

tb_615a_download_faults 覆盖无已提交包、加载互斥、未知文件、错误版次、重复文件、非空LNR自定义数据、
远端ABORT、重试耗尽、等待选择超时、初始化丢ACK、零字节文件。
tb_615a_download_security 覆盖默认ENFORCE下25个真实MAC帧的允许/拒绝。
tb_defense_live 通过真实GMII、安全模块和四个宿主执行体执行加载后卸载，
输出download目录内的原文件与审计结果；需要gcc/g++及numpy/cryptography。

host/download615a.py 提供独立对端编码、解析、收件与分块去重；
完整集成驱动为 scripts/verify_defense_live.py。
按组委会说明，竞赛采用仿真，不要求连接实体FPGA板卡运行以上验证。

本次采用与现工程一致的A4有界实现，不宣称ARINC615A-4全条款或任意
商用加载器互通认证。未增加information/find、OACK协商、认证加密、
周期状态心跳调度、非空LNR自定义数据、超出容量的文件或任意文件系统访问。
状态在事务推进和每文件边界发送；选择等待和传输等待均有界。

协议布局参考原作者发布的实现资料；本次代码自行实现，未复制其实现：
- [扩展名映射](https://github.com/Hitheshkaranth/arinc-615a-cli-tool-suite/blob/main/lib/arinc_615a/files/ProtocolFilename.cpp)
- [操作员下载事务](https://github.com/Hitheshkaranth/arinc-615a-cli-tool-suite/blob/main/lib/arinc_615a/target/implementation/OperatorDefinedDownloadOperationImpl.cpp)
- [LNL目录](https://github.com/Hitheshkaranth/arinc-615a-cli-tool-suite/blob/main/lib/arinc_615a/files/download/DownloadOperationListFile.cpp)
- [LNA选择](https://github.com/Hitheshkaranth/arinc-615a-cli-tool-suite/blob/main/lib/arinc_615a/files/download/DownloadOperationAnswerFile.cpp)
- [LNR请求](https://github.com/Hitheshkaranth/arinc-615a-cli-tool-suite/blob/main/lib/arinc_615a/files/download/DownloadOperationRequestFile.cpp)
- [LNS状态](https://github.com/Hitheshkaranth/arinc-615a-cli-tool-suite/blob/main/lib/arinc_615a/files/download/DownloadOperationStatusFile.cpp)

已通过GitHub官方API读取原始资料；不替代正版标准条款审查。
