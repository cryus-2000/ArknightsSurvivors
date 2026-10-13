# 93 · Codex 美术单：精英化攻击形态（精一 / 精二）全套素材（2026-10-13，按 10-13 审定更新）

> 用户 10-13：「精二最好是带来质变，视觉上也得能看出来」「哪些需要给 codex 美术单？不要吝啬」。
> 设计依据：docs/91（每名干员的精一 / 精二机制、画面要点、原作出处）。本单把 docs/91 里每一个**新出现的画面元素**都列成 Codex 素材；游戏里先用程序版占位，Codex 版到了优先用 Codex 版，程序版留作缺图回退（同 docs/archive/66 的做法）。
> 10-13 用户审定 docs/91 后本单已同步（docs/91 §22）：能天使、艾雅法拉、流明、归溟幽灵鲨、浊心斯卡蒂的条目按审定增删；新增浊心斯卡蒂声浪重做为**优先项**，排在第 1 批之前。
> Codex 只交素材，不改 `game/`。

## 0. 通用规格（每一项都适用，下面各条只写不同的地方）

**特效 / 弹体 / 地面件（`fx_*` / `proj_*`）**——按 docs/archive/66：

| 项 | 规格 |
|---|---|
| 排列 | 横排一条，1x 宽 = 帧宽 × 帧数；另交 `@2x`（每帧 2 倍，**重画细节优先**，来不及可最近邻放大） |
| 透明 | alpha 只有 0 / 255；柔和、半透明感**靠抖动（dither）疏密**表现，游戏里会整体乘透明度 |
| 描边 | 弹体、实体件（盾锯、锚、剑、岩刺、晶柱）1px `#080E18` 外描边（@2x 2px）；光、烟、水流类不描边 |
| 原点 | 每条在 manifest 写明 1x / @2x 原点像素（弹体 = 中心；地面件 = 椭圆中心；从地里长出来的 = 底边中点） |
| 朝向 | 有方向的（弹体、刀光、锚、剑）**一律朝右**画，程序旋转；地面件按俯视透视压扁（y ≈ 0.55） |
| 分层 | 会和人物交叉的特效拆 `_back`（人物后面）/ `_front`（人物前面）；地面件只交一层，标 `ground` |
| 色板 | 每条 ≤ 16 色；沿用该干员现有 `fx_*` / `proj_*` 的主色（下面每节写了参考文件），敌我区分：友方不用敌方的暗红紫（docs/48） |
| 不要 | 不画人物（除非写明是人物帧条）、不画伤害数字、不画 UI |

**人物 / 召唤物帧条（`op_*`）**：一律按 docs/87（96px 为主、只画朝右 3/4 侧身、脚底 (24, 46)、二值透明、`#080E18` 描边、1x 与 @2x 逐帧对应、≤ 24 色、出手帧写进 manifest）。新动作与该干员现有帧条**同一套造型和色板**，首帧 / 末帧能接回 idle f0。

**交付**：只动 `art/incoming/`；每批一个提交；每批附 `elite_art_<批号>_manifest.json`（每条：文件名、帧数、fps、帧尺寸、1x / @2x 原点、层、色数）+ `elite_art_<批号>_handoff.md` + 预览 GIF（深色地面底，特效按游戏缩放合成在人物 / 敌人旁边）。人物帧条交付前跑 `python tools/art_lint.py --ops <id>` 无未豁免 FAIL。

尺寸记法：下表「尺寸」都是 **1x 单帧**（@2x 自动 ×2）；fps 写在帧数后面。

---

## 优先项（独立于精英化，最先交）

### P.1 浊心斯卡蒂 · 声浪画面重做
参考色：`fx_skalter_*`、`fx_skalter_vortex_floor`（低饱和青 + 少量暗红）。现有声浪是程序画的细环，在怪堆里看不清；程序侧的缓动与明暗淡入淡出另行在做，这里只要帧条。

| 文件 | 尺寸 | 帧 | 层 | 用途 |
|---|---|---|---|---|
| `fx_skalter_wave_big` | 约 400×220 | 8–10 帧 12fps，不循环 | ground | 普攻「海潮低吟」每圈声浪（原尺寸大声浪，覆盖歌域）：从内到外扩散、先快后慢，外圈跟两三道渐淡余波；二值透明，渐淡靠抖动疏密 |
| `fx_skalter_wave_big_dim` | 同上 | 同上 | ground | 暗版（灯火暗淡 / 歌域效果弱时用），同一套帧、整体更暗更稀 |

