# 236 敌方 / Boss 攻击特效盘点 + pixelfx 试点（11-02 起，组 E）

用户 11-02 定：敌方 / Boss 攻击特效改用 pixelfx 自写（不用库模板；技能 `.claude/skills/pixelfx`，库在 `<主仓库>/build/pixelfx`）。怪物本体精灵不归 pixelfx。
本稿是 docs/229 §9 的 **E 组**：按 docs/229 §0 / §4 的硬数字（危险色 #ff2667、Boss #ff6726、20 fps、主体 ≤ 0.4 s + 余韵 ≤ 0.4 s / alpha ≤ 0.4、
本体 + glow 单条 ≤ 14 KB、本组 ≤ 200 KB、32 色调色板、近白 ≤ 12%、末帧空、落点 = 判定半径、预警由程序画且 = 判定前摇），
用户 11-02「整套替换，不留旧帧条」，盘点基准是 docs/237 §5（`tools/fx_coverage.py` 生成，59 项）+ §6 动态拼名。

## 0 结论先看

- **11-03 整套替换完成（§4）**：docs/237 §5 全部 62 行（59 项 + 新增的分尺寸帧条）覆盖率 **62 / 62（100%）**：52 行换成 pixelfx 自写的 `fx_e_px_*` / `proj_e_px_*`，10 行登记「不换」并写理由（5 个死分支、3 个扫描误抓的变量名、2 个公共击杀件，见 §4.4）。
- **两个缺图 bug 已修**：浮海飘航者神经弹、固海凿石者碎石弹的 `hit_fx` 现在有图（`fx_e_px_nerve_hit` / `fx_e_px_rock_hit`），命中不再空白（§4.3）。
- **包体**：236 个 PNG（含 _glow 与变体）合计 **334 KB**，导入后 .ctex **272 KB**；单条（本体 + glow）全部 ≤ 14 KB（最大 11.3 KB）。
- **硬数字自检全过**（`python tools/pixelfx_fx/foe/audit_e.py`，§4.5）；判定、伤害、预警一行不动。
- 帧时按 docs/229 §9 免测；对照录像按组长「统一录」不自录，录制参数见 §5。
- 11-02 试点（卡门砸击、斥亡体迸发）与前 8 名盘点见 §1–§3，口径不变。

## 1 盘点

### 1.1 主路径

- 预警结算统一走 `enemies/telegraph.gd _resolve`（281–584 行），按招式往 `g.fx` 追加 kind，`render/world.gd _draw_fx`（1295–1840 行）画。
- Boss 结算另走 `warn_resolve`（telegraph.gd:268）：新追加的特效打 `bfx` 标记，矢量形状（ring / explode / quake / bslash / rays / tracer / wpillar）降到 0.45 透明、上面叠 CPU 颗粒（world.gd `_bfx_grains`）；圆形预警结算时再播一次 `bullet_fx.ground_burst`（`fx_px_burst1/2@2x`，8 帧 × 360²）。
- 帧条特效走 `vfx.fx_sprite`，图缺时返回 false、调用点走程序兜底。**下面 24 个已登记的帧条没有 png，全在走兜底**：
  `fx_runner_blast` `fx_slider_dash` `fx_reaper_scythe` `fx_tracer_thrust(_enraged)` `fx_nest_sweep` `fx_mimic_bite` `fx_rock_hit` `fx_nerve_hit` `fx_saint_shell_burst`
  `fx_carmen_smash` `fx_immortal_burst` `fx_paranoia_stack` `fx_paranoia_gaze_hit` `fx_paranoia_howl` `fx_izumik_share` `fx_archon_breath` `fx_knight_frost_burst` `fx_knight_thrust`
  `fx_ishar_maw_red` `fx_ishar_line_muzzle` `fx_path_fractal_rise` `fx_saint_scatter` `fx_saint_clear_ring` `fx_path_correct_ring`。
  这些槽位接口已经在（名字、调用点、锚点），**补一张 pixelfx 帧条就能上，不用改判定**，是换装成本最低的一批。
- **Bug（未修，另案）**：浮海飘航者神经弹、固海凿石者碎石弹带着 `hit_fx`（`fx_nerve_hit` / `fx_rock_hit`）但图缺；`bullet_fx._die`（235 行）只要 `hit_fx != ""` 就跳过通用命中，所以这两种弹**命中时什么都不画**。

### 1.2 全表

粗糙度 1–5（5 最粗糙）。「频率」按局内实际出现估。

