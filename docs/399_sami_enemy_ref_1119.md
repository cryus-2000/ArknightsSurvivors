# 399 萨米主题敌人 / Boss 原作素材清单与像素帧条（11-19 / 11-20）

（原编号 392，与萨米设计稿 `docs/392_sami_enemies_numbers_1119.md` 撞号，11-20 改 399。）

**状态：记录。** §1–§4 是 11-19 的素材收集，§5 是 11-20 的像素帧条。 萨米样例（docs/390、391，分支 `claude/upbeat-montalcini-b732a9`）的敌人与 Boss 原作素材**收集**，对应 docs/391 的 T-A3。11-19 用户批准敌人和 Boss 也用原作 Spine 直转像素进包（memory `spine-direct-ok`）。这一步**只收集、不转换**：素材全在主工作区 `build/`（不进 git、不进包），帧条转换是 T-A4 / T-A5。

## 1. 怎么拉的

- 原作 id 来自解包数据 `enemy_handbook_table.json`（Kengxxiao/ArknightsGameData，`build/prts_ref/_raw/_gamedata/`），按中文名对上 docs/391 §2–§4 的名单。
- **Spine**：torappu 敌人路径是 `https://torappu.prts.wiki/assets/enemy_spine/<敌人 id>/<敌人 id>.{skel,atlas,png}`，没有皮肤 / 正面子目录（与干员 `char_spine/<id>/defaultskin/front/` 不同；11-19 试出）。已登记进 `tools/prts_spine.py` 的 `ENEMY` 表，键名 `sami_*`：
  ```bash
  python tools/prts_spine.py sami_shell sami_caster sami_drone sami_warrior sami_vinebox sami_blade sami_blade2 sami_will snslime_a snow_icebreaker
  ```
  每个对象出 `build/prts_ref/<键名>/`：idle ×4、move ×4（有移动轨时）、attack ×3、skill ×3（有技能轨时）、death ×3 参照帧（1000 画布透明底），`<键名>_sheet.png` 拼图与 `<键名>_info.json`（全部动画轨的时长和事件）。`prts_spine.py` 这次新增了 move / death 两组参照帧，对干员也生效。不开 Godot，用 node + spine-ts 渲染。
- **图鉴头像**：`https://torappu.prts.wiki/assets/enemy_icon/<敌人 id>.png`（158×158）→ `build/prts_ref/sami_ref/icons/`。原作敌人没有单独的立绘，图鉴里用的就是这张头像。
- **界面 / 地图配色参考**：PRTS 主题页「探索者的银凇止境」的主题图（1560×500）、图标、活动名称图，以及页面里的 4 张剧情 CG（`Avg_pic_rogue_3_31/32/33/35`，1600×900）→ `build/prts_ref/sami_ref/ui/`。PRTS 关卡页（巍峨银凇等）没有地图截图（只有占位图），地图配色只能参照 CG 和区域色。
- **参照拼图**：`build/prts_ref/sami_ref/make_sheets.py` → `build/prts_ref/sami_ref/sheets/`：每个对象一张 `<键名>_ref.png`（各动作一帧 + 图鉴头像 + 体型），`sami_scale_overview.png`（各对象待机按干员同比例并排），`sami_ui_palette_ref.png`（主题图 + CG + PRTS 区域色）；`build/prts_ref/sami_ref/manifest.json` 是下表的机器可读版。

## 2. 清单

「体型」：待机首帧在 Spine 坐标里的宽 × 高；「按干员同比例 @2x」= × 0.17（新干员 Spine → @2x 像素的平均尺度，docs/365 §11 的 0.154–0.188），只是比大小用，转换时按 docs/391 §2.9 / §3.6 / §4.7 的目标尺寸再定。

