# 逻各斯 S1 短符文连射

用户授权按两张截图重画 S1，后续指定：仅保留紧密排列的符文、没有连接线、浅弧发射、目标侧头部亮、施法者侧尾部暗。源母图由内置 imagegen 生成，当前为 `codex/art` 的 `art/incoming/cr_logos_s1_rune_chain_1019/generation/master_runes.png`；完整提示词见 `REVISION_03.json`。只对母图进行等比像素采样、调色板归并与打包。

运行素材 `fx_logos_s1_chain.png` / `@2x.png`，4 帧 / 12 fps，帧尺寸 64×12 / 128×24，左中锚点 (0,6) / (0,12)，16 色、alpha 0/255，每段约 14 个符文。符文间保留透明空隙，不画横向连接丝。检查循环接缝间距，横向平铺、端点裁切，不把整条拉长。

最新用户要求为高频独立攻击。`seg_logos.hw_s1_packet_pose` 对齐每 0.25 秒一次的现有结算，5 秒共 20 束；每束最多约 48 世界像素，约 5～6 个符文。每轮前 0.0625 秒留空，再飞行 0.1875 秒，于该次伤害 tick 抵达目标。沿跨度 5%、上限 12 世界像素的浅弧前进，每束分别头亮尾暗；不再显示常驻整条符文流。复用现有 `draw_colored_polygon`，新图存在时省去原实心连线，保留命中辉光和目标标记；缺图回退旧效果。伤害递增、减速和升级转移规则未改。最新播放约束见源素材包 `RUNTIME_REVISION_04.json`。

实机录制：`tests/logos_projectile_capture.tscn -- --logos-s1`，7.2 秒 / 144 帧，使用实际技能起手和释放。`build/logos_projectile_capture/s1_bursts/` 有完整画面、局部 GIF、原始 PNG、时间、短束长度与伤害记录。聚焦回归 `tests/logos_projectile_test.tscn` 验证短束与间隙、曲线端点、到达时刻、渐变、素材加载、20 次递增伤害、到时停止及目标死亡中断。

与普攻最新速度感候选合并预览：`build/logos_projectile_capture/speed_revision_03/review.html`。独立测试分支 `codex/logos-projectiles`，尚未合入主线或发行包。

最终验收：针对性回归通过；实机 20 束 / 20 次伤害，活动期间采样到 20 个空档帧，无脚本、解析或退出资源错误。`check.py --auto --jobs 3` 共 73 项、0 失败、280 秒（`build/check/quick_1019_111911/`；未编原生核心及 14 份过期金样按项目规则跳过）。与已缓存的 600 弹速版本对照，seed 1 / logos / 60 秒的 61 行 TRACE 相同。源素材与完整提示词已提交 `codex/art@397bcfd3c37fee58b1f92c9d9f293c951d8ae72e`；本分支的运行 PNG 哈希与该导出包一致。