两条帧数必须相同、逐帧对应（程序在明 / 暗两版间交叉淡入淡出）。原点 = 椭圆中心；俯视压扁 y ≈ 0.55。

---

## 第 1 批（积木干员，最先实现）

### 1.1 安洁莉娜 · 精一「重力停顿」/ 精二「失重井」
参考色：`proj_angelina_orb`、`fx_angelina_levitate`（紫 / 淡紫 / 白）。

| 文件 | 尺寸 | 帧 | 层 | 用途 |
|---|---|---|---|---|
| `fx_angelina_halt` | 24×12 | 5 帧 14fps，不循环 | ground | 精一：被重力弹落点命中、停顿的敌人脚下一圈紫色收缩细环 |
| `fx_angelina_well_back` | 96×64 | 8 帧 10fps 循环 | ground | 精二：失重井地面引力环（两层反向旋转的椭圆纹 + 向内吸的碎屑） |
| `fx_angelina_well_front` | 48×48 | 8 帧 10fps 循环 | front | 精二：井心离地 12px 的紫色球核 + 绕核的小碎石 |
| `fx_angelina_well_open` / `_close` | 96×64 | 各 5 帧 14fps | ground | 井张开（从点扩成环）/ 收拢消失 |
| `fx_angelina_float_dust` | 16×16 | 4 帧 8fps 循环 | front | 被托起的敌人身下飘的小尘粒（可散多颗） |

### 1.2 能天使 · 精一「穿甲连射」/ 精二「天使的祝福」
参考色：`proj_exusiai_bullet`（白）、`proj_exusiai_bullet_power`（金）、`fx_exusiai_*`。

| 文件 | 尺寸 | 帧 | 层 | 用途 |
|---|---|---|---|---|
| `proj_exusiai_bullet_t1` / `_t2` / `_t3` | 12×6 | 各 2 帧 20fps 循环 | front | 精一：连续命中同一敌人时子弹逐级 白 → 浅金 → 金（带短拖尾） |
| `fx_exusiai_hit_gold` | 24×24 | 5 帧 20fps | front | 精一满层命中火花（金色十字星 + 弹壳碎屑） |
| `fx_exusiai_halo` | 32×12 | 8 帧 10fps 循环 | front | 精二：挂在受祝福**队友**头顶的金色光环（原作天使光环的意象，慢转；两名队友各一个）；能天使开火时程序整体提亮一下 |
| `fx_exusiai_blessed_flash` | 24×24 | 4 帧 20fps | front | 精二：受祝福队友每次攻击时出手点的金色闪光（小十字星 + 金色光点，不遮挡队友自己的攻击特效） |

### 1.3 星熊 · 精一「反击架势」/ 精二「般若回旋」
参考色：`fx_slash_heavy_steel`、星熊盾面的翠绿（`op_hoshiguma_*`）。

| 文件 | 尺寸 | 帧 | 层 | 用途 |
|---|---|---|---|---|
| `fx_slash_heavy_rose` | 同 `fx_slash_heavy_steel` | 同 | front | 精一：架势期间盾斧斩刀光换暗红（原作「般若」的红） |
| `fx_hoshiguma_guard_glow` | 32×32 | 6 帧 10fps 循环 | front | 精一：格挡后盾面边缘一圈细红光 |
| `proj_hoshiguma_sawshield` | 28×28 | 8 帧 24fps 循环 | front | 精二：掷出的翠绿盾锯（旋转，带 4 道锯齿） |
| `fx_hoshiguma_saw_spark` | 16×16 | 4 帧 20fps | front | 精二：盾锯沿途甩出的绿色火花 |
| `op_hoshiguma_throw` | 人物帧条 | 6 帧 14fps，出手帧 2 | — | 精二：掷盾（前推盾 → 盾离手手臂空 → 回收接盾），末帧接 idle f0 |

### 1.4 凯尔希 · 精一「扑击」/ 精二「回防」
参考色：`fx_mon3tr_*`、`fx_claw_green`、Mon3tr 现有帧条。

