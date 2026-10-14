# 101 · 代码框架审计与 C++ 预留方案（架构，2026-10-15）

> 用户 10-15：「让架构检查一下目前的代码框架是否有问题和冗余。考虑到后续做帧率升级还要做 C++，预留下空间。」
> 本文只出方案，**没有改代码**。基线 main 258ca7ae。做法：按 game.gd + run / enemies / core、characters、render + screens 分三路只读审计，另一路调研 GDExtension / 引擎模块的构建发布约束；关键结论（下文标 ✔）由架构逐条回到代码核对过。行号是 258ca7ae 时的位置，之后会漂。
> 「风险」一列都指**同 seed 结果**：不变 / 可能变 / 会变；涉及画面的另注「像素」。
> 相关文档：docs/39（代码结构）、docs/61（干员积木）、docs/50（性能，§11–§16 是本文的数据来源）、docs/55（10-10 审计）、docs/39 §8（敌人画法缓存约定）。

## 0. 结论（一页）

**规模**：GDScript 共 6.6 万行。characters/ 2.14 万（其中 op_blocks.gd 1.68 万），根目录 1.59 万（title 2764、gallery 1972、game 1925、ui 1352、relic_fx 1480），run/ 8485，screens/ 8360，render/ 6316（world.gd 4267），core/ 2169，enemies/ 2192。

**框架本身没有坏**：每帧顺序清楚（§2.1），敌人只有一套空间网格、没有 O(n²)，Boss 已按只拆分，HUD 已拆层，绘制里没有改变同 seed 结果的路径（唯一例外是 §3.4 ②）。问题集中在四类：

1. **同一件事写了多套**：弹体推进 8 条路径（干员侧另有约 45 张私有表）、对主控的预警结算 8 处、三角形批 8 套、精灵取帧算式 8 处以上、干员间抄写的线段判定 / 弹体 / 浮空 / 链跳 / 伤害公式（§3.2）。
2. **边界被穿透**：boss_ai 的私有预警函数被 4 个模块当公共服务用；伤害参数靠「先写 g.in_type / g.dmg_src / g.hit 再调函数」传递；模拟调用渲染（`g.world.enemy_scale`），渲染反调模拟私有函数（`g.bai._draw_warns`）；只给画面用的字段（dc、mv_until、squash…）挂在模拟字典上；界面直接写 `g.state`（§3.1、§3.3）。
3. **确定性隐患**：两个缺省值每帧白抽一次 `g.rng`；命中特效角度用 `g.rng`；溟痕外观 seed 抽玩法随机流；量帧开关 `g.perf_alt` 会关掉地形阻挡；击退有 15 处没乘失重系数（§3.4）。这些不影响「同 seed 可复现」，但会在以后任何改特效、改量帧方式、搬 C++ 时意外改变结果。
4. **遗留**：约 600 行 `opt_old` 旧路径、约 580 行只有测试引用的 core/ 模块、7538 行 legacy 干员测试、docs/55 §6 的三项搬家没做（game.gd 从 1482 行又长到 1925 行）（§3.5）。

**C++ 值不值**：用户 10-14 定密度 0.4 之后，桌面 7–10 分钟平均约 14 毫秒、P95 约 18.5（docs/50 §16.7），同屏约 60 只。GDScript 里随敌人数线性增长的部分（敌人模拟、排序实体里的敌人、分离）此时合计约 2–3 毫秒；剩下的大头是引擎画布处理与绘制提交（网页上尤其贵）和干员积木的常驻开销。所以：
- **阶段 0（纯 GDScript 改边界）应该做**：本身就有收益（估约 0.5–1.5 毫秒，网页更多），而且不管以后用不用 C++ 都是还债。
- **阶段 1（一个模块进 C++）可以做，但先别急**：敌人模拟 + 网格搬进原生代码，密度 0.4 下桌面约省 1 毫秒、网页约 1.5–3 毫秒；更大的意义是给尖峰（大群、Boss 弹幕）和以后加怪数留余量。
- **阶段 2（绘制批 + 投射物进 C++）是网页帧率的主要希望**，但要动绘制管线，需要像素对照。

**需要用户定的事**（§8）：①阶段 0 里有两项会**一次性改变同 seed 基线**（拆随机流、拆敌人更新三段），是否接受；②原生代码的形式：建议「纯 C++ 内核 + 桌面 GDExtension / 网页编进自编模板」（§4.6），是否同意走自编网页模板；③网页 / Toy 包体能接受多大的增长；④legacy 干员测试是否下线。

## 1. 模块与规模

| 目录 / 文件 | 行 | 职责 | 每帧热路径 |
|---|---|---|---|
| game.gd | 1925 | 状态、主循环 `_update`、输入、开局参数、帧条表；约 300 个公共字段 | 是 |
| run/enemies.gd | 584 | 敌人逐帧更新、敌弹 / 抛射 / 冲击环 / 溟痕推进、敌人网格（build_grid / query / nearest / arc_hit） | 核心 |
| run/combat.gd | 1300 | 对敌伤害与击杀掉落、主控受击与保护、控制、缩圈、Boss 卡点 | 每次命中 |
| run/spawner.gd | 858 | 刷怪、Boss 时间表、存活上限队列、密度、敌人工厂（唯一出生口 798 / 819） | 是 |
| run/weapons.gd · pickups.gd | 195 · 401 | `g.bullets` 推进与命中、无人机 · 掉落物理与拾取 | 是 |
| boss_ai.gd + enemies/（enemy_ai 434、boss_patterns 222、bosses/ 10 个 1499） | 789 + 2155 | Boss 公共段与预警管线 `g.warns`、小怪招式、各 Boss 招式 | 是 |
| world/map.gd · relic_fx.gd | 658 · 1480 | 地面 / 景物碰撞 · 藏品解释器、地雷 / 炸弹 / 桩 | 是 |
| core/ | 2169 | bot、balance（`Bal.v` 每帧几十次）、stat_block、relic_db、cloud_pack；**combat_core / event_bus / modifier_system / build_profile / events 约 580 行只有 tests/test_core.gd 引用** ✔ | 部分 |
| characters/op_blocks.gd | 16815 | 积木编译、条件、校验、执行、画面 + 18 名干员的专属段（731 个 static 函数） | 是 |
| characters/data_operator.gd · character.gd · op_api.gd · squad.gd · batch_canvas.gd | 1247 · 1699 · 255 · 519 · 468 | 数据干员运行时（_sustain 等）· 干员基类 · 干员→主场景接口 · 编队调度与 7 个绘制阶段 · 干员几何合批 | 是 |
| render/world.gd | 4267 | 世界层全部绘制 + 主控 / 博士动画手感 + Boss 演出观察；每帧遍历 `g.enemies` 8 遍 | 是 |
| render/vfx.gd · look.gd · tri_batch.gd · enemy_atlas / declutter / ground_crack | 1056 · 313 · 266 · 414 | 特效生成与推进、受光封顶、三角形批、敌人图集 | 是 |
| screens/（23 个）· ui.gd | 8360 · 1352 | HUD 分层与各全屏界面 · 主题与 77 个绘制助手 | HUD 是 |
| title.gd · title_bg · gallery.gd · settings_panel · art · sfx | 2764 · 727 · 1972 · 639 · 635 · 962 | 局外界面 · 资源加载 · 音频 | 否（sfx 是） |
| run/autotest / demo / enemy_demo / motion_shot | 1270 / 336 / 142 / 393 | 测试、演示 | 仅测试 |

## 2. 每帧顺序与数据（C++ 设计的前提）

### 2.1 一帧的顺序（game.gd `_update`，带 `_pm` 分段名）