| # | 特效 | 画在 / 触发 | 现做法 / 贴图 | 尺寸 · 时长 · 频率 | 粗糙 | 备注 |
|---|---|---|---|---|---|---|
| 1 | 通用 `ring` | world.gd:1464 / 约 60 处 | 两道 `draw_arc`（r 与 r−6）淡出 | r 18–300 · 0.3–1.5 s · 极高 | 5 | **同心圈**；几乎每个 Boss 招 / 精英事件都带 |
| 2 | `explode` 兜底 | world.gd:1549 / enemy_ai:191、telegraph:411/452/514/527、shot_pool:36 | 平涂圆 + 亮芯圆 + 环 | r 46–120 · 0.3–0.4 s · 高 | 5 | 斥亡体迸发、轰击、泡影叠影、狂奔者自爆、巢涌脉冲、抛物落地都落到这里 |
| 3 | `rays` | world.gd:1822 / telegraph:365、bishop:81 | 16 条等距直线；bfx 再加 20 颗放射颗粒 | 30–250 px · 0.25–0.5 s · 400 秒后每只怪的追加齐射 | 4 | **规整放射** |
| 4 | `quake` 兜底 | world.gd:1750 / telegraph:444 | 9 条等距线 + 椭圆环 | r≈135 · 0.6 s · 少（塑路者 / 奠基者已走地裂） | 3 | 规整放射 + 环 |
| 5 | `wpillar` | world.gd:1734 / telegraph:368/418、vfx:1064 | 两个 `draw_rect` + 椭圆环 | r 40–64 · 0.5 s | 3 | 矩形水柱 |
| 6 | `bslash` 扇形横扫 | world.gd:1762 / telegraph:482/577 | 三道套叠 `draw_arc` | r 90–300 · 0.3 s · 高 | 3 | 同心弧带 |
| 7 | `gcrack` 地裂 | ground_crack.gd / telegraph:441/495/526/557 | `tb_poly` 楔形 + 坑，热芯先冷 | r 60–170 · 0.6–0.9 s | 1 | 不规则分叉，**已合口径**；卡门砸击原来用金色（我方色系），本次试点替掉 |
| 8 | 精英 / 奠基者冲击环 | world.gd:2059 `_draw_shock` | 四道叠弧（填充 / 黑 / 色 / 白） | 扩到 r 135 | 3 | 判定前沿，要保留可读，可换颗粒带 |
| 9 | Boss 冲击环（大群之歌 / 震地 / 跃击） | boss_beam.gd:407 `draw_song` | 断续颗粒带 + 3 尾带 + 4 内波纹 | 到 600 px · 2–3 s | 2 | 风格化，但仍是同心波纹带 |
| 10 | Boss 圆形结算落地迸散 | bullet_fx.gd:327 | `fx_px_burst1/2@2x` 2880×360（8 帧） | 2.2 r · 0.9 s · 每次 Boss 圆形结算 | 2 | 预烘颗粒，可用 |
| 11 | Boss 弹迸散 | bullet_fx.gd:509 / `_die`:240 | `fx_px_bpop@2x` 160×60 | ≈40 px · 0.45 s · 极高 | 1 | 可用 |
| 12 | Boss 弹拖尾 | bullet_fx.gd:468 | `fx_px_btrail@2x` 64×9（4 帧） | 持续 | 1 | 可用 |
| 13 | 普通弹命中 | bullet_fx.gd:552 / `_die`:251 | 白 `tb_circle` + 细 `tb_ring` + 3–8 颗粒 | r 3–14 · 0.1 s · 最高 | 4 | 平涂圆 + 细环 |
| 14 | 普通弹消散 | bullet_fx.gd:555–561 | 缩小圆（溶解再加环） | 0.12–0.16 s | 3 | 平淡 |
| 15 | 环形齐射发射口 | bullet_fx.gd:562 / flush:277 | 一道 `tb_ring` + 白点 | r 12–40 · 0.12 s · 每次 nova | 4 | 单圈淡出 |
| 16 | 弹体出生闪 | bullet_fx.gd:538 | 两个圆 | 0.09 s · 每颗弹 | 2 | 小 |
| 17 | Boss 激光边颗粒 / 收束碎裂 | bullet_fx.gd:395 / world:1329 | `fx_px_bpop` 每 22 px 一格 | ≤0.25 s | 1 | 可用 |
| 18 | `kp_beam` Boss 激光 | boss_beam.gd:63 / telegraph:461/599 | Kanpelle 帧条 `fx_kp_<boss>_{src,mid,hit}` 64×48 | 320–1100 px · 0.25 s | 1 | 可用 |
| 19 | `bbeam` / `tracer` 兜底光束 + 端点闪 | laser_draw.gd:31 | 三条线 + 菱形端点 | 0.22–0.35 s | 3 | 端点太小 |
| 20 | 中期卡光束收尾 | mid_card_draw.gd:153 | 12 px 方块按固定顺序消失 | 0.25 s | 3 | 拼接感 |
| 21 | 卡门火线淡出 + 余烬 | saint_draw.gd:68/42 | 分段折线；余烬 = 两圆 + 弧 | 18 px 段 | 3 | 余烬平涂 |
| 22 | 伊莎玛拉统一激光 | ishar_tell_draw.gd:46/96 | 多边形 + `_dot`（三重同心圆） | 0.35 s + 停留 | 3 | 端点同心 |
| 23 | 伊莎玛拉歌声区 | ishar_tell_draw.gd:67 | 填充椭圆 + 每 0.6 s 两道虚线环外扩 | 持续 | 3 | **同心波纹** |
| 24 | Boss 每招签名 | vfx.gd:1035 | 库存帧条 ×2（枪口焰 / 法阵 / 水花 / 爪…）+ r40 环 | 0.3 s · 每个 Boss 招 | 4 | 环 + 小号杂牌帧条，风格不统一 |
| 25 | 图案招（劈 / 线 / 雨 / 缺省） | vfx.gd:1050 / boss_patterns | 刀光帧条 / tracer / wpillar + 水花 ×2.5 / 环 | 0.3–0.5 s | 3 | 缺省分支只有环 |
| 26 | 轰击落点（伊比利亚 / 卡门） | telegraph:408 | `explode` + **1.5 秒环** + 16 火花 + 落地迸散 | r 38–80 | 4 | 长挂的平环 |
| 27 | 轰击炮弹飞行 | world.gd:1624 / saint:273 | 缺 `proj_saint_shell` → 两个圆 + 影子 | 每发 | 4 | 圆球 |
| 28 | 塑路者长枪回旋 | telegraph:393 | 8 个 `fx_slash_heavy_steel` 按 45° 等距 + 环 | r 70 · 0.3 s | 3 | **规整放射** |
| 29 | 骑士「寒冷」 | world.gd:3324 / telegraph:424 | 环 + 10 个 `fx_knight_impact` 按 36° 等距；冰场 = 圆 + 弧 + 6 条旋转辐条 | r≈200 · 0.6 s；冰场 6 s | 4 | **时钟阵 + 辐条** |
| 30 | 骑士冲锋落点 / 咬 | world.gd:3306–3323 | `fx_knight_impact` 192×48 + 刀光 | 每次冲锋 | 2 | 可用 |
| 31 | 骑士冰面 | boss_attack_draw.gd:559 | `tb_quad` 条 + 高光 + 冰裂 | 0.9–3 s | 1 | 好 |
| 32 | 骑士撞柱 | boss_attack_draw.gd:624 | 20 楔圆盘 + 8 条抖动裂纹 + 冰颗粒 | r 46/110 | 2 | 接近放射 |
| 33 | 骑士终局招 | final_boss_materials.gd / final_attack_grains.gd | 程序材质 + `fx_knight_ice_hit` 384×32 | — | 2 | 可用 |
| 34 | 骑士重生 | knight_boss:245/570 | `fx_knight_rebirth` 320×80 | 一次 | 2 | 可用 |
| 35 | 伊祖米克震撼浪 | izumik_attack_draw.gd:105 | quad 浪体 + 浪尖 + 泡沫 | 到 1000 px | 1 | 好 |
| 36 | 伊祖米克分享喷涌 | izumik_attack_draw.gd:254 | 16 条均布喷流 + 雾点 | r 200–300 | 3 | 均布扇 |
| 37 | 伊祖米克漩涡预警 / 爆发 | izumik_attack_draw.gd:288/340 | 6 层同心椭圆 + 螺旋点；爆发 6 臂 + 柱 | 0.95 s | 4 | **6 层同心** |
| 38 | 伊祖米克触腕 / 潮墙 | izumik_attack_draw.gd:187/145 | `_seg` / quad | — | 1 | 好 |
| 39 | 泡影气泡破裂 | paranoia_bubble.gd:65 | 11 个 2 px 方块（黄金角） | — | 3 | 稀 |
| 40 | Boss 换幕 | world.gd:1786 / :341 | 两道外扩环 + **12 条等距光刺** | ≈6 r · 0.9 s | 5 | 环 + 放射，两条禁令都犯 |
| 41 | Boss 倒下 | world.gd:1801 / :350 | 闪光圆 + **三道同心环** + 矩形光柱 | 1.6 s | 5 | 高潮时刻最粗糙 |
| 42 | 育母投掷 / 拟嗣落地 | enemy_ai:481 / shot_pool:60 | `fx_mother_throw@2x`、`fx_brood_land@2x` + 环 + 火花 | ≈0.43 s | 2 | 帧条好，洋红环粗 |
| 43 | 喷吐者酸落点 / 侵蚀命中 | shot_pool:34/263/279 | `fx_spitter_land@2x`、`fx_acid_splash@2x`、`fx_corrode_hit(_acid)@2x` | 0.3–0.4 s | 1 | 可用 |
| 44 | 囊海爬行者破膜 | world.gd:2517/2528 / enemies.gd:529 | `fx_pocket_burst_back/front@2x` + 残液 + r160 环 | 0.375 s | 2 | 帧条好，大平环 |
| 45 | 漂移体枪口 / 滑动者冲刺 / 收割·引痕·巢涌·箱形攻击 / 收割者光环 | enemy_ai:448/345、telegraph:606、enemy_ai:233 | 只有漂移体枪口有图；其余兜底 bslash / tracer / explode；光环每 0.9 s 一道 r90 环 | 高 | 3 | 光环 = 定时平环 |

