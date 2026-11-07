---
name: new-enemy
description: 加一种新怪物（普通怪 / 精英 / 中期 Boss / 最终 Boss）的完整清单与模板：原作查证 → 设计稿 → enemies.json 条目 → waves.json 刷怪位 → Boss 脚本与招式 / 弹幕（东方式弹型、专属弹色、不弹提示）→ Codex 美术单 → 预警与特效 → 音效 → 档案文案 → 快检 / Boss 测试台 → 难度对照 → 交付。在协调人派「加怪物 X」「新中期 Boss」「新结局 Boss」时使用；只改现有 Boss 招式用 docs/95 / 165 各 Boss 文档。
---

# new-enemy：加一种新怪物 / Boss

普通怪以 `bone`、精英以 `mother`、中期 Boss 以 `path`（塑路者，`bosses/path.gd`）、最终 Boss 以 `paranoia` / `ishar` 为样板。官方步骤是 docs/38 §1.17，本清单按代码逐项核过（11-07）。
模板：`templates/enemy_entry.json`（普通 / 精英 / Boss 三种条目骨架）、`templates/boss_design_template.md`。

## 0. 开工前

- 先读：AGENTS.md、docs/00_index.md「新会话先读 · Boss与怪物」行（95 → 38 §1、§8.11–§8.14 → 49 / 49c → 98）、docs/76、docs/306（Boss 弹幕）、docs/283（中期 Boss 可见性）。
- Boss 设计口径（用户定，memory boss-design）：**图案弹幕不做符卡；每只 Boss 专属弹幕色；不弹文字提示（不加「快躲」类横幅 / 头顶字）；弹幕紧张主要交给最终 Boss**；中期 Boss 重在「一眼认出这是 Boss」（docs/283）。
- 自己的工作树和分支（`claude/enemy-<id>` / `claude/boss-<id>`）；入口文件不改；**文档号先查各分支最大号**（同 new-operator §0）；本机 Godot 按协调人当前口径（平时最多 1 个），批跑 / TRACE / 测试台上 GCP。

## ① 查证（docs/76 §4、docs/49c）

1. 原作来源：Kengxxiao/ArknightsGameData `enemy_handbook_table.json`（名字、描述、能力）、`enemy_database.json`（数值、技能）、`roguelike_topic_table.json`（集成战略出场）；PRTS 敌人页（桌面站常 403，走 `m.prts.wiki`）；Boss 原作对照先看 docs/49c，借机制 / 名字前查 docs/49 / 49b。
2. 记：原作名、原作能力（逐条）、出场关卡 / 层、外观（体色 / 眼点 / 器官）、PRTS 小人帧参照。每条写出处；查不到不写；本作原创的招式标「本作原创（取材 …）」/「招式本作拟」（docs/95 头注、docs/165：不声称为原作技能原名）。
3. 来源登进 docs/76 附录 A（Boss 照 A.4 口径）。

**完成标准**：设计稿 §1 每行有出处。

## ② 设计稿（docs 新号；Boss 用 `templates/boss_design_template.md`）