`combat.update_zone` →【pre】→ `spawner.update` →【spawn】→ `enemies_sys.build_grid` →【grid】→ `enemies_sys.update` →【enemies】→ `squad.update` →【squad】→ `weapons_sys.update` / `knight.update` / `touch.update` / `weapons_sys.update_bullets` →【bullets】→ `enemies_sys.update_ebullets` / `bai._update_warns` →【ebullets】→ `enemies_sys.update_status` / `rfx.tick` →【relic】→ 结局 / 围猎 / 灯标 / 商店 / `pickups.update` →【misc】→ `vfx.update` →【fx】→ `_cleanup`。绘制在 `_draw` 里另走（`world.draw_world` + HUD）。

`enemies_sys.update` 按数组下标逐只：计时器 → 流血 / 侵蚀 → 远距回收 → 进化 → Boss AI 或 `eai.pattern` → 移动 → **分离（就地推：第 i 只看到的是 j < i 已经移动后的位置；先 cx 后 cy，格内下标升序）** → 积分位移 → 场地约束 → `push_out`（隔帧做一半，`(i + frame_n) % 2`）→ 爆发 → 接触伤害。

### 2.2 实体怎么存

| 实体 | 存法 | 规模 |
|---|---|---|
| 敌人 | `g.enemies: Array[Dictionary]`；模板 78 个键（spawner.gd 633–655）+ 约 100 个按需键 | 出生口只有 spawner.gd 798 / 819；`dead = true` 约 21 处、`pos` 写 27 处、`kb` 写 39 处；互相引用靠字典身份（partner / feed_to / owner / b_owner / home…，`is_same` 60 处）；全工程读写敌人字段约 2600 处 |
| 我方弹体 | `g.bullets`（约 15 键，`home` 指敌人字典、`on_hit` 指干员对象）+ 干员约 45 张私有表 + relic_fx 地雷 / 炸弹 / 桩 + 骑士 | 见 §3.2 ② |
| 敌方投射物 | `g.ebullets`（14–22 键）、`g.lobs`、`g.shocks` | 读写约 40 处（其中绘制约 30） |
| 掉落物 | `g.gems`（14 键），无网格，线性遍历 | — |
| 空间结构 | 敌人网格 `g.grid: Dictionary<Vector2i, Array[int]>`，格 48，每帧在 spawner 之后、敌人移动之前重建；景物哈希格（map.gd，格 560） | 敌人网格只有一套，分离、query / nearest / arc_hit 共用 ✔ |

### 2.3 随机流

玩法用 `g.rng`，画面用 `g.vrng` 或全局 `randf`，掉落另有 `pickups._drop_r`。敌人循环里消耗 `g.rng` 的点：远距回收的 `edge_pos`、冲刺 / 新星怪缺省值（§3.4 ①）、吞噬、morph、接触伤害的闪避判定、流血 / 侵蚀击杀的掉落、溟痕外观 seed。**结论：只把循环的一部分搬进 C++ 会打乱随机数次序和就地推的顺序；要保持同 seed 不变，必须整段搬并复刻回调次序与 Vector2（float32）/ 标量（float64）的混合精度。** 现实的做法是先在 GDScript 里把循环拆成「段内无回调、无随机」的纯模拟段（§5 阶段 0b），一次性接受新基线，之后 C++ 版与新基线逐位对照。

## 3. 问题 / 冗余清单

### 3.1 跨模块直接访问（选最严重的）

| 位置 | 问题 | 影响 | 建议改法 | 风险 |
|---|---|---|---|---|
| enemy_ai.gd 102 / 123 / 196 / 219 / 236 / 252 / 269 / 380 等、boss_patterns.gd 160 / 175 / 188、bosses/boss_base.gd 77–86 | boss_ai 的私有 `_warn` / `_cd` / `_warn_damage` / `_close_in` 被 4 个模块当公共预警服务用 | 预警管线拆不出来 | 抽成 `enemies/telegraph.gd`（warn / cd / hit_test / resolve），boss_ai 226–707 一并搬入 | 不变 |
| combat.gd 963 / 978 / 986–997 / 1071 / 1094 / 1104–1136 / 1199 | 伤害核心里写死泡影茧壳、骑士重生、接潮假死、圣徒打断、伊莎玛拉变身 | Boss 逻辑混进伤害核心 | `boss_base` 加 `on_damage / on_lethal / on_kill` 钩子 | 不变 |
| combat / enemy_ai / data_operator 595–598 等 | 伤害参数靠全局变量传：`g.in_type`（12 处写）、`g.dmg_src`（10）、`g.hit`（13 处设、21 处读）、`combat.cur_src / cur_dmg`、`telemetry.hit_type / aura_type` | 顺序耦合，没法当纯函数搬走 | 显式传参 `enemy_hit(dmg, src)`、`damage(e, dmg, hit)`，旧全局留兼容一段时间 | 不变 |
| render/world.gd 375；enemies.gd 144；enemy_demo.gd 119 | 渲染调 `g.bai._draw_warns()`（绘制代码长在 boss_ai 里）；模拟 / 演示调私有 `_boss_ai` / `_update_warns` | 模拟与渲染边界不清 | `_draw_warns` 搬进 render/，其余改公开名 | 不变 |
| enemies.gd 280、enemy_ai.gd 393 / 395 | 模拟代码调 `g.world.enemy_scale` / `_eoff` | 无头与原生端都得依赖 render | 缩放 / 锚点改成纯函数放敌人数据层 | 不变 |
| game.gd 1465、map.gd 330–334 / 381–383 | 景物有没有碰撞、底座多大取自**贴图宽度** | 玩法依赖贴图是否加载 | 开局烘成纯数据表 | 不变 |
| characters/（op_blocks 全文） | 绕过 op_api 的访问：`g.tex` + `V6_FRAMES` 123 处、`g.fx.append` 17、`g.bullets.append` 8、写 `doctor.atk_buf`、直接调 `enemies_sys`、直接写 25 种敌人字段（kb 23、stun 20、slow 9、air 6、pos 5…）；op_blocks 头注释「不碰 game.gd 内部」已不成立 | 干员代码与主场景互相缠，也是 C++ 批处理的最大障碍 | 走 op_api：`strip(name)`、`world_fx()`、弹体池、`consume_press()`、`apply_*`（并登记进敌人字段校验 docs/39 §7） | 不变；character 2677 改走 op_api 会加上 Boss 优先，**可能变** |
| squad.gd 371–384 / 515 | 逐人写 `g.world.fx_dim` 当传参通道 | 隐式状态 | 改参数 | 不变 |
| world.gd 101 / 119 / 4194 / 4228 / 3613；vfx.gd 69 / 411；choice_panel 440–444、elite_show、intro | 渲染调 game 私有函数、手感函数推进开场并切 `g.state`、画面里做空间查询、画面更新里 `add_child` 建灯光、特效模块写 `g.hitstop` / `g.lvup_delay`（决定升级面板何时弹）、界面写 `g.state` / 调 `g._check_pending` | 流程状态散在表现层 | 建一个明确的「表现事件 / 流程」步骤，界面只发请求 | 不变 |
| combat.gd 981–982（每次 damage 调 4 次）、op_api、progression、elite_show、stats_panel | 私有 `g._lamp_r` / `_shuffle` / `_check_pending` 被外部调用 | 下划线约定失效 | 改公开名 | 不变 |
| combat.gd 1236–1266；game.gd 231 / 1670 | 掉落表在 combat、计数写 pickups；网格放在 game 上、game 清零 pickups 计数 | 违反 docs/39 §2 | `pickups.loot(e, dk)`（随机数调用次序不变）、grid 移进 enemies_sys | 不变 |
| title.gd 175–230 / 1874 / 2748–2764；hud_* 的 `h._hb` 14 处；`g.draw_off` / 临时换 `g.hud` | 界面之间调私有函数、全局「当前偏移 / 当前画布」 | 维护成本 | 公开接口、显式参数 | 不变；像素不变 |

