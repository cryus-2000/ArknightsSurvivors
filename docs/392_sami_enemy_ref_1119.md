# 392 萨米主题敌人 / Boss 原作素材清单（11-19）

**状态：记录。** 萨米样例（docs/390、391，分支 `claude/upbeat-montalcini-b732a9`）的敌人与 Boss 原作素材**收集**，对应 docs/391 的 T-A3。11-19 用户批准敌人和 Boss 也用原作 Spine 直转像素进包（memory `spine-direct-ok`）。这一步**只收集、不转换**：素材全在主工作区 `build/`（不进 git、不进包），帧条转换是 T-A4 / T-A5。

## 1. 怎么拉的

- 原作 id 来自解包数据 `enemy_handbook_table.json`（Kengxxiao/ArknightsGameData，`build/prts_ref/_raw/_gamedata/`），按中文名对上 docs/391 §2–§4 的名单。
- **Spine**：torappu 敌人路径是 `https://torappu.prts.wiki/assets/enemy_spine/<敌人 id>/<敌人 id>.{skel,atlas,png}`，没有皮肤 / 正面子目录（与干员 `char_spine/<id>/defaultskin/front/` 不同；11-19 试出）。已登记进 `tools/prts_spine.py` 的 `ENEMY` 表，键名 `sami_*`：
  ```bash
  python tools/prts_spine.py sami_shell sami_caster sami_drone sami_warrior sami_vinebox sami_blade sami_blade2 sami_will snslime_a
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
4. **萨米的意志有另一个 id** `enemy_9033_acdeer`（同名，图鉴编号同为 SAM，推测是别的活动用的版本），这次只拉了 `enemy_2054_smdeer`（ro3 Boss 关用的那个，docs/390）。
5. 积雪银凇、国度以外的场景物件（族树、冰岩、萨米石墙等，docs/390 §9）原作里是关卡地图贴图，不是单独资源，这次没收集。

## 4. 文件

- `tools/prts_spine.py`：`ENEMY` 表（敌人 torappu 路径）、`OPS` 补中文名、参照帧加 move / death。
- 素材（主工作区 `build/`，不进 git）：`prts_ref/_raw/sami_*`、`snslime_a`（skel / atlas / png）、`prts_ref/<键名>/`（参照帧与 info）、`prts_ref/sami_ref/{icons,ui,sheets,manifest.json,make_sheets.py}`、`prts_ref/_raw/_gamedata/enemy_handbook_table.json`。
