# 286 · 代码整理盘点与去冗余（11-06 夜）

> 用户 11-06 睡前全权：「代码架构整理去冗余」排第一，行为不变。本篇是盘点 + 实施记录，分支 `claude/code-cleanup-ff82e2`，基线 main 319b5de4b。
> 方向沿用 docs/101（10-15 审计）、docs/126（10-22 架构复审）、docs/39（代码结构）里已定的门面（afflict / build_guide；时间 / 镜头 / 按键统一），不另起一套。
> 「TRACE」= 同种子逐行比（tools/gcp/render_jobs/cleanup_verify.sh：被测提交 vs 基线提交，画画面跑）。

## 0. 结论

| 批 | 内容 | 净删行 | 风险 | 验证 |
|---|---|---|---|---|
| 第一批 b205472bf | 死代码（69 个函数 / 常量 / 成员）+ 2 个无引用脚本 + 4 个已定案的回退开关 | 约 1170 | 低 | GCP 全量 + 12 人 TRACE（§5） |
| 第二批 33e572b1c | pxplane 重复小工具合并到 render/px_util.gd | 约 73 | 低 | 同上 |
| 第三批 82084b428 … f7e4712a9（11-12） | 拆大文件：world / fx_pxplane / ult / character 拆出 17 个模块 | 0（纯搬移，+331 行是签名与 preload） | 中 | §8 |

**整体判断**：精确重复的代码很少（全仓 ≥5 行的完全相同函数体只有 122 行），冗余主要是两类：① 早期功能换代后留下的无调用函数和回退开关；② 大文件（world.gd 5.7k、fx_pxplane.gd 5.0k、character.gd 3.1k、ult.gd 2.7k）里的长 match 分派。①这次清掉了能确定的部分；②要等美术分支停下来再拆（§4）。

## 1. 死代码（第一批已删）

做法：扫 game/ 与 tools/ 全部 .gd / .tscn / .json / .py / .sh / .js，去掉注释后，某个顶层函数 / 常量 / 成员变量的名字在全仓只出现一次（就是定义处）即判死；删完再扫，直到不动点（两轮）。动态调用（`call(fn)`、custom 积木名、`"_exec"` 等）的名字都写在 json / 字符串里，会被计数，不会误删；`test_<id>` 这类按名字拼的测试函数在 tests/ 下，不在删除范围。

| 文件（game/scripts/） | 删掉的名字 |
|---|---|
| boss_ai.gd | draw_warns、_draw_warns |
| characters/blocks/seg_specter.gd | h3_follow_away |
| characters/blocks/seg_ulpianus.gd | HW_WATER |
| characters/character.gd | _draw_skill_floor、draw_entities_over（空的旧钩子，没有子类覆盖）、downed_seconds |
| characters/op_api.gd | play_anim_fx、draw_spr_on |
| core/medals.gd | def_by_id |
| core/roster.gd | pending_total |
| enemies/bosses/saint.gd | _snipe（卡门旧狙击，已不出招） |
| enemies/shot_pool.gd | _layer_keys |
| game.gd | backlight、_lamp_r、_shuffle（docs/101 S6 旧名转发，分支已全部合完）、OPT_GEM … OPT_ATLAS（7 个旧 --optold 位说明常量，位本身由各处数字判断）、TILE |
| relic_fx.gd | dust_t |
| render/boss_attack_draw.gd | _facet |
| render/fx_pxplane_exu.gd | owns_halo |
| render/fx_pxplane_kal.gd | LINK_D、MELT_RED |
| render/fx_pxplane_lp.gd | SIG |
| render/paranoia_bubble.gd | PALETTE |
| render/vfx.gd | LVUP_CYAN |
| render/world.gd | CROWD_FROM、CROWD_SPAN |
| run/enemies.gd | slot_count |
| run/motion_shot.gd | rec_segs |
| run/run_stats.gd | LAMP_NAMES |
| run/shop.gd | merchant_col |
| run/ult_fx_c.gd | SZ_CUT_DT、SZ_CUT_HIT |
| run/ult_moves.gd | AUTO_OPS |
| run/ult_px_exusiai.gd | ring_pulse、hf_mark、lock_break、reticle_break |
| run/ult_px_ho.gd | JADE_D |
| run/ult_px_ir.gd | _plume |
| screens/headhunt.gd | BAG_T、ZIP1、ZIP_STEP、BURST |
| screens/hud_allyhp.gd | m3_low |
| screens/hud_banners.gd | Bars |
| screens/hud_bars.gd | draw_status_bar |
| screens/hud_ult_v.gd | LX |
| screens/meta_tree_ui.gd | C_DISC |
| screens/node_cards_ui.gd | ROMAN、_ending_edge |
| screens/run_stats_screen.gd | SEG_S |
| screens/settle/settle_base.gd | mvp_row |
| screens/tide_ui.gd | SEL_ICO2 |
| screens/title_base.gd | map_title、map_title_en |
| settings.gd | hidpi_render |
| sfx.gd | play_stinger、voice_stem |
| title.gd | _hunt_ready |
| ui.gd | C_D_SEL、porthole |

