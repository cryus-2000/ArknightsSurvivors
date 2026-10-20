# 乌尔比安落地特效与博士新版接入

目标：按用户批准的方案去掉粗大完整圆环，收敛地裂与纯白水花，错开水花和余波；补入此前批准的博士待机、跑步、倒下。沿用独立 codex/siege-ulpianus-runtime，不改 main。

架构：角色专用纯视觉模块负责水花和断续贴地弧，复用现有 pfx 生命周期与局部地裂工具。所有伤害、命中时间、半径、冷却、位移和顿帧时长保持不变。Doctor 复用已验收的 489259e0 接入，不重新生成美术。

- [x] 核对来源：精一 fx_ulpianus_pull_ring 被放大 6 倍，是主要粗灰环来源；S3 旧 fx_circle_steel 也按范围放大。大落地重复生成水花，后续爆破再加双环与水花；当前包缺少 Doctor 新画风提交。
- [x] 将博士已批准的 489259e0 接入本测试分支，核对素材哈希与原点。
- [x] 在现有定向回归中先验证落地只生成一套水花、不生成完整圆环，余波与水花生命周期独立，视觉不消耗玩法 RNG。
- [x] 实现 characters/ulpianus_impact.gd；仅改乌尔比安调用与 fx 配置，保留角色身体、动作、玩法与其他角色通用特效。
- [x] 录制相同夹具的旧版与新版实际视口，展示常速、慢放、关键瞬间与新版博士；先目视检查，再跑定向与分级检查、同种子 TRACE。最终保留原水花版 83 项、0 失败，122 行 TRACE 相同，540 个实机采样点无玩法差异。
- [x] 提交选定文件，更新独立本地内测包，验证图片、存档隔离、解锁、启动与 ZIP 一致性；交付实际录制与启动入口。

交付代码 c19718d2（含博士接入 c4049d5f）。本地包 `build/release/方舟幸存者_Internal_EA_Encrypted_20261020_c19718d2.zip`，直接启动 `build/_export/方舟幸存者/开始游戏.bat`。1351 张 PNG、319 个音频、30 份 JSON 读取、内测解锁、独立存档迁移、打包游戏启动与 ZIP 一致性通过；报告 `build/encrypted_game_verification_internal_c19718d2.json`。实际游戏启动无资源清理告警；资源探针 / 画面采集退出保留既有清理告警。汇总 `build/ulpianus_impact_revision/delivery.json`。

复现入口：tools/probes/siege_ulpianus_runtime.py；现有实际视口基线 build/siege_ulpianus_runtime。最终新增审阅目录 build/ulpianus_impact_revision。自动检查通过不等于用户视觉批准。

用户看首轮预览后修正：原水花好看，保留 `fx_splash_blue` 原版，只去掉重复水花；继续取消粗灰收链贴图和大圆环。最终效果以这一指示为准。