### 1.3 最值得先换的前 8

排序按「违反口径 × 出现频率 × 画面占比」，同分时看换装成本（缺图槽位优先，接口现成）。

| 名次 | 对象 | 为什么 | 建议做法 |
|---|---|---|---|
| 1 | `explode` 兜底（#2；斥亡体迸发、轰击、泡影叠影、狂奔者自爆、巢涌脉冲、抛物落地） | 平涂圆 + 环，至少 6 个招落到这里；缺图槽位，接口现成 | 本稿试点已换斥亡体；其余按招式 r 各导一张 pixelfx（爆闪 → 冷却 → 碎屑，按酸 / 炮 / 泡影分色），**每招按自己的 r 导出** |
| 2 | 通用 `ring`（#1，约 60 处） | 同心圈本体，几乎每个 Boss 招都带一道 | 不逐个换：直接删掉做装饰用的环（判定前沿已有冲击环 / 预警），只留读判定必需的；必需的换成断续颗粒带 |
| 3 | Boss 换幕（#40） | 外扩环 + 12 条等距光刺，两条禁令都犯；每场 1–3 次、全屏注目 | 一张 pixelfx：不规则裂网从本体爬出 + 首帧爆亮冷却 + 本体脚下尘墙隆起，Boss 专属色只做描边 |
| 4 | Boss 倒下（#41） | 三道同心环 + 矩形光柱，高潮时刻 | pixelfx：本体崩解成碎块下落 + 地面裂网 + 余震两次，时长 1.5 s |
| 5 | `rays`（#3） | 16 条等距直线；400 秒后每只怪的追加齐射都会放，后期满屏 | 换成 3–5 条不等长、不等距的短火舌小帧条（≤ 24×24），或直接只留弹体出生闪 |
| 6 | 骑士「寒冷」（#29） | 10 个冲击帧条按 36° 排成时钟 + 冰场 6 条旋转辐条 | 冰裂网（不规则）+ 冰棱随机簇；冰场辐条去掉，改冰面高光 |
| 7 | 轰击落点 + 炮弹（#26/#27） | 炮弹是两个圆；落点留 1.5 秒平环；缺 `fx_saint_shell_burst` / `proj_saint_shell` | 落点：同本稿砸地按 r 80 / 38 导出，火光改危险色冷却；炮弹另补小帧条 |
| 8 | 普通弹命中 / 消散 / 齐射口（#13–#15） | 全游戏出现最频繁的敌方画面，全是平涂圆 + 细环；**另有神经弹 / 碎石弹命中无画面的 bug** | 一张 ≤ 16×16、4 帧的通用溅射帧条按弹色着色；先修 `hit_fx` 缺图时回落通用命中 |

