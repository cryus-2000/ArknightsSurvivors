# 逻各斯 S1 短符文连射

用户授权按两张截图重画 S1，后续指定：仅保留紧密排列的符文、没有连接线、浅弧发射、目标侧头部亮、施法者侧尾部暗。源母图由内置 imagegen 生成，当前为 `codex/art` 的 `art/incoming/cr_logos_s1_rune_chain_1019/generation/master_runes.png`；完整提示词见 `REVISION_03.json`。母图经过像素采样、机械布局整理及调色板映射后打包。

运行素材 `fx_logos_s1_chain.png` / `@2x.png`，4 帧 / 12 fps，帧尺寸 64×12 / 128×24，左中锚点 (0,6) / (0,12)，16 色、alpha 0/255，每段约 14 个符文。最新修订保留原符文与配色，各帧共用同一套列映射剔除字间空白，再以最近邻放回固定帧宽；字符高度不变，轮廓紧贴，没有透明竖列，也没有新增连接丝。布局记录见 `REVISION_05.json`，原始生图提示词仍见 `REVISION_03.json`。

`seg_logos.hw_s1_packet_pose` 对齐每 0.25 秒一次的现有结算，5 秒共 20 束。最新修订将每束从约 48 加长到 60 世界像素，约 6～7 个紧贴符文；每轮前 0.0375 秒留空，再飞行 0.2125 秒，于该次伤害 tick 抵达目标。与上一版相比，飞行速度约慢 12%，攻击间隔和伤害结算不变。仍沿跨度 5%、上限 12 世界像素的浅弧前进，每束头亮尾暗；不显示常驻整条符文流。复用现有 `draw_colored_polygon`，新图存在时不叠旧实心连线，保留命中辉光和目标标记；缺图回退旧效果。伤害递增、减速和升级转移规则未改。最新播放约束见 `RUNTIME_REVISION_05.json`。

实机录制：`tests/logos_projectile_capture.tscn -- --logos-s1`，7.2 秒 / 144 帧，使用实际技能起手和释放。最新输出 `build/logos_projectile_capture/s1_bursts_revision_02/`；上一版保留在 `s1_bursts/`。聚焦回归验证较长短束、较慢飞行、无字间透明列、曲线端点、到达时刻、渐变、素材加载、20 次递增伤害、到时停止及目标死亡中断。

与普攻最新速度感候选合并预览：`build/logos_projectile_capture/speed_revision_03/review.html`。独立测试分支 `codex/logos-projectiles`，尚未合入主线或发行包。

上一版验收：针对性回归及 20 束 / 20 次伤害实机检查通过；`check.py --auto --jobs 3` 共 73 项、0 失败、280 秒（`build/check/quick_1019_111911/`；未编原生核心及 14 份过期金样按项目规则跳过）。初版源素材提交 `codex/art@397bcfd3c37fee58b1f92c9d9f293c951d8ae72e`。

本轮验收：先验证旧版未通过加长、放慢与零透明列断言，再修改并通过针对性回归。实机 20 束 / 20 次伤害、GIF 7.2 秒及等比尺寸均通过；源素材 1x / 2x 全部帧字间透明列为 0，配色仍来自原 16 色。`check.py --auto --jobs 3` 共 73 项、0 失败、294 秒（`build/check/quick_1019_113902/`；原生核心与过期金样跳过范围同上），无脚本或解析错误。seed 1 / logos / 60 秒与缓存基线逐行对照，61 行 TRACE 相同。当前源素材提交 `codex/art@adb9d41f4201429309e42b6a51117b0b49bd54d1`，运行 PNG 哈希一致。