- 普通怪 / 精英：定位一句话（逼走位 / 远程压制 / 自爆 / 伏兵 …，与现有 14 种普通怪、5 种精英不重复）、`ai`、行为（现成 pattern / extra 能否组合出来）、出场档位（waves `threat` 第几级、权重）、体型档（docs/98 §3–§4：普通 12–30 站高 < 精英 24–30）。
- Boss（docs/95 §0.2 + docs/38 §1）：
  - **4 招 = 4 种不同预警样式**，只从 ① 落点圈、② 直线、③ 扇形、④ 缺口环、0 区域场里选（⑤ 全场·必须冲刺只给伊祖米克），不发明新样式；标志性招式动词与现有 Boss 不重复。最终 Boss 主动攻击另按 docs/165 口径（7–8 招、连段后 ≥ 7 秒）。
  - 时序下限：预警 ≥ 0.6 秒；锁定窗口 ≥（半宽 + 12）÷ 105 + 0.1 秒；连发间隔 ≥ 0.6 秒；追踪落点半径 ≤ 45；缺口弧长 ≥ 80px、扩散 ≤ 220px/s、缺口提前 ≥ 0.8 秒画出。
  - 伤害上限：单发 ≤ 40% 最大生命、2 秒合计 ≤ 50%、持续 ≤ 4%/秒（统一入口 `combat.lose_hp`）；永不硬控、移速下限 0.7（docs/38 §1.11）。
  - 阶段：中期 50% 两幕、最终 66% + 第二道（`gates`）；每幕最短时长中期 6 / 最终 13 秒（`act_min`）；每幕新元素中期 1 个、最终 ≤ 2 个（§1.10）；二阶段用 `e.tint2` 程序着色，不另交帧条。
  - 时长目标：中期 25–40 秒、最终 60–90 秒（§1.1，以 §8.5 / §8.9 为准）。
  - **专属弹幕色**（docs/306 §2.1 / docs/142b §8.4）：避开保留色相（小怪青蓝约 194°、预警洋红约 340°、主轴金约 45°、假死青约 175°、灯火橙约 27°）；每幕同一色系里变、色相不跳；同一场的 Boss 要分得开。
  - **弹型**（docs/306 §2）：小 / 中 / 大圆弹（直径 9 / 13 / 19，判定 r ≤ 6 / 7–9 / ≥ 10）、米弹、针弹，加本 Boss 专属一种（菱晶 / 水泡环 / 月牙 / 泪滴 …）；白芯 + 专属色环 + 暗边，和普通怪弹（洋红描边、无白芯）一眼分开。
  - 测试机器人要会这只 Boss 的主轴（docs/142b §1）。`core/bot.gd` 现在没有按 Boss 种类分段（11-07 核过），新主轴（要打的部件、要站的圈）得确认机器人会做，不会就加一段，否则批跑胜率不可信。
- 新机制先给方案、用户审过再做。

## ③ 数据（`game/data/enemies.json`，键 = 全局唯一 id）

从 `templates/enemy_entry.json` 起步。

- **必填 8 个**（`spawner.gd new_enemy` 直接取，缺了报错）：`name hp spd dmg r xp tex ai`。`ai` 只有 `melee / ranged / static`；`tex` = `e_<id>`。
- 常用可选：`role`（"" / elite / boss / rare）、`anchor: "foot"`、`ecol`（碎屑色）、`weak`（物理 / 法术）、`armor`、`corrode / nerve / frost`、`cap`（同种上限）、`elite_after`、`no_spawn`、免疫类（`stun_immune / seal_immune / …`）、`hover`、`dormant`、`atk_anim`、`move_fps`、`chips`（图鉴标签）、`desc`（图鉴机制说明）。
- 行为纯数据能组合的：现成 `pattern`（bite / stomp / dash / acid / nova / blast / reap / thrust / nest，各自参数见 `enemies/enemy_ai.gd`）、`extra`（swipe / pulse / pierce / volley；必填 `name mode range cd damage_mult`，volley 另要 `count speed spread`）、远程 `shot_*`、抛射 `lob / spit / lob_kind (rock|brood)`、专属帧条名（`shot_tex hit_fx atk_fx muzzle_fx blast_fx dash_fx land_fx lob_tex`，缺图回退程序画）。
- **新 pattern 要写代码**（改 5–6 处）：`enemy_ai.gd` `pattern()` 的 match + `_xxx()`；新状态字段加进 `spawner.new_enemy` 字面量和 `spawn_chest` 的手拼字典（否则 `check_enemy` 报缺键）；蓄力 / 形变画面进 `world._dc_ok` 排除或签名；新预警 act 在 `telegraph.gd _resolve` 加分支并在 `cue_cat` 登记音效类别；封印期间要推进的状态进 `busy()`；蓄力时长过 `_wu()`。设计稿写明为什么现成 pattern 不够。
- Boss 另写：`role: "boss"`、`intro {en, sub, line}`（登场名片）、`portrait_crop`、`bcol`（+ `bcol_core / bcol_trail / bcol_outline`）、按需 `patterns`（数据招式，`boss_patterns.gd` 文件头有逐字段说明；mode fan / ring / rain / line / cleave / stack）、`gates`、`act_min`、`arena_r`（最终）、`draw_full`、`script`（缺省 = id）。
- 数值旋钮按 id 拼键，写进 `balance.json` 而不是改曲线：普通 / 精英 `enemy/dmg_x_<id>`；Boss `boss/hp_x_<id>`、`boss/dmg_x_<id>`；中期 Boss 画面放大 `render/mid_boss_scale_<id>`（缺省 1.35）。数值一律 `Bal.v("boss/...")`，不在 .gd 写裸数。