### 1.4 对齐 docs/237 §5（59 项 + 动态拼名）的去向

按「整套替换」口径分五类。「换」= 本组用 pixelfx 新出 `fx_e_px_*`（按各招判定半径导出），旧名对应的图删掉或不再引用。

| 类 | 项（docs/237 §5 原名） | 数 | 去向 |
|---|---|---|---|
| 已做 | `fx_e_px_carmen_smash`、`fx_e_px_immortal_burst`（原 `fx_carmen_smash` / `fx_immortal_burst`，缺图） | 2 | 本稿试点 |
| 扫描误抓 | `boss_patterns|fx_col`、`boss_patterns|fx_scale`、`bullet_fx|fx_col` | 3 | 不是贴图，登记「不换」 |
| 缺图槽位（现在走程序兜底，补图即上） | `fx_runner_blast` `fx_slider_dash` `fx_reaper_scythe` `fx_tracer_thrust(_enraged)` `fx_nest_sweep` `fx_mimic_bite` `fx_rock_hit` `fx_nerve_hit` `fx_saint_shell_burst` `fx_saint_scatter` `fx_saint_clear_ring`（carmen / iberia 两行） `fx_path_correct_ring` `fx_path_fractal_rise` `fx_bishop_wave` `fx_paranoia_stack` `fx_paranoia_gaze_hit` `fx_paranoia_howl` `fx_izumik_share` `fx_archon_breath` `fx_knight_frost_burst` `fx_knight_thrust` `fx_ishar_line_muzzle` `fx_ishar_maw_red` `proj_offspring_spore` | 26 | 换。第一批：轰击 `fx_saint_shell_burst`（r 80 / 38，同砸地写法）、`fx_runner_blast`、`fx_rock_hit` / `fx_nerve_hit`（顺带修 §1.1 无画面 bug，要改 bullet_fx 回落，提给组长） |
| 已有旧帧条（Codex / 库存，整套替换要重画） | `fx_mother_throw` `fx_brood_land` `fx_acid_splash` `fx_corrode_hit` `fx_corrode_hit_acid` `fx_skimmer_muzzle` `fx_spitter_land` `fx_pocket_burst`（back / front）`fx_pocket_puddle` `fx_knight_impact` `fx_knight_rebirth` `fx_knight_ice_hit`（两处）`fx_knight_crystal_rise/hold/break` `fx_knight_ice_crest` `fx_knight_ice_wall` `fx_water_splash`（telegraph 两处）`fx_slash_heavy_steel`（长枪回旋，现为 45° 等距，§1.2 #28） | 20 | 换。docs/229 §4 的前 3（育母落点、喷吐落点、囊海破膜）优先 |
| 弹体 / 公共预烘颗粒 | `proj_skimmer_corrode` `proj_spitter_acid` `proj_knight_ice` `proj_knight_spear`；`fx_px_bpop` `fx_px_btrail` `fx_px_burst1` `fx_px_burst2`（docs/206 pxburst 预烘，Boss 弹迸散 / 拖尾 / 落地迸散） | 8 | 待组长定：弹体是否算「特效」（docs/229 §2.5 有弹道档，按它就换成 ≤ 4 帧循环、敌弹色 #33ceff）；`fx_px_*` 是程序着色的颗粒预烘、已合口径，倾向登记「不换：预烘颗粒，按弹色程序着色」 |

**§6 动态拼名 `fx_kp_%s_{src,mid,hit}[_on]`**（render/boss_beam.gd:79–81，Kanpelle 激光）手查结果：现有 6 只 Boss × 3 段 × 2（常亮 / `_on`）= 36 张：
archon、bishop、carmen、iberia、ishar、paranoia。激光是长条拼接件、按线长平铺，pixelfx 重画要保持三段接口（源 / 中段可平铺 / 命中）。
归入「已有旧帧条」一类，数量另计（不在 59 项内）；排在缺图槽位之后。

## 2 试点：`impacts/ak-e-slam`

### 2.1 选谁、为什么

首选 Boss 砸地 / 裂地类。塑路者震地已经是不规则地裂 + Boss 冲击颗粒带，基本合口径；最差的两个砸地类都是**缺图在走兜底**：