| 对象 | 本作定位 | 原作 id | 键名 | 动画轨（秒） | 体型（Spine） | 按干员同比例 @2x |
|---|---|---|---|---|---|---|
| 染污躯壳 | 普通 · 主力杂兵 | `enemy_2043_smsbr` | `sami_shell` | Idle 1.0、Move 2.0、Run 0.67、Attack 1.17、Die 1.0 | 361 × 370 | 61 × 63 |
| 坍缩构造体 | 普通 · 飞行 | `enemy_2045_smdrn` | `sami_drone` | Idle / Move / Attack 均 0（单帧姿势）、Die 0.5 | 304 × 127 | 52 × 22 |
| 歪曲施法者 | 普通 · 远程 | `enemy_2044_smwiz` | `sami_caster` | Idle 2.0、Move 2.0、Run 0.67、Attack 1.67、Die 1.0 | 246 × 384 | 42 × 65 |
| 冰爆源石虫·α | 普通 · 借用 | `enemy_1067_snslime_2` | `snslime_a` | Idle 1.0、Move 1.0、Attack 2.5、Die 1.0 | 350 × 231 | 60 × 39 |
| 木裂战士 | 精英 | `enemy_2046_smwar` | `sami_warrior` | Idle 1.67、Move 0.8、Attack_A 1.0、Attack_B 1.0、Die 0.67 | 497 × 446 | 84 × 76 |
| 雪怪小队破冰者 | 精英 · 借用（用户 11-19 加） | `enemy_1069_icebrk_2` | `snow_icebreaker` | Idle 2.0、Move 1.2、Attack 3.0、Die 1.0 | 466 × 349 | 79 × 59 |
| 巨壳藤蔓 | 稀有 · 宝箱拟态 | `enemy_2059_smbox` | `sami_vinebox` | Idle 2.0（宝箱态）、Start 1.1（起身）、Move 1.33、Attack 1.0、Die 1.0 | 337 × 270 | 57 × 46 |
| “邪魔的利刃” | 中期 Boss 3:30 | `enemy_2048_smgrd` | `sami_blade` | Idle 2.0、Move 1.33、Attack 2.17、Combat 1.83、Die 1.0 | 425 × 463 | 72 × 79 |
| “邪魔的利刃”，游荡者 | 中期 Boss 7:00 | `enemy_2049_smgrd2` | `sami_blade2` | 同上（骨架与利刃相同，贴图另一份） | 425 × 463 | 72 × 79 |
| “萨米的意志” | 最终 Boss | `enemy_2054_smdeer` | `sami_will` | Idle 4.0、Attack 3.0（冰凌）、Skill_01_Begin 3.0 / Loop 2.0 / End 0.67（自然涌动）、Skill_02 2.67（叹息）、Die 1.1 | 1425 × 1188 | 242 × 202 |
| 积雪银凇 | 意志关场景装置 | `enemy_2047_smtree` | `sami_tree` | — | — | — |
| 国度 | 地形（中期 Boss / 坍缩范式） | — | — | — | — | — |

## 3. 拿不到 / 要注意的

1. **积雪银凇没有 Spine**：`enemy_spine/enemy_2047_smtree/` 下的 .skel 返回 404（11-19），已登记在 `ENEMY` 表里（`sami_tree`），只拿到图鉴头像 `icons/enemy_2047_smtree.png`。它在原作是不动的装置，可能只有静态图；转换时按头像和关卡 CG 画，或再找 `trap_` / 关卡装置资源。
2. **国度没有对应模型**：原作是地块上的效果（我方攻速 −50），不是单位，没有 Spine / 头像；做地形时按 docs/390 §6、§9 的描述画。
3. **坍缩构造体渲染不对**：本地渲染出来是一团暗紫色剪影，跟图鉴头像（黑核 + 白色光晕的「黑洞」）对不上。它的动画轨时长都是 0（单帧姿势），光晕大概靠加色 / 屏幕混合或程序特效；转换时要么补混合模式，要么光晕交给特效、本体按头像画。
4. **雪怪小队破冰者**同族还有「雪怪小队凿冰人」`enemy_1069_icebrk`（精英，图鉴 Y6），没拉。
5. **萨米的意志有另一个 id** `enemy_9033_acdeer`（同名，图鉴编号同为 SAM，推测是别的活动用的版本），这次只拉了 `enemy_2054_smdeer`（ro3 Boss 关用的那个，docs/390）。
6. 积雪银凇、国度以外的场景物件（族树、冰岩、萨米石墙等，docs/390 §9）原作里是关卡地图贴图，不是单独资源，这次没收集。