### 刷怪位（`game/data/waves.json`）

- 普通怪：写进 `threat[i].pool`（**重复次数 = 权重**）、按需 `horde` / `horde_mix`（`{name, body:[id…], extra:[{id, pct, min, max, at}]}`）/ `horde_lead`。
- 精英：`role: "elite"` 自动进精英池（`spawner.pick_elite`，看 `elite_after`、`no_spawn`）。
- 中期 Boss：`mid_pool` 加一组（是否进 `mid_first` 3:30 首只）；同一人物互斥看 `spawner.SAME_PERSON`。进了 mid_pool 自动放大 1.35（docs/283）。
- 最终 Boss：`endings.<结局>`（name / en / boss / col / omen / gallery / requires …，docs/154 节点卡与结局规则）；`spawner.is_final_boss_type` 按它判定；最终 Boss 在场停刷（docs/38 §8.14）。

**完成标准**：`python tools/data_lint.py` 通过（waves 引用的 id 都存在、Boss 位是 role boss 且有 `bosses/<script>.gd`）。

## ④ Boss 脚本与招式（只 Boss）

1. 新建 `game/scripts/enemies/bosses/<id>.gd`：`extends "res://scripts/enemies/bosses/boss_base.gd"`，覆写 `step(e, dt, dir, dist, ready, mate)`、`demo_moves(e)`、`force_move(e, name, dir, dist)`；有二阶段加 `setup_preview_phase2`；按需 `block_damage / taken_mult / on_damaged / on_lethal / on_gate / super_armor`。脚本无状态，状态放敌人字典。基类工具：`_first_tell`（D 招先亮名 0.6 秒）、`_tint2`、`_warn`、`_aim_fan`、`_cd`、`_close_in`、`_dash_through`。`.gd.uid` 让 Godot 生成、随脚本同一提交。
2. 中期 Boss 分级弹 / 连段用 `enemies/mid_cards.gd` 积木（docs/170：tier 0/1/2、hold、acc、turn、split）；最终 Boss 补充攻击在 `enemies/final_attacks.gd`。
3. 预警走 `g.tele.warn(e, shape, dur, d)`（circle / line / cone），每条预警 / 子弹带 owner；每只 Boss 同屏 warn ≤ 5；预警 / 残留绘制走 `world.tb_*` 合批或 `fx_sprite`。
4. **按 type 写死、新 Boss 要手动补的表（不补就静默不生效）**：
   - `render/boss_bullet_draw.gd` `TYPES / RAMP / SHAPE / AMB`：不在表里就不走 docs/306 东方化弹体；
   - `enemies/boss_patterns.gd FINAL_TYPES`（最终 Boss 二阶段强化）、`enemies/final_attacks.gd NAMES`（最终补充攻击）；
   - `render/vfx.gd BOSS_STYLE`（出招签名特效）、`vfx.gd HIT_SHELL / HIT_SPIRIT`（受击材质：甲壳 / 灵体，缺省血肉）；
   - `render/world.gd boss_strip_animation`（`draw_full` 专用帧条挂点）、`render/boss_attack_draw.gd`（最终 Boss 专属预警画法）；
   - `run/music_director.gd FINAL_TRACK`（最终 Boss 曲目，缺省 final）、`sfx.gd CUE_VOL`（专属音电平，缺省 -22）；
   - 机器人主轴（见 ②）。
