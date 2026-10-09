# 53 · 打击感与音效：一轮审计与收口（2026-10-10）

> 范围：主控 / 队友普攻、技能、藏品伤害、敌人死亡、Boss 命中主控。只动画面与音效，不动伤害、出手节奏、模拟随机数（`g.rng`）；旋钮全部在 `data/balance.json` 的 `fx` 段。
> 前置：docs/25（干员特效）、docs/28（干员音效）、docs/36 §9（10/01 真机验收打分）、docs/38 §1.8（**Boss 演出全部不震屏**）、docs/50 §9.9（敌人画法缓存约定）、docs/41 09-30「音效与打击感审查」。

## 1. 方法

- 代码走读：`run/combat.gd`（`damage` / `kill` / `hurt`）、`render/vfx.gd`（`hit_react` / `contact` / `impact_pause`）、`render/world.gd`（敌人绘制两条路径）、`sfx.gd`（路由、合并、优先级）、各干员脚本的 `Sfx.op` / `impact_pause` / `_hit_fx`、`run/weapons.gd`（弹体命中）、`relic_fx.gd`（藏品伤害）。
- 确定性测量：`--headless --balance --seed=1 --bot=expert --trace=1 --sfxstat --perf`，水月 / 斯卡蒂 / 逻各斯各 200 秒，另加水月 `--bosstimes=40,90,130` 150 秒。`--sfxstat` 给每个音名的 [请求, 实播, 同名合并, 满槽丢弃, 降音量]。没有逐次命中的日志；命中次数用音效请求数代替（同一局请求数是确定的）。
- 画面对照：同一份代码，改动前 = 用 `--bal=fx/…` 把新旋钮全部关掉（和改动前逐行等价），改动后 = 缺省；`--fixed-fps 30 --realtime` 1280×720，`tools/promo_shots.gd --promo_rec` 录三段各 10 秒（普攻命中 / 击杀爆点 / Boss 命中主控），`imageio_ffmpeg` 编成 `build/hitfeel/before.mp4` / `after.mp4` + `contact.png`，副本在 `E:\ArknightsSurvivors\build\hitfeel_out\`。

## 2. 审计：现状（改动前）

### 2.1 所有命中共用的一段（`combat.damage` → `vfx.hit_react` → `dmg_number`）

| 项 | 现状 |
|---|---|
| 白闪 `e.flash` | 普攻 0.08 / 持续伤害 0.05 / 技能 0.11 / 暴击·弱点 0.12 / 破绽 0.14（`fx/flash_*`） |
| 受击形变 `e.squash` | 0.14 / 0.08 / 0.18（`fx/squash_*`），画成横 +30% 纵 −25% 再回弹 |
| 位移 | **没有**。只有带击退 `kb` 的攻击才有一个按 `kb` 长度算的抬跳（≤14），不带击退的命中（逻各斯、流明、藏品、持续伤害…）敌人纹丝不动 |
| 火花 | 暴击 4 金 / 弱点 3（按弱点色）/ 破绽 6 金 + 金环；普通命中**没有**（干员各自的 `contact()` 在 `deal_damage` 后补 2–3 粒，只有干员走得到，藏品 / 弹体不走） |
| 顿帧 | 只有 Boss 破绽命中 `fx/break_pause` 0.035；其余由各干员自己 `impact_pause`（共享预算：0.28 秒最多一次、单次 ≤0.075，受「命中顿帧」设置） |
| 伤害数字 | 普通白 14 / 弱点金 18 / 暴击金 22；Boss 0.3 秒合并；Boss 战期间小怪只飘暴击；飘字 >30 条时普通白字不飘 |
| 音 | 暴击 `crit_tick` −6.8 dB；命中音由干员自己播（见 2.2）；**通用层没有命中音** |

### 2.2 干员普攻（主控 / 队友相同）

| 干员 | 出手音 | 命中音 | 顿帧 | 命中特效 | 缺口 |
|---|---|---|---|---|---|
| 水月 | `op_mizuki_atk` +3；强化挥砍 `swing_heavy` −3 | `op_mizuki_hit` +4 / 强化 +8、0.85 音高 | 0.03 / 强化 0.09 | 伞击帧条、火花 3–4、触手追击 `tentacle` | — |
| 斯卡蒂 | `op_skadi_atk`（连斩三段各自音高） | `op_skadi_hit`（潮汐 +2） | `contact` 近战 0.018 | 泡沫短线 `_hit_fx` | — |
| 逻各斯 | `op_logos_atk`（整轮一次） | **无**：「言」命中不播任何音，只有湮灭处决播 `op_logos_big` | 无 | 骨笔符文 / 墨点 | **命中无声**（200 秒 122 次出手，命中 0 次发声） |
| 推进之王 | `op_siege_atk` | `op_siege_hit`（碎颅 +2、0.85） | 0.04 | 十字重击闪 | — |
| 塞雷娅 | 落空 `op_saria_atk` | `op_saria_hit`（有命中时） | 0.05 | — | — |
| 铃兰 | `op_suzuran_atk` | `op_suzuran_hit`（狐火弹 `weapons.gd` arcane） | 无 | 环 + 火花 3 | — |
| 艾雅法拉 | `op_eyjafjalla_atk` | `op_eyjafjalla_hit`（熔岩弹爆炸） | 0.05 | 爆炸帧条 | — |
| 凯尔希 | `op_kaltsit_atk`（Mon3tr 撕裂，设计为命中才响） | 无文件；不调用 | `contact` 重型 0.032 | 光点 | 出手即命中音，可接受 |
| 维什戴尔 | `op_wisadel_atk` | `op_wisadel_hit` / `quake` / `big` | 0.05 | 爆炸 | — |
| 艾丽妮 | `op_irene_atk` | `op_irene_hit` | 0.08（碎潮） | — | — |
| 流明 | `op_lumen_atk` | `op_lumen_hit`（光弹 0 / 其他 −4） | 无 | — | — |
| 归溟幽灵鲨 | `op_specter_unchained_atk`（求生之压 +4、0.8） | 无文件；不调用 | `contact` 近战 0.018 | 光点 | 锯刃环斩的出手音已含命中感，可接受 |
| 乌尔比安 | `op_ulpianus_atk` | 无文件；不调用 | 技能 0.045–0.1 | 光点 | 抡锚出手音即砸地，可接受 |

技能发动音统一挂在 `character.spend_sp()`（`op_<id>_s1/s2/s3`，docs/28），大招落点 `big`，各干员另有自己的 `impact_pause`。没有发现无声的技能。

### 2.3 藏品伤害、弹体、敌人自伤

| 路径 | 画面 | 音 | 备注 |
|---|---|---|---|
| 藏品持续伤害（对眩晕 / 减速敌人每 0.5 秒，`relic_fx` 425）| `flash_dot` 0.05 | 无 | 持续伤害本就该安静 |
| 支援地雷 | explode + 火花 14 + 击退 | `boom` −6 | 完整 |
| 岁怒 / 殉爆等范围（`_area`） | 各自的 explode | `boom` −8 | 完整 |
| 扣挠之手（追击命中 3% 真伤，每 0.5 秒） | 白闪 | 无 | 可接受 |
| 弹体 arrow / fire / arcane（`weapons.gd`） | 帧条 + 血点 / 爆炸 / 环 | 干员 `hit` 或 `boom` | 完整 |
| 骑士（援护）劈砍 | — | `swing` | 没有命中音，援护非本轮范围 |
| 潮汐弹 `tide` | 环 + 火花 | 无 | **没有任何代码生成 tide 弹**，死代码 |

### 2.4 击杀

| 项 | 现状 |
|---|---|
| 爆点 | 火花固定 7 粒 + 冲击环 r×1.2（0.18 秒）+ 死亡帧条（有 `_death` 帧条的怪）或 `fx_death_dissolve`；**不按体型分档**，r=8 的小海嗣和 r=18 的大体型同一个爆点 |
| 音 | `kill` −8 dB 固定音高，最短间隔 0.045 秒；200 秒里请求 931 次、实播 69–82 次（合并 525–637、满槽丢 254–337）——同屏成片倒下时听起来是一串相同的「噗」，**分不出大小** |
| 顿帧 | 普通击杀 **0**；精英 / Boss `g.hitstop` 0.12 + `boom` + 24 金火花 |

### 2.5 主控受击（`combat.hurt`，所有来源同一条路）

| 项 | 现状 |
|---|---|
| 人物 | 白闪 0.2 秒（>0.12 时整体 3 倍亮，之后偏红）、受击帧条、向远离最近敌人的方向坐 9 像素 + 后仰 |
| 全屏 | 红边 `red_flash`（HUD 边光 + 0.16 底色）、后期红暗角 `hurt_vignette` 0.6–1.0（按伤害 ÷ 最大生命 12% 分级 `sev`）、血条抖动 + 残影、头顶血条 2.5 秒 |
| 粒子 | 红火花 6–14 + 红环 40–70 |
| 顿帧 | 0.045 + 0.06×sev（Boss 大招约 0.1）；首次跌破 30% 0.35 秒 + 横幅 |
| 音 | `hurt` +3…+6 dB、音高随 sev 降到 0.8，优先级 4 从不被合并丢弃；手柄震动 |
| 配乐 | 低通只跟灯火（<30 时 700–4000 Hz）和暂停；**挨重击时配乐不闷** |
| Boss 命中 | 和小怪同一条路，只靠 sev 把上面各项拉满；**没有专属的「重击」声层**。溟痕 / 伊莎玛拉之泪每跳只有 0.06 秒小红闪 |

### 2.6 全局

- **震屏**：`vfx.shake_screen` 是空函数（「镜头震动已整体移除（看着头疼）」），docs/38 §1.8 / §6.3 规定 Boss 演出全部不震屏。本轮**不恢复**。设置页的「震屏强度」（`Cfg.shake`）因此没有任何读取方，是一行死设置，见 §6。
- **顿帧**：`game.gd` 在 `Cfg.hitstop` 关闭时直接跳过 `hitstop` 计时，本轮新增的顿帧都走 `impact_pause`，自动受这个开关和 0.28 秒共享预算约束。
- **随机数**：`vfx.hit_fx` 在没传方向时用 `g.rng` 取角度（现在只有水月调用且传了方向）；推进之王 `_hit_fx` 的十字闪角度也用 `g.rng`。两处都是无条件调用，不破坏复现，但按 docs/36 §3 的约定应改 `vrng`——改了会让所有 seed 的结果整体换一套，本轮不动，记在 §6。
- 10/01 真机验收（docs/36 §9）里「暴击 / 击杀区分」只有 3 分，和上面 2.4 的发现一致。

## 3. 改动（全部纯画面 / 音效，`fx` 段旋钮）

| # | 改动 | 文件 | 旋钮（缺省） |
|---|---|---|---|
| 1 | **受击后坐**：每次非持续伤害的命中，敌人本体沿「远离主控」的方向顶开 `recoil_px`，`recoil_t` 秒内线性回位；技能 / 暴击 / 弱点 ×`recoil_skill_k`。Boss 不顶。`hit_react` 只写 `rc_at / rc_dir / rc_k`，位移在 `world._eoff` 里按 `g.t` 算，缓存路径和原路径同一个表达式（`draw_off` 本来就每帧照算、不进签名，`--dccheck` 两条路径记录一致） | `render/vfx.gd` `hit_react`、`render/world.gd` `_eoff` | `recoil_px` 3.0（世界单位，PX=2 即 1.5 像素）、`recoil_t` 0.1、`recoil_skill_k` 1.6；`recoil_px=0` 关 |
| 2 | **击杀爆点按体型分档** `vfx.kill_burst`：火花 = `kill_sparks` + r×`kill_sparks_per_r`（r 8→9 粒、r 18→12 粒），速度随 r 略增；r ≥ `kill_big_r` 再加一圈慢扩散外环 + 脚下尘土 | `render/vfx.gd`、`run/combat.gd kill` | `kill_sparks` 7、`kill_sparks_per_r` 0.3、`kill_big_r` 16（覆盖 r 16–18 的大体型小怪和全部精英；普通怪 r 8–15 不算） |
| 3 | **击杀音分层**：`kill` 音高 = 1.15 − r ÷ `kill_pitch_r`（0.75–1.15，小怪尖、大怪沉），大体型 +2 dB；大体型再叠一层材质音：甲壳类（`HIT_SHELL`）`kill_shell_sfx`，其余 `kill_big_sfx` | 同上 | `kill_pitch_r` 60、`kill_big_sfx` "mire_splat"（−9 dB、0.85）、`kill_shell_sfx` "hit"（−6 dB、0.6 音高）；空串 = 不叠 |
| 4 | **击杀顿帧**：大体型或暴击击杀 `impact_pause(kill_pause)`（≈2 帧），走共享预算，受「命中顿帧」设置 | 同上 | `kill_pause` 0.033 |
| 5 | **主控重击层**：单发 ≥ 最大生命 12%×`hurt_heavy_sev`（Boss 招式基本都到，小怪接触一般到不了）时叠一层低沉 `boom`，并把配乐低通**立刻**压到 `hurt_duck_hz`、保持 `hurt_duck_t` 秒后按原速率回升 | `run/combat.gd hurt`、`run/music_director.gd`、`sfx.gd duck_music`、`game.gd hurt_duck`、`render/world.gd` 衰减 | `hurt_heavy_sev` 0.5、`hurt_heavy_db` −10、`hurt_duck_t` 0.4、`hurt_duck_hz` 900 |
| 6 | **逻各斯「言」命中音**：`_word_hit` 播 `Sfx.op(id, "hit")`；没有 `op_logos_hit` 文件时经新的 `sfx.OP_ALT` 借 `op_mizuki_hit`（0.8 音高、−4 dB，湿润闷响当墨弹落点），不再退回通用 `hit` | `characters/logos.gd`、`sfx.gd` | `OP_ALT`（代码常量） |

性能：每次命中多 3 个字典写；每只敌人每帧多一次 `e.get("rc_at")` 和一次减法（命中 0.1 秒内才算位移）；击杀火花上限仍受 `sparks` 的 400 条总量约束。200 秒局的画面峰值 `bot.peak[3]`（特效条数）从 307 → 358，在上限内。

## 4. 验证

- **确定性**：改动前后各跑 4 局（`--seed=1 --bot=expert`，水月 / 斯卡蒂 / 逻各斯 200 秒，水月 `--bosstimes=40,90,130` 150 秒），每秒一行 `TRACE`（时间、等级、击杀、生命、敌人数、`rng.state`、主控坐标、全体敌人位置 / 生命哈希）**201 / 201、201 / 201、201 / 201、151 / 151 行逐字节相同**；`BALANCE` 除 `bot.peak` / `bot.peak_min` 的特效条数峰值外全部字段相同；`--sfxstat` 的每个音名**请求数**前后相同（实播 / 合并数随机器负载变，不是对局状态）。
- **快检**：`python tools/check.py --auto --jobs 4`（本次改到 `sfx.gd` / `music_director.gd`，分到 full 档）→ `build/check/hitfeel_auto.txt`：**41 项通过、0 失败，rc=0**（126 秒，含同 seed 复现、`--dccheck` 冒烟、攻击反馈回归）。
- **画面对照**：`build/hitfeel/before.mp4` / `after.mp4`（各 30 秒 = 三段 10 秒，1280×720 30 fps）+ `contact.png`；副本 `E:\ArknightsSurvivors\build\hitfeel_out\`。

## 5. 待制作音效（本轮用近似音顶替，交音频 / Codex）

| 音名 | 用途 | 现在顶替的 | 要求 |
|---|---|---|---|
| `op_logos_hit` | 逻各斯「言」命中 | `op_mizuki_hit` 0.8 音高 −4 dB | 墨滴落纸 + 低语余音，短（≤0.15 秒），和出手音同一音色族 |
| `kill_big` | 大体型 / 精英倒下的血肉层 | `mire_splat` −9 dB 0.85 | 比 `kill` 更湿更沉，带一点体积感；最短间隔可和 `kill` 一样 0.045 |
| `kill_shell` | 甲壳类（石怪、喷吐者、口袋、拟态…）倒下 | `hit` 0.6 音高 −6 dB | 壳裂 + 碎块落地 |
| `hurt_heavy` | 主控挨重击（Boss 招式）的低频层 | `boom` −10 dB 0.7 | 次低频「咚」+ 短暂耳鸣感，配 900 Hz 低通 |
| `op_kaltsit_hit` / `op_ulpianus_hit` / `op_specter_unchained_hit` | 三人目前靠出手音兼任命中 | 不播 | 可选；做了之后在各自脚本的命中处加 `Sfx.op(id, "hit")` 即可 |

## 6. 遗留与建议（不在本轮）

- ~~**「震屏强度」设置项是死的**~~：[用户 10-10 定] 已从设置页与存档键删除（settings_panel.gd / settings.gd），震屏不恢复。
- `vfx.hit_fx`、推进之王 `_hit_fx` 的角度用 `g.rng`，应改 `g.vrng`；改动会让所有 seed 的结果整体换一套，宜和下一次数值基线一起换。
- 弹体 `tide` 分支没有任何生成者，可删。
- 援护骑士的劈砍没有命中音（只有 `swing`）。
- 低画质在 12 路同时发声时直接丢弃优先级 ≤2 的音（docs/36 §9）：本轮新增的大体型材质层和重击 `boom` 都是优先级 2，拥挤时可能被丢；重击层若要保证必响，把 `boom` 提到 `PRIO_NAME` 4 或单独做 `hurt_heavy` 音。