## 4. 文件

- `tools/prts_spine.py`：`ENEMY` 表（敌人 torappu 路径）、`OPS` 补中文名、参照帧加 move / death。
- 素材（主工作区 `build/`，不进 git）：`prts_ref/_raw/sami_*`、`snslime_a`（skel / atlas / png）、`prts_ref/<键名>/`（参照帧与 info）、`prts_ref/sami_ref/{icons,ui,sheets,manifest.json,make_sheets.py}`、`prts_ref/_raw/_gamedata/enemy_handbook_table.json`。

## 5. 像素帧条（11-20）

用户 11-20 要求把这批做成游戏里能直接用的像素帧条（11-19 已批准 PRTS Spine 直转像素进包，扩到敌人和 Boss，memory `spine-direct-ok`）。名单与本作 id 按 docs/392（萨米设计稿）§1、§6.9。坍缩体 / 撑持体不是单独的模型（撑持体 = 普通坍缩体加一层状态，docs/392 §4），不另出帧条；积雪银凇没有 Spine、国度没有模型，这次不做。

### 5.1 怎么出的

- `tools/spine_px_enemy.py`：按表写 `tools/spine_run_trial/cfg/sami_<id>{.src,,_px}.json`，借 `tools/spine_px.py` 整条流程（逐附件渲染 → 64 色调色板（意志 96 色）→ 清理 → 描边，同干员 B 方案 docs/365），再按全部动作的并集包围盒裁成紧框。无腿配置：地线 = 待机首帧最低点（同令的召唤物）。
- **命名与目录**照水月敌人（docs/189 §2）：`game/art/enemies/sami/e_sami_<id>@2x.png`（待机）、`e_sami_<id>_<动作>@2x.png`；Boss（利刃、游荡者、意志）另有 1 倍 `e_sami_<id>[_<动作>].png`（同 `install_enemy_redraw.BOSS_1X`：Boss 登场画面读 1 倍）。普通怪只进 @2x。前缀 `e_sami_` 是为了不跟水月键名撞（`asset_paths` 按第一段归到 `enemies/sami/`）。`.import` 由 Godot 生成，参数跟水月敌人一致（`fix_alpha_border=false`）。
- **帧数**照水月同档：普通 4 / 4 / 6 / 6 + 受击 1，精英 6 / 6 / 8 / 8 + 1，Boss 6 / 6 / 8 / 8 + 招式 8。原作没有受击轨，`wound` 取 Die 开头约 0.1 秒的后仰姿势。
- **尺寸**照现有同档敌人（@2x 待机顶到脚：水月普通 36–50、高阶 60–64、精英约 72、中期 Boss 80–94、最终 Boss 126–168），按体型档放大，见下表。
- **规格**：`tools/spine_run_trial/cfg/sami_enemies_sprites.json`，每个运行时键给 `pixels`（= `enemy_pixels.json` 条目：anchor / frames / frame_size）和 `redraw`（= `enemy_redraw.json` 条目：frames / event_frames（按原作 OnAttack 事件）/ sample_times / loop / duration）。**游戏现在不读**；主题开关合入后并进 `game/themes/sami/data/` 再接刷怪。
- 对照图：`python tools/spine_px_enemy_cmp.py` → `build/spine_px/_sami_cmp/<id>_cmp.png`（原作参照 / 像素 @1x ×4 / 像素 @2x ×2，每动作一行取出手帧或中间帧）与 `sami_overview.png`。

### 5.2 清单

