# 157 首局聚光框引导 + 到点小提示

状态：已实现，待用户看实机（10-26，分支 `claude/spotlight-tour`）。起因：协调人转用户 10-25「开局指南不要写太多」，10-26 用户同意方向：开局改成进局后的聚光框引导，其余知识点改到点小提示；翻页式指南（`data/guide.json` / `screens/intro.gd`）保留在暂停菜单「指南」里重看，不再在开局强制弹。

## 1. 聚光框引导（只在第一局）

- 触发：开场动画结束（`intro.end_opening`）时存档 `Cfg.seen_intro` 为假 → `g.tour.start()`。看完 / 跳过后置 `seen_intro`，以后不再出现。测试局 / 批跑没有开场，不触发。
- 借用 `state INTRO` 暂停局内；整屏压暗（0.68），用方框（淡黄底 + 四角 L 括号，呼吸）框住 HUD 元素，旁边一块斜切说明板（黄条、`GUIDE 01 / 04 · HEALTH` 小标、标题、一两句正文）。
- 步骤（4 步；`command/on = 0` 时没有第 4 步）：① 生命值（归零失败）② 灯火（受击下降、低于 30 受到伤害更多、灯油 / 灯标补）③ 移动与冲刺（桌面框玩家，触屏框摇杆区 + 冲刺键）④ 指挥（桌面框右下「指挥 · 随行」，触屏框指挥键；讲队形与突击）。
- 操作：点击 / 任意键下一步，右键 / ← / Backspace 上一步，Esc 或底部「跳过引导」结束；手柄 Ⓐ 下一步、Ⓑ 跳过；触屏点任意处下一步（按钮点击区上下左右外扩）。
- 触屏按键、指挥状态原本只在 `state PLAY` 画：新增 `Game.hud_live()`（PLAY 或引导中），`touch.gd` / `hud_banners.draw_command` 改用它，引导期间 `touch.handle` 不吃输入。
- 框的位置：桌面 = `hud_bars.draw_top_left` 的固定坐标（生命 `Rect2(70,4,176,66)`、灯火 `Rect2(246,4,134,66)`）与 `hud_squad.squad_top()`；触屏 = `touch.layout()` 的 stick / dash / cmd。改 HUD 布局时同步 `tour.gd _build`。

## 2. 到点小提示

第一次遇到精英（600 像素内）、第一次 Boss 在场、灯火第一次低于 30（对局 15 秒后）、第一次升级选卡（state CHOICE，kind level）：左上角（y 112）弹一个不暂停的小框，8 秒，滑入 / 淡出，不拦输入，同时只弹一个（其余排队）。每样只弹一次，弹的同时记进存档 `[progress] seen_tips`。只在真人对局里弹（`mode == PLAY`、非演练 / 图鉴演示 / 练习）。老存档（已看过旧指南、没有 `seen_tips` 键）读入后按「都看过」处理，不再弹。文案在 `tour.gd TIPS`（docs/76）。

## 3. 测试 / 录片

- `python tools/check.py --only tour`：`tests/tour_test.gd`（小提示只弹一次 / 排队 / force 不记 / 存档往返 / 老存档迁移 / TIPS 与 `Cfg.TIP_IDS` 一致）。
- 演示：`godot … -- --tourdemo`（真人局、跳过开场、第 25 帧起走一遍引导，每步 2.2 秒自动下一步）、`--tipdemo=<elite|boss|lamp|levelup>`（第 25 帧弹该提示 8 秒）；配 `--fixed-fps 30 --shotdir=<目录>` 每帧存 `rec_%05d.png`，再用 ffmpeg 合成 mp4；加 `--touch` + 手机比例分辨率（1170×540）录手机版。
- 引导新玩家时名册已有 10 人（对内包）或寻访会话的新开局，不影响引导：框的只是 HUD。