5. 确定性：玩法随机只用 `g.rng`，画面用 `g.vrng`；必须经 `spawn_enemy` 出生；Boss 专属字段只加在 Boss 上，所有敌人都读的字段进 `new_enemy` 模板。

## ⑤ 美术单给 Codex（本体动作归 Codex，docs/98 §6）

- 范本：普通 / 精英重画单 docs/94（§0 通用规格、§1 清单、§2 交付与自检）；攻击特效单 docs/96；流程纪律沿用 docs/104 §1–§4（单子只写范围、生成稿只当参照、按部件重排、动画分层合成、人眼先行）。
- 规格（docs/98）：@2x 为主，**Boss 不许只有 1x**；横向等宽帧条、alpha 只有 0 / 255、不画阴影辉光；`#080E18` 外描边闭合；只画朝右；脚底贴画布底边居中；色数普通 ≤ 16、Boss ≤ 32；画布 普通 18–40 × 18–38 / 精英 30–34 × 28–32 / Boss 40×48 … 96×80（1x）；同屏比例 小怪 < 精英 < 干员 32–36 < 中期 Boss 40–56 < 最终 Boss 72–96。
- 配色（docs/98 §5）：深海青灰、骨白、腐蚀紫、暗红眼点；精英标识低饱和桃橙 `#FAB297` 器官 + 亮边；禁灯火金 `#F4C04E`、UI 青 `#36E2DC` 高饱和版；最暗一阶 luma ≤ 35。**与原作立绘一致是硬要求**：交四列对照「立绘参考 / PRTS 小人 / 上一版 / 本版」。
- 动作约定（docs/94）：基础 2 帧，`_move` 4 帧，`_attack` 4 帧且 f2 = 命中帧；Boss 按招式要 `_charge / _skill / _slam / _wound / _death …`，每条配 `_emit` 发光层。
- 命名（docs/189 §3，docs/05 那节已作废）：`e_<id>[_<动作>][_<层>]@2x.png` 放 `game/art/enemies/<id>/`；Boss 名片 `boss_<id>` 放 `enemies/_portraits/`；新前缀先登 `tools/asset_lint.py PREFIXES`；变体名不许 v2 / new / old。交付路径 `art/incoming/<内容简称+月日>/`。
- 收货：`tools/install_enemy_redraw.py` 生成 `game/data/enemy_pixels.json`（锚点 / 帧数 / 帧尺寸）与 `enemy_redraw.json`（帧数、出手帧、时长），并改写 `art.gd V6_FRAMES` 的死亡帧条段；**跑 `python tools/asset_index.py` 重建 `game/art/index.json`**（按名取图先查索引，不进索引静默回退；该文件在 git 里跟踪，随提交）。

## ⑥ 特效、预警、画面

