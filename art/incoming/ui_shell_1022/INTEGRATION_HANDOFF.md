# 难度 / 设置实装交接

分支：`codex/ui-shell`。基线：`9257e701`，通过 `6ac7321f` 合入工作分支。协调人审后合 main；本次不修改 main。

## 本轮范围

- 难度页：接入用户确认的海域剖面动态稿。标准 / 困难 / 极限绑定 `D.DIFF_PRESETS`、真实累计行动条件、解锁与通关次数；移除最长存活的展示，保留原存档字段。
- 海洋：游戏现用海嗣素材只取透明轮廓；鱼群、章鱼、鲸鱼、珊瑚和海草为界面示意。定位框沿外缘移动，横向等高定位线贯穿海域；不表示实际敌人生成位置。减少动态直接静止。
- 设置：沿用全部原设置键、平台隐藏条件、分辨率应用和云存档二次确认。左栏按画面 / 声音 / 操作 / 存档排列，存档仍仅在支持的平台出现。暂停保留边缘空间；内容避让四向安全区。
- 结算：`settlement_motion/review.html` 仅为待审动态候选。900 ms 一次性展开，终态与已确认的静态图逐像素一致；尚未接入游戏。

## 代码边界

`screens/difficulty_screen.gd` 与 `difficulty_ocean.gd` 负责难度表现；`title.gd` 仅接线，原确认出发、返回和解锁检查保留。`screens/settings_shell.gd` 负责设置布局，原 `settings_panel.gd` 继续拥有输入与保存逻辑。没有改 `hud.gd`、战斗每帧路径、玩法 RNG 或结算数值。

## 验证

实机图：`integration/review.html`，桌面 1280×720、手机横屏 1480×720；三档、锁定态、设置各分类共 13 次截图均无脚本错误。另附暂停云存档四分类与不对称安全区压力截图。截图来自 Godot，不以 HTML 样稿代替实装验收。

- `tools/check.py --auto --jobs 3`：113 项中 112 项通过，唯一失败为 14 份积木金样过期（工单 §0.4 明确允许的例外）。没有重录或提交 golden_current。原生核心对照按工具结果跳过（本机未编 ark_native），其余专项及冒烟通过。完整输出见 `integration/verification.txt`。
- 最终检查使用 `D:/Anaconda/python.exe`，先串行 import `numpy, PIL.Image, fontTools.ttLib`，再以 runpy 执行原 check.py 的 `--auto --jobs 3`。首次 bundled Python 缺 fontTools；第二次 Anaconda 在并行检查中触发 NumPy 循环导入。没有改变检查逻辑或放宽断言。
- `trace_base.py 1 mizuki 240 --ref 9257e701 --here` 与 `2 wisadel 240`：各 241 行 TRACE 逐行相同。BALANCE 中画面/性能字段有差异，TRACE 没有差异。
- `TITLE MENU INPUT: 0 failures`：键鼠、手柄、触屏、锁定档拒绝出发、减少动态、X/手柄 Y 打开认知塑造后返回原档。
- `ESC LAYERS: 0 failures`、`TOUCH LAYOUT failures=0`、`SETTINGS PAUSED CLOUD: 0 failures`。云存档测试只模拟布局，不发送云端请求；页脚返回关闭设置后仍暂停。
- 独立规格与质量审查完成；修复控件命中、分类可视顺序、四向安全区、暂停紧凑布局及标题后期色散。未改 hud.gd 或 game.gd。

复现完整检查（PowerShell）：

```powershell
& 'D:/Anaconda/python.exe' -c "import numpy, PIL.Image, fontTools.ttLib, runpy, sys; sys.path.insert(0, 'tools'); sys.argv=['tools/check.py','--auto','--jobs','3']; runpy.run_path('tools/check.py',run_name='__main__')"
```

结算候选独立浏览器验证已通过：终态一致、暂停恢复、点击跳过、系统减少动态、无页面异常。原结算静态稿的“潮位 VIII”为历史样例，未来结算实装时需绑定三档真实数据。
