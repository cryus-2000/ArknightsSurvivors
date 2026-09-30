# 宣传截图图注 · Screenshot captions

实机截图（1920×1080，保留 HUD），用 `tools/promo_shots.py` 确定性批跑（真实步长、`--fixed-fps 60`、Ⅳ、高手机器人、高画质）自动抓取。
In-game screenshots (1920×1080, HUD on), captured automatically with `tools/promo_shots.py` from deterministic bot runs.

| 文件 · File | 中文（≤ 12 字） | English | 场面 · Scene |
|---|---|---|---|
| shot_01_tell.png | 读懂预警，躲开杀招 | Read the tell. Dodge the blow. | 10:30 伊祖米克战，扇形与落点圈预警 · Izumik fight, cone and landing-circle tells |
| shot_02_beacon.png | 点亮灯标，驱散深海 | Light a beacon. Push back the deep. | 2:54 灯标刚点亮，光圈扩散 · a beacon just lit |
| shot_03_levelup.png | 三选一，组出你的流派 | Pick one of three. Build your style. | Lv.5 升级三选一 · level-up pick |
| shot_04_horde.png | 大群来袭，撑住！ | The swarm is coming. Hold on. | 4:13「大群来袭」横幅 · swarm warning banner |
| shot_05_manual_aim.png | 手动普攻，指哪打哪 | Manual aim: hit where you point. | 2:29 手动普攻方向指示 · manual-attack direction arrow |
| shot_06_ult.png | 斯卡蒂大招，浪墙压境 | Skadi's tide crashes in. | 4:10 斯卡蒂潮汐浪墙（另一局：斯卡蒂主控、seed=3）· Skadi's tide, separate run (Skadi leading, seed 3) |

## GIF

| 文件 · File | 内容 · Content |
|---|---|
| gif_01_first30s.gif | 开局 30 秒成长（延时，约 4 倍速）· first 30 seconds, timelapse ~4× |
| gif_02_boss_dodge.gif | 10:25–10:32 偏执泡影战躲招 · dodging Paranoia's attacks |
| gif_03_horde.gif | 4:12–4:19 大群来袭与清场 · the swarm arrives and gets cleared |

录制：`python tools/promo_shots.py <tag> --promo_only=none --promo_rec=名@起始秒@时长@每几帧`，拼接：`python tools/promo_gif.py <帧目录> <输出.gif> 20`（640 宽、≤ 8 MB）。
