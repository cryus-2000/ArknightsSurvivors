# docs/97 D · 1x / @2x 对位

艾雅法拉、维什戴尔四动作统一色板到≤24并以既有 @2x 几何逐帧导出 1x，修复维什戴尔 idle f1 对位。凯尔希仅修 op_mon3tr_skill（m_skill）同序导出，消除 f5 错配；逻各斯已在 A 完成，本批复查。未改 @2x 动作几何、出手帧、尺寸和帧数。

QA：`python tools/art_lint.py --ops eyjafjalla,logos,wisadel,kaltsit --no-images`，四人 pair 全 PASS、未豁免 FAIL = 0。剩余7项 WARN：既有跑步 foot 配置、维什戴尔待机呼吸幅度、逻各斯亮部比例、凯尔希待 E 批处理的明度及其他身体动作总色数。完整测量在 QA，帧条 SHA256 / 配置见 manifest。

Mon3tr 与凯尔希色数分别处理，未把召唤物调成凯尔希色板。本批新增动作0，仅对位与色板导出；@2x主稿保持原姿势。新出技能末帧继续与待机一致。

preview.gif 为交付帧条按原 fps 播放；lineup 是本批干员及斯卡蒂、浊心斯卡蒂、流明的脚底对齐亮暗两行。只交 art/incoming，未接入 game/main。