- 卡门「炮身砸击」（`act: smash`，r 70）：原画面 = **金色**地裂 + 暖金火花（我方灯火色系）。
- 斥亡体「迸发」（`act: erupt`，r 120，自身为心）：原画面 = `explode` 平涂圆 + 亮芯 + 环，火花是海嗣青。

### 2.2 画法（`tools/pixelfx_fx/impacts/ak-e-slam.js`）

俯视 3/4 地面，判定圈 = R × R·0.55 的地面椭圆（与游戏 `ground_y` 同）。色取 house.js：普通敌方 `DANGER_RAMP`，`opts.boss = 1` 用 Boss 色 #ff6726 的同构 7 阶（house.js 只给了单色，阶数照 DANGER_RAMP 的明度比例）。尘土 = 色阶暗阶混中性灰，不用深海青、不用我方色阶。

| 拍 | 时间 | 画面 |
|---|---|---|
| 爆亮 | 第 0–1 帧 | 不规则热团（9–12 顶点、半径抖动 0.55–1.3，0.46 R），**白只在核心**（× 0.4）；第 1 帧缩到 0.34 R、只留一小点白芯；热裂同帧长到 60% |
| 冷却 | 0–0.35 s | house.js `heat(t)`：白 → 浅 → 设定色 → 暗阶，逐级实色 |
| 裂网 | 0–0.4 s | 4–6 条主裂，角度随机且两两 ≥ 0.6 弧度，长 0.45–0.95 R，各 0–2 个分叉；**不等距、不等长** |
| 尘墙 | 0–0.2 s 推出，0.2–0.4 s 缓入淡出 | 尘团沿圈**随机步进**（步长 0.45–1.7 倍均值）、大小随机游走（2.2–6.2 纹素，15% 大团 × 1.3–1.6）、半径 0.78–1.0 R、近厚远薄、顶亮底暗、2–3 个断口；每团外沿钳在 R 以内：**外沿 = 判定半径、不超** |
| 碎石 | 0–0.4 s | 12 块，地面影子 + 抬高石块，落地弹一次 |
| 余震 | 0.2 s、0.3 s | 热裂根部回热 + 尘墙整圈抖 1 纹素 + 坑内小尘团 |
| 余韵 | 0.4 s 起 | 只剩尘墙沉降：每团一层、单层 ≤ 0.12 × `TAIL_ALPHA`（尘团扎堆最多叠约 8 层，合成后 ≤ 0.4），卡门 0.32 s、斥亡体 0.24 s；末帧近空（最大 alpha ≤ 0.07） |
| 光晕 | 0–0.2 s | 两盏灯（设定色 k 0.45、白 k 0.7 半径 0.45 R），单独导出成 `_glow` 条，加色层叠画 |

### 2.3 导出与接入

```bash
python tools/pixelfx_export.py --lib <主仓库>/build/pixelfx --only fx_e_px_carmen_smash,fx_e_px_immortal_burst
```

| 贴图（各 3 个变体：本名 / `_v1` / `_v2`） | 帧 × 单帧 | fps | 色数 | 本体 + glow（PNG，三个变体） | .ctex 合计 | 尘墙外沿 / 判定 | 近白 |
|---|---|---|---|---|---|---|---|
| `fx_e_px_carmen_smash` | 13 × 70×52–56 | 20 | 32 | 7.5 / 7.3 / 8.2 KB | 20.5 KB | 69 / 70 | ≤ 0.3% |
| `fx_e_px_immortal_burst` | 12 × 120×72–80 | 20 | 20 | 11.0 / 10.9 / 12.5 KB | 28.9 KB | 119 / 120 | ≤ 0.5% |

斥亡体 R 60 半透明尘多，32 色时单条 20.6 KB：按 docs/229 §2.9 的顺序先收短余韵（0.32 → 0.24 s）、关墙后内尘（`inner: 0`），再降到 20 色，才进 14 KB。
帧条以落点为中心对称裁边，宽度正好 = 2r / 2 纹素（70 / 120），即水平外沿不超出判定。

代码改动（只改帧条和调用参数，判定不动）：
- `art.gd` 组 E 块登记 12 个名字（2 招 × 3 变体 × 本体 / glow）；原 `fx_carmen_smash` / `fx_immortal_burst` 两行恢复原值（不再引用）。火星没写进第 3 项：调用点原本就有 `vfx.sparks`，只把颜色改成 Boss 色系。
- `telegraph.gd` smash：有图时只播 `fx_e_px_carmen_smash`（`Game.PX`、地面层、居中 = 落点），**不再叠金色地裂**；缺图照旧地裂。火花改 Boss 色系。
- `telegraph.gd` erupt：改播 `fx_e_px_immortal_burst`，缩放由 `PX × r / 60` 改为固定 `PX`；火花改 Boss 色系。
- `.import` 的 `process/fix_alpha_border` 改 false（docs/229 §10）。`game/art/index.json` 不提交（合并人跑 `python tools/asset_index.py`）。
- `autotest.gd`（调试开关）：`--bossmoves` 加 `--shotstep=N` 逐帧截图（`shot_bmframe_*`）与 `--perfab` 帧时输出（`BOSSMOVES PERF`），供逐招前后对照。

**按每招 r 单独导出、固定 `Game.PX`** 的原因：地面帧条在光学低分辨率层会被 `vfx.int_scale` 取整到 2 的倍数（`render/fx_int_scale`），按 `w.r` 连续缩放的话 r 70 / r 120 都会取整成 r 88，尘墙外沿对不上判定。1 纹素 = 2 世界像素，密度正好 2.0（§0 要求 1.6–2.2）。

