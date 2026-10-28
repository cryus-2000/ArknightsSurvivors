# 189 · 素材目录与命名规范（10-28 定稿）

10-28 用户：「素材整理之后能不能进一步规整、分门别类，并写好规范，之后不会乱」。本文分两部分：**规范**（§1–§5，批了以后所有新素材按它放）和**迁移方案**（§6–§8，把现状搬成规范的样子，分批做，每批单独提交）。

用户 10-28 批准，§9 五点按推荐定。迁移进度：批 1 已做；批 0 等 claude/web-shrink 合入；批 2 起等 codex/art 收完（协调人安排）。检查 `python tools/asset_lint.py` 已接进 check.py（`--only asset_lint`），先只报告。

相关：docs/188（10-28 现状清单）、docs/131（10-24 清理盘点）、docs/104（Codex 像素流程）、docs/87 / 98（人物帧条规格）、docs/93（特效规格）、docs/94（敌人重画）。

## 0. 现状为什么乱

1. **`art/incoming/` 一身二用**：名字叫「收货区」，实际是游戏的运行时贴图目录。游戏按名字平铺读它的根目录（`A.tex(name)`，art.gd `_incoming_path`；桌面版直接读 `../art/incoming/*.png` 原图，网页版导出时复制进包）。1845 张在用的 PNG、40 份交接文档、Codex 的单子挤在同一层，新交付没法和在用的分开。
2. **运行时贴图没有分类**：干员 / 敌人 / 特效 / 藏品图标 / 地图件全在一层，只靠前缀区分。
3. **`game/` 里规则不统一**：界面图在 `game/art/ui/<界面>/`、占位图在 `game/art/px/`、根目录还有一张遗物 `game/art/player.png`；语音母带（源文件）放在 `game/audio/voice/masters/`。
4. **id 写法不一**：`fx_eyja_*`（应为 eyjafjalla）、`fx_specter_*` / `skill_specter_*`（应为 specter_unchained）、`op_mon3tr_*`（召唤物没带主人）、水月用 `mizuki_runtime_*` / `player_*`。

## 1. 三段生命周期

