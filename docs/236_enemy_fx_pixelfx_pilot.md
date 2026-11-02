# 236 敌方 / Boss 攻击特效盘点 + pixelfx 试点（11-02）

用户 11-02 定：敌方 / Boss 攻击特效改用 pixelfx 自写（不用库模板；技能 `.claude/skills/pixelfx`，库在 `<主仓库>/build/pixelfx`，评估见 docs/228）。怪物本体精灵不归 pixelfx。
敌方档口径（统一规范 docs/2xx_fx_style_spec 写好前先按这几条）：危险色用 balance.json `render/optical_col_danger`；预警形状与真实判定严格一致；可读性优先于华丽；
不与我方特效同色系（灯火金 `#F4C04E`、UI 青 `#36E2DC`）；不被我方特效盖住。力量感：不规整分叉裂网、首帧爆亮后冷却、隆起尘墙、预兆余震；禁止规整放射与同心圈。

本稿做了三件：§1 盘点全部敌方 / Boss 攻击特效并排出前 8；§2 两个试点（卡门「炮身砸击」、斥亡体「迸发」）；§3 对照录像、帧时、包体。

## 0 结论先看

- **前 8 名**（§1.3）：通用 `ring` 环、`explode` 兜底、Boss 换幕、Boss 倒下、`rays` 齐射放射线、骑士寒冷时钟阵、轰击落点、普通弹命中 / 消散 / 齐射口（含一处无画面 bug）。
- **试点已接进游戏**：两个原本缺图走兜底的槽位换成 pixelfx 自写的 `foe/slam-quake`。判定、伤害、预警都没动；同 seed TRACE 逐行相同（§3.1）。
- **包体 +27 KB**（导入后 .ctex 10.1 + 16.5 KB）。网页包现在贴着 44.5 MiB 预算，合入前要确认余量或在别处省出同等体积（§3.3）。
- **帧时**：§3.2。

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

## 2 试点：`foe/slam-quake`

### 2.1 选谁、为什么

首选 Boss 砸地 / 裂地类。现有塑路者震地已经是不规则地裂 + Boss 冲击颗粒带，基本合口径；最差的两个砸地类是**缺图在走兜底**的：

- 卡门「炮身砸击」（`act: smash`，r 70）：原画面 = **金色**地裂 + 火花（金色是我方灯火色系）。
- 斥亡体「迸发」（`act: erupt`，r 120，自身为心）：原画面 = `explode` 平涂圆 + 亮芯 + 环。

两个都是现成的帧条槽位（`fx_carmen_smash` / `fx_immortal_burst`），补图即上，判定、伤害、预警一行不动。

### 2.2 画法

源文件 `tools/pixelfx_foe/foe/slam-quake.js`（pixelfx「simulated」写法，自写，没套库里的 ground-slam / quake）。俯视 3/4 地面，判定圈 = R × R·0.55 的地面椭圆（与游戏 `ground_y` 同）。

| 拍 | 时间 | 画面 |
|---|---|---|
| 爆亮 | 0–0.07 s（第 0 帧） | 不规则白热团（9–12 顶点，半径抖动 0.55–1.3）+ 危险粉外缘；热裂同帧长满 |
| 冷却 | 0.07–0.5 s | 白 → 浅粉 → 危险色 `#ff2667` → 暗红 → 焦黑，逐级实色（不抖动成棋盘格） |
| 裂网 | 0–0.6 s | 4–6 条主裂，角度随机且两两 ≥ 0.6 弧度，长 0.45–0.95 R，各 0–2 个分叉；**不等距、不等长** |
| 尘墙 | 0–0.26 s 推出，之后沉降 | 44 个尘团互相叠压、半径 0.84–1.0 R 抖动、近侧厚远侧薄、顶亮底暗、高低错落、2–3 个断口；远侧先画、碎石、近侧后画；**尘墙外沿 = 判定半径** |
| 碎石 | 0–0.5 s | 12 块，地面影子 + 抬高石块，落地弹一次 |
| 余震 | 0.30 s、0.46 s | 热裂根部回红 + 尘墙整圈抖 1 纹素 + 坑内 3 团小尘 |
| 收尾 | 0.72 s | 全空 |

配色：危险色梯度取自 `render/optical_col_danger`（h 0.95 s 0.85 v 1 ≈ `#ff2667`），尘土中性冷灰 5 阶；不用金 / 青。光只给首 0.18 秒两盏小灯（k 0.35 / 0.5），避免发白。