| 文件 | 尺寸 | 帧 | 层 | 用途 |
|---|---|---|---|---|
| `op_kaltsit_m_lunge` | 同 Mon3tr 帧条 | 6 帧 14fps，出手帧 3 | — | 精一：Mon3tr 前扑（伏低 → 扑出 → 落爪） |
| `op_kaltsit_m_leap` | 同 Mon3tr 帧条 | 6 帧 12fps | — | 精二：Mon3tr 从敌群跃回队长身边（起跳 → 空中蜷身 → 落地） |
| `fx_mon3tr_slam_ring` | 64×32 | 6 帧 16fps | ground | 精二：回防落地四爪砸地的一圈绿色爪痕 |
| `fx_mon3tr_afterimage` | 同 Mon3tr 帧 | 1 帧（剪影） | back | 扑击 / 跃回的绿色残影剪影（程序复制 3 份渐隐） |

### 1.5 德克萨斯 · 精一「钉剑」/ 精二「余像·剑雨」
参考色：`fx_texas_rain_mark`、`fx_texas_rain_hit`（源石剑的红橙 + 钢）。

| 文件 | 尺寸 | 帧 | 层 | 用途 |
|---|---|---|---|---|
| `fx_texas_pin_sword` | 12×24 | 4 帧 12fps（插入）+ 定格 | front | 精一：插在被钉住敌人身上的源石剑 |
| `fx_texas_pin_shatter` | 24×24 | 5 帧 18fps | front | 精一：钉剑消失时碎成红光 |
| `fx_texas_sword_drop` | 12×40 | 5 帧 20fps | front | 精二：从天而降的剑（带下落光迹，最后一帧剑尖入地） |
| `fx_texas_sword_impact` | 32×16 | 5 帧 18fps | ground | 精二：剑雨每一柄落地的地面裂光 |

---

## 第 2 批（精二最弱的 4 名手写干员，迁积木时一起做）

### 2.1 逻各斯 · 精一「剜魂」/ 精二「连缀」
参考色：`fx_logos_glyph`、`fx_logos_script`（黑底暗金 / 白金）。

| 文件 | 尺寸 | 帧 | 层 | 用途 |
|---|---|---|---|---|
| `fx_logos_soul_rune_1` / `_2` / `_3` | 8×10 | 各 4 帧 8fps 循环 | front | 精一：敌人头顶 1–3 层暗金符；`_3` 为满层白金版 |
| `fx_logos_chain_tile` | 16×8 | 6 帧 12fps 循环（横向可平铺） | front | 精二：咒文链的一节（黑带 + 流动的金字），程序沿线平铺 |
| `fx_logos_chain_pulse` | 16×8 | 4 帧 20fps | front | 精二：伤害沿链传递时亮起的一节 |
| `fx_logos_chain_anchor` | 16×16 | 6 帧 12fps 循环 | front | 精二：链在敌人身上的咒文结 |

### 2.2 艾雅法拉 · 精一「熔蚀」/ 精二「三重咏唱·低抛」
参考色：`proj_lavaball`、`fx_flames`（暗橙 / 熔红 / 黄）。

| 文件 | 尺寸 | 帧 | 层 | 用途 |
|---|---|---|---|---|
| `fx_eyja_melt_crack` | 24×12 | 6 帧 8fps（出现 → 停留 → 淡出） | ground | 精一：被熔蚀的敌人脚下暗红裂纹 |
| `proj_eyja_lava_lob` | 16×16 | 4 帧 16fps 循环 | front | 精二：低弧抛射的熔岩弹（顶点约 20px、飞行约 0.25 秒；翻滚 + 甩火星）。地面影子由程序画，不出落点预示圈 |
| `fx_eyja_lava_pool` | 48×24 | 8 帧 10fps 循环 | ground | 精二：1.2 秒熔池（冒泡、边缘冷却变暗） |
| `fx_eyja_lava_splash` | 40×28 | 6 帧 18fps | front | 精二：熔岩弹落地溅起 |

### 2.3 斯卡蒂 · 精一「跃浪击」/ 精二「涌潮」
参考色：`proj_tide_blade`、`fx_skadi_wave`、`fx_water_splash`（深海蓝 / 青白）。