整文件：

- `title_bg.gd`（726 行）：旧沙滩封面，10-24 换深海水母版（title_deep.gd）后只剩 doctor_run_test 一处锚点检查引用；检查项一并删，title_op_pick 里 `has_method("reload_guest")` 的死分支删。
- `render/retreat_fx.gd`（59 行）：全仓无引用（撤退表现已改走 squad.remove 的 fx）。tests/retreat_capture 录像脚本不依赖它，保留。

tests/ 下只被录像 / 截图用、没有快检项引用的场景（attack_timing_capture、wisadel_s2_capture 等 25 个，docs/131 已列过）**不删**：它们是按需手动跑的录像工具。

## 2. 已关开关

### 2.1 已删（第一批）

条件：缺省就是「新」、用户已明确定案、回退值放了一周以上没人再用。

| 开关 | 定案 | 删掉的东西 |
|---|---|---|
| render/hit_rings | 10-13 用户删干员命中装饰圈 | declutter.hit_rings 与 7 处回退绘制（ob_hw 疾风环、德克萨斯终结亮环、世界层 op_hit 环 / 法术弹冲击环、character pfx 环） |
| render/hit_spokes | 10-13 用户删放射线 | declutter.hit_spokes 与 6 处回退绘制（Mon3tr beamray、推进之王狮鬃纹 / 光柱放射、维什戴尔爆炸刀锋、水花放射纹、rays） |
| sustain/regen_div | 10-13 时间成长改入队台阶（docs/83） | combat.regen_time_mult（恒为 1） |
| atkspeed/legacy_floor | 10-25 整条攻击条等比缩放 | 旧 min_duration 下限与 min_rest 间隔两处分支 |

只删绘制分支，粒子的生成、计数、寿命一律不动（画面随机流 vrng 的消耗次数不变）。

### 2.2 留着（待定，见 §6）

缺省 0 / 关、但不是「已否决」，或是对照 / 调参旋钮，这次不动：

