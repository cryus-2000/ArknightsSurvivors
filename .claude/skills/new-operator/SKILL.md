---
name: new-operator
description: 加一名新干员（原作查证 → 设计稿 → characters/<id>.json 积木 → 转平面特效 → Codex 美术单 → 音效语音 → 文案 → 快检 → 木桩表与 GCP 同种子配对 → 交付）的完整清单与模板。在协调人派「加干员 X」「做第 N 批干员」、或要改一名干员的整套设计时使用；只调某个数值用数值口径（docs/80），只做特效用 pixfx / 各干员转平面文档。
---

# new-operator：加一名新干员

以拉普兰德（docs/122 设计稿、docs/273 转平面、`game/data/characters/lappland.json`、`seg_lappland.gd`）为样板。每步做完对一遍「完成标准」再往下走。
检查脚本：`python tools/new_op_check.py <id>`（只读，列缺项；见 §⑧）。模板在本目录 `templates/`。

## 0. 开工前

- 先读：AGENTS.md、docs/00_index.md「新会话先读 · 干员」行（61 → 26 文首 → 23 → 91 §0.5；改数值前 79、80）、docs/76。
- 在自己的工作树、自己的分支（`claude/op-<id>`）干活；主工作区不碰。入口文件 AGENTS.md / CLAUDE.md 不改（要改先列出来交协调人问用户）。
- **文档号先查最大号**：本分支、`claude/integ-1105` 和其他在途分支都可能占号（`git ls-tree --name-only <分支> docs/ | grep -oE 'docs/[0-9]{3}' | sort | tail -3`，各分支都看一遍取最大 +1）。
- 本机 Godot 同时最多 1 个；快检超出短本地检查、批跑、TRACE 一律上 GCP（docs/41、AGENTS「Cloud first」）。

## ① 查证（原作资料只取可查证来源，docs/76 §4）

1. PRTS 干员页 `https://prts.wiki/w/<干员名>`（MediaWiki API 取 wikitext 最稳）；解包 `Kengxxiao/ArknightsGameData` zh_CN `character_table / skill_table / handbook_info_table / uniequip_table`，英文名取 YoStar en_US（docs/76 附录 A.5）。
2. 逐项记：职业 · 分支、星级、阵营 / 国家 / 种族、**招聘合同 · 干员简介原文**（引言一字不改）、特性、天赋名与效果、技能名（中英）与效果、精二满级面板（生命 / 攻击 / 防御 / 法抗）、档案要点（客观履历 / 档案资料）、原作 Spine 动画轨与事件时刻（`tools/prts_spine.py <id>` 拉到 `build/prts_ref/<id>/`，不进 git）、立绘设定色（发 / 瞳 / 衣 / 武器）。
3. 每条写清出处（页面 + 段落 / 表名）；**查不到的不写**，任务单里写的名字原作查不到就照实写「查不到」并用本作自创名（docs/76 §5，docs/122 文首就是例子：任务单的「S2 狼之隐」原作不存在）。原作只有两个技能时第三技能本作自创另起名。
4. 来源 URL 登进 docs/76 附录 A（新开一节 A.x）。

**完成标准**：设计稿 §1 表每行都有出处列；附录 A 已加；没有「印象中」的条目。
**坑**：干员简介补充（描述句）≠ 引言；档案栏位 PRTS 写「未公开」就填未公开；技能 / 天赋名用原作（memory canon-skill-names），本作自创招式名不受约束。

## ② 设计稿（存 docs 新号，用 `templates/design_template.md`）

结构照 docs/122 / 123：§1 原作身份与技能（查证表）→ §2 本作改编（定位一句话 + 与同职业现有干员的区分；普攻、天赋（精一）、三技能、精一 / 精二、成长线 6 节点 + 节点 4 二选一 + 节点 5 沿路线、响应动作）→ §3 积木落地（用了哪些积木、需要的新积木清单、已知妥协）→ §4 数值预算表（docs/27 §9.1）→ §5 木桩表与对照 → §6 美术需求单 → §7 验收记录与待办。

