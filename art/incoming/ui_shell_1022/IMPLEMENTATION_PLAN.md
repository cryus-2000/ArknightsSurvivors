# 难度与设置接入计划

用户已确认当前难度动态预览和设置视觉，并明确要求接入游戏后交付合入。结算本轮仅新增独立动效预览。

Goal: 在 codex/ui-shell 接入两屏，不改战斗时序、RNG、存档键或 hud.gd。
Architecture: 难度独立 screens/difficulty_screen.gd，复用 title 的选择/确认/退出语义；海洋纯画面时钟。设置保留 settings_panel.gd 逻辑及行定义，独立 renderer 负责新布局，与已有触屏裁剪与滚动协作。
Tech: Godot GDScript、现有 UI/Art；结算预览 HTML Canvas。

- [ ] 固化已确认样稿，合并当前 main 到工作分支，核对基线。
- [ ] 设置接入：左分类右控件，全部原有键、条件显示、分辨率应用及云存档二次确认不变；桌面/手机/暂停。
- [ ] 难度接入：三档真实规则、解锁、通关次数，无最长存活；生态动画、纯海嗣剪影、沿轮廓定位框与横线；减少动态。
- [ ] 结算动态独立预览：短标题展开、奖励计数、伤害条填充、时间轴揭示，末帧静止可分享。
- [ ] 增加必要输入/状态回归，导入与解析检查，桌面1280×720及手机1480×720截图。
- [ ] 同基线水月 seed1 / 维什戴尔 seed2 TRACE；python tools/check.py --auto --jobs 3。
- [ ] 规格及代码审查；只提交所选文件，推送分支+提交+截图供协调人合入，明确结算动效未实装。

设置任务只编辑 settings_panel.gd、screens/settings_shell.gd、设置回归；难度任务由主代理编辑 title.gd、screens/difficulty_screen.gd 及专用海洋绘制。共享文件修改先沟通，工作目录均为 .worktrees/codex-ui-shell。