- 终结技转平面 `ult/px_plane_<id>`：11 人全部缺省 1（用户逐个过了），**flag = 0 的原版画法分支**还在（ult_moves*.gd、ult_px_*.gd 里 `_px_on()` 一类判断）。是否删原版见 §6-1。
- `fx/recipe`（运行时特效配方，11-05 新方向试点中）、`render/gem_cap`（11-05 候选）、`render/light_share` / `late_read_*`（docs/251 后期可读性，用户批了但缺省关）、`render/clarity_bloom`：都是在途试验，不碰。
- `feel/move_sticky`（10-24 用户试过、缺省关；还有 `--sticky` 开发参数）、`render/optical_fg_px`（-1 原虚化 / 1 像素剪影 / 0 不画缺省）、`render/optical_normals`（对照用）、`render/dash_tell_flow` / `dash_tell_white` / `ebullet_outline`、`fx/material_lappland` / `material_fluid`、`fx/boss_squash` / `heavy_knockback`、`shield/block_invuln`、`squad/solo_buff`、`bot/swap`、`link/v2_spread`、`ult/cult_on`、`ui/link_cue`、`boss/break_text_final`、`boss/izumik_lamp_eat`：都是「0 = 现行」的数值或回退旋钮，删掉省不了多少行，留着方便回退。§6-2 列了建议下一轮删的几个。
- balance.json 里约 230 个键不在代码里以字面量 `"段/键"` 出现：绝大多数是拼名字读的（`boss/hp_x_` + 类型、`ult/dmgk_` + 干员、`link/bond_buff_` + 羁绊名），不是死键。这次不清数据。

## 3. 重复实现

全仓扫 ≥5 行、去注释后完全相同的函数体：

| 重复 | 份数 | 处理 |
|---|---|---|
| 「这一拍（1/15 秒）出过几个」计数：fx_pxplane._lm_beat_n + fx_pxplane_ang / exu / ir / lp / sa / sz / wd._beat_n | 8 | **第二批已合**：render/px_util.gd `beat_n(cnt, t, key)`，各文件保留原名一行转发、各自的计数表不变 |
| 「挑最近一档」：fx_pxplane / gl / su / ul._bucket、ir / lp / sa._near | 7 | **第二批已合**：`PxU.nearest(opts, v)`（kal._bucket 是「不超过 1.1 倍的最大一档」，语义不同，不动） |
| ult_moves / _b / _c 的 `_hit`（带 cap 的一段伤害） | 3 | 未合：ult_moves 预载 _b / _c，反向引用会成环；要合得放进 ult.gd 或新文件。8 行 × 2，收益小 |
| seg_logos.hw_bolt_pose / fx_recipe._bolt_pose | 2 | 未合：fx_recipe 是试点中的新特效方向（docs/245），等试点定了再合 |
| ult_px_ir / ult_px_mz `_glow`、fx_pxplane_ir / ult_px_ir `_star` | 2 | 未合：两处都是本周在途美术文件，等美术停手 |
| ishar_combos / izumik `card_names`、link_fx_common / ult_pixfx `pick` | 2 | 未合：5 行，跨模块，收益小 |

**preload 常量**：同一个脚本在多处各写一份 `const X = preload(...)`（balance.gd 30 多处、data.gd、mid_cards.gd 等）。这是 GDScript 的正常用法（每个文件自己声明依赖），不算冗余，不动。

**结构性重复**（不是逐字相同，是同一套写法抄了 N 份）：

- 20 名干员的 pxplane / ult_px 文件各自有「配色表 + 帧条键前缀 + 事件 match」，写法一致但内容各异。合成数据驱动要先定「转平面」的最终格式，属于美术管线的事，不在本次范围。
- 世界层 `_draw_fx`（world.gd，573 行）一个 match 分 60 多种 fx kind，和 vfx.gd、各干员 `_draw_pfx` 有部分画法相同（环、放射线、十字）。这次删了其中已废弃的环 / 放射线回退；其余要合得先拆文件（§4）。

## 4. 过大的脚本（第三批，未做）