| 对象 | 本作 id | 档 | 帧框 @2x | 待机本体 @2x | 顶到脚 | 动作（帧数） |
|---|---|---|---|---|---|---|
| 染污躯壳 | `husk` | 普通 | 60 × 62 | 51 × 52 | 52 | idle 4、move 4、rush 4、attack 6、death 6、wound 1 |
| 坍缩构造体 | `drone` | 普通 | 64 × 34 | 59 × 25 | 25 | idle 1、move 1、attack 1、death 6、wound 1 |
| 歪曲施法者 | `caster` | 普通 | 62 × 68 | 37 × 58 | 58 | idle 4、move 4、rush 4、attack 6、death 6、wound 1 |
| 冰爆源石虫·α | `icebug` | 普通 | 90 × 52 | 58 × 38 | 38 | idle 4、move 4、attack 6、death 6、wound 1 |
| 雪怪小队破冰者 | `breaker` | 高阶 | 134 × 118 | 85 × 64 | 64 | idle 4、move 4、attack 8、death 6、wound 1 |
| 木裂战士 | `warrior` | 精英 | 104 × 90 | 79 × 71 | 71 | idle 6、move 6、attack 8、attack_b 8、death 8、wound 1 |
| 巨壳藤蔓 | `vinebox` | 稀有 | 94 × 74 | 67 × 46 | 52 | disguised 4、reveal 6、idle 1、move 6、attack 6、death 6、wound 1 |
| “邪魔的利刃” | `blade` | Boss | 142 × 106 | 81 × 89 | 90 | idle 6、move 6、attack 8、combat 8、death 8、wound 1 |
| “邪魔的利刃”，游荡者 | `wanderer` | Boss | 142 × 106 | 81 × 89 | 90 | idle 6、move 6、attack 8、combat 8、death 8、wound 1 |
| “萨米的意志” | `will` | Boss | 198 × 222 | 192 × 160 | 160 | idle 6、attack 8、surge_begin 8、surge_loop 6、surge_end 4、sigh 8、death 8、wound 1 |

动作说明：`rush` = 原作 Run 轨（躯壳受击暴冲、施法者停火突进用）；`attack_b` = 木裂战士 Attack_B（突进劈砍可用）；巨壳藤蔓 `disguised`（宝箱态 Idle）→ `reveal`（Start 起身）→ `idle` / `move`（逃跑）；利刃 / 游荡者 `combat` = 原作 Combat 轨（招式起手用）；意志 `attack` = 冰凌、`surge_begin / loop / end` = 自然涌动、`sigh` = 叹息（均为原作技能轨），意志不移动所以没有 `move`。

### 5.3 修图

1. **利刃的青色眼睛**：眼睛画在 Head 贴图里只占几个像素，量化时被并进灰白。利刃和游荡者是同一套骨骼和动画，游荡者的品红眼留得住，就按游荡者同帧眼睛像素的位置把利刃这几格换成原作青色（`#a9eddc` / `#62b7a6`，取自 Head 贴图）；两人的眼色都补进了调色板（`keep`）。
2. **坍缩构造体**：原作 Spine 本体只有墨色剪影 + 两端蓝灯，图鉴里的「黑核 + 白色光晕 + 横竖光芒」是游戏里另挂的特效。按图鉴头像在本体中心手补光核（`post_drone`）；原作 Die 轨是整体渐隐，二值透明后整段消失，死亡帧改成光核爆亮 → 本体按点溶解、光核收缩。悬浮起伏交给运行时 `hover`。
3. 其余几只没有手改；色调、眼色和衣服细节逐只对过原作（对照图第一列）。

### 5.4 已知问题 / 接入时注意

- 朝向：帧条保持原作朝向（朝右），运行时按 `e.fx < 0` 翻转，同水月。
- 破冰者 Attack 轨 3 秒、举刀很高，帧框 134 × 118 比本体大很多；接入时出手帧按 `event_frames`。
- 意志的帧框 198 × 222：招式轨里冰晶向上长，待机本体只有 192 × 160。
- 死亡帧除构造体外都是原作 Die 轨（倒地 / 跪下，没有渐隐），消失仍按水月的运行时淡出。
- 包体：80 张 PNG 共约 2.3 MiB（意志 8 条约 0.9 MiB）。

