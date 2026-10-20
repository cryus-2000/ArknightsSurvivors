# 推进之王与乌尔比安原生美术接入

用户批准取消换手号令，并将两人新美术接入测试版。本分支从 main 开出，再同步此前测试版 1e109651，以保留其他干员、博士、怪物与 Logos 弹体的已有改动。

推进之王：Idle、Run、Attack、LeapSlam、HeavyAttack、Die 六组。Command 停用；S1 / S3 保持正常持锤，事件仍 0.208333 秒。普攻事件 0.178571 秒，重锤事件 0.291667 秒，S2 在实际起跳后 0.42 秒落地。

乌尔比安：Idle、Run、Attack、ThrowReel、ZipLand、Whirl、S2Attack、Die 八组；另交原生离手四刃锚组件。普通与 S2 锚击事件仍 0.291667 秒；投锚、回拉、停顿与弹射由真实阶段驱动。链条读当前帧手部连接点，离手锚使用同一四刃组件环心。

8 帧横条均只交 @2x；安全共同裁窗为 128，放不下的回旋 / S2 完整场景保留 256 与对应 foot。原始像素不重新绘制或缩放，遮挡在烘焙时保留；不是运行时 Spine 网格。来源哈希见 siege_ulpianus_native_sources.json，复现工具 tools/probes/package_siege_ulpianus.py。

原有玩法攻击窗口不变，视觉收势单独延续，可被下一动作打断；没有延长冷却、改变伤害或消耗玩法 RNG。定向回归、同种子 TRACE、快检与实际视口证据另见 build/siege_ulpianus_runtime，构建产物不进 Git。

验收：项目分级快检 83 项、0 失败；两人各 61 行、合计 122 行 TRACE 与 1e109651 相同。15 张原生运行时贴图通过二值透明与帧数尺寸检查，数值数据未变。旧 1x 条已移除，避免新旧帧数混用。旧描边 / 跑姿 / 最低行指标保留 6 项明确例外、11 项警告，不当作视觉通过；记录在 siege_ulpianus_runtime_qa.json。实际视口覆盖所有主要槽位，录制夹具退出有既有资源清理告警，定向回归未发现脚本或解析错误。精英化掷锚亦复用新身体和原生锚，飞 / 绷紧 / 拖回按实际阶段取帧，原有额外回旋同时触发时仍保留效果。

本地测试包：代码 0abf7207，`build/release/方舟幸存者_Internal_EA_Encrypted_20261020_0abf7207.zip`。可直接运行解包目录 `build/_export/方舟幸存者/开始游戏.bat`；真实视口预览 `build/siege_ulpianus_runtime/review.html`。独立内测包保留此前测试分支已有的干员、博士、怪物与 Logos 弹体修改。包内 1351 张 PNG、319 个音频、30 份 JSON、内测全解锁、独立存档迁移、打包游戏启动和 ZIP 文件一致性均验证通过，详见 `build/encrypted_game_verification_internal_0abf7207.json`。未合入 main、未公开发版。