| 阶段 | 位置 | 放什么 | 谁放 / 谁挪 |
|---|---|---|---|
| 收货 | `art/incoming/<批次>/` | 新交付：帧条、交接文档 handoff、清单 manifest、审阅图 | Codex 在 codex/* 分支提交到**自己的批次子目录**（例 `art/incoming/skalter_s3_1029/`），根目录不放图；Claude 自制素材不经过收货区 |
| 在用 | `game/art/…`、`game/audio/…`、`game/fonts/` | 游戏运行时读的文件，只放这些 | 接入的会话（界面与美术 / 干员 / Boss 与怪物）验收通过后**复制**进对应目录（接入工具或手工），同一提交里改 json / 代码 |
| 归档 | `art/archive/<来源>_<月日>/` | 已接入批次的整个子目录（交接文档、审阅图、源图、生成脚本） | 接入合入 main 后，协调人或接入会话 `git mv` 整个批次子目录过去；docs 里的路径同一提交改 |

规则：

- 收货区根目录只留 `README.md`（规则说明）和 Codex 的总入口单（`codex_handover_*.md`）；**一个批次一个子目录，子目录名 = 内容简称 + 交付日期（月日）**。
- 在用目录里**不放**交接文档、清单、审阅图、源文件、母带。生成在用文件的脚本放 `tools/`（或随批次归档），不放 `game/`。
- 一张图「在用」与否只看它在不在 `game/` 里；`art/` 下的一切都不进包。
- 源文件、母带（WAV、PSD、大号母稿）放 `art/source/<类别>/`（在仓库里、不进包，例：语音母带 `art/source/voice/`）；Spine 源等超大文件仍只留本地（不进仓库）。都不放 `game/`。

## 2. `game/` 目录分类

```
game/
├─ art/
│  ├─ operators/<干员id>/      干员帧条、技能条、召唤物（op_<id>_*、op_<id>_<召唤物>_*），立绘位用同名 @2x 待机条
│  │   ├─ doctor/              博士
│  │   └─ _reserve/            旧预备干员 ally_*
│  ├─ enemies/<敌人id>/        敌人与 Boss 帧条（e_<id>*，含 _emit 发光层、_white 剪影）
│  │   └─ _portraits/          Boss 名片头像（boss_<id>）
│  ├─ fx/                      技能 / 命中 / 场景特效（fx_*）
│  │   ├─ proj/                弹体（proj_*）
│  │   └─ _optical/            光学观感压阶版（与原名同名，optical.gd 按 "optical_fx/<名>" 取）
│  ├─ world/                   局内地图件
│  │   ├─ terrain/  props/  mire/  pickups/  npc/
│  │   └─ _legacy/             初版占位（drifter、tiles …，docs/05 旧表）
│  ├─ ui/
│  │   ├─ relics/  skills/  growth/   藏品 / 技能 / 成长图标
│  │   └─ <界面>/              各界面专用图（现有 medals、title_deep、professions、settlement、node_cards）
│  ├─ event_cg/{hi,web}/       事件插画（桌面 / 网页两档）
│  └─ px/                      程序用的小贴图（光斑、阴影、占位），不加新东西
├─ audio/
│  ├─ music/                   配乐 ogg + suno_layers.json
│  ├─ voice/                   语音 <干员id>_<事件>.ogg + manifest.json；母带不放这里
│  └─ sfx/                     音效 wav
├─ fonts/                      字体
└─ shaders/                    着色器（专用查找表贴图可以跟着放，例 optical_lut.png）
```

- 子目录按**类别**分，类别下按**id** 分（干员、敌人）；其余类别平铺。
- **加载仍然按名字**：代码和 json 里写的是贴图名（`op_skadi_idle`），不写路径。路径由索引给出（§6.1），所以以后挪目录不用改代码。
- 名字全局唯一：不同目录里不许有同名文件（检查报 ERROR）。

## 3. 命名规则

### 3.1 前缀登记表

| 前缀 | 类别 | 目标目录 | 格式 |
|---|---|---|---|
| `op_` | 干员 | `operators/<id>/` | `op_<id>_<动作>[_<变体>]`；召唤物 `op_<主人id>_<召唤物>_<动作>` |
| `e_` | 敌人 / Boss | `enemies/<id>/` | `e_<id>[_<动作>][_<层>]` |
| `boss_` | Boss 名片 | `enemies/_portraits/` | `boss_<敌人id>` |
| `fx_` | 特效 | `fx/` | `fx_<主人id 或通用词>_<内容>[_<层>]` |
| `proj_` | 弹体 | `fx/proj/` | `proj_<主人id 或通用词>_<内容>` |
| `relic_` | 藏品图标 | `ui/relics/` | `relic_<原作编号>`（docs/11） |
| `skill_` | 技能图标 | `ui/skills/` | `skill_<干员id>_s<1-3>` |
| `growth_` | 成长图标 | `ui/growth/` | `growth_<分支>_<内容>` |
| `terrain_` `prop_` `mire_` `pickup_` `gem_` `drone_` | 地图件 | `world/…/` | `<前缀>_<内容>` |
| `merchant` `doctor` `ally_` | NPC / 博士 / 预备干员 | 见 §2 | 保持现名 |
| `ui_` | 通用界面件 | `ui/` | `ui_<界面>_<内容>` |

新类别先在本表和 `tools/asset_lint.py` 的 `PREFIXES` 登记，再交付。

### 3.2 id

- 干员 id = `game/data/characters/<id>.json` 的文件名，**写全**（`eyjafjalla` 不写 `eyja`，`specter_unchained` 不写 `specter`）。
- 敌人 id = `game/data/enemies.json` 的键。
- 主人 id 同上；通用特效用通用词（`fx_hit_*`、`fx_circle_*`），不要用缩写充当 id（`fx_kp_*` 这类内部缩写要在 handoff 里写明全称）。

### 3.3 后缀（顺序固定：名字 → 动作 → 变体 → 层 → 密度）

| 位置 | 取值 | 说明 |
|---|---|---|
| 动作 | `idle` `run` `move` `attack` `skill` `skill_s<1-3>` `death` `hurt` `fall` `dormant` `awaken` `enraged` … | 人物按 docs/87 / 98，敌人按 docs/94 |
| 变体 | `native`、`melt`、`e2`（精二）… | 同一动作的另一版本；**不许**用 `v2` `new` `old` `final` `bak` 当变体 |
| 层 | `_back` / `_front` / `_orbit` / `_ground`（特效分层，docs/93）、`_emit`（发光层）、`_white`（剪影，一般程序生成） | 同一帧条的各层同画布同帧数 |
| 密度 | `@1x` / `@2x` | 放最后；有 `@1x` 时 `@2x` 只作界面立绘 / 回退（docs/128） |

### 3.4 帧

- 动画一律**横向一行帧条**，一个文件一个动作，**文件名不带帧号**（帧数写 json / manifest）。
- 文件名带序号只用于「一组同类图」：`medal_<章号>`、`jelly_<序号>`、`fx_logos_soul_rune_<层数>`。

### 3.5 字符

- 只许小写字母、数字、下划线；扩展名小写。**禁止中文、空格、大写、连字符。**（10-28 全仓扫描：`art/` 与 `game/` 下没有中文或空格文件名。）
- 音频：配乐 `<曲名>.ogg`，分层 `suno_<曲>_<层>.ogg`；语音 `<干员id>_<事件>.ogg`（事件：entry / command / battle / skill_1-3 / w_laugh / syn_*）；音效 `<类别>_<内容>.wav`，干员音效 `op_<id>_<类别>.wav`。

## 4. 与现有规范的关系

| 文档 | 关系 | 冲突 / 需要改的地方 |
|---|---|---|
| docs/104（Codex 像素流程） | 不冲突：104 只管制作与验收，原来没写交付路径 | 已在 §1 加一行交付路径（用户 10-28 定） |
| docs/87 §1「命名」 | 一致（`op_<id>_<动作>` + `@2x`） | 87 写「json 文件名」= 本文 id 口径，无冲突 |
| docs/98 §1「命名」 | 一致；98 允许「水月 `player_*`」 | 本文把水月 `player_*` / `mizuki_runtime_*` 记为历史遗留，新素材一律 `op_mizuki_*`（旧名这次不改，见批 6） |
| docs/93 §0（特效） | 一致（`_back` / `_front`、ground） | 93 写「只动 `art/incoming/`」→ 迁移后改为「只动 `art/incoming/<批次>/`」，随迁移批 2 一起改 |
| docs/05（旧交接说明） | 顶部已声明以 87 为准 | 「放进 incoming 后重开游戏就能看到」的热替换说法迁移后失效，第 2 批时改 05 |
| docs/06（Git 协作）、AGENTS.md | Codex 范围写的是「art/incoming/ 中的 player_*、e_* …」 | 迁移后改为「art/incoming/<批次>/」；06 由迁移批次改，AGENTS.md 只给建议文字（§9） |

## 5. 检查：`tools/asset_lint.py`

只读、只报告（退出码恒 0；`--strict` 时有 ERROR 返回 1，规范批准、迁移完再接进 check.py）。规则：

| 编号 | 级别 | 内容 | 10-28 现状 |
|---|---|---|---|
| N1 | ERROR | 名字含大写 / 中文 / 空格 / 连字符 | 0 |
| N2 | WARN | 前缀不在登记表 | 0 |
| N3 | WARN | `op_` / `e_` 后的 id 在 data 里找不到 | 0 |
| N4 | WARN | 主人 id 写缩写 | 27（`fx_eyja` / `proj_eyja` / `fx_specter` / `skill_specter`） |
| N5 | WARN | 召唤物没带主人前缀 | 22（`op_mon3tr_*`） |
| N6 | WARN | 版本号 / 临时后缀 | 3（`op_skadi_attack_v2` ×2、`archive_v2.ogg`） |
| N7 | INFO | 历史遗留名（登记表 LEGACY） | 47（水月 31、初版占位 16） |
| D1 | WARN / INFO | `game/` 下放错目录 | 1（`game/art/player.png`）+ 1 INFO（`optical_lut.png`） |
| D2 | WARN | 源文件在运行时目录 | 123（语音母带） |
| D3 | INFO | 收货区里的非运行时文件 | 40 |
| H1 | INFO | 同内容不同名 | 42 组（多为 optical_fx 压阶后与原图相同、发光层空帧） |

迁移完成后加两条：**L1 ERROR 运行时贴图仍在收货区根目录**、**L2 ERROR 同名文件出现在两个目录**。

## 6. 迁移方案

### 6.1 关键改动：按名字找图改成查索引

现在 `A.tex(name)` 拼 `art/incoming/<name>.png`。迁移后：

- 新工具 `tools/asset_index.py` 扫 `game/art/` 生成 `game/art/index.json`（名字 → `res://` 路径，含 @1x / @2x），check 项核对索引与磁盘一致；
- art.gd `_incoming_path` / `_packed_path` / `incoming_dir` / `has_override` 改成查索引，**过渡期保留回退到 `art/incoming/` 根目录**（别的分支还往根目录加图时照样能用，lint 报 L1 提醒挪）；
- 贴图进 `game/` 后由 Godot 导入，桌面版不再读原图、改走和网页版同一条 `ResourceLoader` 路（网页版已经这样跑了一个多月）。代价：每个工作树第一次打开要导入约 1850 张小图；桌面包里不再带散装 PNG（在 pck 里）；「丢进 incoming 重开就生效」的热替换没了（改成跑一次接入工具）。

### 6.2 现状 → 目标（运行时贴图 1845 张，21.4 MB）

| 目标（game/art/ 下） | 文件 | MB | 来源 |
|---|---|---|---|
| operators/<id>/ | 495 | 14.08 | `art/incoming/op_*` |
| operators/mizuki/ | 31 | 0.90 | `mizuki_runtime_*`、`player_*` |
| operators/doctor/ | 8 | 0.03 | `doctor_*` |
| operators/_reserve/ | 12 | 0.05 | `ally_*` |
| enemies/<id>/ | 416 | 2.64 | `e_*` |
| enemies/_portraits/ | 20 | 0.02 | `art/incoming/portraits/`（docs/131 记为死路径；用户定照搬，不删） |
| fx/ | 237 | 1.83 | `fx_*` |
| fx/proj/ | 37 | 0.05 | `proj_*` |
| fx/_optical/ | 194 | 0.98 | `art/incoming/optical_fx/` |
| ui/relics/ | 264 | 0.48 | `relic_*` |
| ui/skills/ | 54 | 0.03 | `skill_*` |
| ui/growth/ | 23 | 0.10 | `growth_*` |
| ui/ | 3 | 0.03 | `ui_*` |
| world/props、terrain、mire、pickups、npc | 35 | 0.21 | `prop_` `drone_` `terrain_` `mire_` `pickup_` `gem_` `merchant` |
| world/_legacy/ | 16 | 0.01 | 初版占位 |

`game/` 内部另有三处（批 1 已做）：`game/art/player.png` 删（无人读，docs/188 §2.1）、`game/art/px/mizuki_chibi_walk.png` 删、`game/audio/voice/masters/`（123 个 WAV，22 MB）移到 `art/source/voice/`。

### 6.3 要改的加载路径

| 位置 | 处数 | 内容 |
|---|---|---|
| game/scripts/art.gd | 6 | `incoming_dir` / `_incoming_path` / `_packed_path` / `has_override` → 查索引 |
| game/scripts（其他） | 2 | optical.gd `"optical_fx/"` 名前缀、boss_intro.gd `"portraits/"` 名前缀（改成索引里的名字，或保留前缀写进索引） |
| game/data/enemies.json | 10 | `intro.portrait: "portraits/boss_<id>"`（同上） |
| tscn | 0 | 场景里没有引用 art/incoming |
| 导出预设 export_presets.cfg | 2 个预设 | include `art/incoming/*.png` 与 18 条审阅图排除规则 → 改为 game/art 下的规则（审阅图本来就不该进 game/，规则可删） |
| 打包 / 检查工具 | 8 个文件 | export_build.py（`ART_SUBDIRS`、复制散装 PNG、加密包 alias 校验）、export_web.py、encrypted_release.py、release_slim.py、check.py（输入哈希 4 处）、godot_runner.py（缓存键）、art_lint.py、enemy_art_check.py |
| 生成 / 接入工具 | 约 47 个（tools/ 55 个文件提到 incoming，其中 44 个把它当输出目录） | 统一改用新 helper `tools/asset_paths.py` 的 `out_dir(name)`（按前缀给目录）；probes 22 个只在用到时改 |
| 文档 | 82 篇 223 处 | 只改现行规范（05 / 06 / 87 / 93 / 98 / 36）；历史记录不改，归档目录有对照 |

### 6.4 分批

| 批 | 内容 | 文件 | 风险 | 验证 |
|---|---|---|---|---|
| 0 | 索引工具 + art.gd 查索引（带 art/incoming 回退）+ `asset_paths.py` + lint 接进 check.py（只报告）。**不挪文件** | 0 | 中：加载器是全游戏入口 | `--auto`、smoke 全员、`--only op_select codex gallery_demo enemy_pixels look`、Windows 包 + 网页包各导一次、加密包 alias 校验 |
| 1（已做） | game/ 内部：删 2 张遗物图、语音母带移到 art/source/voice、导出预设的 `player_cut` 死规则 | 3 + 123 | 低：语音 manifest.json 的 `master:` 字段与 `voice_ogg.py` 的母带目录要一起改 | data_lint、core（语音清单测试）、`--only voice_command` |
| 2 | 干员：op_ / 水月 / 博士 / 预备干员 → `operators/` | 546 | **高**：最大一批、Codex 分支最常改 | 批 0 全套 + art_lint、`--only three_operator_art mizuki_runtime skill_lifecycle ea_ui run_stats`、同 seed 1 局画面对照 |
| 3 | 敌人 + Boss + 名片 → `enemies/` | 436 | 中：Boss 分支在改 | `--only enemy_pixels knight_pixel_split boss_variety boss_trial enemy_demo`、`--dccheck`、bosstest 截图 |
| 4 | 特效 / 弹体 / 光学压阶 / 图标 / 地图件 → `fx/` `ui/` `world/` | 863 | 中：名字最杂 | `--only look relic_impl card_desc settlement title_menu node_cards medals`、光学开 / 关各截一张、网页包 |
| 5 | 收尾：art.gd 去掉 art/incoming 回退、lint 加 L1 / L2 并改 `--strict`、收货区根目录剩余 40 份文档进批次子目录或归档、改现行文档 | — | 低 | 全量（云端，按合入流程） |
| 6（可选，这次不做） | 改名：`op_mon3tr_*` → `op_kaltsit_mon3tr_*`、`fx_eyja_*` → `fx_eyjafjalla_*`、`*_specter_*` → `*_specter_unchained_*`、`op_skadi_attack_v2` → 正式名、水月旧名 | 约 100 + json / gd 字面量 | 中：改名要动数据和代码 | 同批 2 / 4；§9-③ 定做不做 |

每批：一个提交（`git mv` 保历史）+ 相关快检；批 2–4 之间可以隔几天，等其他分支合完。

## 7. 对进行中分支的影响

| 分支 | 现状（10-28） | 冲突 | 处理 |
|---|---|---|---|
| codex/art（.worktrees/codex-art） | 比 main 多 89 个提交（最后 10-25），art/incoming 下差异约 3 万个文件，根目录 193 个 | **最大**：批 2–4 把根目录图挪走后，Codex 再改同名图会成「改名 + 修改」冲突；文件太多时 git 的改名识别会失效（要调大 `merge.renameLimit`） | 批 2 前先请协调人把 codex/art 该收的收完、Codex 同步 main；之后 Codex 交付一律进 `art/incoming/<批次>/`，不再写根目录 |
| codex/boss-fx-rework、final-boss-complete、bgm-memory、merchant-bgm、visible-growth、node-icons、event-cg | 都已合进当前分支（ahead 0） | 无 | — |
| claude/boss-*（paranoia / izumik / ishar / bench）、knight-fx-polish | 10-28 在改，没动 art/incoming 与加载器 | 以后新加的 fx_ / e_ 图如果还放根目录：批 0 的回退能读，lint 报 L1 | 批 3 / 4 动手前问一下在不在加图 |
| claude/web-shrink | 改了 export_web.py | 批 0 / 2 也改 export_web.py | 先合 web-shrink 再做批 0 |
| 本分支（asset-tidy） | 归档 art/incoming 批次子目录、删旧合成配乐、docs/188–189、asset_lint | — | 先合本分支 |

## 8. 不做的

- 不改贴图内容、尺寸、帧数；不重画。
- 不改 docs/104、AGENTS.md、CLAUDE.md（只给建议）。
- 历史文档（归档、计划记录、交接页）里的旧路径不改。

## 9. 用户已定（10-28）

1. **运行时贴图搬进 `game/art/<类别>/`**（A 方案）：Godot 导入、按索引找图，放弃收货区热替换。
2. **语音母带**移到 `art/source/voice/`，在仓库里、不进包（批 1 已做）。
3. **旧名这次不改**：`op_mon3tr`、`fx_eyja`、`*_specter`、`op_skadi_attack_v2`、水月旧名放批 6，可选。
4. **docs/104 §1 加交付路径一行**（已加），docs/93 跟着迁移批次改。
5. **`art/incoming/portraits/` 照搬**到 `enemies/_portraits/`，不删。

开搬顺序：批 1 先做；批 0 等 claude/web-shrink 合入；批 2 起等 codex/art 收完。

### AGENTS.md / CLAUDE.md 建议文字（未改，协调人另找用户确认）

- AGENTS.md 第 16 行 Codex 范围改为：「Codex art scope: deliveries under `art/incoming/<batch>/` (characters, monsters and commissioned effects) with their handoff; runtime files live in `game/art/` and are installed by Claude. Naming and folders: docs/189.」
- AGENTS.md 第 21 行后加一句：「Asset folders and file names follow docs/189; check with `python tools/asset_lint.py`.」
- CLAUDE.md 第 8 行（五个怪物 v2 帧条在 art/incoming/）：迁移批 4 后这几张初版占位会搬到 `game/art/world/_legacy/`，届时改为「…now in game/art/world/_legacy/ (docs/189)」。