- Boss 弹体：docs/306 运行时生成（`render/danmaku_v2` 1，包体 0），把新 Boss 加进 `boss_bullet_draw.gd` 四张表；Noita 式粒子同屏 ≤ 700（手机网页 ≤ 350），同一处 0.1 秒内一个发射闪光。
- 预警样式与填充：`render/telegraph_draw.gd`（① 实填 ② 斜条纹 ③ 暗填亮边 ④ 空心 0 低亮度），填充用本 Boss 的 `bcol`，白芯 + 深描边；画即判（`GROUND_Y` 0.72 椭圆）。**最终 Boss 新招要接专属画法**，否则 `final_boss_tells` 快检失败；确需通用画法就加进测试的 `GENERIC_OK` 名单并写明原因（docs/215 §5）。
- 中期 Boss 可见性：进 mid_pool 自动 ×1.35（只放大绘制，判定不变）；**不加头顶箭头 / 文字**（docs/283 推荐常驻锁定框 / 脚下环）。
- 新 `fx_* / proj_* / e_*_death` 帧条登记 `art.gd V6_FRAMES [帧数, fps]`；普通怪新画面状态进 `world._dc_ok` 排除或画法缓存签名（`e.dc`），快检冒烟带 `--dccheck` 会抓漏（Boss 不进缓存，不受影响）。
- 精英：`role: elite` 自动挂 `render/elite_mark_v2` 白 ▼（docs/244）。
- 只改画面时同种子 TRACE 必须逐行一致（`tools/trace_base.py`，GCP）。

## ⑦ 音效

- 普通怪没有按 id 的专属音：`Sfx.enemy(kind)` 只认 `screech spit bite nerve acid elite`，远程开火类别由 `enemy_ai.shot_sfx` 按字段推出（Boss 一律 spit、acid → acid、精英 → elite …）。
- Boss：起手 / 命中 `Sfx.play_cue(类别, boss, start|hit)`，类别沿用 docs/38 §8.11 五类（落地 / 冲锋 / 光束 / 近身 / 全场 / 阶段），不新增；专属层 `game/audio/sfx/boss_<id>.wav`（缺文件静默），电平 `CUE_VOL`。原作客户端音效可进包（memory canon-audio-ok）。测试一律静音。

## ⑧ 文案（docs/76）

- `name`、`intro.sub / line`、`extra.name`、`patterns[].name`、`chips`、`desc` 都是玩家可见文字。
- **档案 `game/data/lore.json` `{"<id>": {"lore": "…"}}` = 现场观察记录**：写它是什么、长什么样、做什么，最后一句停在一个具体画面上；**机制不写进档案**（docs/76 §1.1、§3 X9），机制写在图鉴机制行。
- 图鉴机制说明：`gallery.gd ENEMY_DESC` 常量优先于 json `desc`（新怪写 json `desc` 即可，别再往常量里加）；附加攻击 / 攻击模式行由 `extra.name` / `patterns` 名自动拼。
- 术语（docs/76 §5）：「中期 Boss / 最终 Boss」不写「强敌」；「Boss 除外 / Boss 免疫 / Boss 减半」；写「队长」不写「主控」。提交前过 §8 自查。

## ⑨ 测试

输出进文件看 rc（同 new-operator §⑧）：

```bash
python tools/data_lint.py                 > build/chk_dlint.txt 2>&1; echo rc=$?
python tools/check.py --only enemy_art    > build/chk_eart.txt 2>&1; echo rc=$?
python tools/check.py --only asset_index  > build/chk_aidx.txt 2>&1; echo rc=$?
python tools/check.py --only enemy_pixels > build/chk_epix.txt 2>&1; echo rc=$?
python tools/check.py --auto --jobs 1     > build/chk_auto.txt 2>&1; echo rc=$?   # 改 enemies / waves 触发 core / enemy / boss / repro / smoke
```

- 场景回归组（`check.py` 场景表 / `tools/check_map.json`）：enemy 组 `enemy_status enemy_attack_variety enemy_identity enemy_prepare enemy_demo enemy_pixels …`；boss 组 `boss_variety boss_pressure mid_boss final_boss_tells final_boss_completion boss_fx_geometry boss_support boss_boundary …`；图鉴 `public_gallery gallery_demo`。
- **测试里写死的 id 列表要手动加新怪**：`game/tests/boss_variety_test.gd`（十只）、`final_boss_tells_test.gd`（四只最终）、`enemy_pixel_contract.gd`（draw_scale 期望表，不在表里不查）、`enemy_scale_field.gd`（布阵）。
- 演示 / 截图开关：`--spawntest=<id,…>`（小怪 / 精英招式截图，时间照走）、`--bossmoves=<id>[2]`（按 `demo_moves` 逐招放，预警 60% 时截图）、`--bossacts=<id>`（逐幕，`tools/probes/boss_act_gifs.py`）、`--bossintro=<id>`、`--bosstest=<id>[2]`（**g.t 冻结在约 150**，靠 g.t 的画面不动，时间类画面改用普通 autotest 前 15 秒，memory bosstest-frozen-time）、`--forceboss=k` / `--forceending=<结局>`。
- 审阅媒体：只发 mp4、`--realtime` 30 帧、原色原速（memory review-media）；发前 `vreview` 预审。