硬规则：
- **普攻**：写形状、射程 / 半径、间隔、击退、前压；远近两态（如领主）写清切换条件与谁数次数。
- **精一**：普攻追加一个可感知的机制 + 画面上一个小新元素（输出位 ≤ +8%）；**精二**：普攻形态质变、一眼认出，动词不能和 docs/91 §0.4 表里已有的重复，替换不叠加（docs/91 §0.2 / §0.5）。
- **成长节点**（docs/202 §0）：节点 1、2 只落在普攻 / 已有天赋式行为 / S1；节点 4、5 可落在 S1 / S2，不依赖 S3；不做纯数值（倍率 / 半径 / 冷却 / 层数 +1），要新触发 / 新形状 / 新目标规则 / 引爆 / 标记 / 残留；普通节点自带 +6% 攻击（`NODE_ATK`）不动；不许第 7 个节点、不许 >20% 的单节点（docs/27 §9.5）。
- **每个节点玩家选了以后 1 倍像素能看出变化**（docs/310 标准）：设计稿里每个节点写「画面：……」一列。
- 终结技 Q / 连携 E（docs/198 / 199、280 §6）：新干员也要一个终结技、一个连携效果，名字与说明进 `ult_text.json`；连携不和已有的重复。
- 不改 `balance.json enemy / xp / levelup` 来适配她；不新增只对她生效的全局属性（用 `op:<id>` 作用域）。

**完成标准**：协调人 / 用户审过设计稿（新机制先给方案再做，memory self-tune-authority）；00_index 已加一行。

## ③ 数据（`game/data/characters/<id>.json`，积木优先）

从 `templates/character_skeleton.json` 起步（键序与拉普兰德相同；`_doc` 键只是注释，可留）。必备字段：

| 字段 | 要点 |
|---|---|
| `id / name / en / class / branch / lanes / col / trail_col` | `class` 用 docs/76 §5 的职业名；`trail_col` 主 / 辅色按 PRTS 立绘（docs/160）；`lanes` 是构筑流派（现有取值 melee / multi / summon / control / heal / weak，docs/181 / 197） |
| `script` | `res://scripts/characters/data_operator.gd`（有 `blocks` 时可省） |
| `base` | **全部**数字（攻击、间隔、射程、范围、各技能倍率、天赋系数）；积木与文字只用 `$key`，脚本只用 `base("key", 默认值)` 且默认值 = JSON 值（docs/27 §9.2、61 §0.3） |
| `leader` | 当队长的受击属性（max_hp / armor / arts_res / regen），`_doc` 写原作面板依据 |
| `sprites / extra_sprites / native_motion` | 帧条槽：`idle run attack skill death move_attack entry dash_run`，可加 `throw / s1cast` 等；`foot`、`frames`、`frame_durations`、`fire_time`；`sprites.skills.s1..s3.anim` 指定技能用哪条 |
| `attack / skills[3] / talent` | 玩家可见的名字与 `desc`（`{$key}` 占位，docs/61 §1.4）；`skills[i]`：`name en sp dur|permanent icon desc` |
| `hit_sources` | 每个伤害 `src` 都登记 `emitter origin range kind tags`（否则校验报错、藏品 Tag 对不上） |
| `progression` | 6 项：custom、custom、elite1、custom（带 `branch{a,b}` + `branch_desc` + `bot`）、custom（带 `routes{a,b}`）、elite2；精英节点带 `attack{name,desc}` 写普攻变化 |
| `blocks` | `attack / skills[3] / trait / talent / progression{<节点id>, elite1, elite2}`，可加 `zone / follow / hit_fx / summons / response` |
| `gallery` | `tags`、`desc`（图鉴机制说明）、**`intro`（招募卡简介）** |
| `recruitable` | 缺省 true；不想进招募 / 名册时写 false |

其他数据文件（新干员都要补）：

