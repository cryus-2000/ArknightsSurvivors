# Mon3tr 重绘配套攻击特效

- fx_mon3tr_claw：普通攻击三道绿色爪痕；协同状态叠加旋转爪痕。
- fx_mon3tr_melt_slash：熔毁绿色月牙；加载失败时沿用程序月牙回退。
- 两项均为 48×48 ×4 帧，16 FPS，中心锚点 (24,24)，单次播放；@2x 单帧 96×96。透明像素为二值 alpha。
- 原始母图由 imagegen 绘制，按 4列×2行机械切分、最近邻采样与颜色量化；96px 从母图独立采样。来源路径和哈希在 manifest。
- 接入 game/scripts/characters/kaltsit.gd 和 game/scripts/game.gd。只替换表现，伤害、攻击间隔与命中判定未改。
- 保留左右镜像、成长节点第二爪交叉和协同双爪。常驻 fx_mon3tr_blade 不变。

## 验证

- 图片：4 条、16 帧的尺寸、二值透明、非空与哈希检查通过，见 QA。
- game/tests/mon3tr_fx_test.tscn：普通/协同/熔毁 ×左右方向 6 种触发检查通过；修复前 6 种均未触发新素材。
- 使用 godot_runner 启动静音最小化 OpenGL 实机截图，见两个 preview；额外四张左右/协同截图在 build/mon3tr_fx_*。
- python tools/check.py：20 项、0 失败，日志 build/check/quick_0927_121254。
- 已接入本地 main 源码；旧安装包及网页未重新构建/发布，运行中游戏须重启刷新缓存。