| 文件 | 行 | 函数 | 拆法 | 冲突风险 |
|---|---|---|---|---|
| render/world.gd | 5668 | 178 | `_draw_fx`（573 行）→ render/world_fx_draw.gd；`_draw_enemy_full` / `_dc_*` 敌人绘制缓存（约 700 行）→ render/enemy_draw.gd；`draw_warn_outlines` / `draw_zone_band` / `classify_tells` 预警（约 400 行）→ render/telegraph_draw.gd（已有，顺着放） | 中：帧率会话今晚要改 world.gd，**建议帧率会话开工前或做完后再拆**，别同时动 |
| render/fx_pxplane.gd | 4959 | 183 | 按干员前缀（hsg_ / lm_ / ey_ / sg_ / sk_ / tx_ …）照现有 fx_pxplane_<id>.gd 的做法拆出 6–7 个文件，主文件只留帧条表、通用画法、分派 | 高：pxplane-texas、trusting-noyce（拉普兰德终结技）两条在途分支都在改它 |
| characters/character.gd | 3109 | 224 | docs/126 已列：JSON 加载 + 文本公式求值（约 180 行）、契约校验（约 120 行）挪到 operator_defs / operator_contract | 中：trusting-noyce 在改 |
| run/ult.gd | 2731 | 161 | 瞄准已拆 ult_aim；可再拆 HUD 徽记 / 冲击帧 | 高：终结技美术在途 |
| game.gd | 2343 | 64 | docs/126 已列：`_ready` 里的难度预设 / 批跑参数解析挪到 run_setup.gd | 低，但帧率会话可能动 `_update` |
| gallery.gd、title_op_pick.gd、autotest.gd | 2.2–2.5k | — | 图鉴演示 / 选人页 / autotest.step | 低，收益也低 |

结论：第三批的最佳时机是**美术分支合完、帧率会话交出后**，否则拆分本身没风险，但会让三四条在途分支全部变成大冲突。

## 5. 验证

- 每批推到 origin 后在 GCP 跑 `tools/gcp/render_jobs/cleanup_verify.sh`：
  1. 真全量快检（`ci_pack.sh --nocache`，**不重录金样**：积木等价金样是基线 319b5de4b 上录的，整理后必须原样通过）；
  2. 跨提交同种子 TRACE：被测提交 vs 基线 319b5de4b，12 名干员（水月、维什戴尔、德克萨斯、凯尔希、推进之王、艾雅法拉、斯卡蒂、能天使、艾丽妮、星熊、浊心斯卡蒂、归溟幽灵鲨）各 240 秒，**画画面跑**（Xvfb + opengl3，绘制代码也执行），逐行比。
- 结果：见 §7。

## 6. 待定（需要用户 / 协调人拍板）

1. **终结技转平面的原版画法**：11 人 `ult/px_plane_<id>` 都已缺省 1（用户逐个说「新版没问题」）。原版（flag = 0）的绘制分支还在，约占 ult_moves*.gd 的几百行。删了就不能再切回原版对照。建议：等用户把 20 人终结技都过完（docs/280 待定重做名单）后一次删。
2. 建议下一轮删的回退旋钮（都已定案两周左右）：`render/optical_fg_px` 的 -1 / 1 分支（10-24 用户「看不出来区别」，缺省 0 不画）、`render/optical_normals`（对照用）、`render/dash_tell_flow` / `dash_tell_white`（10-24 收敛冲刺预警）、`feel/move_sticky`（10-24 试过没开）。要用户点头，因为都是用户亲自试过的手感 / 画面。
3. 第三批拆大文件的时间：建议排在帧率会话交出、pxplane-texas 与拉普兰德终结技分支合入之后（§4）。

## 7. 结果

| 运行 | 提交 | 全量快检 | TRACE（12 人 × 240 秒，画画面） | 积木等价 |
|---|---|---|---|---|
| cloud-results/cleanup1-b205 | 第一批 d3a53e2b0 | 194 / 195 通过，唯一红项是积木等价「金样过期」（按代码哈希判过期，不是不同） | 12 / 12 逐行一致 | — |
| cloud-results/cleanup2-33e5 | 第二批 33e572b1c | 同上 194 / 195 | 12 / 12 逐行一致 | — |
| cloud-results/cleanup-eq-8e43 | 8e43100bc（含两批） | — | — | `ARK_EQ_FORCE=1` 强制对改前金样比：**28 / 28 与金样相同** |

