# 207 本地 Spine 自产干员动作帧条试点（乌尔比安终结技）

10-30，分支 `claude/spine-anim-pilot`（基于 `claude/ult-proto` 8bd0c6881）。用户 10-30：「角色本人动作动画我们这里有全套的 spine 工具，我们也可以做」。本页回答：用本地原作 Spine 自己出干员动作帧条，可不可行、一套要多久、哪些还得人工、哪些人能做。

## 1. 结论

- **可行，而且大部分已经是脚本**。`tools/spine_run_trial/run_trial.js` 早就能把原作 Spine 骨架逐部件像素化成游戏帧条，16 人的入场条、多人的跑步条和移动攻击都是用它出的。这次只补了三个小开关，就做出了乌尔比安终结技身体条。
- **形象一致性没问题**：用的是原作骨架和贴图，配色映射到本人部件调色板，所以瞳色、帽上红羽、白领结、双爪锚的形状都和原作一致（对照图第一、二列）。和 Codex 版比：同样来自原作 Spine，色调一致；我们的版本手里带着锚，人也略大，因为画布是 96 而不是 64，人的比例没变。
- **人工主要花在挑动作和对时序上**，渲染和接入是机械活。一个动作约 1–1.5 小时（会话时间，含审阅），见 §3。
- **20 人都有原作 Spine**（`build/prts_ref/_raw`，3.8 骨架 8 人、3.5 转 JSON 12 人），脚本两种都能读。「只有 8 人能做」只是说交互式姿势编辑台：它目前只开 3.8 骨架，其余 12 人得先跑出数据包才能进编辑台手调。脚本出帧条不受这个限制。

## 2. 这次做了什么

| 项 | 内容 |
|---|---|
| 动作 | 终结技身体条 `op_ulpianus_ult_spine`（8 帧，96 画布 @2x，foot (48,76)，另由 2×2 合并出 @1x） |
| 原作轨 | f0–f3 `Skill_3_Begin` 0.061 / 0.183 / 0.306 / 0.428（起手 → 后摆 → 抡出 → 锚离手）；f4–f5 `Skill_3_ReStart_A` 0.20 / 0.35（沿链冲）；f6–f7 同轨 0.55 / 0.80（落地握锚、收势） |
| 时序 | 逐帧 0.045×4、0.11×2、0.15、0.30；前 6 帧合计 0.40 秒，对齐终结技 `ult/ul_throw` 0.18 + `ult/ul_dash` 0.22，第 7 帧正好在落地时刻 |
| 改动 | 锚离手后（f3–f5）隐藏 `C_Weapon*` / `C_Chain*`，因为飞锚和锁链由游戏特效画；f3–f5 原作自带向前的根位移，这三帧水平钉回原地，位移交给游戏代码；调色板补两档铜色，否则锚上的铜轮会变灰 |
| 接入 | `ulpianus.json` sprites 加 `ult_spine` 并列进 extra_sprites；`ult_moves.gd` `_ul_start` 在开关打开时 `play_vis_anim("ult_spine")`，落地时不再播普攻。开关 `--bal=ult/ul_spine_body=1`，**缺省关**，关着时行为与原来完全相同 |
| 工具 | `run_trial.js`：`sample.anims`（逐帧换轨）、`sample.hide`（逐帧按槽名前缀隐藏）、`sample.pinX`（逐帧钉髋骨水平位置）、`paletteAdd`（补调色板）；新增 `ref_sheet.js`（原作高清联排，用来挑轨和时刻）、`compare3.py`（三列对照：原作直出 / 本流程 / Codex） |
| 复现 | `NODE_PATH=<主仓库>/build/prts_ref/_node/node_modules node tools/spine_run_trial/run_trial.js tools/spine_run_trial/cfg/ulpianus_ult.json --out build/spine_anim_pilot/ulpianus_ult/frames --clean --hires`，再用 `sheet.py --size 192` 拼条，`make_op_1x.downsample` 出 @1x，最后跑 `asset_index.py` |

审阅产物都在 `build/spine_anim_pilot/ulpianus_ult/review/`，不进 git：逐帧 ×8、GIF、`compare3.png`。