## ⑩ 难度与数值

- Boss 单场测试台 `tools/boss_bench.py`（docs/177）：`BOSSES` 字典加新 Boss（键 → (种类, 登场位 1/2/3, 中文名)）；`record` 录正常编队到场快照 → `run --bosses <id> --tag <唯一 tag>` → `table base.json new.json` 出对照（用时、破绽输出占比、承伤）。GCP 跑（`tools/gcp/batch.py run <tag> --cmd …`，tag 唯一）。
- 整局难度看局外成长口径：无认知 m0 45–55%、18 细胞 m18 65–75%（docs/38 §8.12、memory difficulty），≥ 3 份均值；同种子配对，**胜率差 < 10 点不下结论**（docs/80）；看用户会不会嫌难另跑 `--bot=human`（docs/308）。只用不给奖励的旋钮（hp_x / dmg_x / 出场权重），不改全局曲线。
- 普通怪：同种子配对看加进池前后胜率 / 低血秒 / 死因分布（`tools/balance_run.py --preset starts`）。

## ⑪ 交付

- 只提交自己的文件；`.gd.uid` 随脚本；`.import` 别手写 uid（让 Godot `--import` 生成）；index.json 随提交。
- 00_index「敌人与 Boss」表加设计稿行；docs/76 附录 A 加来源；docs/38 / 95 如改通用规则同步。
- 三行汇报：分支 + 提交号（读到再报）+ 关键数字；不合 main、不推分支（协调人做）。

---

## 样板核对：塑路者 `path` 的文件落在哪一步（11-07 走查）

| 文件 | 步骤 |
|---|---|
| `data/enemies.json path`（bcol / intro / portrait_crop / patterns / draw_full）、`waves.json mid_pool`、`lore.json path` | ③ ⑧ |
| `scripts/enemies/bosses/path.gd` + `.uid`；中期分级弹 `enemies/mid_cards.gd`（docs/170 / 175） | ④ |
| `art/enemies/path/e_path{,_move,_attack,_charge,_skill,_slam,_wound,_death}` + 各 `_emit`；`enemy_pixels.json` / `enemy_redraw.json` 各 8 条；`art/index.json` | ⑤ |
| `render/boss_bullet_draw.gd TYPES`（菱晶 #96B2E6）、`vfx.gd`、`world.gd`、`boss_beam.gd`、`enemies/telegraph.gd` 里的 `"path"` 分支；`patterns[].fx` 写的 `fx_path_correct_ring` 仓库里没有图（走程序画回退） | ⑥ |
| `audio/sfx/boss_path.wav` | ⑦ |
| `gallery.gd ENEMY_DESC.path`（优先于 json desc） | ⑧ |
| `tests/boss_variety / boss_pressure / boss_support / mid_boss_* / enemy_pixel_contract / enemy_attack_variety / prot_test`；`tools/boss_bench.py BOSSES`、`tools/balance_run.py` | ⑨ ⑩ |
| 其余按 type 的特例：`run/combo.gd`、`screens/hud_bossbar.gd`、`run/run_stats.gd`、`run/demo.gd` | 见下表 |
| 不用照做：`tools/danmaku_*.py`、`tools/concept_danmaku.py`（docs/306 一次性对照工具） | — |