game/ 合计：71 个文件，+65 / −1286 行（净删约 1220 行）。金样过期按惯例由协调人合入后统一重录（内容会与现在相同，只换代码哈希）。

## 8. 第三批：拆大文件（11-12，分支 claude/frosty-colden-7dda5d，基线 bc5fb7d5b = integ-1111 + 英文版）

做法统一：被搬的函数原样搬到新文件，改成 `static func f(宿主, 原参数…)`；函数体里对宿主成员的读写加宿主前缀（world 用 `wv.`、fx_pxplane 用 `pv.`、ult 用 `uv.`、character 用 `ov.`），
宿主常量 / 静态函数经宿主脚本常量（`W.` / `P.` / `U.` / `C.`）取，preload 常量在新文件各抄一行（同一资源）；`g` 在函数开头取一次成局部（同一对象，少一次属性查找）。
宿主类型都标注（`wv: W` 等），成员名拼错在加载时就报错；子类覆盖的方法经宿主实例调用，动态分派不变。
状态变量全部留在宿主（实例状态），搬走的只有函数和只被它们用的常量；有外部直接调用（其他脚本 / 测试 `x.f()`）的函数留在宿主，不加转发。
搬移用一次性脚本做（按词法改写 + 局部变量遮蔽检查），每个文件一个提交。

| 提交 | 宿主（行数前 → 后） | 新文件 |
|---|---|---|
| 82084b428 | render/world.gd 5916 → 4014 | world_fx_draw（_draw_fx 分派 + 刀光颗粒 / 月牙 / 灯标驱散环）、world_ebullet_draw（敌方弹幕三遍）、world_zone_draw（缩圈 / 溟痕带）、world_shield_draw（队长护盾）、world_tells_draw（敌人前摇提示 / Boss 状态 / 落柱）、world_aura_draw（巢穴光环 / 灯标） |
| 067803849 | render/fx_pxplane.gd 5664 → 1574 | 照已有 gl / kal / su 的做法按干员拆：fx_pxplane_hsg / lm / lg / ey / sg / mz / sk / tx（节标题说明随文件走） |
| 9435a9b44 | run/ult.gd 2828 → 2432 | ult_draw（舞台、冲击帧、像素形、定格白、连携闪、吸气、起手条） |
| f7e4712a9 | characters/character.gd 3213 → 2863 | op_skill_seq（多段技能帧条序列）、op_rush（突击冲锋 / 低频自冲刺 / 拖尾） |