| 文件 | 内容 |
|---|---|
| `game/data/lore.json` `<id>` | `profile`（性别 / 出身地 / 种族 / 所属，按 PRTS）+ `lore`（引言 = 招聘合同原文 + 转述正文） |
| `game/data/balance.json` | `operators.<id>` = `{"tier": "A", "atk": 0, "aspd": 0, "range": 0, "skill_power": 0}`（先全 0，§⑨ 后再定档）；`vis_nodes/team/<id>`（精二给全队的一条效果，docs/249）；按需 `fx/hf_op/<id>`、`fx/melee_evo_op/<id>` |
| `game/data/ult_text.json` `ops.<id>` | 终结技 `ult{name,en,desc}` + 连携 `link{…}` |
| `game/data/ult_audio.json` `ops.<id>` | 终结技语音 `voice / voice_alt`、`hf_slot`（docs/205） |
| `game/data/synergy.json` / `skill_link.gd` 表 | 有原作关系（PRTS 可查证）才加连携对（docs/160_op_synergy） |
| `game/art/operators/avatar_eyes.json` `ops.<id>` | HUD 头像眼睛对齐 `{tex, fh, eye, d}`（memory hud-ult-badge） |
| `tools/balance_run.py OPS` | 加 id（solo / pairs 预设自动覆盖） |

**积木不够才写 `seg_<id>.gd`**，并在设计稿 §3 写明「为什么积木不够」。写法（照 `seg_lappland.gd`）：
1. `game/scripts/characters/blocks/seg_<id>.gd`：`extends` 当前链尾（现在是 `seg_gladiia.gd`），`op_blocks.gd` 的 `extends` 改指向新文件，op_blocks.gd 文首继承链注释同步。
2. 新瞬时积木 `verb.<前缀>_*`：登记 `seg_hoshiguma.gd EXT_BLOCKS` 与 `data_operator.gd EXEC_SEG`（+ `_ext_exec` 的 match），校验表（ob_check）认得它；docs/61 末尾加一节写参数。
3. 只走 op_api / 公共状态；玩法随机只用 `g.rng`，画面用 `g.vrng`；不在 .gd 里写裸平衡数。
4. 本链也被 `-s` 契约测试加载：**不许直接引用自动加载**（Sfx / Cfg / Pad / ui_motion 等；平衡值用 `preload("res://scripts/core/balance.gd")` 的 `Bal.v`，单例要用时 `get_node_or_null` + 运行时 load，memory no-autoload-in-render）。
5. `seg_<id>.gd.uid` 由 Godot 生成后**随脚本同一提交**；`.import` 文件别手写 uid（让 Godot `--import` 生成，GCP 上自动）。

**完成标准**：`python tools/check.py --only core` 0 失败（validate_operator：积木族名在表里、`$key` 都在 base、`src` 都在 hit_sources、`custom` ≤ 2、夹紧通过）；`--only data_lint` 通过。

## ④ 特效（转平面 fx_pxplane，成长节点必须看得见）

现行：20 人都走「转平面」（`fx/px_plane` 1，docs/246 / 254 / 273 各人页、标准 docs/270、口径 memory fx-style-pixelfx-noita）。**转平面接管后 `o.fx()` / `o.sparks()` / `spawn_fx_sprite` 全部不画**（`character.gd draw_pfx` 直接 return，只 `Pxp.KEEP_PFX` 白名单例外），所以节点 / 技能提示必须发 `_FXR.ev(o, "<事件>", {...})` 交给转平面画（docs/310 §2）。

1. 写转平面文档（docs 新号，照 docs/273）：配色表（依据原作）、每招拆法（立起层 / 贴地层 / E0 / E1 / E2 各多一个新元素）、范围档、实现、自查表。同一招元素 ≤ 3，红色只给危险。
2. 代码：`game/scripts/render/fx_pxplane_<短名>.gd`（本人一节）；`fx_pxplane.gd` 的 `IDS` / `METAS`（键前缀）加她，`ev / draw_floor / draw_over / sort_items / draw_sorted` 各一行转发；需要保留的旧粒子进 `KEEP_PFX`。
3. 帧条：`tools/pxplane_bake_<id>.py`（图形 `pxplane_<id>_art.py`）烤 `game/art/fx/pxp/pxp_<前缀>_*.png` + `game/data/pxp_<id>.json`；Noita 颗粒 / 照地光参数 `game/data/fx_pxplane/<id>.json`；旧式 `fx_<id>_*` / `proj_<id>_*` 帧条（`game/art/fx/`、`fx/proj/`）登记 `art.gd` 帧数 / fps 表，并跑 `python -X utf8 tools/optical_fx_quant.py` 出光学观感压阶版（`game/art/fx/_optical/`，同名同密度）。
   GCP 三栏 / 三档截图照 `tools/pxplane_shots_<id>.py`（本机不开 Godot 时用）。