## 纯数据化缺口（为将来玩家自制怪物 / 模组）

**已经纯数据的**：普通怪（8 必填 + `ai` 三选一 + 10 种 pattern + 4 种 extra + 远程 / 抛射 / 状态 / 免疫 / 上限字段 + 专属帧条名）；刷怪池、大群混编、精英池；Boss 名片、专属色、卡点、每幕时长、场地半径、数据招式 `patterns` 6 种 mode；演练菜单、HUD 血条、中期放大、图鉴收录都从 json 自动派生。

**还要写代码或改硬编码的**：

| 缺口 | 位置 | 补全方向 |
|---|---|---|
| 新 Boss 必须有 `bosses/<script>.gd`（data_lint 强制），没有「纯 patterns Boss」 | boss_ai.gd `script_of / boss()`、data_lint.py | 允许 `script: "generic"`：只跑 `patterns` + `mid_cards` 连段的缺省脚本 |
| `ai` 只有 3 个字符串分支；pattern 10 种、参数名各自专用；extra 4 种 | run/enemies.gd、enemy_ai.gd | 拆成「蓄力 → 预警形状 → 结算」通用积木（同干员 docs/61 思路） |
| 新预警 act 要在 `telegraph._resolve` / `cue_cat` 加分支 | enemies/telegraph.gd | act 按「形状 + 效果积木」数据化 |
| 东方化弹体 `TYPES / RAMP / SHAPE / AMB` 写死八只 | render/boss_bullet_draw.gd | 从 `bcol` 推色带，加 `bullet_shape` / `amb` 字段 |
| 最终 Boss `FINAL_TYPES`、`final_attacks.NAMES`、`boss_attack_draw` 专属画法 | boss_patterns.gd、final_attacks.gd、boss_attack_draw.gd | 改用 `is_final_boss_type`（endings），补充攻击进数据 |
| `vfx.BOSS_STYLE`、`HIT_SHELL / HIT_SPIRIT`、`CTRL_CATS` | vfx.gd、combat.gd | 加 `sig_fx` / `hit_mat` / `ctrl_cat` 字段 |
| `world.boss_strip_animation` match、骑士公共段硬编码 | world.gd、boss_ai.gd | 帧条挂点进 enemy_redraw.json |
| `FINAL_TRACK`、`CUE_VOL` | music_director.gd、sfx.gd | 加 `music` / `cue_db` 字段 |
| 蜕变产物写死 bone / slider / stone；爆裂节点只认 pocket；同种上限缺省 match；抽满回退 bone / slider、精英池空回退 pocket | run/enemies.gd、spawner.gd | `morph_into`、`burst_at`、全部用 `cap`、waves 里写 fallback |
| 图鉴 `ENEMY_DESC` 常量优先于 json `desc` | gallery.gd | 迁进 enemies.json `desc` |
| `art.gd V6_FRAMES` 帧数是代码常量 | art.gd | 帧数改读 enemy_pixels.json |
| docs/142 §2.1 幕招表 `acts / pattern_mods` 未实现 | — | 按 142 落地后，Boss 分幕可纯数据 |
| 测试 / 工具写死 id：boss_variety_test、final_boss_tells_test、enemy_pixel_contract、enemy_scale_field、boss_bench.py `BOSSES` | game/tests、tools | 改成遍历 `D.ENEMIES` / role |
| 按 type 名的特例（`e.type ==` / `type in [`）：saint.gd 22、world.gd 18、boss_beam.gd 11、final_attacks.gd 8、enemy_ai.gd 7、hud_bars.gd 7 处，另有十余个文件各 2–5 处（如 塑路者在 combo / hud_bossbar / run_stats / demo 里） | 多处 | 逐项挪成字段 |
| 疑似死字段：`nest.aura_nerve`、`knight_boss.phases` 无读取方 | enemies.json | 删掉或接上 |
