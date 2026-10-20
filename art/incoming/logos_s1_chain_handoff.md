# 逻各斯 S1 短符文连射

用户授权按两张截图重画 S1，后续指定：仅保留紧密排列的符文、没有连接线、浅弧发射、目标侧头部亮、施法者侧尾部暗。源母图由内置 imagegen 生成，当前为 `codex/art` 的 `art/incoming/cr_logos_s1_rune_chain_1019/generation/master_runes.png`；完整提示词见 `REVISION_03.json`。母图经过像素采样、机械布局整理及调色板映射后打包。

运行素材 `fx_logos_s1_chain.png` / `@2x.png`，4 帧 / 12 fps，帧尺寸 64×12 / 128×24，左中锚点 (0,6) / (0,12)，16 色、alpha 0/255，每段约 14 个符文。最新修订保留原符文与配色，各帧共用同一套列映射剔除字间空白，再以最近邻放回固定帧宽；字符高度不变，轮廓紧贴，没有透明竖列，也没有新增连接丝。布局记录见 `REVISION_05.json`，原始生图提示词仍见 `REVISION_03.json`。

`seg_logos.hw_s1_train_pose` 按用户最新澄清，让前后两束也首尾相接。首轮在基础 0.25 秒内从手部铺向目标，此后符文列持续向目标滚动，每个攻击周期推进 60 世界像素，基础速度 240 世界像素/秒。沿跨度 5%、上限 12 世界像素的浅弧排布，目标侧头部亮、施法者侧尾部暗，没有符文之外的连接线；不再在结算处清空整束。显示为连续流动的符文列，伤害仍是独立的每 0.25 秒一次、5 秒共 20 次，不将符文滚动速度当作弹体碰撞时间。复用已有平铺和 `draw_colored_polygon`，正模处理负滚动偏移，避免起点漏空；缺图仍回退旧效果。伤害递增、减速、升级转移及普攻 A/B 不改。最新约束见 `RUNTIME_REVISION_06.json`，替代此前留时间空档的 `RUNTIME_REVISION_05.json`。

实机录制：`tests/logos_projectile_capture.tscn -- --logos-s1`，7.2 秒 / 144 帧，使用实际技能起手和释放；最新输出 `build/logos_projectile_capture/s1_rune_train_curve/`。已验证 100 个技能活动采样帧均有符文、20 次伤害相隔 0.25 秒、首末伤害相隔 4.75 秒。聚焦回归覆盖所有结算边界不断开、前向滚动裁剪、渐变、弧线、到时停止和目标死亡中断；seed 1 / logos / 60 秒与缓存 600 弹速基线的 61 行 TRACE 一致。最终曲线版项目检查 73 项、0 失败、240 秒（`build/check/quick_1019_120612/`），无脚本或解析错误；本机未编译的原生核心与 14 份过期金样按项目规则跳过。

与普攻最新速度感候选合并预览：`build/logos_projectile_capture/speed_revision_03/review.html`。独立测试分支 `codex/logos-projectiles`，尚未合入主线或发行包。

上一版验收：针对性回归及 20 束 / 20 次伤害实机检查通过；`check.py --auto --jobs 3` 共 73 项、0 失败、280 秒（`build/check/quick_1019_111911/`；未编原生核心及 14 份过期金样按项目规则跳过）。初版源素材提交 `codex/art@397bcfd3c37fee58b1f92c9d9f293c951d8ae72e`。

上一轮验收（留空短束版）：先验证旧版未通过加长、放慢与零透明列断言，再修改并通过针对性回归。实机 20 束 / 20 次伤害、GIF 7.2 秒及等比尺寸均通过；源素材 1x / 2x 全部帧字间透明列为 0，配色仍来自原 16 色。`check.py --auto --jobs 3` 共 73 项、0 失败、294 秒（`build/check/quick_1019_113902/`；原生核心与过期金样跳过范围同上），无脚本或解析错误。seed 1 / logos / 60 秒与缓存基线逐行对照，61 行 TRACE 相同。当前源素材提交 `codex/art@adb9d41f4201429309e42b6a51117b0b49bd54d1`，运行 PNG 哈希一致。

曲线微调按用户追加要求：相邻符文在主浅弧两侧最多偏移 1.5 世界像素，局部曲线与符文一起向前移动，不消耗 RNG，手部和命中点固定。平铺相邻几何段共享边，避免衔接处裂缝。

本轮曲线与衔接验收记录：`build/logos_projectile_capture/s1_rune_train_curve/validation.json`。源素材约束提交 `codex/art@204b6e5f3aa862fdd9d5929fc65bdc5d09f6e700`，PNG 内容仍与上一版相同。