4. 成长节点：**每个节点 / 精英化 / 分支 / 路线都有一个转平面事件**（docs/310 建议的通用 `node_cue` 或本人专属件）；精英化另有 `growth/elite_show` 定格横幅（docs/249）。
5. 只画钩子第一行判断「没接管就返回」；转平面开 / 关 TRACE 必须逐行一致（只改画面）。
6. 送审：先 GIF（`tools/pxplane_gif_<id>.py`，上半 1 倍下半 2 倍、15 fps 原速）→ 用户点头 → 图鉴演示录像逐招 E0→E2 mp4（`tools/elite_demo_shots.py`，memory review-in-gallery）→ `vreview` 预审 → 发用户。GIF 过审 ≠ 实机过（memory gif-not-ingame：另查 1 倍尺寸、半透明盘 / 细环、红铺满屏）。体检 `tools/fx_audit.py both --ops <id>`（docs/270）。

**完成标准**：`new_op_check.py` 的「节点画面事件」一项全绿；fx_audit 核心项过；用户看过录像。
**坑**：录像前先跑 `python tools/asset_index.py` 重建 `game/art/index.json`（新帧条不进索引会静默回退旧画面，memory px-index-json-local）；新画面状态若影响普通敌人绘制，进 `_dc_ok` 排除或签名（`check.py --dccheck`）；圆 / 环 / 线用 `world.tb_*` 合批（memory godot-draw-batching）。

## ⑤ 美术单给 Codex（docs/104，只写范围）

- Codex 画人物本体帧条（idle / run / attack / skill / death / move_attack / entry …）；特效、弹体、图标归 Claude（AGENTS 分工）。
- 单子只写**范围**：谁、哪一版母稿、单帧 f0 还是整条、交付路径 `art/incoming/<内容简称+月日>/`；口径（尺度、画布、原点、簇卡、七条约束）只引 docs/103 §3–§5，设定色 / 标志饰件 / 参照路径写进 docs/97 名单一行；不在单子里写数值（docs/104 §1）。
- 规格要点：身体 64 @2x（128 画布，攻击越界条可 96 / 192）、头高按本人 PRTS 比例 26–30（`tools/prts_metrics.py` 先量）、只交 @2x、只画朝右、二值透明、`#080E18` 外描边；色调 / 瞳色 / 衣服细节与 PRTS 立绘一致，明度范围与 24 色让位于设定色（docs/87 §4.3）。f0 先过，再按部件分层出动画（docs/104 §2–§3）。
- 设计稿 §6 列原作 Spine 轨 → 本作槽对照表（时长、OnAttack 事件时刻 → 出手帧、帧数 / 画布）。帧数和别人一致（8 帧级）。
- 收货：三列对照（PRTS / 交付 / 现行）先看（memory canon-art-consistency）；`python tools/art_lint.py`（未豁免 FAIL 0；`art_lint.py` 的 id → 中文名表加她，原作原生像素口径的豁免写进豁免表并注明理由）；复制进 `game/art/operators/<id>/op_<id>_<槽>@2x.png`；占位期可借别人帧条槽。
- 1 倍帧条（docs/128，`render/op_1x`）：`tools/op_1x/make_op_1x.py` 从原作 Spine 逐部件出 `op_<id>_<槽>@1x.png`（含 `move_attack` 边跑边攻击槽），眼睛修正 `tools/op_1x/eye_fix.py`；拉普兰德 9 条 @1x 都由它出。
- 技能图标 `game/art/ui/skills/skill_<id>_s1..s3.png`（Claude 出：`tools/make_skill_icons.py` 或 pixgen）。

**完成标准**：art_lint 过；`sprites` 里每个槽都有图（或注明借用占位）。

## ⑥ 音效与语音

