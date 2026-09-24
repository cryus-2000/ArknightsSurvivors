# 配乐设计与接入（v1.0，2026-09-24）

全部曲目由 `game/tools/gen_music.py` 程序化合成（numpy + scipy + ffmpeg），旋律、和声原创；
标题曲与结算曲参考的是《海愿》的气质（慢板、留白、钢琴 + 竖琴 + 无词人声 + 弦乐涌浪），不引用其旋律。
重新生成：`cd game/tools && python3 gen_music.py [title|explore|boss|final|shop|stingers|opening|boss_cues|result_loops]`。

## 曲目表（game/audio/music/）

| 文件 | 用途 | 循环 | 触发（game.gd / sfx.gd） |
|---|---|---|---|
| title | 标题《海底祈愿》升 F 小调 60 BPM，引子 4 / A 8 / B 8 / 尾声 8 小节 | 是 | title.gd `play_music("title")`；图鉴沿用 |
| opening | 开场引子《沉降》，对齐开场动画 1.7 s 落地 / 2.1 s 灯火 | 否 | `S.OPENING`，以及首次进入的指南页直到引子播完 |
| explore{,2,3}_{base,pulse,drive,danger} | 战斗《深潮》三段 × 四层，104 BPM 16 小节同长同步 | 是 | 威胁等级 0–1 / 2–3 / 4+ 切段；四层按局势叠加（`set_layers`） |
| boss / final | 中期 Boss / 最终 Boss | 是 | `_boss_alive()` / `final_boss` |
| boss_in / boss_down | Boss 登场 / 击破叠加短乐句 | 否 | `play_overlay`：Boss 刷出时；非最终 Boss 全部倒下时 |
| shop | 商人 | 是 | `S.SHOP` |
| win / lose | 结算短乐句 | 否 | `play_stinger`，播完自动接 `*_loop` |
| win_loop / lose_loop | 结算后循环：标题主题钢琴变奏 / 深海沉底氛围 | 是 | `after_stinger` |

## sfx.gd 约定

- `MUSIC` 表定义曲目组；`ONESHOT` 里的组不循环；`OVERLAYS` 走独立的 `overlay` 播放器，不改变 `cur_track`。
- `play_music(name)` 同名重复调用无副作用；切换时新曲从头淡入、旧曲淡出（0.8 / 0.6 每秒）。
- `track_playing(name)` 用于等待不循环曲目播完（开场引子）。
- 所有战斗段共享 `layers` 音量，`is_explore()` 判断前缀。

## 响度基准（ffmpeg volumedetect，mean）

标题 -19.6 dB、商店 -15.2、Boss -14.7、最终 -13.7、战斗 base -26 / drive -21（叠加后约 -16）、胜利循环 -18.7、失败循环 -21.8。

## 待办

- 升级 / 圣遗物选择界面叠一层轻竖琴或人声（目前只做低通）。
- 最终 Boss 二阶段加强层。
- `boss.ogg` / `final.ogg` 仍用旧的锯齿 pad 与 FM 铃声，可按标题曲的新乐器翻新。