| 文件 | 尺寸 | 帧 | 层 | 用途 |
|---|---|---|---|---|
| `op_skadi_leap_strike` | 人物帧条 | 7 帧 14fps，出手帧 4 | — | 精一：跃起下劈（蹲 → 起跳 → 空中举剑 → 劈落 → 收势），末帧接 idle f0 |
| `fx_skadi_leap_splash` | 64×32 | 6 帧 18fps | ground | 精一：下劈落地的水花与地面水纹 |
| `proj_skadi_surge_blade` | 48×24 | 4 帧 16fps 循环 | front | 精二：涌潮潮刃（比现有 `proj_tide_blade` 更大、带浪尖与水沫拖尾） |
| `fx_skadi_surge_hit` | 32×32 | 5 帧 18fps | front | 精二：潮刃命中的浪花 |
| `fx_skadi_surge_release` | 48×32 | 4 帧 18fps | front | 精二：连斩收尾甩出潮刃时剑身上的水弧 |

### 2.4 乌尔比安 · 精一「收链」/ 精二「掷锚」
参考色：`proj_ulpianus_anchor`、乌尔比安的暗红纹（`op_ulpianus_*`）。

| 文件 | 尺寸 | 帧 | 层 | 用途 |
|---|---|---|---|---|
| `fx_ulpianus_chain_tile` | 16×8 | 2 帧 12fps（横向可平铺） | front | 精一 / 精二：锁链一节（程序沿线平铺，绷直时换第 2 帧） |
| `fx_ulpianus_pull_ring` | 64×32 | 6 帧 14fps | ground | 精一：锚落地时一圈锁链影子收向中心 |
| `op_ulpianus_throw` | 人物帧条 | 8 帧 14fps，出手帧 3、回拉帧 6 | — | 精二：掷锚（后摆 → 掷出手空 → 握链 → 拽回 → 接锚），末帧接 idle f0 |
| `fx_ulpianus_anchor_impact` | 64×40 | 6 帧 16fps | ground + front 两层 | 精二：锚砸地（地面裂纹 `_back`、碎石与尘 `_front`） |
| `fx_ulpianus_drag_dust` | 24×12 | 4 帧 14fps | ground | 精二：被拖回的敌人脚下拖痕尘土 |

---

## 第 3 批（迁积木 + 形态）

### 3.1 归溟幽灵鲨 · 精一「卷刃」/ 精二「替身闪现」
参考色：`fx_specter_saw`、`op_specter_unchained_doll`。

| 文件 | 尺寸 | 帧 | 层 | 用途 |
|---|---|---|---|---|
| `fx_specter_inward_ripple` | 96×48 | 6 帧 18fps | ground | 精一：环斩前外圈向内收的水纹 |
| `fx_specter_doll_appear` | 32×32 | 5 帧 18fps | front | 精二：替身人偶在敌群里从水花中现身（地面水花溅起 → 人偶剪影升起），末帧接 `op_specter_unchained_doll_spin` f0 |
| `op_specter_unchained_doll_spin` | 同人偶帧条 | 6 帧 16fps，出手帧 2 | — | 精二：替身人偶现身后的旋身环斩 |
| `fx_specter_saw_cold` | 同 `fx_specter_saw` × 0.85 | 同 | back / front | 精二：人偶那道冷色小一号锯环 |
| `fx_specter_doll_burst` | 32×32 | 6 帧 18fps | front | 精二：环斩完人偶碎成泡沫消失（人偶剪影裂开 → 一团泡沫上浮散开） |

### 3.2 水月 · 精一「拖拽」/ 精二「深蓝之籽」
参考色：`fx_mizuki_jelly`、水月触手（淡紫 / 粉紫 / 深蓝）。

| 文件 | 尺寸 | 帧 | 层 | 用途 |
|---|---|---|---|---|
| `fx_mizuki_tentacle_curl` | 16×16 | 4 帧 14fps | front | 精一：触手末端卷住敌人收回的小卷 |
| `fx_mizuki_jelly_dart` | 20×12 | 6 帧 14fps 循环 | front | 精二：离身游猎时拉长成水滴形的水母（带淡紫细尾） |
| `fx_mizuki_jelly_sting` | 24×24 | 5 帧 18fps | front | 精二：蜇中时触须一甩 |
| `fx_mizuki_bind_ring` | 24×12 | 6 帧 10fps 循环 | ground | 精二：被束缚敌人脚下淡紫束缚环 |