## 6. 全量名单（11-20 调研）

用户 11-20：范围扩到萨米全量（所有敌人和 Boss），今晚**只调研**——补收缺的 Spine、参照帧、头像，清单写全；像素化等选定处理方式（§7）后再批量做。名单按 docs/390 §3–§4（sami-research 分支），原作编号查 `enemy_handbook_table.json`。素材 11-20 起放 `F:\ArknightsSurvivors_build\kind-dijkstra\`（E 盘 `build/prts_ref`、`build/spine_px` 已整个挪过去，原位置留目录联接，工具路径不变）。

- 「进度」：**帧条** = §5 已出（处理方式待 §7 选定，选完按新方式重出）；**参照** = Spine + 参照帧 + 头像已收，未像素化；**缺** = 拿不到的项。
- 「目标 @2x」= 待机顶到脚的像素高（按 §5.1 同档口径）；宽度按 Spine 比例换算，巨型 Boss 宽 ≤ 320。
- 「工作量」：**小** = 套 `spine_px_enemy.py` 配置 + 对照检查，约 0.3 小时；**中** = 有特殊轨（起身、闪现、多段技能）或要手补一处，约 1 小时；**大** = 多段技能 + 胜利 / 决胜等专属轨、体型大，约 2 小时。同骨骼换贴图的变体按「小」。

| 对象 | 原作编号 | 样例 / 全量 | 档 | 原作动作轨（秒） | Spine 体型 | 目标 @2x（高 × 宽约） | 进度 | 工作量 |
|---|---|---|---|---|---|---|---|---|
| 染污躯壳 | `enemy_2043_smsbr` | 样例 | 普通 | Idle 1.0、Move 2.0、Run 0.67、Attack 1.17、Die 1.0 | 361 × 370 | 52 × 51 | 帧条 | 小 |
| 坍缩构造体 | `enemy_2045_smdrn` | 样例 | 普通 · 飞行 | 单帧姿势、Die 0.5 | 304 × 127 | 25 × 59 | 帧条（手补光核） | 中 |
| 歪曲施法者 | `enemy_2044_smwiz` | 样例 | 普通 · 远程 | Idle 2.0、Move 2.0、Run 0.67、Attack 1.67、Die 1.0 | 246 × 384 | 58 × 37 | 帧条 | 小 |
| 冰爆源石虫·α | `enemy_1067_snslime_2` | 样例（借用） | 普通 | Idle 1.0、Move 1.0、Attack 2.5、Die 1.0 | 350 × 231 | 38 × 58 | 帧条 | 小 |
| 雪怪小队破冰者 | `enemy_1069_icebrk_2` | 样例（借用） | 高阶 | Idle 2.0、Move 1.2、Attack 3.0、Die 1.0 | 466 × 349 | 64 × 85 | 帧条 | 小 |
| 木裂战士 | `enemy_2046_smwar` | 样例 | 精英 | Idle 1.67、Move 0.8、Attack_A / B 1.0、Die 0.67 | 497 × 446 | 71 × 79 | 帧条 | 小 |
| 巨壳藤蔓 | `enemy_2059_smbox` | 样例 | 稀有（宝箱） | Idle 2.0、Start 1.1、Move 1.33、Attack 1.0、Die 1.0 | 337 × 270 | 52 × 67 | 帧条 | 小 |
| “邪魔的利刃” | `enemy_2048_smgrd` | 样例 | 中期 Boss | Idle 2.0、Move 1.33、Attack 2.17、Combat 1.83、Die 1.0 | 425 × 463 | 90 × 81 | 帧条（借眼修色） | 中 |
| “邪魔的利刃”，游荡者 | `enemy_2049_smgrd2` | 样例 | 中期 Boss | 同利刃（同骨骼，另一套贴图） | 425 × 463 | 90 × 81 | 帧条 | 小 |
| “萨米的意志” | `enemy_2054_smdeer` | 样例 | 最终 Boss | Idle 4.0、Attack 3.0、Skill_01 Begin 3.0 / Loop 2.0 / End 0.67、Skill_02 2.67、Die 1.1 | 1425 × 1188 | 160 × 192 | 帧条 | 中 |
| 积雪银凇 | `enemy_2047_smtree` | 样例（装置） | 装置 | —（无 Spine，.skel 404） | — | 约 64 高（静态） | 缺 Spine；只有头像 | 中（按头像 + CG 手画静态 + 碎裂几帧） |
| 可汗片影 | `enemy_2060_smshdw` | 全量（EJ6） | 普通 | Idle 2.0、Move 1.1、Attack 2.0、Die 1.0 | 314 × 482 | 56 × 36 | 参照 | 小 |
| 王者友伴 | `enemy_2061_smhond` | 全量（EJ7） | 高阶 | Idle 1.33、Move 0.5、Attack 1.0、Die 1.0 | 687 × 388 | 64 × 113 | 参照 | 小 |
| 勘察用自走车 | `enemy_2062_smcar` | 全量 | 普通（我方科考车，撞敌） | Idle 3.2、Move 3.2、Die 1.0（无攻击轨） | 483 × 337 | 44 × 63 | 参照；**头像 404** | 小 |
| 乌萨斯裂兽 | `enemy_1108_uterer` | 全量（借用，利刃所指关） | 普通 | Idle 2.67、Move Begin 0.33 / Loop 0.6 / End 0.33、Attack 1.0、Die 1.0 | 349 × 277 | 44 × 55 | 参照 | 小 |
| 乌萨斯裂兽族母 | `enemy_1108_uterer_2` | 全量（借用） | 普通 | 同裂兽（同骨骼） | 349 × 278 | 44 × 55 | 参照 | 小 |
| 寒霜 | `enemy_1042_frostd` | 全量（借用，「寒霜无人机」） | 精英 · 飞行 | Idle 2.0、Move Begin 0.33 / Loop 2.0 / End 0.33、Die 1.0（无攻击轨，攻击用待机） | 472 × 252 | 40 × 75 | 参照 | 小 |
| 雪怪小队 | `enemy_1064_snsbr` | 全量（借用） | 普通 | Idle 1.0、Run_Loop 0.8、Attack 1.0、Die 1.0 | 440 × 365 | 50 × 60 | 参照 | 小 |
| 雪怪小队凿冰人 | `enemy_1069_icebrk` | 全量（借用） | 精英 | 同破冰者（同骨骼） | 466 × 349 | 64 × 85 | 参照 | 小 |
| 陷落雪祀 | `enemy_2050_smsha` | 全量 | 中期 Boss | Idle 2.0、Move 0.8、Attack 1.5、Skill 1.67、Die 1.8 | 484 × 476 | 90 × 92 | 参照 | 中 |
| 空洞雪祀 | `enemy_2051_smsha2` | 全量 | 中期 Boss（变体） | 同陷落雪祀（同骨骼） | 484 × 477 | 90 × 92 | 参照 | 小 |
| 纠缠藤蔓 | `enemy_2052_smgia` | 全量 | 中期 Boss | Idle 2.67、Move 2.67、Attack 1.83、Skill 1.83、Die 2.0 | 525 × 564 | 94 × 88 | 参照 | 中 |
| 古老藤蔓 | `enemy_2053_smgia2` | 全量 | 中期 Boss（变体） | 同纠缠藤蔓（同骨骼） | 525 × 564 | 94 × 88 | 参照 | 小 |
| 「木裂」埃克提尔尼尔 | `enemy_2055_smlead` | 全量 | 最终 Boss | Idle 3.33、Move_A 1.33、Move_B 0.87（自我泯灭疾奔）、Attack 2.5、Die 1.0 | 359 × 557 | 150 × 97 | 参照 | 中 |
| 无垠回荡克雷松 | `enemy_2056_smedzi` | 全量 | 最终 Boss | Idle 4.0、Attack 3.17、Move Begin / End 0.67（Loop 0 秒 = 闪现中不可见）、Die 6.0（另有 Die Begin / Loop / End） | 605 × 613 | 150 × 148 | 参照 | 中–大（闪现进出要配特效） |
| 哈兰杜汗，大地之鞭 | `enemy_2057_smkght` | 全量 | 最终 Boss（双王） | Idle 1.67、Move 1.87、Attack 2.03、Skill Begin 1.43 / Loop 1.0 / End 2.1（征服）、Victory 1.77、Die 2.5 | 810 × 553 | 140 × 205 | 参照；**头像连接超时没拿到** | 大 |
| 路加萨尔古斯，历法之王 | `enemy_2058_smlion` | 全量 | 最终 Boss（双王） | Idle 1.5、Move 1.5、Attack 1.67、Combat 1.67、Skill_1 Begin / End（瞬身）、Skill_2 Begin / Loop / End（敕令）、Victory 1.0、Die 3.0 | 826 × 539 | 140 × 215 | 参照 | 大 |

合计 27 个对象：样例 11（帧条 10 + 积雪银凇缺 Spine），全量 16（参照已收齐，头像缺 2）。估计工作量：其余 16 只约 10 小时（小 10 × 0.3 + 中 3 × 1 + 中–大 1 × 1.5 + 大 2 × 2），加上 §5 已出的 10 只按选定方式重出约 1 小时，积雪银凇手画约 1 小时。

没收的：
- docs/390 §4 各层「主要借用」里的通用敌人（囚犯、源石虫、萨卡兹、呼啸骑士团学徒、士兵、狙击步兵、乌萨斯突击者、军用猎狗、萨卡兹魔剑士、提亚卡乌各兵种、倾轧者、末路狂徒、特工组长、残党、高塔术师、量产巨像）：都是通用敌人，跟主题关系弱，等设计稿定了要借哪些再收。
- 随机打劫者（鸭爵 / 高普尼克 / 流泪小子）：水月已有鸭爵，萨米沿用。
- 国度（地块效果，无模型）、萨米的意志另一个编号 `enemy_9033_acdeer`（别的活动用的版本）。

工具改动：`tools/prts_spine.py` 的 `ENEMY` 表补了这 16 个键（`sami_shaman` 等）；`tools/prts_spine_render.js` 跳过包围盒算出 NaN 的姿势（克雷松闪现中的 Move_Loop 姿势会让整张参照帧空白）。

## 7. 处理方式候选（11-20）

用户 11-20：先挑 2 只样例出几种处理方式，选定后再批量做其余敌人。挑的是染污躯壳（普通、人形、小）和萨米的意志（最终 Boss、大、雪白高光多），两头各一只。

| 候选 | 做法 | 看点 |
|---|---|---|
| A 现行 | 64 色（意志 96 色）+ 外描边（`#0a1418`，混 55%）——即 §5 已出的帧条 | 跟干员 B 方案一致；暗面偏深 |
| B 无描边提亮 | 去外描边、只留原作线稿；明度按 v^0.8 提亮暗部 | 更接近原作亮度，在深色地面上轮廓较弱 |
| C 少色平涂 | 24 色（暗面并块）+ 纯色硬外描边 | 更像手绘像素、轮廓最清楚；细节（意志的冰晶纹、躯壳的皮毛）丢得最多 |

- 出法：`python tools/spine_px_enemy.py husk will --variant <A|B|C> --out <目录>`（候选写到候选目录，不进 `game/`）；对照：`python tools/spine_px_enemy_cmp.py --variants <目录>` → 每只一张 `<id>_variants.png`（行 = 候选 × 动作，列 = 原作 / @1x ×4 / @2x ×2）+ `sami_variants_overview.png`。
- 候选图在 `F:\ArknightsSurvivors_build\kind-dijkstra\sami_candidates\`。
- 用户选定后：把选中的参数写进 `ENEMIES` 缺省值，重出 §5 的 10 只，再按 §6 顺序做全量（普通 / 精英 → 其余 Boss）。