验证：`ult_rec.py --clips ulpianus` 用同一种子录开 / 关两段（`--camzoom=150`、不刷怪团），两段都没有脚本错误；逐帧比对，差异集中在掷锚到落地这一段的队长身体上。并排录像在 `build/spine_anim_pilot/out/ulpianus_ult_spine_on_vs_off.mp4`。本地快检 asset_index / art_lint / data_lint / siege_ulpianus_art 全部通过。

## 3. 每个动作要多久，哪些是人工

| 步骤 | 人工 / 脚本 | 耗时（一个动作） |
|---|---|---|
| ① 列出原作轨（`anims_probe.js`），出高清联排（`ref_sheet.js`），挑轨和时刻 | **人工判断**（要看懂原作动作、对上本作玩法时序） | 15–20 分钟 |
| ② 写 cfg：时刻、逐帧时长、离手部件隐藏、根位移钉住 | 半人工（照模板改数） | 10 分钟 |
| ③ 渲染、像素化、拼条、@1x、索引 | 脚本 | 1–2 分钟 |
| ④ 看逐帧 ×8 和三列对照：色调、瞳色、饰件、出界、碎点 | **人工验收**（docs/104 人眼先行） | 10–15 分钟；有问题回到 ② 再来一轮 |
| ⑤ 接入：json 登记 + 在玩法代码里挂播放点 | 半人工（新槽要写代码；替换现有槽只改 json） | 10–30 分钟 |
| ⑥ 录像审阅（`ult_rec.py`） | 脚本 | 5–10 分钟 |

- 一个动作：**约 1–1.5 小时**。替换已有槽（同帧数同锚点换图）大约是这个时间的一半。
- 一个干员一整套（待机、跑步、普攻、移动攻击、技能 1–2 条、终结技、死亡、入场，约 8–9 条）：其中待机 / 跑步 / 普攻 / 移动攻击 / 入场已有脚本 cfg（20 人大多做过），重出只要几分钟。真正新做的是技能和终结技 2–3 条，**约 3–5 小时 / 人**。
- 20 人的终结技身体条全做一遍：约 20–30 小时会话时间。适合按人拆给几个会话并行做，每个会话只碰本人的 cfg、帧条和 json。

**还得人工的部分**：挑轨和时刻（原作技能轨常常一条里同时包含起手、瞬移、隐身、特效部件，要判断取哪几帧，例如乌尔比安 `Skill_3_Begin` 后半段人是隐身的）；对玩法时序；决定哪些部件交给游戏特效画；像素尺度下的可读性验收。

**能继续脚本化的部分**：时刻可以按原作事件（OnAttack 之类）自动对齐出手帧（`make_op_1x` 普攻已经这样做）；可以自动检测脚下出界和碎点；可以自动找调色板缺色（原作直出与像素帧的色差热点，这次的铜轮就属于这种），然后自动补色。

## 4. 8 人以外的 12 人缺什么

| 人 | 骨架 | 缺什么 |
|---|---|---|
| 安洁莉娜、能天使、艾雅法拉、星熊、凯尔希、塞雷娅、推进之王、斯卡蒂、浊心斯卡蒂、德克萨斯 | 3.5（已转 `.35.json`） | 脚本出帧条：**不缺**，cfg 写 `json` 源即可（入场条已经这样出过）。交互式编辑台：缺 3.5 数据包，需先用 run_trial 生成 `editor_pack` 再 `--source` 打开 |
| 拉普兰德、歌蕾蒂娅 | 3.5 | 上面那些之外，还缺 bz_18 部件包（调色板和比例）：现在用 cfg.pack 从 Codex 帧条取调色板和尺度，能出图，但配色依赖那份 Codex 条 |

另外几点注意：
- 召唤物和第二形态（凯尔希的 Mon3tr、归溟替身）有单独的骨架或替身骨，需要按 `retarget` / `scaleMul` 的写法单独配置。
- 原作技能轨里的叠加光效（blendMode ≠ normal）像素化后会变成白块。要么开 `skipAdditive` 不画，要么交给游戏特效画。

## 5. 待决

- 三列对照与录像交用户看。认可的话开关可以改成缺省开，并把这条身体条推广到其余 19 人的终结技。
- 画布 96（@2x 192）比普通 64 画布大，因为抡锚要占地方。游戏里 foot 对齐后人的大小不变，只是贴图更宽。