### 3.3 艾丽妮 · 精一「挑刺」/ 精二「裂潮余波」
参考色：`fx_slash_arc_deep`、艾丽妮的青白 / 手炮橙火。

| 文件 | 尺寸 | 帧 | 层 | 用途 |
|---|---|---|---|---|
| `fx_irene_lift_arc` | 24×24 | 4 帧 20fps | front | 精一：第 2 段刺击末端向上挑的小弧光 |
| `op_irene_finisher` | 人物帧条 | 7 帧 14fps，斩出帧 2、开枪帧 5 | — | 精二：锥形斩收尾 + 侧身举手炮追击，末帧接 idle f0 |
| `fx_irene_crescent_wide` | 80×56 | 5 帧 20fps | front | 精二：90° 青白新月斩 |
| `fx_irene_gun_burst` | 20×12 | 3 帧 24fps | front | 精二：手炮枪火 |

### 3.4 流明 · 精一「折光」/ 精二「灯塔光柱」
参考色：`fx_lumen_unit`、`fx_holy_impact_lantern`（暖白 / 灯火金）。

| 文件 | 尺寸 | 帧 | 层 | 用途 |
|---|---|---|---|---|
| `fx_lumen_refract_hit` | 16×16 | 4 帧 20fps | front | 精一：折光到下一名敌人时的小光点 |
| `fx_lumen_beam` | 32×10 | 4 帧 20fps（横向可平铺拉伸） | front | 精二：直线短光柱的一段（暖白，中间白芯；4 帧由亮到收束变细），程序沿光柱长度平铺，0.2 秒播完 |
| `fx_lumen_beam_flare` | 32×32 | 5 帧 20fps | front | 精二：出光处的镜头光晕（十字星芒 + 暖白光团） |
| `fx_lumen_beam_hit` | 24×24 | 4 帧 20fps | front | 精二：光柱穿过敌人时的闪白 |

---

## 第 4 批（精二保留，补精一与画面）

### 4.1 推进之王 · 精一「粉碎」/ 精二「破阵 + 岩刺」
参考色：`fx_rock_burst`、推进之王的金色（`fx_siege_*`）。

| 文件 | 尺寸 | 帧 | 层 | 用途 |
|---|---|---|---|---|
| `fx_siege_pebbles` | 40×24 | 6 帧 16fps | front | 精一：锤击击倒敌人时迸出的金色碎石 |
| `fx_siege_rock_spike` | 16×28 | 7 帧 18fps（拔起 → 停 → 缩回） | 原点底边中点 | 精二：沿地裂冒出的金色岩刺 |
| `fx_siege_fissure_tile` | 32×12 | 4 帧 12fps（横向可平铺） | ground | 精二：地裂本体（替换现在的一条金线） |

### 4.2 铃兰 · 精一「狐火灼印」/ 精二「九尾祈愿 + 狐火拖尾」
参考色：`fx_suzuran_wisp`、`proj_suzuran_bigfox`、`fx_circle_gold`。

| 文件 | 尺寸 | 帧 | 层 | 用途 |
|---|---|---|---|---|
| `fx_suzuran_seal` | 20×10 | 6 帧 10fps 循环 | ground | 精一：被狐火灼印的敌人脚下金色小印 |
| `fx_suzuran_bigfox_trail` | 16×16 | 5 帧 12fps | front | 精二：大狐火身后一串逐个熄灭的小火 |

### 4.3 维什戴尔 · 精一「好礼」/ 精二「死魂灵的余息 + 魂灵开火」
参考色：`fx_wisadel_soul`、`fx_wisadel_mark`、`fx_wisadel_cannon`。

| 文件 | 尺寸 | 帧 | 层 | 用途 |
|---|---|---|---|---|
| `fx_wisadel_gift_mark` | 16×16 | 6 帧 10fps 循环 | front | 精一：炮击主目标直接挂上的残影标记（比现有 mark 多一圈礼花状缎带） |
| `fx_wisadel_soul_fire` | 同 `fx_wisadel_soul` | 5 帧 16fps，开火帧 2 | front | 精二：魂灵之影开炮（收缩 → 炮口喷暗紫烟） |
| `proj_wisadel_soul_shell` | 14×8 | 2 帧 20fps 循环 | front | 精二：魂灵之影的小号炮弹 |