## 3 验证

### 3.1 同 seed

- TRACE：seed 13、德克萨斯 + 能天使 + 拉普兰德、`--balance --bot=expert --maxt=660 --trace=1`，改前（c73d2ff86 独立检出）与改后：**512 行 TRACE 全同**；末行 BALANCE 只差 `bot/peak` 的 g.fx 数、飘字数峰值（纯画面计数）。这局没有卡门 / 斥亡体出场，只证明没有动到模拟。
- 逐招：`--bossmoves=carmen2 / immortal --bossonly=…`（seed 1），改前改后 BOSSMOVES 日志行对照见 §3.4。

### 3.2 帧时

**本组免测**：docs/229 §9 第 5 条（用户 11-02「等所有美术都做完了再测」），由组长在全部美术合完后统一测。
按画法：每次结算 1 次贴图绘制 + 1 次加色层光晕，不新增逐像素运算；`autotest --bossmoves --perfab` 已能打 `BOSSMOVES PERF`，统一测时可直接用。

### 3.3 包体

调色板 PNG +57.3 KB（含 3 个变体与 glow），导入后 .ctex +48.5 KB（≈ 0.047 MiB）。组 E 额度 200 KB 已用 57.3 KB（29%）。
网页包 b0343aca1 后约 44.47 MiB、预算 44.5；总增量按 docs/229 §0 由音频腾出的 1.39 MiB 补（组长前置任务），本组不另腾。

### 3.4 对照录像与预警 = 判定

录制：`python tools/pixelfx_fx/foe/rec_moves.py carmen2:炮身砸击,炮身砸击 immortal:迸发,迸发`（`--bossmoves`、seed 1、`--fixed-fps 30` 每帧截图，原速；卡门要 `carmen2` 才放得出砸击）。
改前 = c73d2ff86 独立检出（build/_fx_before，只多了同一份 autotest 截图开关），改后 = 本分支。两局 BOSSMOVES 日志行逐行相同。

| 产物（`Claude outputs/fx_enemy_pilot/`） | 内容 |
|---|---|
| `fx_e_slam_compare.mp4`（8.9 MB，15.7 秒） | 左旧右新，1:1 像素裁 640×360，30 帧原速；卡门两次砸击 + 斥亡体两次迸发 |
| `_peak_carmen2.png` / `_peak_immortal.png` | 每段新旧差异最大的一帧并排 |
| `warn_proof_carmen2.png` / `warn_proof_immortal.png` + `warn_proof.txt` | 预警 = 判定：结算前 1 帧（预警圈画满）、结算 +6 帧（0.2 秒尘墙推满）、两者 50% 叠合 |

**预警 = 判定的依据**（按可信度排）：
1. **构造上一致**：预警圈、判定、帧条都用同一个 `w.pos` / `w.r`（telegraph.gd `_resolve` 里 `fx_sprite(..., w.pos, Game.PX, ...)`）；帧条按 R = r / 2 纹素导出、以落点为中心对称裁边，固定 `Game.PX` 画（不受 `int_scale` 取整影响）。
2. **帧条离线实测**：尘墙水平外沿 69 / 119 世界像素（判定 70 / 120），各变体、各帧都不超（§2.3）。
3. **录像目视**：叠合图里尘墙左右边界与预警圈重合（斥亡体第 1 次：预警中心 (580, 386) 半宽 100 屏幕像素，尘墙 (573, 395) 半宽 93）。
   这些屏幕量测只作佐证：卡门那段在结算前后镜头有跟随移动（地上虚线下移约 30 屏幕像素），脚本的平移估计没能补上；预警圈的红色掩码有时会混进血条、火线，个别行（卡门第 2 次、斥亡体第 3 次）数字偏差大，不采信。

**vreview（ult_fx，3 次表决，--crop right 审新版）**：先改 → 已改，第二轮结论如下。
- 第一轮 2 高：①尘墙尘团等距排列有拼接感（属实：角度只抖 ±0.07 弧度）→ 改成随机步进 + 大小随机游走；②首帧爆亮偏弱 → 热团 0.36 → 0.46 R、第 1 帧留白芯、白光 k 0.45 → 0.7。
- 第二轮 1 高 1 中：拼接感（3/3，说的是「完全相同的矩形色块等距排列」）、力量感（1/3，中）。**判断为误报 / 不归本次**：同一段用 `--crop left` 审旧版也报了同样的「矩形贴图等距排列」（旧版另有力量感高项）。新旧两边共有、成片方块感的是 Boss 圆形结算都会播的落地迸散预烘颗粒 `fx_px_burst1/2`（docs/206，§1.4 末行待组长定是否替换），本次帧条已逐帧检查没有等距重复。
- 探针：近白最高 1%。花费：四次共约 0.05 美元。

**待组长定（vfx.gd 不归本组改）**：88c92cb8a 的 `px_vary` 会对 `fx_e_px_*` 随机做 fy = -1（沿朝向轴镜像）和 ±0.1 弧度转角。对俯视地面落点类：镜像后尘墙往下长、远近透视颠倒；转角让外沿偏离判定椭圆（r 120 约 5 像素）。已发消息请组长给地面帧条（`ground = true`）免掉镜像 / 转角，或在 V6_FRAMES 第 3 项加「不变形」标记。本次录像里两种情况都会随机出现。