### 2.3 导出与接入

```bash
python tools/pixelfx_foe/export.py foe/slam-quake fx_carmen_smash --opts '{"R":35,"seed":3}'
python tools/pixelfx_foe/export.py foe/slam-quake fx_immortal_burst --opts '{"R":60,"seed":8}'
```

脚本把源拷进 pixelfx 检出、`render --sheet`、裁并集边框、去首尾空帧、横排、量化 ≤ 32 色，写 `game/art/fx/`；之后 `python tools/asset_index.py` 重写索引。

| 贴图 | 帧 × 单帧 | fps | 锚点（1x 纹素） | PNG | 导入后 .ctex |
|---|---|---|---|---|---|
| `fx_carmen_smash` | 11 × 81×57 | 15 | (42, 29) | 8.6 KB | 10.1 KB |
| `fx_immortal_burst` | 11 × 131×78 | 15 | (65, 37) | 13.0 KB | 16.5 KB |

代码改动只有三处，全是画面：
- `art.gd` V6_FRAMES：两条改成 `[11, 15.0]`。
- `telegraph.gd` smash：有图时只播帧条（`Game.PX` 缩放、锚点对落点、地面层），**不再叠金色地裂**；缺图照旧地裂。
- `telegraph.gd` erupt：缩放由 `PX × r / 60` 改为固定 `PX`、加锚点。

**按每招 r 单独导出、固定 `Game.PX` 缩放**的原因：地面帧条在光学低分辨率层会被 `vfx.int_scale` 取整到 2 的倍数（`render/fx_int_scale`），按 `w.r` 连续缩放的话，r 70 会被取整成 r 88、r 120 取整成 r 88，尘墙外沿对不上判定。1 纹素 = 2 世界像素，与地裂的 2 像素网格一致。

## 3 验证

### 3.1 同 seed TRACE

seed 13、德克萨斯 + 能天使 + 拉普兰德、`--balance --bot=expert --maxt=660 --trace=1`，改前（c73d2ff86 独立检出）与改后逐行比：**512 行 TRACE 全同**；末行 BALANCE 只差 `bot/peak` 第 4 / 5 项（g.fx 数、飘字数峰值，纯画面计数）。这局没出现卡门 / 斥亡体。
另：`--bossacts=carmen` / `bishop+immortal` 改前改后的 BOSSACTS 状态行逐行相同（但 14 秒演示里两招都没触发，所以改用 §3.4 的逐招录制）。
（代码改动只在 `fx_sprite` 调用与帧表；`fx_sprite` 不抽随机数，地裂兜底用自己的局部随机数，按理不会动模拟。）

### 3.2 帧时

**未完成**：逐招帧时（`--bossmoves --perfab=30`，autotest 已加 BOSSMOVES PERF 输出）已排队，本机 Godot 并发满，11-02 夜未跑完。按画法估计：每个实例每帧 1 次贴图绘制（原兜底是地裂 tb 批或 3 次矢量绘制），预期无可测差异。

### 3.3 包体

导入后 .ctex：`fx_carmen_smash` 10.1 KB + `fx_immortal_burst` 16.5 KB = **+27 KB（约 0.026 MiB）**。网页包 b0343aca1 后约 44.47 MiB，预算 44.5，加上后贴线，合入前要实测网页导出或在别处省出同等体积。

### 3.4 对照录像

**未完成**：`tools/pixelfx_foe/rec_moves.py immortal:迸发,迸发 carmen2:炮身砸击,炮身砸击`（卡门要 `carmen2`，砸击只在第二幕）→ `compare_video.py <输出> immortal:120,-40 carmen2`。改前侧斥亡体 260 帧已录，改后侧排队中；vreview 预审未跑。
注意：`--bossacts` 的 14 秒演示不一定放出这两招（第一次录的视频里没有砸击，已删）。

## 4 后续

- 前 8 的 #1（其余 `explode` 兜底）与 #7（轰击）可以直接复用本稿的导出脚本：改源里的配色 / 拍子，按各招 r 导出即可。
- `hit_fx` 缺图时跳过通用命中的 bug（§1.1）另案修。
- 地面帧条画在单位之下（`gsprite`），尘墙不会盖住干员；docs/226 的敌方顶层合入后，可以考虑把爆亮第 0–1 帧挪到顶层，保证不被我方特效盖住。