- 普攻 / 命中 / 技能音：缺专属文件时 `sfx.gd OP_ALT` 借现有音（docs/61 §7、docs/28）；专属音 `game/audio/sfx/op_<id>_*.wav` 并在 `OP_SFX` / JSON `sfx` 段接上；响度 `OP_DB`、间隔 `OP_GAP`（docs/113）。原作客户端音效可进包（memory canon-audio-ok）。
- 语音：原作语音（入队 / 突击 / 技能 / 闲聊 / 终结技），`game/audio/voice/<id>_*.ogg`（母带 `art/source/voice/<id>_*.wav`），登记 `voice_manifest.json`（`operators.<id>` = 原作 char 编号 + 每条 clip）与 `voice_pools.json pools.<id>`（docs/190）；`sfx.gd VOICE_TRIM` 调响度。
- 终结技音效用录音（memory ult-sfx-recordings）：`game/audio/sfx/ult_<id>_*.wav`，候选 2 人一批给用户挑，映射进 `ult_audio.json`。
- 测试一律静音（`--audio-driver Dummy`，autotest 自动静音，不许绕过）。

**完成标准**：`new_op_check.py` 语音 / 音效项全绿或注明 OP_ALT 借用。

## ⑦ 文案（docs/76）

- 所有玩家可见文字（attack / skills / talent / progression 的 name、desc、branch_desc，gallery.desc，ult_text）走 docs/76：方舟口吻、简短精确、无口号 / 排比 / 感悟尾句、§5 术语表、§6 数值写法（数字一律 `{$key}` 占位，不写死）、§7 性别中立（藏品 / 通用说明里写「该干员」）。
- `lore.json`：引言 = 招聘合同干员简介原文；正文每句能在附录 A 的来源里找到。
- **`gallery.intro`（招募卡简介）是用户亲写的**（memory recruit-intros-user，docs/76 A.7）：新干员先按 PRTS 客观履历转述一句草稿，**标「草稿，待用户改」交协调人**，用户定稿后不按 docs/76 改；放不下只调版式。
- 提交前过 docs/76 §8 自查 10 条；改用词时 `grep -rn` 全游戏搜旧叫法。

## ⑧ 测试

本地只跑短检查，**输出进文件看退出码**（别 `| tail` 吞掉 rc，memory check-exit-code；偶发 numpy 循环导入先 `import numpy` 再 runpy 跑，memory check-numpy-preload）：

```bash
python tools/new_op_check.py <id> > build/new_op_check_<id>.txt; echo rc=$?
python tools/check.py --only core      > build/chk_core.txt 2>&1; echo rc=$?
python tools/check.py --only data_lint > build/chk_lint.txt 2>&1; echo rc=$?
python tools/check.py --only card_desc > build/chk_card.txt 2>&1; echo rc=$?   # 改了卡片 / 节点文字
python tools/check.py --only touch_layout > build/chk_touch.txt 2>&1; echo rc=$?  # 改了 screens/*.gd
python tools/check.py --auto --jobs 1  > build/chk_auto.txt 2>&1; echo rc=$?   # 按改动分层：契约 + 本人冒烟 + 同种子
```

- 冒烟：`--auto` 会挑出改动干员的冒烟；`--only smoke` 全员。`--only nodes`（每个成长节点当场有变化）、`--only hold_aim`（手动瞄准）按 `data/characters/` 自动覆盖新干员，不用登记。任何 SCRIPT ERROR / Parse Error 都算失败。
- 终结技 / 连携：录像与时长工具 `tools/ult_rec.py` / `ult_run.py` / `ult_dur.py`；演示局 `--elite2 --sptest`。
- 老干员同种子不变：新干员不在其中的编队，TRACE 逐行一致（docs/36 §3.2，`tools/trace_base.py` 基线缓存，GCP 跑）。
- 专属脚本有新时序（如剑气生命周期）就写一个 `game/tests/<id>_*_test.gd` + `.tscn`，登记进 `check.py SCENE_REGRESSIONS`（照 `lappland_presentation`）。
- 金样过期在角色分支忽略，合入后协调人统一重录（memory no-golden-rerecord-on-branches）。

**完成标准**：以上 rc 全 0；`new_op_check.py` 无「缺」项（「注」项写进设计稿 §7 待办）。

## ⑨ 数值（木桩表 + GCP 同种子配对）

