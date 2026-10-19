# 逻各斯 A/B 普攻飞弹：实机接入候选

2026-10-19，分支 `codex/logos-projectiles`，基线 `6b6977965`。用户授权把蓝紫螺旋与白紫咒文交替发射，并要求使用不同弧线、放入实机画面比较。本分支已接入；未合入主线，未更新发行包。

素材：`proj_logos_ink_a` / `_b` 各有 1x 与 @2x；每种 4 帧，母图设计 12 fps，当前运行 16 fps，单帧 32×12 / 64×24，中心锚点。A 为蓝紫螺旋，B 为白紫主体与局部橙金符文。母图、提示词和像素采样来源在 Codex 美术工作树的 `cq_logos_attack_fx_ab_1019`；本分支的素材哈希见 `logos_attack_ab_manifest.json`。

`blocks.attack.flight_visual` 为 A/B 提供两条独立弧线：跨度 ×0.09 的上弧、跨度 ×−0.05 的下弧，偏移上限 26 世界像素。显示位置取抛物线，朝向取其切线；飞弹相位按弹龄推进。新帧条优先于原随机符文，缺图保留回退。只有有目标、成功发出的普通攻击切换一次 A/B，同轮追加目标共用队列快照；独立技能飞弹保留原表现。

弧线位于表现层，原来的逻辑弹位、追踪、弹速、生命期、命中时刻和伤害没有重写，也不额外消耗玩法 RNG。该边界用同种子 TRACE 验证。

初版 260 弹速的验证（提交 4f9396a0）：

- `tests/logos_projectile_test.tscn`：目标选择后的 A/B 切换、无目标不切换、同轮多目标一致、共享配置不修改、技能隔离、两条弧线端点与弧顶、切线、玩法 RNG、原逻辑弹速均通过。
- `python tools/check.py --auto --jobs 3`：73 项，0 失败，250 秒。原生核心因本机未编译而跳过，14 份过期金样未作等价断言；没有脚本或解析错误。日志：`build/check/quick_1019_010045/`。
- `python tools/trace_base.py 1 logos 60 --ref 6b6977965 --here`：61 行 TRACE 逐行相同。
- `tests/logos_projectile_capture.tscn`：实际游戏场景、当前地图/人物/受光/HUD、固定站位和静止高生命靶；168 帧，20 fps，8.4 秒。记录六次 A/B 交替发射，发射帧 4/32/60/88/116/144，间隔均为 1.4 秒。最终录制无退出资源错误、脚本或解析错误。

预览：`build/logos_projectile_capture/review.html`；完整实机 GIF、局部等比放大 GIF、原始 PNG、逐帧位置与变体记录均在同目录。GIF 只做固定调色板编码及最近邻缩放/裁切，没有把特效后贴进背景。原始 PNG 是画面核对依据。

已检查实机 A/B 截图及输出 GIF 的解码帧。待用户确认弧度和视觉表现；尚未验证网页导出包，也未发布测试包。

## 速度修订

当前共享参数 `base.bolt_speed` 为 600（初版 260），固定靶示例中六发飞弹的可见飞行时间均约 0.4 秒。最新视觉修订收浅双弧线，自转提高到 16 fps；`flight_visual.trail_alpha` 为 0.72，`trail_width` 为 2，使短拖尾细而明亮。帧条本身不重画，普攻间隔仍为 1.4 秒，单次伤害不变。600 参数也用于同源的追加咒文弹，实际命中比 260 版提前，因此不沿用初版「与旧弹速 61 行 TRACE 相同」的结论。

当前录制以 `build/logos_projectile_capture/speed_revision_03/` 为准；02 保留为上一轮 600 弹速对照，01 为 260 / 312 历史对照。最新 S1 蓝紫符文链另见 `logos_s1_chain_handoff.md`。

上一轮 600 弹速的验收：针对性回归通过；`check.py --auto --jobs 3` 共 73 项、0 失败、244 秒（`build/check/quick_1019_103349`，原生核心与过期金样的跳过范围同初版）。同版两次 seed 1 / logos / 60 秒运行，61 行 TRACE 逐行一致。它是本轮纯视觉修改的 TRACE 基线，没有声称与 260 弹速等价。

上一版验收（98c75b35：速度感修订 + S1 高频短符文）：`logos_projectile_test.tscn` 通过；`check.py --auto --jobs 3` 共 73 项、0 失败、280 秒，日志 `build/check/quick_1019_111911/`。本机未编译的原生核心和 14 份过期金样仍按项目规则跳过，没有脚本或解析错误。seed 1 / logos / 60 秒与上一轮已缓存的 600 弹速基线逐行对照，61 行 TRACE 相同。

普攻仍为 168 帧 / 8.4 秒，六次发射间隔均 1.4 秒；S1 实机为 144 帧 / 7.2 秒，活动期间 20 束短符文、20 次伤害，20 个采样帧为空档。最新合并预览及验收记录在 `build/logos_projectile_capture/speed_revision_03/`，S1 原始录制在 `s1_bursts/`。GIF 通过解码核对时长与等比尺寸。S1 源素材提交 `codex/art@397bcfd3c37fee58b1f92c9d9f293c951d8ae72e`。

后续 S1 微调：当前每束约 60 世界像素、飞行 0.2125 秒，束内符文紧贴，具体见 `logos_s1_chain_handoff.md`。普攻参数不变。最新 S1 实机在 `s1_bursts_revision_02/`；针对性回归通过，项目检查 73 项、0 失败、294 秒（`build/check/quick_1019_113902/`），61 行 TRACE 与缓存基线一致。源素材为 `codex/art@adb9d41f4201429309e42b6a51117b0b49bd54d1`。
