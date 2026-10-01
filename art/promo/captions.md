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

### 第三批（2026-10-01，main cc7a25d，含 V14 / V15 新美术、灯标光域、新地裂）

| 文件 · File | 中文（≤ 12 字） | English | 场面 · Scene |
|---|---|---|---|
| shot_07_saints.png | 双圣徒同时登场 | Two saints take the field. | 圣徒卡门与伊比利亚同场（游戏自带的 --bosstest，HUD 隐藏）· Saints Carmen and Iberia together, HUD hidden |
| shot_08_paranoia_hatch.png | 泡影破壳，深海觉醒 | Paranoia breaks free. | 10:39 偏执泡影二阶段落地破壳，脚下洋红地裂 · Paranoia's phase-2 hatch with the new ground crack |
| shot_09_knight_charge.png | 最后的骑士，冰枪冲锋 | The Last Knight charges. | 10:23 骑士冲锋预警与冰枪 · the Knight's lance charge |
| shot_10_beacon_glow.png | 灯标点亮，暖光护身 | A lit beacon warms the dark. | 9:49 点亮的灯塔照亮周围，水月大招中 · a lit beacon's warm light pool |
| shot_11_final_crowd.png | 终局决战，满屏怪潮 | The final tide. | 10:19 终局 Boss 战与满屏海嗣 · the final boss fight in a full-screen swarm |
| shot_12_relic.png | 三选一，拿走你的藏品 | Pick your relic. | 1:18 获得藏品三选一 · relic pick |
| shot_13_altar.png | 祭坛抉择，改写命运 | Altar choices change your fate. | 2:33 海嗣祭坛事件抉择 · altar event choice |
| shot_14_gallery.png | 图鉴收录每一位强敌 | Every foe, catalogued. | 图鉴 · Boss 页（偏执泡影）· the gallery's boss page |
| shot_15_knight_lance.png | 撞上冰桩，长枪脱手 | Lance lost on the ice stake. | 10:16 骑士冲锋撞上冰枪桩、长枪脱手进入破绽（HUD 隐藏；冲锋前方摆了一根桩，撞桩与破绽由游戏自己结算）· the Knight hits an ice stake, drops its lance and opens a break window |

主视觉变体：keyart_saints_1920x1080 / capsule_saints_616x353（圣徒卡门与伊比利亚，编队维什戴尔 / 逻各斯 / 水月 / 艾雅法拉 / 推进之王）；keyart_paranoia_b_1920x1080 / capsule_paranoia_b_616x353（泡影，编队乌尔比安 / 凯尔希 / 水月 / 艾丽妮 / 归溟幽灵鲨）。干员阵容：roster_1920x1080（13 名可选主控）。
工具：`tools/promo_keyart.py --boss saints --squad a,b,c,d,e`、`tools/promo_roster.py`；截图 `tools/promo_shots.py` 新增类别 saint / hatch / stake / glow / mire / late / relic 与 `--promo_rt=起-止,…`（窗口外快进）。

## GIF

| 文件 · File | 内容 · Content |
|---|---|
| gif_01_first30s.gif | 开局 30 秒成长（延时，约 4 倍速）· first 30 seconds, timelapse ~4× |
| gif_02_boss_dodge.gif | 10:25–10:32 偏执泡影战躲招 · dodging Paranoia's attacks |
| gif_03_horde.gif | 4:12–4:19 大群来袭与清场 · the swarm arrives and gets cleared |

录制：`python tools/promo_shots.py <tag> --promo_only=none --promo_rec=名@起始秒@时长@每几帧`，拼接：`python tools/promo_gif.py <帧目录> <输出.gif> 20`（640 宽、≤ 8 MB）。