## 6. 第二批终结技本体动作（协调人 10-30 排单）

做法：从原作技能轨整条重出，替代 Codex 第二批动画单 `codex_order_anim.md`（6ba45c89b）。特效层由 fx-strip-pilot / session-2 叠在本体上，锚点用本体条脚底（96 画布 foot (48,76)）。
顺序：维什戴尔 → 艾丽妮 → 逻各斯 → 流明 → 水月 → 归溟幽灵鲨 → 铃兰 → Mon3tr（骨架需下载）→ 其余人。每做完 2 人接游戏、发三列对照与录像。

通用接法：
- 统一开关 `--bal=ult/spine_body=1`（缺省关）。`ult_moves_b / _c._spine_body(o)` 在终结技开头播 `ult_spine`，原来借用的 attack 段不再播；乌尔比安也认这个开关。
- `tools/spine_run_trial/ult_install.py <id>`：把逐帧拼成 `op_<id>_ult_spine@2x / @1x`，写 json 的 sprites.ult_spine 和 extra_sprites，重建索引。
- `compare3.py --codex-at 行=png`：Codex 第二批只交了 f0 和代表帧两张关键帧，按行放进第三列。
- `run_trial.js` 新增 `sample.kick`：逐帧整个人绕脚底后移 / 后仰，用于原作循环轨静止时补出后坐。
- `character.gd` 新增 `sprites.<槽>.vis_order`（纯画面动作按帧号表播、可重复）：循环段不用重复画帧，只影响 play_vis_anim 的画面。
- 契约 V2：顶层 foot 是小数或画布口径不同（维什戴尔、水月）时，`ult_install` 自动写 `foot_exempt` 说明（同入场 / 跑步条做法）。
- `run_trial.js`：`sample.pinY`（跃起类竖直位移钉回，腾空由游戏给）、`cfg.ground`（召唤物没有常规腿时直接给地面高度）。
- `ult_install.py`：cfg 写 `install: {op, slot, tex}` 可装进主人 json 的别的槽（Mon3tr → kaltsit.json `m_ult`）。
- 召唤物：`ob_summon._mf_frame` 认 `s.ult_anim = {key, t0}`，先播完这一条（按主人 sprites 的 frame_durations / vis_order）；凯尔希终结技落地时在开关打开下设置。
- 发用户前先过 vreview 预审（`record_sprite` 审对照图与特写，`ult_fx --crop left` 审实机录像左半）。