### 3.2 重复实现

| # | 什么 | 现状 | 建议 | 风险 |
|---|---|---|---|---|
| ① | 对主控的预警结算 | 统一队列 `g.warns` 已有，但另有一套「自带计时、就地结算」：blast_w、burst_w、nova_w、dash_w、lobs 落点、shocks；几何判定 + 「设 dmg_src / in_type 再调 enemy_hit」写了 8 遍（enemies.gd 283 / 298 / 381 / 450 / 519、enemy_ai 147、boss_ai 394 / 661、hunt） | 一个入口 `telegraph.hit_leader(shape, geom, src)`，只合并判定与结算 | 不变（若把 blast / burst 也并进 `g.warns` 队列则时序会变，不建议） |
| ② | 弹体推进 | **8 条路径**：`g.bullets`（weapons.gd 59）、`g.ebullets`（enemies.gd 416）、`g.lobs`、`g.shocks`、`g.warns`、relic_fx 地雷 / 炸弹 / 桩、干员约 9 张表（op_blocks shots / waves / bolts / sa.shots / crystals）+ 约 45 张私有列表、骑士；清理分散 4 处。干员侧「步进 → 挡墙 → 查询 → 命中表 → 伤害」抄了 6 份；艾雅法拉火弹、铃兰狐火放进全局 `g.bullets`，干员却又每帧扫全表找自己的弹 | 两个池：**敌方投射物池**（ebullets / lobs / shocks 合一，kind = 直线 / 追踪 / 抛物 / 环；只对主控判定，第一个 C++ 候选）；**我方投射物池**（g.bullets + relic_fx + 干员私有表，命中发事件） | 合池时保持原推进次序则不变；顺序变了会变 |
| ③ | 三角形批 | **8 套**：world 的 tb_*（带索引，圆 14 段）/ _gt_* / _afx_* / _zone_*、TriBatch（无索引 64 段斜接）、hud_tris 的 Tris（带索引 12 段不斜接，HUD 约 80 处 + UI.sink 29 处）、hud_relics 在 TriBatch 上重抄 Tris.frame / diamond、BatchCanvas（干员约 500 处，新旧两套，斜接上限与引擎不同） | 唯一批层留 **TriBatch**，补「照旧几何」原语（circle_n / ring_n / arc_q / quad / grad / frame / diamond，顶点与三角形顺序照搬）；tb_* 转发、Tris 改别名、BatchCanvas 只留代理职责 | 不变；保留原段数时像素 0 差（docs/50 §14.4 的做法），改段数要单独一步截图对照 |
| ④ | 精灵「取帧 + 锚点 + 取整 + 翻转」 | 写了 8 遍以上：vfx.spr（43 处调用）/ spr_rot / spr_on、EnemyAtlas.spr、_espr、_gem_sprites、_pq_sprite、影子内联、world.draw_sprite_at、op_api.draw_spr、map._spr；干员侧另有 6 个帧条助手 + 7 处手写，锚点 3 种口径 | 公共 `frame_dst()` + `op_api.strip(spec)` | 不变；像素 0 差 |
| ⑤ | 干员间抄写 | 线段判定 6 份（9073 用全宽、其余半宽）；浮空 3 套都写 `e.air`；链跳 3 份；`_dmg_bonus()` 手写 46 处、精英系数 12 处；清主控溟痕 / 神经损伤 6 份（有的记遥测有的不记）；目标优先序 4 种；`.filter()` 每帧重建约 45 处 | `ob_geom`（rect_hits / chain_next / splash / push）、`op_dmg()`、`op_api.cleanse_leader` | 多数不变；浮空 / 链跳合并**可能变**；清除统一后遥测会变 |
| ⑥ | 全表扫描 | 60 多处 `for e in g.enemies`：每次击杀全表找部件（combat 1209）、`type_n / mob_count / normal_count` 每次刷怪扫、music_director 每帧扫、world 每帧 8 遍 + HUD 4 遍 | 维护部件列表与按种类计数；世界层剔除一次、各层共用视野内下标表 | 不变 |

### 3.3 绘制与模拟纠缠

render 审计**没有找到绘制改变同 seed 玩法结果的路径**（TRACE 不受影响），但下列「只给画面用的状态」写在模拟字典里或在绘制里推进，导致有头 / 无头跑出来的字段值不同，也挡住了「模拟搬原生、绘制只读快照」：

| 位置 | 写了什么 |
|---|---|
| world.gd 1994–1997 / 2250–2253、1999 / 2017、2278、2368 | `e.mv_until`、`e.dpos`、画法缓存 `e.dc` / `e.dcs`、`e.atk_until`（模拟也写，enemy_demo 读）、`e.squash`（模拟递减） |
| world.gd 3634、2521 | `e.tell_dim`、`w.dim`；`e.act_seen_t` + 播音效 + 加特效 |
| world.gd 207 `watch_bosses`（在 draw_world 里） | 追加 `g.fx`、调 `boss_intro.on_spawn / on_down`——无头时从不触发 |
| world.gd 4194 `update_player_feel` | 调 `intro.update_opening`，后者在 `end_opening` 把 `g.state` 切成 PLAY |
| vfx.gd 411 / 69 | 递减 `g.lvup_delay`、写 `g.hitstop` |

建议：画面字段按 `e.id` 挪到渲染侧表里（照 `vfx._sight` 的做法），模拟字典只留模拟字段；`watch_bosses`、`_enemy_act_fx`、开场状态机、`lvup_delay` 搬进一个明确的「表现事件」步骤。玩法与像素都不变。

### 3.4 确定性与正确性隐患（都已回到代码核对）

| # | 位置 | 问题 | 建议 | 风险 |
|---|---|---|---|---|
| ① ✔ | enemy_ai.gd 275 / 313 | `e["dash_cd"] = e.get("dash_cd", g.rng.randf_range(1.5, 3.5)) - dt`：缺省值参数**每帧都会求值**，冲刺怪 / 新星怪每只每帧白抽一次玩法随机数 | 先 `has()` 再抽 | **会变**（少抽随机数，之后序列全变） |
| ② ✔ | render/vfx.gd 551 `hit_fx` | 命中特效角度用 `g.rng.randf()` | 改 `g.vrng` | **会变**；在此之前改这个特效（换图、加减调用）都会改同 seed 结果 |
| ③ | enemies.gd 377 / 441 | 溟痕外观 seed 抽玩法随机流 | 改 vrng 或派生流 | 会变 |
| ④ | characters 749 / 853、squad 298 / 303、op_blocks 8017 | 画面用 `g.rng` | 改 vrng | 会变 |
| ⑤ ✔ | map.gd 439、op_blocks.gd 15747 | 量帧开关 `g.perf_alt` 会关掉地形阻挡与塞雷娅晶柱阻挡（测量工具改了玩法；正式游戏恒为 false） | `perf_alt` 只许影响绘制 | 不变（正式游戏） |
| ⑥ ✔ | op_blocks.gd | `e.kb +=` 19 处只有 4 处乘失重系数 `kb_taken`（失重对 501 / 2005 / 3516 / 6815 等无效） | 统一走 `geom.push` / `apply_kb` | **会变**（这是 bug，修了才符合设计） |
| ⑦ ✔ | weapons.gd 108 | `query(b.pos, 40.0)` 的半径小于最大的 `e.r + b.r`（40 + 8），按格子对齐可能打不中大体型 Boss | 半径改 `b.r + 最大 e.r` | 会变（bug） |
| ⑧ | enemies.gd build_grid | 网格在敌人移动前建、本帧新刷的敌人不在格里，之后的查询用旧位置 | C++ 版先原样复刻；要修正就并入阶段 0b 的换基线 | 修正会变 |
| ⑨ | 敌弹 6 个生产点 | 字典键不一致：patterns 写 `source_type`、其余写 `src_type`；`extra_volley` 写 `boss: false` 且没有 `src_type`——放招敌人的 cold_hit / wound_hit / apop_hit 对这类弹不生效、遥测按「场上第一个 Boss」兜底归因 | 统一字段（敌方投射物池顺手做） | 会变（bug） |
| ⑩ | run/enemies.gd nearest 536 | `[d, e]` 对 + 闭包排序，同距时顺序不稳定 | 原生版按 id 打破平局 | 可能变 |