1. 预算表（docs/27 §9.1）：职业角色 → 直接 DPS 预算（主输出 100 / 节奏 85 / 保护 70 / 治疗 65 / 增幅 65%），S1 ≈ 3–5 秒普攻伤害、S2 ≈ 8–12 秒、S3 ≈ 15–25 秒或 8–14 秒形态；天赋 +10–20% 效率。
2. 木桩表（docs/79）：`python tools/op_dummy_table.py --ops <id>,<同职业 2–3 人> --stages 0,1,2`（seed 1、热身 20 + 统计 60 秒、`--bot=afk`），看 E0 / E1 / E2 木桩与怪群秒伤、来源拆分（每项都「看得见」）、和同职业对照的比例。
3. 胜率：单人开局（目标 60–75%，docs/111 全员均值口径）+ 队友身份冒烟；GCP 跑，**tag 唯一**（如 `op-<id>-solo-1107a`）：
   ```bash
   python tools/gcp/batch.py run op-<id>-solo-1107a --commit <sha> --cmd 'python3 tools/balance_run.py --op <id> --bot expert --seeds 16 --nocache --jobs $GODOT_MAX_PROCS --tag $TAG --out $OUT'
   ```
   结论用同种子配对（`tools/cloud_compare.py`），≥ 3 份实现取均值；**胜率差 < 10 点不下结论**（docs/80 §1）；难度窗口 m0 45–55 / m18 65–75（memory difficulty）；看用户会不会嫌难另跑 `--bot=human`（docs/308，`--preset humanstarts`）。
4. 定档（docs/27 §9.4）：通过后才写 `balance.json operators.<id>`，强一点 +3–5%，不许用档位系数救数值。

**完成标准**：设计稿 §4 / §5 填满，结论带区间与配对；老编队回归逐局相同。

## ⑩ 交付

- 只提交自己的文件（`git add <明确路径>`，不扫别人的改动）；`.gd.uid` 随脚本；不提交 `.godot/`、build 产物、`build/prts_ref`。
- 00_index 加设计稿 / 转平面文档行；docs/61 末尾加新积木节；docs/76 附录 A 加来源；docs/41 / 交接页如有要求一并更新。
- 汇报三行以内：分支 + 提交号（commit 结果出来后再写，memory hash-after-commit）+ 关键数字（胜率区间 / 快检 rc）。**不自己合 main、不推 main**，推分支也归协调人（memory no-self-merge-main）。
- 用户要看的 mp4 / 图用 SendUserFile 直接发文件，不贴本地链接。

---

## 样板核对：拉普兰德的全部文件落在哪一步（11-07 走查，`new_op_check.py lappland` 缺 0）

| 文件 | 步骤 |
|---|---|
| `docs/122`（设计）、`docs/273`（转平面）、`docs/297`（姿势审查）、docs/76 附录 A.6 | ① ② ④ ⑤ |
| `data/characters/lappland.json`、`lore.json`、`balance.json`（operators / vis_nodes/team / fx/hf_op / fx/melee_evo_op / fx/material_lappland）、`ult_text.json`、`ult_audio.json`、`synergy.json`、`avatar_eyes.json` | ③ |
| `scripts/characters/blocks/seg_lappland.gd` + `.uid`（四个 `verb.ll_*`，`EXEC_SEG` / `EXT_BLOCKS` 登记） | ③ |
| `render/fx_pxplane_lp.gd`、`fx_pxplane.gd`（IDS / METAS）、`data/pxp_lappland.json`、`data/fx_pxplane/lappland.json`、`art/fx/pxp/pxp_lp_*`、`art/fx/fx_lappland_slash`、`fx/proj/proj_lappland_sword` 与 `_optical/` 同名件；`tools/pxplane_{bake,art,gif,shots}_lappland.py` | ④ |
| `art/operators/lappland/op_lappland_*@2x / @1x`（idle run attack combat skill die entry move_attack；`throw / s1cast` 槽复用条）、`art/ui/skills/skill_lappland_s1..3`、`art/index.json` | ⑤ |
| `audio/sfx/op_lappland_flesh_*`、`ult_lappland_*`（7 个）；`audio/voice/lappland_*.ogg` + `art/source/voice/*.wav`、`voice_manifest.json`、`voice_pools.json`、`sfx.gd VOICE_TRIM` | ⑥ |
| `tests/lappland_presentation_test.gd/.tscn` + `check.py SCENE_REGRESSIONS`；`tools/balance_run.py OPS` | ⑧ ⑨ |
| 代码表里的 id（roster / combo / skill_link / link_bond / ult / ult_aim / ult_moves_c / melee_impact / fx_grains / vis_growth / ob_summon / art.gd / art_lint） | 各步专属接入，见下表「纯数据化缺口」 |
| 不用照做：`data/practice_squads.json`（Boss 演练快照，`tools/practice_squads.py` 生成）、`screens/ak_mock.gd`（界面样机）、各 `tests/*` 里把她当夹具的用例、`tools/probes/*`（一次性探针） | — |