## 4 整套替换（11-03）

组长 11-03 定：做满 docs/237 §5；敌方弹体 4 项、Boss 弹迸散 / 拖尾（`fx_px_bpop` / `fx_px_btrail`）归组 E；`fx_px_burst1/2` 是公共击杀件，登记不换；对照录像最后统一录。
地面免镜像 / 转角由组长在 660d61d22 改好（`fx_e_px_*` 与地面帧条只挑变体）。

### 4.1 公共写法（`tools/pixelfx_fx/**/ak-e-*.js`）

| 源 | 写法 | 用在 |
|---|---|---|
| `impacts/ak-e-slam.js` | 砸地：爆亮 → 热裂 → 尘墙推到判定半径 → 碎石 / 余震；`cracks / rocks / core = 0` 时只留一道尘浪（环形脉冲） | 卡门砸击、斥亡体迸发、轰击落点（r80 / r38）、狂奔者自爆、出环 / 订正环（伊比利亚 / 卡门 / 塑路者）、骑士重生 |
| `impacts/ak-e-hit.js` | 命中 / 小溅射：不规则热团 + 四种材质（shard 碎片、goo 液滴落地成渍、nerve 短分叉电弧、grit 碎石 + 尘）；`dir` 定向、`half` 前后分层、`ramp: grey` 给代码着色 | 各类 hit_fx、酸溅、落点、出手口、凝视命中、碎冰迸溅、水花、泡影叠影、Boss 弹迸散 |
| `impacts/ak-e-sac.js` | 同 hit 的 goo，只换画布（囊海破膜要锚点 0.7 高、前后两层） | 囊海破膜 |
| `melee/ak-e-swipe.js` | 扇形挥击（月牙铺满再从尾部收回）/ 咬合 / 直线突刺 / 扇形喷涌 | 收割者镰肢、巢涌横扫、箱形咬合、引痕突刺（含狂暴）、滑动者冲刺、伊莎玛拉撕咬、长枪回旋、散射、潮汐波、分享、呼号 |
| `projectiles/ak-e-proj.js` | 弹体循环（孢子 / 侵蚀弹 / 酸团 / 冰棱 / 拖尾），首尾无缝 | 子代孢子、漂移体侵蚀弹、喷吐者酸团、骑士冰棱弹 / 长枪、Boss 弹拖尾 |
| `impacts/ak-e-ice.js` | 骑士冰材质：晶簇 / 冰浪冠 / 冰墙 × 升起 / 持续（循环）/ 碎裂 | 骑士终局冰晶、冰浪、冰墙 |

色：普通敌方 `DANGER_RAMP`，Boss 招式 Boss 色 #ff6726 的同构 7 阶（`BOSS_RAMP`），代码着色件用中性灰阶。**骑士终局的冰也按规范改成 Boss 色阶**（原来是冷白冰蓝），这是看得见的风格变化，统一录像时请重点看。

### 4.2 导出

```bash
python tools/pixelfx_fx/foe/export_e.py     # targets_e.json → tools/pixelfx_export.py → 重写 art.gd 组 E 块 → asset_index → audit_e 自检
python tools/pixelfx_fx/foe/fixed_e.py      # 代码写死帧数 / 网格 / 画布的件（Boss 弹迸散 / 拖尾、囊海破膜、骑士冰材质）
```

- 每招按最终尺寸导出、固定 `Game.PX` 画（普通 / 地面帧条都会被 `vfx.int_scale` 取整成 2 的倍数，连续缩放对不上判定）；锚点 = 帧中心（导出以原点对称裁边）。
- 通过 `fx_sprite` 播的件各 3 个种子变体（滑动者冲刺 2 个）；弹体、Boss 弹迸散 / 拖尾、囊海、冰材质由代码直接取帧，只出 1 个（迸散的 3 个种子拼成网格的 3 行）。
- 火星没写进登记第 3 项：调用点原本就有 `vfx.sparks`，只把颜色改成 Boss / 危险色系。

### 4.3 调用点改动（只改帧条名和调用参数，判定不动）

- `enemies.json`：hit_fx / atk_fx / blast_fx / dash_fx / land_fx / burst_fx / puddle_fx / muzzle_fx / shot_tex / lob_tex / patterns.fx 换新名；`*_origin` 改 [-1, -1]（帧中心）；出招 fx 加 `fx_scale: 1.0`；去掉卡门出环的金色 `fx_col`。
- `telegraph.gd`：碎冰迸溅、水花、轰击（按 r 选大 / 小）、叠影、凝视命中、喷涌（按 r / 半角选，原点 = 扇心）、伊莎玛拉撕咬（原点 = 扇心）换新名、固定 PX；**长枪回旋**原来 8 把刀光按 45° 等距排成时钟（违反 §2.6），改成一道绕开缺口的整圈扫弧，缺图照旧程序刀光。
- `shot_pool.gd`：落点 / 酸溅 / 拟嗣落地以落点为中心（去掉旧条的偏心锚点和 bottom）。拟嗣落地不再把 e_brood 首帧嵌进末帧，帧条播完拟嗣本体直接出现。
- `enemy_ai.gd`（育母出手）、`knight_boss.gd`（重生、桩落点碎冰）、`final_attacks.gd`（冰刺尖端，不再 1.3 倍放大）、`bullet_fx.gd`（`POP` / `TRAIL` 常量）、`final_boss_materials.gd`（冰材质换名；冰棱弹由 3 倍放大改 Game.PX、按登记帧数取帧；冰墙去掉冷色 tint）、`tests/final_boss_materials_test.gd`（检查名单换新名）。
- **缺图 bug**：`bullet_fx._die` 只要弹带 hit_fx 就跳过公共命中画面；现在两种弹的 hit_fx 都有图，命中不再空白。`_die` 本身「图缺也跳过」的写法没改（bullet_fx 的公共逻辑，留给组长决定要不要加缺图回落）。
- **没改的同名调用**（不在 §5 名单里、属组长 / 公共文件）：world.gd 骑士 `_enemy_act_fx` 与 vfx.gd `BOSS_STYLE` 仍用 `fx_knight_impact` / `fx_water_splash`；world.gd `spear_fly` 仍用 `proj_knight_spear`。需要的话可以照 §4.3 换成 `fx_e_px_*`。