### 3.5 死代码与遗留

| 位置 | 现状 | 建议 | 风险 |
|---|---|---|---|
| `g.opt_old` 旧路径 | 约 600 行：world ≈260、look 36、batch_canvas 55、HUD ≈115、run/ ≈140（pickups `_update_old` 79、`_separate_old` 23、OPT_ENEMY / OPT_GEM / OPT_CLEANUP）。docs/50 §11–§15 都已量完结案 | 删已定案的位的旧实现，**保留 `--optab / --optmask / --optold` 框架**，给以后的原生对照位用（命名 `OPT_CPP`） | 不变；像素 0 差 |
| core/combat_core + event_bus + modifier_system + build_profile + events ✔ | 约 580 行，只有 tests/test_core.gd 引用；docs/55 §6 建议的改名没做 | 挪进 tests/ 或删 | 不变 |
| tests/data_ops/*_legacy.gd | 13 个、7538 行，仍跑 blocks_eq（只比精零）；继承 character.gd，基类 / op_api 一改名就要改 13 份 | 录一次金样 TRACE 后下线，或明确冻结这套 API | 不变（测试） |
| weapons.gd 127–147、67–76 / 93–95、191–195 | 箭矢 / 导弹加速 / 缺省分支没有生产者；112 读 `b.hit`、145 写 `b.hit_ids`，穿透去重本来就不生效 | 删约 40 行 | 不变 |
| combat 18–19、enemies 11–13、spawner 12–13（含 432 分支） | `flesh_heal / ember / seed_heal / evo_age / evo_xp / horde_mult / horde_chest` 从未被赋值（旧藏品残留） | 删或改常量 | 不变 |
| enemy_ai 370–383 `spawn_on_shot`、boss_ai 669–672 `"spawn"` 招式、game.gd 1604 `_sync_stats`、title 2672 `_wrap_text`、sfx 784 `loop_pitch`、op_blocks `custom` 积木 | 0 使用 | 删 | 不变 |
| boss_ai.gd 154–209 | 14 个转发函数，8 个下划线名只有测试和 combat 964 在调 | 调用方改 `g.bai.boss(type)` | 不变 |
| docs/55 未做项 | §1.2 的 4 个 0 引用符号；§2.5 `V6_FRAMES` 改名（76 处）；§6 game.gd 三项搬家（帧条 / 贴图表 → art.gd、INTRO_PAGES → lore.json、`_update_doc_follow` → doctor.gd）；§3 截图开关合并（10 个） | 按 §7 派 | 不变 |
| 缺图退回程序画 | `if not …fx_sprite(` 30 处（10-10 时 22 处）；world 另有 38 处贴图 null 判断、约 11 段程序画兜底 | 先做「贴图加载保证」再删（docs/55 §2.4） | 像素可能变 |
| Character.create 261 | 每次招募（含局中）都跑约 2500 行积木校验 | 只在 debug / 快检跑 | 不变 |
| enemy_demo.gd 116–125 | 复刻了主循环子集，不清 ebullets / fx | 调用公共 step 段 | 不变 |

### 3.6 大文件拆分

| 文件 | 拆法 | 风险 |
|---|---|---|
| op_blocks.gd 16815 | **按干员段拆**（117 个积木 tag 里 91 个只有 1 名干员用）：公共 `ob_core`（tag 表、compile、条件、exec_shape、注册表，约 900 行）、`ob_fx` + `ob_vortex`、新建 `ob_geom`（几何判定 = 原生接缝）、`ob_proj`（统一弹体池）；`seg_<干员>.gd` ×18；校验移到 `check/<段>.gd`。分派改**注册表单播**（每段导出 TAGS + 可选 tick / sustain / exec / draw，compile 时建「tag → 段」表，按现在的调用顺序固定），拆掉现在的广播（`_exec_list` 的 `_:` 分支广播给 7 个段执行器、update 每帧无条件调 5 个段 tick）与参数钩子（exec_shape 看到 basis / only / band… 就转段） | 可能变：要先确认没有哪个 tag 同时被两个广播处理器接手 |
| render/world.gd 4267 | 敌人（约 900，`_draw_enemy_full` 258 行）/ 预警（约 800）/ 特效（`_draw_fx` 417 行 → 按 kind 的函数表）+ 弹体（约 600）/ 掉落（约 250）/ 缩圈（约 330）/ 主控视图（约 500），主文件只留调度与提交点 | 不变；像素 0 差 |
| game.gd 1925 | 输入 1097–1355 → `run/input_router.gd`；冲刺 + 移动段 → `run/leader_motion.gd`；命令行解析 → `autotest.parse_args`；帧条表 → art.gd；主控约 80 个状态字段收进 `LeaderState`（原生端需要它的只读快照） | 不变；最后一项改动点多，分批 |
| combat.gd 1300 | 主控受击管线 → `run/leader_hurt.gd`；缩圈 → `run/zone.gd`；卡点 / 韧性 / 伤害预算 → `enemies/boss_gate.gd`；掉落段 → pickups | 不变 |
| spawner.gd 858 | 敌人工厂 → `enemies/enemy_factory.gd`（原生存储的唯一出生口）；存活上限队列 → `spawn_queue.gd` | 不变 |
| boss_ai.gd 789 | 预警管线 226–707 → `enemies/telegraph.gd`；`_draw_warns` → render/ | 不变 |
| title.gd 2764 | 选人页 1510–2724（约 1200 行）→ `screens/op_pick.gd`；难度页、制作人员、开发参数（`_ready` 271 行里约 200 行）各自拆出 | 不变 |
| gallery.gd 1972、run_stats_screen 1061、autotest 1270、relic_fx 1480 | 数据 / 输入 / 绘制分开；autotest `step()` 454 行按开关拆；relic_fx 的地雷 / 炸弹 / 桩单独成文件 | 不变 |

### 3.7 每帧临时分配（干员段的常驻开销，docs/50 §14.1 / §14.6 的「干员 1.8–2 毫秒」）

| 位置 | 每帧新建 | 改法 | 风险 |
|---|---|---|---|
| character.gd 878 `scopes()` / stat_block 103 | 每次 `stat()` 新建数组、拼 3 次字符串再 join；op_blocks 里 `stat` 调用 76 处 | 作用域键缓存成成员 | 不变 |
| data_operator.gd 264–431 `_sustain` + 5 个段的 sustain | act 数组、add / mul 字典、want（4 元数组 + 拼串）、seen / fseen、4 次 `keys()`；各段重扫 | 按 tag 预索引活动集、复用缓冲 | 不变 |
| `.get(k, {})` 261 处 + `.get(k, [])` 308 处（data_operator 另 57 处） | 每次调用新建空容器 | 只读常量 | 不变 |
| tint / off / anchor 每帧 JSON → Color / Vector2；`_trigs()` 每帧重拼；`cond_true` 拼字符串 | — | compile 时定型 | 不变 |
| op_blocks `fx_vortex` 1494 | 每条流线 3 个 Packed 数组、每个四边形一个临时数组 | 预分配、按下标写；改成生成网格的纯函数 | 不变；像素 0 差 |

## 4. C++ 预留

### 4.1 热点在哪（数据来自 docs/50）

| 场景 | 帧构成（毫秒 / 帧） |
|---|---|
| 桌面安静时、密度 1.0（§15.3，同屏约 130） | 平均 18.6；engine 11.9（其中世界绘制 7.4：排序实体 2.35、干员上层 0.86、影子 0.72、掉落 0.63、缩圈 0.36）、敌人模拟 2.2、干员 1.8、HUD 1.5 |
| 敌人模拟细分（§14.1，约 127 只、负载中等） | 计时器 0.83、出招 `eai.pattern` 1.12、移速 0.67、分离 0.91、位移 / 推出景物 0.47——每只约 130 次字典读写，常驻开销 |
| 排序实体细分（§14.1） | 敌人 3.1（受光封顶 0.47、缓存判定 0.67、签名比对 0.29、贴图 0.41、非缓存敌人原路径 0.88、词条 0.16）、建表 + 排序约 0.5、干员本体 0.45、景物 0.38 |
| 密度 0.4（§16.7，用户 10-14 定的缺省，同屏约 60） | 桌面平均约 14、P95 约 18.5；网页平均降 22–28% |
| 网页（§11.4 / §12–§14） | 绘制调用约 270–290 次 / 帧，每次都要过 wasm → JS → WebGL，引擎画布处理与提交占大头；GDScript 在 wasm 里比桌面慢约 1.3–1.7 倍 |

**判断**：
- 随敌人数线性增长的 GDScript 段（敌人模拟、排序实体里的敌人、分离 / 网格、敌方投射物）在密度 0.4 下合计约 2–3 毫秒（桌面）——这是原生代码最容易拿、也最确定的部分，搬过去约省 1.5–2.5 毫秒（桌面）、网页按 1.5 倍左右。
- 干员积木（干员段约 1.8 毫秒）大头是**每帧临时分配和字典查找**，先做 §3.7 的 GDScript 清理比搬 C++ 划算；积木逻辑 78% 只有一名干员用，不适合整体搬原生，只搬 §4.2 ③ 的几何批判定。
- 网页的最大开销在引擎侧的绘制提交。原生代码能帮上的是「敌人 / 影子 / 掉落一次生成一大段三角形、少几十次绘制调用」（§4.2 ④），这是阶段 2 的事，也需要像素对照。docs/50 §12.5 的「每只一个 canvas item 的保留模式」已量过是负收益，不走那条路。

### 4.2 切入面：四个原生模块（按先后）

| # | 模块 | 内容 | 输入 / 输出（一帧一次调用） |
|---|---|---|---|
| ① | **敌人核心 `EnemyCore`** | 网格重建、计时器递减、移动（朝主控 / 绕行）、分离（保持就地推的次序）、积分位移、场地约束、`push_out`（景物碰撞烘成数据）、接触判定 | 入：热字段平行数组（见 §4.3）+ 主控快照 + 景物表 + dt；出：写回热字段、接触命中事件数组（下标、伤害、类型）。AI 决策（出招）与事件结算留 GDScript |
| ② | **敌方投射物池 `EnemyShotPool`** | ebullets / lobs / shocks 合一：直线 / 追踪 / 抛物 / 环推进、灯标吞弹、地形阻挡、与主控判定 | 入：池（全量 SoA）+ 主控快照 + 灯标列表；出：命中事件、到期 / 落地事件（落地后的预警仍由 GDScript 生成） |
| ③ | **几何批查询 `GeomQuery`**（给干员 / 藏品 / 我方弹体） | `hits_circle / hits_cone / hits_rect / nearest_k(prio) / chain_next / splash / sweep`，都查 ① 的网格 | 入：查询参数（或一帧的查询批）；出：`PackedInt32Array` 下标（按原顺序 / 原平局规则） |
| ④ | **精灵批 `SpriteBatch`**（阶段 2） | 敌人（缓存 + 图集路径）、影子、掉落物：取帧、受光封顶查表、y 排序键，一次生成带贴图的三角形数组；Boss、特殊状态、干员打断时回到 GDScript | 入：渲染侧平行数组 + 33 格受光表 + 视野；出：顶点 / UV / 颜色数组 + 排序段表（键、种类、下标），交给一次 `draw_mesh` / `RenderingServer` 提交 |

我方投射物池（`g.bullets` + relic_fx + 干员私有表合一）先在 GDScript 里做（阶段 0），推进逻辑简单、命中后回调干员，原生化收益排在 ①–③ 之后。

### 4.3 数据结构：混合方案（不全量改 SoA）

全工程读写敌人字段约 2600 处，全量改成扁平数组不现实，也会把 op_blocks 的 800 处一起拖进来。建议：

- **敌人字典仍是权威数据**。原生端只持有约 12 个热字段：`pos(x,y)`、`kb(x,y)`、`r`、`spd`、`hp`、`dead`、`stun`、`slow`、`age`、`wind`、`flags`（位：dormant / boss / friendly / hover / …）、`type_id`，存成 `PackedFloat32Array` / `PackedInt32Array` 的列（按槽位下标），外加空闲槽位表。
- **每帧段首读入、段尾写回**：只有 enemies.gd 与网格调用方要改（约 60 处）；其他代码继续读写字典。原生段运行期间 GDScript 不碰这些字段（§2.1 的顺序天然满足：敌人模拟段里只有 AI 决策会读写，它在原生段之前）。
- **出生口唯一**：敌人工厂（spawner.gd 798 / 819）分配槽位、写 `e.id`；`_cleanup` 回收槽位。敌人之间的互相引用（partner / owner / home…，`is_same` 60 处）改成 `e.id` 句柄——这是原生端能理解的唯一引用方式。
- **敌方投射物**：读写只有约 40 处（绘制约 30），直接全量 SoA + 空闲槽位表。
- **Packed 数组按引用传给原生端、不拷贝**；字典 / Array 跨边界要逐元素转 Variant，必须避免（具体开销量级见 §4.6 ⑤）。

### 4.4 接口要先收口成「一帧一次调用」

原生化的收益取决于调用次数。现在的形状是「每只敌人每帧几十次 GDScript 调用 + 字典读写」「每颗弹每帧一次 query、每次新建数组」——如果原封不动换成「每只敌人调一次原生函数」，跨边界开销会吃掉大部分收益。所以先在 GDScript 里把这些路径改成下面的形状（阶段 0a / 0b），换语言时只是替换函数体：

```
EnemyCore.step(dt, hot: Dictionary of Packed*, leader: Dictionary, props: PackedFloat32Array) -> PackedInt32Array  # 接触事件
EnemyShotPool.step(dt, pool, leader, beacons) -> PackedInt32Array                                                    # 命中 / 到期事件
GeomQuery.hits_circle(o: Vector2, r: float, prio: int) -> PackedInt32Array   # 以及 hits_cone / hits_rect / nearest_k / chain_next / splash / sweep
SpriteBatch.build(view: Rect2, render_cols, light_lut) -> {verts, uvs, cols, segments}
```

### 4.5 确定性约束

- 原生段内**不回调 GDScript、不抽随机数**。需要随机的（远距回收的落点、吞噬、冲刺 / 新星计时）在段外用从局种子派生的独立流做（阶段 0b）。
- 浮点：GDScript 的标量是 float64、`Vector2` 是 float32。原生端要逐表达式复刻这种混合精度，否则同 seed 对不上；对照方法沿用 docs/50 的 `--optab` 同局轮换 + 同 seed TRACE 逐行比，原生路径挂新位 `OPT_CPP`。
- 平局规则：最近 N 个、同距排序按「下标升序」写死（现在闭包排序不稳定，§3.4 ⑩）。

### 4.6 构建与发布约束（GDExtension / 引擎模块）

调研结论（出处附后；「本地」指 godot-source 4.7.2 与本仓库，已回到文件核对 ✔）：

| 问题 | 结论 |
|---|---|
| ① 网页能不能加载 GDExtension | **能，不需要线程版**，但要换模板：预设打开 `variant/extensions_support` 后导出器找 `web_dlink_nothreads_*`（本地 `platform/web/export/export_plugin.h` ✔）；本机只装了 `web_nothreads_*` ✔，要另装。只在开线程时才检查 COOP / COEP（`platform/web/js/engine/features.js`；官方「Exporting for the Web」文档仍写需要，和源码不一致，以实测为准）。扩展必须用**与模板相同的 emscripten 版本**编译（动态链接没有稳定 ABI；4.6 / 4.7 官方模板用 4.0.20，见 godot build-containers 的 Dockerfile.web），godot-cpp 要加 `threads=no`（缺省开线程会卡在加载页） |
| ② dlink 的代价 | dlink 模板把整个引擎编成位置无关的附属模块 `index.side.wasm`，主模块导出全部符号、不做死代码剔除，启动时逐个下载编译附属模块和扩展 `.wasm`。官方说缺省模板不带 GDExtension 是「for performance and compatibility reasons」，emscripten 文档也建议优先静态链接。**多几 MB、慢多少：没查到数据，只能实测**；Safari 内存高时会自行重载页面，dlink 多出的内存会加重老 iPhone 的风险（docs/33 已记） |
| ③ 编进引擎的模块 | 运行最快（直接调用、能和引擎一起 LTO），还能用 build_profile / `disable_3d` / `optimize=size_extra` 给 wasm 瘦身（社区实测 4.4 网页包 42 → 约 25 MB，但自动检测会误删用到的类，要手工核对）。网页模板：`scons platform=web target=template_release threads=no production=yes custom_modules=<目录>`，emscripten ≥ 4.0.0（本地 `detect.py` ✔），对齐官方 4.0.20；`production=yes` 开 thin LTO，链接要 ≥ 8 GB 内存。`javascript_eval` 必须保留（settings.gd 用 `JavaScriptBridge.eval`）。文字服务器不能换轻量版（不支持中文）。**代价：凡要用到这个类的二进制都得自编**——编辑器、两个 Windows 加密模板、诊断模板、云端 Linux 版、网页模板 |
| ④ Windows | GDExtension 的 dll 导出时放在 exe 旁、不进 PCK，加密只管 PCK——dll 是机器码，不比加密 PCK 更好读，但可被替换（完整性问题）；.gdextension 放在加密 PCK 里能否读取没查到说明，要实测。我们的自编模板没关 GDExtension，应能加载。llvm-mingw 编 godot-cpp 有坑：不设 `mingw_prefix` 时会忽略 `use_llvm` 用 PATH 里的 gcc；设了前缀又会追加 `-lstdc++`，而本机工具链只有 libc++，可能链接失败 |
| ⑤ 数据接口 | Packed 数组传给原生端只复制句柄、`ptr()` 读不拷贝；但对共享缓冲 `ptrw()` 写会触发写时复制整块（`core/templates/cowdata.h`）。Dictionary / Array 传递便宜，但原生端每读一个字段都是一次接口调用 + 类型转换（godot-cpp 里 `PackedFloat32Array::operator[]` 每取一个元素也是一次接口调用，要用指针批量读）。社区数据：GDScript 一次函数调用约 170 纳秒；逻辑改原生可快 40–100 倍；但「每只怪计算很少、频繁跨边界」时原生没有收益（gdext-evaluation）。**所以 §4.4 的「一帧一次调用、状态按字段数组持有」是前提** |
| ⑥ 移动 | 网页上的动态链接是 JS 实现的（下载 + 标准 instantiate），能跑现在模板的 Android Chrome / iOS Safari 就能加载；异步加载碰不到 Chromium 主线程 8 MB 同步编译限制。原生包：GDExtension 用官方模板即可（Android 每架构一个 .so；iOS 要 .xcframework，需 Mac + Xcode）；模块方案要自编 Android / iOS 模板 |
| ⑦ 发布链路要改的 | **GDExtension + dlink**：装 dlink 模板；`export_web.py` 类型表与分片清单加 `index.side.wasm`（超过 25 MB 必须分片）和扩展 `.wasm`；`loader.js` 的 fetch 拦截仍有效（emscripten 4.0.20 加载附属模块走全局 fetch），加清单条目即可；`verify_web_build.py` 用 Windows 诊断模板加载网页 pck 时要提供 Windows dll；包体重量、看 Toy 50 MB。**模块 + 自编模板**：文件名不变，loader 与分片不用改；预设改指自编模板；诊断模板、两个 Windows 模板、编辑器、云端 `setup_linux.sh` 都换带模块的版本，像 `template.json` 那样记下 emsdk 版本与 sha256。两种方案的 Windows 包都要让 `export_build.py` / `verify_encrypted_game.py` 认得 dll（若用 GDExtension） |

**对比**

| 维度 | GDExtension + dlink 网页模板 | 引擎模块 + 全平台自编模板 | 维持纯 GDScript |
|---|---|---|---|
| 网页可行性 | 可行（nothreads 有官方 dlink 模板），实例少，文档与源码不一致 | 可行，静态链接最成熟 | 现状 |
| 包体 | 会增加，增量未知，可能逼近 Toy 50 MB | 可用 build_profile 抵消甚至变小 | 不变 |
| 性能 | 内核快，但整个引擎变附属模块、全部符号导出，退化幅度未知 | 最好 | 已到天花板（docs/50 §14.6） |
| 构建复杂度 | 中：godot-cpp 编 Windows、Linux（云端）、网页三份 | 高：编辑器、三类模板、云端全部自编，并分发给各会话 | 无 |
| Godot 升级 | 网页跟 emscripten 版本重编；桌面向前兼容 | 每次全部重编，内部 API 可能变 | 无 |

**建议**：
1. **原生内核写成不碰 Godot 类型的纯 C++**（只收指针和长度），外面一层很薄的绑定。这样同一份内核既能做 GDExtension 也能做引擎模块，以后换形式不重写。
2. **先在 Windows 上用 GDExtension 做阶段 1 原型**：官方编辑器不用换，`--optab` 量出真实收益，不行随时删。
3. **网页（主渠道）优先走「同一内核编进自编的 nothreads 网页模板」**：没有 dlink 的整引擎附属模块代价，还能用 build_profile 抵消包体；桌面与云端继续用 GDExtension 版，网页导出时排除 .gdextension，避免同名类注册两次（**未验证，要先做原型**）。若不想维护两套绑定，就退回全平台模块，代价是编辑器与云端都要自编。

出处：godot-build-scripts `build-web/build.sh`；godotengine/build-containers 各分支 `Dockerfile.web`；Godot 文档「Exporting for the Web」「Compiling for the Web」「Optimizing for size」「What is GDExtension」「Compiling with script encryption key」；emscripten「Dynamic Linking」；W3C 2023 年 Godot 团队发言（alessandrelli-godot）；Godot 4.3 网页导出进展文章；Godot 论坛「How to build a GDExtension C++ library for web」「Why is there such a massive overhead in calling a function」；godot-cpp-template；PR #70838 评论；franziskusz/gdext-evaluation；popcar「How to minify Godot's build size」；issue #90168（iOS 导出回归）。本地：godot-source `platform/web/export/export_plugin.h`、`platform/web/detect.py`、`platform/web/SCsub`、`platform/web/js/engine/features.js`、`editor/export/editor_export_platform_pc.cpp`、`core/templates/cowdata.h`。

### 4.7 GDExtension 桌面原型：最小工程方案（10-15 协调人派；只写方案，不建工程）

**目标**：在 Windows 上用官方 4.7.2 编辑器加载一个原生类，`--optab` 同局轮换量出 `EnemyCore` 的真实收益；不影响任何发布包（原型阶段 `.gdextension` 不进导出）。

**目录**

```
native/                              # 新目录，与 game/ 平级（不进 Godot 工程，不进 pck）
  core/                              # 纯 C++ 内核：不 include 任何 Godot 头，只收指针 + 长度
    enemy_core.h / enemy_core.cpp    #   struct EnemyCols { float* px; float* py; … int n; }; void enemy_step(EnemyCols&, const LeaderSnap&, const Props&, double dt, Events& out);
  gdext/                             # godot-cpp 薄绑定（桌面 / 云端）
    register_types.cpp               #   注册 EnemyCore（RefCounted）
    enemy_core_bind.h / .cpp         #   step(dt, cols: Dictionary of Packed*, leader: Dictionary, props: PackedFloat32Array) -> PackedInt32Array
  module/                            # 以后编进网页模板时用的引擎模块绑定（阶段 1 网页时再建；同一个 core/）
  godot-cpp/                         # 不入库；构建脚本按固定提交拉取（见下）
  SConstruct                         # 参照 godot-cpp-template
  build_native.py                    # 一条命令：拉 godot-cpp → 导出 API → scons → 复制到 game/bin/
game/bin/ark_native.gdextension      # entry_symbol / compatibility_minimum = "4.7" / libraries（windows.debug.x86_64、windows.release.x86_64；以后 linux.*）
game/bin/ark_native.windows.*.dll    # 构建产物，不入库（.gitignore）
game/scripts/native/native.gd        # 薄封装：ClassDB.class_exists("EnemyCore") 才实例化，否则返回 null → 调用方走 GDScript 路径
```

**godot-cpp 与 4.7.2 对齐**：用我们自己的编辑器导出接口描述，避免分支 / 标签对不准——
`godot --headless --dump-extension-api --dump-gdextension-interface` 生成 `extension_api.json` 与 `gdextension_interface.h`，scons 时传 `custom_api_file=<路径>`（godot-cpp 支持）；godot-cpp 本身固定到某个提交，记进 `native/VERSION`（同 `template.json` 的做法记 sha256）。

**Windows 构建步骤**（原型）：
1. `pip install scons`（工具链用现有的 llvm-mingw-20260922）。
2. `python native/build_native.py`：拉 godot-cpp 指定提交 → 导出 API → 分别 `scons platform=windows arch=x86_64 target=template_debug` 与 `target=template_release`，`use_mingw=yes use_llvm=yes mingw_prefix=<llvm-mingw 路径>`。
3. 已知坑（§4.6 ④）：godot-cpp 的 `tools/windows.py` 在 llvm 下会追加 `-lstdc++`，而本机工具链只有 libc++——构建脚本里给 godot-cpp 打一行补丁（`-lstdc++` → `-lc++`，静态链接 `-static`），失败再退 MSVC Build Tools（C ABI 兼容，mingw 编的引擎能加载 MSVC 编的 dll）。
4. 编译选项：`-O2`，**不开 `-ffast-math`**，加 `-ffp-contract=off`（不让编译器把乘加合成 FMA）；MSVC 用 `/fp:precise`。标量用 `double`、`Vector2` 分量用 `float`，与 GDScript 的混合精度一致（§4.5）。
5. 编辑器打开工程能看到 `EnemyCore` 类即成功；`.gdextension` 原型期加进 Windows / Web 导出预设的 exclude_filter，发布包不受影响。

**开关与对照**：
- 新位 `OPT_CPP := 65536`（game.gd 现有位到 32768）。`g.opt_old & OPT_CPP` 为真时走 GDScript 旧路径。
- `--optab=60 --optmask=65536`：每 60 帧在原生 / GDScript 之间轮换，量 7–10 分钟段帧时；`--optold=65536` 整局走 GDScript。
- 同 seed：原生路径对 B7 新基线的 TRACE 逐行相同才算过；check.py 加一项 `native_eq`（只在 dll 存在时跑：同一局 `--optold=65536` 与缺省各一次，TRACE 逐行比）。
- 没有 dll（网页、云端暂未编、别人的机器）时 `native.gd` 返回 null，自动走 GDScript，游戏行为不变。

**原型通过后的去向**：dll 进 Windows 发布包（`export_build.py` 复制到 `game/`、`verify_encrypted_game.py` 的逐文件一致检查算上 dll）；云端 `setup_linux.sh` 多编一个 `.so`；网页按 §4.6 建议把同一个 `core/` 编进自编 nothreads 模板（`module/` 绑定），网页包硬线 ≤ 48 MB（§8）。

## 5. 分阶段路线

| 阶段 | 内容 | 预期收益（桌面 / 网页，粗估） | 风险 | 需要谁定 |
|---|---|---|---|---|
| **0a 纯清理（同 seed 不变）** | §3.5 死代码与已定案的 `opt_old` 位；§3.1 显式传参、telegraph 抽出、Boss 钩子、私有改公开；§3.3 画面字段挪到渲染侧、表现事件步骤；§3.2 ③④ 三角形批 / 精灵取帧统一（保留原段数）；§3.7 干员每帧分配；§3.6 game / combat / spawner / boss_ai / world 拆文件；世界层 8 遍遍历改剔除一次 | 约 0.5–1.5 / 0.8–2 毫秒（主要来自 §3.7 与少遍历；其余是可维护性） | 低；每步同 seed TRACE 逐行相同 + 关键帧像素 0 差 | 协调人派活即可 |
| **0b 换基线的一步（同 seed 会变，一次性）** | 敌人更新拆三段（AI 决策 → 纯模拟 → 事件结算），纯模拟段内无回调、无随机；随机流拆分（§3.4 ①②③④）；修 §3.4 ⑥⑦⑨（失重击退、弹体查询半径、敌弹字段）；敌方投射物池合一；敌人互引用改 id 句柄；我方投射物池合一 | 约 0.3–0.8 毫秒（少抽随机、少临时数组）；主要是给阶段 1 铺路 | 中：胜率会有小幅漂移，要云端重跑一次基线（数值会话按 docs/80 口径核对） | **用户**：是否接受一次性改基线（含修 bug 带来的数值变化） |
| **1 第一个原生模块（可开关回退）** | `EnemyCore`（§4.2 ①），挂 `OPT_CPP` 位，`--optab` 同局轮换 + 与 0b 新基线逐行对照；缺原生库时自动回退 GDScript 路径 | 密度 0.4：约 1 / 1.5–2 毫秒；密度 1.0 或大群尖峰：约 2 / 3 毫秒以上；P95 改善大于平均 | 中：构建链路（§4.6）、三端包体、Godot 升级时要重编 | **用户**：走 GDExtension 还是引擎模块；网页 / Toy 包体上限 |
| **2 扩展** | `EnemyShotPool`、`GeomQuery`、`SpriteBatch`（敌人 / 影子 / 掉落一次提交，少几十次绘制调用） | 网页最可能见效的一步：绘制调用减少的收益要实测（docs/50 §12 的经验：调用数在桌面已不是瓶颈，网页是）；桌面约 1–2 毫秒 | 中高：动绘制管线，需要像素对照；受光封顶要原样复刻 | **用户**：画面允许的微小差异（若有）；优先级与内容开发的排期 |

每一阶段结束都要能单独停下：阶段 0 做完不做 C++ 也成立。

## 6. 与现有约定对齐

| 约定 | 本方案的处理 |
|---|---|
| docs/39 §2「模块 extends RefCounted、持有 `g`」 | 不变；新增的 telegraph / enemy_factory / leader_motion 等照此写。原生模块包在一个 GDScript 薄封装里（同名接口），调用方不感知后端 |
| docs/39 §2「被多个模块读的状态留在 game.gd」 | 继续成立；原生端拿的是**热字段副本**，权威仍在字典 / game.gd |
| docs/39 §4 op_api 接口层 | 收紧：§3.1 列出的绕过点逐步改走 op_api；`GeomQuery` 通过 op_api 暴露给积木 |
| docs/39 §8 敌人画法缓存（`e.dc` 签名、`_dc_ok` 排除、`--dccheck`） | 阶段 0a 把 `dc / dcs` 挪到渲染侧按 id 存，约定的语义不变；阶段 2 的 `SpriteBatch` 只处理「缓存路径 + 图集」的敌人，不缓存的照旧走 GDScript |
| docs/61 积木 | 不改积木语义；拆文件 + 注册表单播是实现层的事；新增 `ob_geom` / `ob_proj` 作为积木可用的几何与弹体原语 |
| docs/50 测量方法 | 沿用 `--optab / --optmask / --optold` 同局轮换与 `--prof` 分段；原生路径挂 `OPT_CPP` |
| docs/36 §1.1 测试分工 | 阶段 0a 每步：`--auto` + 同 seed TRACE（`tools/trace_base.py`）；0b 的换基线由协调人建云端例行任务重跑 |

## 7. 派活清单

### 7.1 现在就该做的小清理（同 seed 不变，可分给各会话）

| 编号 | 内容 | 建议会话 |
|---|---|---|
| S1 | 删 §3.5 的死代码：weapons 无生产者分支、从未赋值的开关、`spawn_on_shot` / `"spawn"`、`_sync_stats`、`_wrap_text`、`loop_pitch`、`custom` 积木 | 架构（weapons / enemy_ai / boss_ai 先【协调】Boss与怪物；op_blocks 先【协调】干员） |
| S2 | 删已定案 `opt_old` 位的旧实现（OPT_ENEMY / GEM / CLEANUP / GEMDRAW / DRAW / CV / ZONE / SORT / EDRAW），保留开关框架 | 架构 |
| S3 | core/ 只给测试用的 5 个文件挪进 tests/ | 架构 |
| S4 | `g.perf_alt` 只许影响绘制（map 439、op_blocks 15747） | 架构 |
| S5 | docs/55 §6 的 game.gd 三项搬家（帧条 / 贴图表 → art.gd、INTRO_PAGES → lore.json、`_update_doc_follow` → doctor.gd） | 架构 + 文案（lore.json） |
| S6 | 私有函数改公开名（`_lamp_r` / `_shuffle` / `_check_pending` / `_draw_warns` 等）；`has_method` 多余判断 | 架构 |
| S7 | 维护部件列表与按种类计数，消掉每次击杀 / 刷怪的全表扫描 | Boss与怪物 |
| S8 | `Character.create` 的积木校验只在 debug / 快检跑 | 干员 |
| S9 | §3.7 干员每帧分配（stat 作用域键、`_sustain` 预索引、空容器缺省值、compile 时定型、漩涡预分配） | 干员（docs/50 §14.6 已点名，等精英化批次合入后做） |

### 7.2 C++ 之前必须先做的边界重构（按顺序）

| 编号 | 内容 | 同 seed | 依赖 |
|---|---|---|---|
| B1 | 伤害上下文显式传参（替代 `g.in_type / dmg_src / hit / cur_src`）；Boss 特例进 `boss_base` 钩子；模拟不再调 `world` | 不变 | — |
| B2 | `enemies/telegraph.gd`（预警服务 + 8 处结算合一个入口）；`_draw_warns` 搬 render/ | 不变 | B1 |
| B3 | 画面字段挪渲染侧按 id 存；表现事件步骤（watch_bosses、开场状态机、lvup_delay） | 不变 | — |
| B4 | 三角形批统一 TriBatch、精灵 `frame_dst()`；`g.draw_off` / `g.hud` 改显式参数；世界层剔除一次共用视野下标表 | 不变；像素 0 差 | — |
| B5 | 敌人工厂独立（唯一出生口 + 槽位 + `e.id`）；敌人互引用改 id 句柄 | 不变（只改引用方式） | — |
| B6 | op_blocks 按干员段拆 + 注册表单播；`ob_geom`（几何判定合一，替代 6 份线段判定等）；干员敌人字段写入走 `apply_*` | 不变；浮空 / 链跳合并可能变 | S9 |
| B7（换基线） | 敌人更新拆三段；随机流拆分；修失重击退 / 弹体查询半径 / 敌弹字段；敌方投射物池、我方投射物池合一 | **会变（一次性）** | B1、B2、B5；用户同意 |
| B8 | 热字段平行数组（段首读入、段尾写回）+ `OPT_CPP` 对照位 | 不变（相对 B7 基线） | B7 |

## 8. 需要用户定的事项

> **2026-10-15 用户全部批准（协调人转达），按建议执行**：
> 1. B7 换基线：**接受**（拆随机流、敌人更新拆三段、修 §3.4 ⑥⑦⑨ 三个 bug；开始前先告诉协调人，由协调人安排云端新基线）。
> 2. 原生代码形式：**纯 C++ 内核 + 桌面 / 云端 GDExtension + 网页把同一内核编进自编的 nothreads 模板**（§4.6、§4.7）。
> 3. 网页包体：**硬线 ≤ 48 MB**（B 站 Toy 50 MB 留余量）。
> 4. legacy 干员测试：**录金样 TRACE 后下线**。
> 5. 排期：**0a 立即派**；0a 完成后按 §7.2 顺序做 B1 → B6（同 seed 不变），B7 前通知协调人。每项合入前量一次 7–10 分钟段帧时（同局轮换）写进提交说明。
>
> 下面是原来的问题，保留作记录。


1. **B7 换基线**：敌人更新拆三段、随机流拆分、修 3 个 bug（失重对部分击退无效、我方弹体查询半径偏小、部分敌弹不带来源）会让同 seed 结果整体变一次、胜率可能小幅漂移。是否接受？（不接受也能做原生化，但原生段就必须逐表达式复刻现在的回调与随机次序，工作量和风险都大得多。）
2. **原生代码的形式**：建议纯 C++ 内核 + 桌面 / 云端用 GDExtension、网页把同一内核编进自编的 nothreads 模板（§4.6）。这意味着网页包从此用自编模板（和 Windows 一样记版本与 sha256），并多维护一套 emscripten 工具链；或者选全平台 GDExtension（网页用官方 dlink 模板，包体与启动开销未知，要先量）。
3. **包体**：网页 zip 现约 40 MB，B 站 Toy 内测上限 50 MB。dlink 方案的增量未知（要实测）；自编模板方案可用 build_profile 抵消甚至变小。
4. **legacy 干员测试（7538 行）**：录一次金样 TRACE 后下线，还是继续维护。
5. **排期**：阶段 0a 可以马上分给各会话做；0b / 1 / 2 建议排在内容开发的空档，由协调人定先后。