## 纯数据化缺口（为将来玩家自制干员 / 模组）

拉普兰德是「纯积木 + 一个 seg 段」的干员，但走一遍发现**以下地方仍按干员 id 写死在代码里**；做模组前要把它们挪进 JSON 字段或通用积木：

| 位置 | 现在怎么写死 | 补全后可纯数据化的做法 |
|---|---|---|
| `characters/blocks/seg_<id>.gd` + `op_blocks.gd` 继承链 | 每人一个段文件串成一条继承链，新段要改链尾；新瞬时积木要登记 `EXT_BLOCKS` / `EXEC_SEG` | 段文件改成按 id 注册的插件表（不靠继承）；常见专属时序（格挡后强化下一击、死亡扩散、追踪剑气）收成通用积木 |
| `render/fx_pxplane.gd` `IDS / METAS / KEEP_PFX` + `fx_pxplane_<短名>.gd` + 各处 `if id == "<id>"` | 转平面接管名单、帧条前缀、每人一节画法都是代码 | `data/fx_pxplane/<id>.json` 扩成「事件 → 件表」描述（帧条、层、跟随、颗粒、灯），通用解释器画；节点提示统一 `node_cue` 事件（docs/310 §2） |
| `ob_summon.gd` 封印 / 观察画法 `if id == "lappland"` | 状态标记外观按 id 分支 | `st.*` 的 `look` 参数扩成数据（形状 / 色 / 位置） |
| `run/combo.gd` 精英读招表、`run/skill_link.gd`（连携对、`KIND4`、颜色）、`run/link_bond.gd`、`run/ult.gd` 连携名、`run/ult_moves_c.gd`（终结技招式实现）、`run/ult_aim.gd`（瞄准预览形状） | 终结技 / 连携 / 读招全部按 id 写在代码表里 | 终结技做成积木（形状 + 时序 + 预览由同一份数据推出），连携对与类型并进 `synergy.json` / `ult_text.json` |
| `render/melee_impact.gd IDS`、`render/fx_grains.gd _<id>_step`、`characters/blocks/vis_growth.gd OWN_QI / QI_PROJ` | 命中色、材质颗粒、可见成长剑气帧条按 id | 并进 JSON（`col`、`hit_fx`、`vis_growth{proj}`） |
| `core/roster.gd RARITY_5 / PRIORITY` | 星级、寻访权重 | JSON `rarity`、`roster_weight` |
| `sfx.gd OP_SFX / OP_ALT / OP_DB / OP_GAP / VOICE_TRIM` | 音色映射与响度 | JSON `sfx` 段已部分支持，响度 / 借用一并挪进 |
| `art.gd` 帧条帧数 / fps 表、别名表 | 旧式 `fx_* / proj_*` 帧条参数 | 帧条旁放 manifest（同 pxp_<id>.json） |
| `screens/ak_mock.gd`、`tools/art_lint.py` 名字表 / 豁免、`tools/balance_run.py OPS`、`check.py` 每人回归项 | 工具与样机名单 | 工具改读 `Character.list_ids()` 与 JSON 字段 |
| `validate_operator` 夹紧 / `custom` 逃生口 | docs/61 §6 已规定外部干员忽略 `custom`（📝 `modded` 标记未做） | 实现 `modded` 标记：模组干员只许积木 + 数据，夹紧照 §8 第 8 条 |

`new_op_check.py` 会把新干员 id 在上述代码表里**是否出现**列成「注」（不算缺项），方便确认哪些专属接入做了、哪些没做。