**没拆的**（留给以后，理由）：
- world.gd 敌人绘制缓存（`draw_enemy` / `_dc_*` / `_draw_enemy_full`，约 700 行）：每帧每只敌人都走，搬出去每次成员访问多一跳，帧率会话量过这里是瓶颈，不在纯整理里动。
- character.gd 命令 / 走位 AI（`roam_target` / `_cmd_*` / `_izu_intercept` 一族，约 450 行）：command_ai_test 等按实例方法直接调（含 `has_method`），要拆得一起改测试，另开。
- fx_pxplane 各节的状态变量（`_lg_fire_t`、`_sk_st` …）仍在主文件：是实例状态，搬要改成每节一个实例，属结构调整不属搬移。
- game.gd（2819）/ gallery / title_op_pick / autotest：§4 已判收益低；screens/*.gd 英文版刚合，不碰。

**验证**：
- 本机：每个新文件 Godot 加载无报错；窗口跑（画画面）16 局 × 75–90 秒（星熊、流明、逻各斯、艾雅法拉、推进之王、水月、浊心斯卡蒂、德克萨斯、安洁莉娜、拉普兰德、乌尔比安、铃兰、维什戴尔、能天使 等），SCRIPT ERROR 0；
  快检单项 core、ult_playback、angelina_skill_anim、assault_dash、skill_lifecycle、render_perf、command_ai、mizuki_skill_anim 全部通过（`--auto` 对这些核心文件判全量，全量放 GCP）。
- 注：`cleanup_verify.sh` 的基线检出这次在云上导入失败，改成两台机器分别以基线 / 被测提交做主检出跑同一组局再逐行比（scratchpad 脚本 trace_base.sh，内容同 cleanup_verify 的 TRACE 段）。
- GCP：`cleanup_verify.sh`（真全量快检 + 12 人 × 240 秒画画面跨提交 TRACE，对基线 bc5fb7d5b）与 `ci_cmd.sh`（重录金样 + 全量）——结果见下表。

| 运行 | 提交 | 全量快检 | TRACE（12 人 × 240 秒，画画面，对 bc5fb7d5b） |
|---|---|---|---|
| cloud-results/ci-f7e4712a9 | f7e4712a9 | 214 项红 12：其中 9 项基线 ci-bc5fb7d5b 同样红（release_slim、check_map、图鉴连携行 v2、EA 标题、触屏布局、图鉴敌人攻击演示、Boss 演练入口 ×2、卡片描述不串台，均与本批无关）；新增 3 项是测试直接调了搬走的技能序列函数（`o._tick_sq_atk()` 等），8190ceed3 改测试后本机三项通过 | — |
| cloud-results/cleanup3b-f7e4 | f7e4712a9 | 同上 3 项 + 本脚本不重录金样 / 不建贴图索引的环境项（积木等价金样过期、graph_lint、asset_index） | 未出结果：基线检出导入时 Godot Aborted，基线局全部超时 |
| cloud-results/trace3c-8190 | 8190ceed3 | — | 未出结果：基线检出（git worktree 浅取）在云上导入三次都 rc=1，同上 |
| cloud-results/trace3d-base + trace3e-8190 | 基线 bc5fb7d5b / 8190ceed3 各自做主检出、同镜像同参数跑 | — | **12 / 12 逐行一致**（两边各自 A/B 也逐行一致；texas 153 行、irene 148 行两边相同，是局内阵亡提前结束），SCRIPT ERROR 0 |

## 9. §6 旧回退开关（11-12 复查）

结论：**这次一个也没删**。按协调人口径「只删已定案、缺省值不会再改的，拿不准的列进文档」，§6 列的都还差用户一句话：

| 开关 | 现缺省 | 状态 | 删掉能省 |
|---|---|---|---|
| `render/dash_tell_flow` / `dash_tell_white` | 0 | 10-24 收敛成缺省（docs/139 §7.2），三周没人改回；docs/286 当时写的是「要用户点头」 | world_tells_draw._tell_line 两处判断与水纹 / 白芯画法 |
| `render/optical_fg_px`（-1 / 1 分支） | 0 | 10-24 用户「看不出来区别」 | world/map.gd 前景两个分支 |
| `render/optical_normals` | 0 | 对照用 | settings.gd 一处判断 |
| `feel/move_sticky` + 对内包 F8 `sticky_on` | 0 | 10-24 用户试过没开 | game.gd 移动粘滞一段 + F8 切换 |
| `ult/px_plane_<id>` 原版画法（§6-1） | 1 | 等 docs/280 二十人终结技过完一次删 | ult_moves*.gd 几百行 |
| `render/knight_frost_tell`（json 里没有，代码缺省 1） | 1 | 10-27 骑士冰裂纹预警，旧斜线画法的回退 | telegraph_draw.knight_line 与 world.gd 一处判断 |
| `boss/break_text_final` | 0 | 10-28 用户定「只给 Boss 写字」，1 = 恢复写字 | combat.gd 一处 |

另：代码里 `Bal.v("段/键", 缺省)` 读了、balance.json 没有的键现在约 770 个（docs/199 §4 时 366），绝大多数是调参旋钮不是开关，不在本次范围。
建议：用户点头后按上表前四行一次删（都是画面 / 手感回退，删分支不动缺省路径，TRACE 应逐行一致）。