### 4.4 登记「不换」的 10 行（`tools/pixelfx_fx/coverage_e.json`）

| 行 | 理由 |
|---|---|
| `boss_patterns|fx_col`、`boss_patterns|fx_scale`、`bullet_fx|fx_col` | 变量名被扫描误抓，不是贴图 |
| `bullet_fx|fx_px_burst1/2` | 公共击杀件，组长 11-03 定不在本轮 |
| `telegraph|fx_archon_breath` | 死分支：蔑死体吐息带 kp，`_kp()` 恒真，帧条永远不画（吐息由 `fx_kp_archon_*` 画） |
| `telegraph|fx_ishar_line_muzzle` | 死分支：只在 `render/ishar_laser = 0` 时画，缺省 1 |
| `telegraph|fx_knight_frost_burst` | 死分支：没有招式建 act = frost 的预警 |
| `telegraph|fx_knight_thrust` | 死分支：`w.thrust` 从不设 |
| `telegraph|fx_path_fractal_rise` | 死分支：`spawn_after` 无数据 |

### 4.5 硬数字自检

`python tools/pixelfx_fx/foe/audit_e.py`：逐条（含变体）查体积（本体 + glow ≤ 14 KB）、调色板实用色数（≤ 32）、近白（≤ 12%）、余韵段最大 alpha（≤ 0.4，量化取整允许 0.41）、末帧、水平外沿。11-03 结果：**超标 0 条**；最大单条 11.3 KB（斥亡体迸发 _v2）；近白最高 9.2%（伊祖米克三叶扇 _v1，细流束占比高）；地面落点外沿均 ≤ 判定。
固定格式件（fixed_e.py）另计 13.5 KB，帧数 / 画布与代码一致（迸散 8 × 3、拖尾 4、囊海 6、晶簇 7 / 3 / 10、冰浪冠 11、冰墙 36）。
棋盘格：所有带 alpha 的点改用真半透明（`p.blend` / `p.disc`），没有抖动淡出。

## 5 统一录制参数（给组长批量录）

逐招 Boss（`python tools/pixelfx_fx/foe/rec_moves.py <spec>:<招>,<招> …`；`--bossmoves=<spec> --bossonly=<招> --shotstep=1`、seed 1、`--fixed-fps 30`）：

| 帧条 | spec | 招式名（demo_moves 里的原名） |
|---|---|---|
| carmen_smash、carmen_clear_ring | `carmen2`（砸击只在第二幕） | 炮身砸击、环射 |
| saint_shell_burst（r80）/ _s（r38）、iberia_clear_ring、saint_scatter | `iberia` | 轰击、三连曲射、清膛、散射 |
| immortal_burst | `immortal` | 迸发 |
| path_correct_ring、path_spin | `path` | 订正、长枪回旋 |
| paranoia_stack、paranoia_gaze_hit、paranoia_howl | `paranoia` | 叠影、凝视、呼号 |
| izumik_share（r300 半角 1.0）/ _n（三叶扇）/ _s（r200） | `izumik`（三叶扇要 `izumik2` 第三幕） | 分享 |
| ishar_maw | `ishar2`（濒死强化第 2 段才出镜像牙光） | 撕咬 |
| bishop_wave、water_splash | `bishop` / `bishop+archon` | 接潮扇浪、潮汐柱 |
| knight_impact、knight_rebirth、knight_ice_hit、冰晶 / 冰浪 / 冰墙 / 冰棱弹 / 长枪 | `knight_boss` / `knight_boss2` | 冰线、掷枪、长枪连刺、冲锋（重生在一阶段半血入潮时） |

普通怪（`python tools/probes/enemy_animation_capture.py --ids <id,…>`，录真实 AI 前 5 秒）：runner、slider、reaper、tracer（狂暴另录）、nest、mimic、floater、stone、spitter、mother、skimmer、pocket、offspring。

预警 = 判定的对照图：`python tools/pixelfx_fx/foe/warn_proof.py <输出目录> <tag> …`（读 rec_moves 的改前 / 改后截图）。

## 6 后续

- `bullet_fx._die` 缺图时也跳过公共命中的写法，建议组长加缺图回落（§4.3）。
- world.gd / vfx.gd 里同名旧条（骑士冲锋 / 咬 / 寒冷、Boss 签名、spear_fly）要不要也换，等组长定（§4.3 末）。
- 骑士终局冰改为 Boss 色阶是规范要求，但和原「冰」的识别有冲突，统一录像后请用户看。
- docs/226 的敌方顶层合入后，可以考虑把爆亮第 0 帧挪到顶层，保证不被我方特效盖住。