| 干员 | 原作轨 | 帧 / 时长 | 对齐玩法 | 人工处理 |
|---|---|---|---|---|
| 维什戴尔 | Skill_3_Begin 架炮 → Skill_3_Loop 炮口朝天 → Loop 放平 → Skill_3_End | 10 帧 / 1.00 秒 | f3–f6 对 6 排炮击（0.15–0.65 秒） | 原作循环里炮身不动，用 kick 补后坐（隔帧后仰 6°、后移 4 px） |
| 艾丽妮 | Skill_3_Start 拔剑起风 → Skill_2 风中斩 ×6 → Skill_3_Attack 回原地举手炮开枪 | 12 帧 / 1.055 秒 | 起风 0–0.22、6 刀每 0.075 秒、0.675 秒回原地、0.735 秒开枪 | 隐藏 `F_Weapon(2)`（原作刀光拖影，按单子归特效层）；原作 S3 里化风那段是全空帧，按单子「风中一现一刀」改借 Skill_2 斩击 |
| 逻各斯 | Skill_3_Begin 抬手 → Skill_3_Idle 念诵 → Skill_3_Attack 一词（双臂展开）→ Skill_3_End | 10 帧 / 0.91 秒，64 画布 | f6「一词」落在 0.5 秒标记爆裂，停 0.15 秒 | 隐藏半透明咒刃 F_Weapon3 / F_Weapon_light（像素化后成白点，归特效层） |
| 流明 | Skill_3_Begin 举起 → Skill_3_Idle 持械站定 6 帧 × 0.33 秒 → Skill_3_End | 10 帧 / 2.42 秒，64 画布 | 0.2 秒光柱升起时举到位，覆盖 2 秒光柱 | 单子要「站定举高」，所以不用会大幅摆灯的 Skill_3_Loop；原作 S3 举的是长杖（单子：持械以 PRTS 技能动画为准） |
| 水月 | Skill_1 伞击：后拉 → 由下往上挥伞 → 收 | 10 帧 / 1.10 秒 | f2–f5 对 0.15–0.65 秒触手横扫 | **原作没有「俯身按地」**（技能全是伞的动作），借 Skill_1 挥伞对「抬臂随横扫一挥」；破土交特效层 |
| 归溟幽灵鲨 | Skill_3_Begin 举锯 → Skill_3_Attack 抡锯一圈 6 帧 → Skill_3_End | 10 帧，播 3.17 秒 | 抡锯 6 帧 × 0.05 = 0.3 秒一圈，`vis_order` 循环 9 遍覆盖 3 秒 | 原作抡锯带根位移，钉回原地（她移动时由游戏位移）；引擎新增 `sprites.<槽>.vis_order` |
| 铃兰 | Skill3_Begin 捧杖闭眼 → 举杖伸手 → Skill2 扬杖 → Skill3_End | 10 帧 / 1.20 秒，64 画布 | 0–0.3 忍冬现身、0.3–0.6 停顿、0.6 扬杖对斩痕炸开 | 无 |
| Mon3tr（凯尔希终结技） | Skill_2 蜷身蓄力（往返）→ 张开 → Skill 张爪 | 8 帧，播 1.03 秒 | 落地起播，蓄力 0.48 + 张爪 0.12 = ult/ka_wind 0.6，爪最开那一帧落在爆点（之后解体） | 骨架下载自 PRTS（token_10002_kalts_mon3tr，Spine 3.8，放 build/prts_ref/_raw/mon3tr）；无 bz_18 部件包，比例 0.201 与调色板取 Codex `op_mon3tr_native_idle`；`cfg.ground = 0`（原作悬空）；召唤物走 `ob_summon._mf_frame` 新钩子 `s.ult_anim` |

验证：（第 1 组）本地无头跑一局，打印确认两人放终结技时 anim_kind = ult_spine（1.00 / 1.055 秒），没有脚本错误；快检 asset_index / art_lint / data_lint 通过。录像：`build/spine_anim_pilot/out/<id>_ult_spine_on_vs_off.mp4`（同种子，左开右关）、`<id>_ult_spine_closeup.mp4`（原速 4 倍特写）。第 2 组（逻各斯 0.91 秒 / 流明 2.42 秒）同样无头确认、无脚本错误。

### 6.1 其余 8 人原作轨评估（10-30）

| 干员 | 原作可用轨 | 判断 |
|---|---|---|
| 推进之王 | Skill：蹲 → 起跳空翻 → 举锤 → 砸地 → 起身 | 几乎一一对上，已出 cfg（pinY 钉竖直位移） |
| 安洁莉娜 | Skill2_Begin / Loop / End：举杖 → 托举 → 下压 | 对得上，已出 cfg |
| 艾雅法拉 | Skill_Start / Loop / End：起杖施法 | 对得上，已出 cfg |
| 星熊 | Skill_Begin 立盾 → Skill 顶盾 → Skill_End | 对得上 |
| 歌蕾蒂娅 | Skill_3_Startup / Begin / Chant / Loop / End：举矛吟唱 | 大体对得上（「收—停—爆」靠选帧） |
| 拉普兰德 | Skill / Combat：双刃斩、半圈旋身 | 部分对得上（原作没有连续四圈狂舞，需循环拼） |
| 斯卡蒂 | 只有 Attack（横斩，含转身） | **原作没有相近轨**（单子要举剑过头下劈），先跳过 |
| 塞雷娅 | Skill 是插盾 + 合手（治疗），Attack 是盾击 | **原作没有相近轨**（单子要一拳砸地；插盾入地可作替代，待定），先跳过 |

拉普兰德 / 歌蕾蒂娅的 cfg 原来指向别的工作树里的 build/lg_src，这里改用主仓库 `build/prts_ref/_raw` 的 3.5 骨架（cfg/*_raw.src.json）。