### 4.4 塞雷娅 · 精一「钙化拳」/ 精二「莱茵充能护服 + 晶柱环」
参考色：`fx_saria_calcite`（琥珀 / 米白）。

| 文件 | 尺寸 | 帧 | 层 | 用途 |
|---|---|---|---|---|
| `fx_saria_amber_spot` | 12×12 | 4 帧 8fps（出现 → 淡出） | front | 精一：被拳击命中敌人身上的琥珀斑 |
| `fx_saria_pillar_rise` | 16×32 | 5 帧 20fps | 原点底边中点 | 精二：晶柱从地面拔起 |
| `fx_saria_pillar_idle` | 16×32 | 4 帧 6fps 循环 | 原点底边中点 | 精二：晶柱站立时的微光（阻挡敌人的 2 秒） |
| `fx_saria_pillar_break` | 32×32 | 6 帧 18fps | front | 精二：晶柱碎裂 |

---

## 第 5 批（浊心斯卡蒂，召唤物帧条**必需**；实现先用 Boss 帧条缩小占位）

### 5.1 浊心斯卡蒂 · 精一「余音」/ 精二「远古血亲」
参考色：`fx_skalter_*`、`fx_skalter_vortex_floor`（低饱和青 + 少量暗红）。海嗣用**伊莎玛拉**的形象（结局三「息潮的代价」Boss，本作 `ishar`，参考 `art/incoming/e_ishar.png` / `e_ishar_move.png` / `e_ishar_attack.png`，单帧 80×80），与浊心斯卡蒂立绘一致：按 `e_ishar` 造型缩画到召唤物尺寸，**保留原设计和配色**，只在外轮廓加一圈青色友方描光（在 `#080E18` 外描边之内或之外由 Codex 定，manifest 写明）以区分敌我。

| 文件 | 尺寸 | 帧 | 层 | 用途 |
|---|---|---|---|---|
| `fx_skalter_echo_ring` | 160×88 | 5 帧 14fps | ground | 精一：声浪扩散完外圈留下的淡回声环（比声浪更细更淡，停 0.3 秒） |
| `op_skalter_ishar_idle` | 召唤物帧条 48×48 | 4 帧 4fps 循环 | — | 精二：伊莎玛拉待机（漂浮、肢体缓摆） |
| `op_skalter_ishar_move` | 48×48 | 6 帧 10fps 循环 | — | 精二：伊莎玛拉移动 |
| `op_skalter_ishar_attack` | 48×48 | 4 帧 10fps，出手帧 2 | — | 精二：伊莎玛拉发声（张开 → 声波），末帧接 idle f0 |
| `op_skalter_ishar_summon` | 48×48 | 6 帧 12fps | — | 精二：伊莎玛拉从地面水纹中浮现 |
| `fx_skalter_seaborn_zone` | 160×88 | 8 帧 10fps 循环 | ground | 精二：海嗣的第二个小歌域（同 vortex 风格、小一号、更淡） |

---

## 6. 优先级与节奏

- **优先项（声浪重做）最先交**，独立于精英化；之后按批交付，**第 1 批先交**（Claude 实现顺序同 docs/91 §19）；每批内部先交「精二」项，再交「精一」项。
- 人物 / 召唤物帧条（`op_*`）的返修成本最高，按 docs/87 自检后再交；特效类可以先交一版，Claude 接入后看效果再提返修。
- 第 5 批的伊莎玛拉召唤物帧条是必需项；实现先用 `e_ishar*` 缩小占位，正式帧条到了替换（占位版能否发版由用户审画面定）。

合计：优先项 2 条；第 1 批 25 条、第 2 批 20 条、第 3 批 17 条、第 4 批 12 条、第 5 批 6 条，精英化 5 批共 80 条；连优先项共 82 条（含 11 条人物 / 召唤物帧条；`_1/_2/_3`、`_t1/_t2/_t3`、`_open/_close` 各按多条算，`fx_mon3tr_afterimage` 剪影按特效算）。
