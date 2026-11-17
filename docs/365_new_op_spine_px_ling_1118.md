# 365 新干员 B 方案像素帧条：令试点与照做手册（2026-11-18）

11-18 用户定：下一批 6 名干员（令、傀影、夕、黍、史尔特尔、菲亚梅塔）美术走 **B 方案**——PRTS Spine 渲染 → 缩到画布 → 自动像素化 / 压色 → 人工修 → 直接作为游戏内帧条进包（用户批准原作贴图加工后可直接进包）。本文是令的试点记录，后面 5 人照做。

只做了美术管线和帧条：`game/art/operators/ling/` 下 10 条 @2x 帧条已提交，**没有**建 `characters/ling.json`、没有接入玩法，游戏不会加载它们。

## 0. 复用了什么、新增了什么（协调人 11-18 要求核对）

现有 20 人的 Spine 转像素流程是三段：Codex 的 **bt_18**（`art/incoming/bt_18_complete_parts_1017`，逐槽导出原生附件 1000 画布 PNG + `catalog.json`）→ Codex 的 **bz_18 部件包**（`bz_18_native_spine_parts_1017/build_operator.py`：统一网格逐件像素化，`manifest.json` 定缩放 / 原点，调色板 = 全部原生附件色 96 色中位切分 + 眼 / 嘴附件各 8 色）→ 本仓库 **`tools/spine_run_trial/run_trial.js`**（读原生 skel / atlas 摆姿势，逐附件 4 倍渲染 → alpha 加权 4×4 BOX → 阈值 96 二值透明 → 映射到 bz_18 `parts/*.png` 的全部颜色 → 按层序合成）。游戏里的入场 / 跑步等 Spine 帧条都是第三段出的；部件包对第三段只提供**两样东西**：缩放（`global_transform.scale × catalog.scale`）和调色板。没有部件包的新干员（拉普兰德、歌蕾蒂娅）走 `cfg.pack = {scale, root, palette_png}`。

**复现核对**（11-18，用现有 cfg 原样重跑，与仓库帧条逐像素比）：

| 帧条 | 配置 | 结果 |
|---|---|---|
| `suzuran/op_suzuran_entry@2x.png` | `cfg/suzuran_entry.json` | 8 帧 0 像素差（24205 个不透明像素） |
| `mizuki/op_mizuki_entry@2x.png` | `cfg/mizuki_entry.json` | 8 帧 0 像素差（22810 个） |

```bash
export NODE_PATH=E:/ArknightsSurvivors/build/prts_ref/_node/node_modules
node tools/spine_run_trial/run_trial.js tools/spine_run_trial/cfg/suzuran_entry.json --clean --out build/spine_px/_repro/suzuran_entry
```

令用的就是这第三段（`run_trial.js` 原样，走 `cfg.pack`），所以出帧算法与现有 20 人一致。

| | 复用 | 新增 / 不同 |
|---|---|---|
| 拉模型 | `tools/prts_spine.py`（TORAPPU 路径表） | 登记 6 名新干员 |
| 部件包 | 不做 bt_18 / bz_18 那套逐槽 PNG：`run_trial.js` 只用到它的缩放和调色板，逐槽 PNG 与 `parts/` 本身不参与出帧；那两段脚本在 Codex 工作树、依赖 bs_18 审计和维什戴尔渲染器，不宜从本仓库改跑 | `tools/spine_px.py` 直接从令的 atlas 算调色板（同 bz_18 算法：96 色中位切分；可选眼 / 嘴补色），缩放按 docs/103 头身公式定，写进 `cfg.pack` |
| 调色板偏离 | — | 令关了 bz_18 的眼部补 8 色（令有 19 个眼眉睫附件，补了多 94 色，刘海阴影被映射成粉色带），取色 alpha 下限 230（不然半透明光晕把提灯橙色拉淡）；瞳色等设定色用 `keep_colors` 手选补回 |
| 出帧 | `run_trial.js` 的 `sample`（按时间采样原作轨）、步态合成（跑步）、`skipAdditive`、`hide`、编辑台数据包 | `boneScale`（Q 版大头：放大头骨）、`trackBones`（逐帧骨骼像素位置） |
| 入场取段 | `entry_batch.py` 的口径（整个人进画布起到收势） | 令的 Start 全程都在画布里，直接全程 8 帧 |
| 清理 / 修 | `px_lint.py` 验收口径 | `spine_px.py`：去 ≤ 2 像素碎块、并单点杂色、外圈压暗、按骨位贴手画眼睛、逐帧补丁接口 |
| 审阅 | `sheet.py` 的 8 倍图思路 | `spine_px_review.py`：同屏站位 + 原速循环 mp4 |

## 1. 结论

| 项 | 结果 |
|---|---|
| Spine | 令 = `char_2023_ling`，Spine 3.8，torappu 站 `assets/char_spine/char_2023_ling/defaultskin/front/`；贴图只有一页 512×512 |
| 动画轨 | Idle 10 s、Attack 1.6 s（OnAttack 0.6）、Skill_02 1.2 s（OnAttack 0.5）、Skill_03_Begin / Idle / Loop / End、Die 1 s、Start 1 s；**没有 Move**（辅助干员） |
| 帧条 | 10 条 66 帧，192 画布 @2x、原点 (96,152)（= 1x foot [48,76]，同水月 / 德克萨斯攻击条） |
| 尺度 | 整体 0.148 + 头骨 ×1.46：发顶到脚底约 64、头高约 27（docs/103 公式 28 × 2.9 ÷ 3.0） |
| 色数 | 每条 97–117 色（现有 20 人 @2x 每条 95–130 色） |
| px_lint（待机 f0） | 单点高光 10（铃兰现版 13）、alpha 四连通体 8（发丝与提灯链对角相连）、最低行比脚底低 10（提灯下垂，原作如此） |
| 人工修 | 眼睛：手画两只 6×4 小图，按逐帧虹膜骨位置贴 54 帧（闭眼的 8 帧不贴）；逐像素补丁 0 帧 |

审阅件（本机 build，不进 git）：`build/spine_px/ling/review/lineup_x1.png`、`lineup_x4.png`（与铃兰 / 安洁莉娜 / 水月 / 德克萨斯同地线）、`ling_anims.mp4`（10 个动作原速循环 8 秒）；每个动作 `build/spine_px/ling/<动作>/<动作>_x8.png` 逐帧放大与 GIF。

| 动作 | 原作轨 / 取法 | 帧 | 逐帧时长 |
|---|---|---|---|
| idle | Idle 0–2.1 s 均匀 8 帧（一次呼吸，2.1 s 处回到首帧附近） | 8 | 0.2625 |
| run | 原作无 Move：`run_trial.js` 步态合成（同现有 20 人跑步口径） | 8 | 0.075 |
| attack | Attack 0.1 / 0.3 / 0.45 / 0.6 / 0.75 / 0.95 / 1.2 / 1.45 s，出手 f3 | 8 | 0.2 / 0.15×3 / 0.2 / 0.25 / 0.25 / 0.15 |
| skill | Skill_02 0–1.2 s，出手 ≈ f3 | 8 | 0.15 |
| skill_s3 | Skill_03_Begin 0–0.5 s | 4 | 0.125 |
| skill_s3_loop | Skill_03_Loop 0–1.633 s，出手 ≈ f2 | 8 | 0.204 |
| skill_s3_end | Skill_03_End 0–0.5 s | 4 | 0.125 |
| hurt | 原作无受击轨：Die 0.05 / 0.12 s 当后仰 | 2 | 0.07 / 0.08 |
| death | Die 全程 8 帧（含末帧定格） | 8 | 0.143（末帧 0.125） |
| entry | Start 全程 8 帧（全程都在画布里，不用切空中段） | 8 | 0.143（末帧 0.125） |

接入时注意：attack 原速 1.5 s / 8 帧，比现有干员普攻慢（14–22 fps），按 docs/335 出手对时缩放；Skill_03_Idle（站桩待机，6.3 s）没出，三技能要不要单独的持续待机由技能设计定。

## 2. 命令（照做顺序）

```bash
# 0. 新干员先登记到 tools/prts_spine.py 的 OPS（中文名）与 TORAPPU（角色 id）；6 人已登记
python tools/prts_spine.py ling                       # 拉 skel / atlas / png 到主工作区 build/prts_ref/_raw/ling/，出参照拼图与动画清单 ling_info.json

# 1. 列骨骼，写 rig：tools/spine_run_trial/cfg/<id>.src.json（skel / atlas 路径）+ <id>.json（躯干 / 腿 / 臂骨骼名、持物手、次级摆动、boneScale）
export NODE_PATH=E:/ArknightsSurvivors/build/prts_ref/_node/node_modules
node tools/spine_run_trial/load.js tools/spine_run_trial/cfg/ling.src.json

# 2. 写动作清单 cfg/<id>_px.json（尺度、画布、色数、外圈压暗、设定色、眼睛小图、每个动作的采样时刻），然后一键出
python tools/spine_px.py ling                 # 全部动作 → build/spine_px/ling/
python tools/spine_px.py ling --only idle     # 调参时只出一个
python tools/spine_px.py ling --no-fix        # 不贴眼睛 / 补丁，看自动结果
python tools/spine_px.py ling --apply         # 帧条复制到 game/art/operators/ling/

# 3. 审阅：同屏站位 + 原速录像
python tools/spine_px_review.py ling --vs suzuran angelina mizuki texas --secs 8
python tools/px_lint.py <单帧@2x.png> --only2x --foot 48 76 --out build/px_lint/ling
```

`tools/spine_px.py` 每步做什么：

1. **调色板**：从本人 atlas 贴图的不透明像素中位切分压到 `colors`（96）色，再补 `keep_colors`（瞳色、高光、瞳孔、睫毛、肤色——量化时会被并进头发 / 衣服，docs/87 §4.3）。
2. **渲染**：每个动作写一份临时 cfg 调 `run_trial.js`（逐附件 4 倍渲染 → 4×4 BOX → 阈值 96 二值透明 → 映射调色板 → 按层序合成）；`sample` 采样原作轨，没有 `sample` 的动作走步态合成（跑步）。`trackBones` 逐帧记下眼骨像素位置。
3. **自动清理**：≤ 2 像素的游离碎块删掉；单点杂色（八邻无同色、八邻 ≥ 6 个同一色）并入周围色，眼睛 9×9 范围内不动。每条清 0–8 个碎块、13–59 个孤点。
4. **外圈压暗**（`outline`）：与透明四邻接的像素向 #140f18 混 55% 再就近映射回调色板；一像素宽的细件（枝杈、发丝、提灯链）不压。原作描边被 4×4 BOX 冲淡，不压的话边缘发灰发散，和现有 20 人一排就显得糊。
5. **人工修补**：`fix.eyes` 手画眼睛小图按逐帧骨位贴；`art/src/<id>_fix/<动作>.json` 逐帧逐像素补丁（令没用到）。
6. 拼帧条、8 倍逐帧图、GIF、`summary.json`（帧数、时长、色数、包围盒、清理计数）。

## 3. 关键参数怎么定

- **尺度**（`scale` + rig 的 `boneScale`）：原作小人头身约 3.0，统一缩放会让脸只剩 20 像素高、眼睛一行。做法：先只用 `scale` 让「发顶到脚底」≈ 64，量头高 h0；再按 docs/103 公式 目标头高 = 28 × 2.9 ÷ 本人头身（夹 26–32），`boneScale` 放大头骨 = 目标 ÷ h0，同时把 `scale` 按「颈下身体 = 64 − 目标头高」回调。令：0.16 时头 20 / 全高 60 → 0.148 + 头 ×1.46。放大的是 `F_Head_01`（脖子以上全部挂件跟着放大）；头上的帽 / 角 / 头发也一起变大，这是 Q 版大头口径要的。
- **画布**：先用 256 画布采样每个动作 16 帧，量包围盒相对原点的范围。令的提灯杖左伸 55、下垂 30，128 放不下 → 192（原点 (96,152)）。
- **待机取段**：Idle 轨往往很长（令 10 s，含若干次小动作），以 0.1 s 密采样、逐帧与 t=0 比像素差，找最早回到首帧附近的时刻（令 2.1 s，差 62 像素）当一次循环。
- **跑步**：原作没有 Move 的（辅助 / 术师多半没有）用 `run_trial.js` 步态，rig 里填腿臂骨骼、持物手 `hold` 与武器骨 `weapon`、次级摆动正则（头发 / 辫子 / 尾巴 / 衣摆 / 提灯穗）。
- **受击**：原作没有受击轨，取 Die 开头两帧。
- **眼睛**：在 `--no-fix` 结果上找虹膜所在行（令：睫毛一行 + 虹膜两行，左右眼差一行），图案首行睫毛、两行虹膜（高光 2 格成组，px_lint 要求 @2x 无单点高光）、末行肤色盖掉 BOX 残留的眼白和黑点；`anchor` 让图案对准虹膜骨（`F_[LR]_Eye_02`）。色值从 atlas 里眼睛附件的贴图取：令 虹膜 #9b79ac、高光 #c3dcdc、瞳孔 #4a3a55、睫毛 #2a1f2e。**闭眼帧不贴**：`--no-fix` 出倒下 / 受击后逐帧看，原作闭眼的帧写进 `eye_frames` 排除（令：death 只贴 f0、hurt 只贴 f0）。

## 4. 人工修工作量（令实测）

| 步骤 | 内容 | 用时 |
|---|---|---|
| 拉模型 | 页面原文接口 403，改走 torappu | 10 分钟 |
| rig + 动作清单 | 骨骼挑名、16 帧探针量画布、待机取段 | 40 分钟 |
| 尺度 / 大头 | 三轮（0.16 → 0.13×1.6 → 0.148×1.46），每轮看同屏 | 30 分钟 |
| 眼睛 | 读色、画两只 6×4 小图、两轮对位、闭眼帧排除 | 40 分钟 |
| 逐帧检查 | 10 个动作 8 倍图各看一遍；没有需要逐像素补的帧 | 30 分钟 |
| 审阅件 | 同屏图、录像 | 10 分钟（脚本） |

逐帧逐像素补丁：0 帧。每个动作的眼睛贴片 = 自动按骨位，不按帧人工对。**后面每人预计 2–3 小时**（脚本已搭好；主要花在尺度、眼睛、闭眼帧和逐帧看）；像史尔特尔 / 夕这类大件武器或特效多的，画布和层序可能要多一轮。

## 5. 遇到的问题与留待用户看的点

1. **PRTS 页面原文接口对脚本返回 403**（11-18 起）。torappu 站同一路径规则可用：`assets/char_spine/<角色 id>/defaultskin/front/<角色 id>.{skel,atlas,png}`。另 5 人的角色 id 已按游戏数据填进 `TORAPPU`（傀影 char_250_phatom、夕 char_2015_dusk、黍 char_2025_shu、史尔特尔 char_350_surtr、菲亚梅塔 char_300_phenxi），**还没逐个试拉**。
2. **飘散发丝**：令的发尾在原作里就是散开的墨色细丝，像素化后是一像素宽的对角线条（alpha 四连通体 8 个的来源）。按设定保留没删；用户若嫌脏，可在 rig 里 `hide` 掉对应头发槽或补一个「去细丝」步骤。
3. **提灯低于地线**：待机提灯挂到脚底以下 10 像素（原作姿势），同屏时影子 / 脚底圈需要注意。
4. **跑步步幅小**：长外套盖住大腿，读起来偏碎步（同铃兰 / 塞雷娅，docs/plans/2026-10-20-spine-run-trial.md §6）；可调 `stride` / `lift` 或补侧向鞋部件。
5. **包体**：10 条帧条共 452 KB，放在 `game/art/` 下会随导出进包（导出过滤只排除 art/incoming）；接入前不想占包体可先挪到 art/incoming。
6. **配色**：用的是 PRTS 原色（atlas 中位切分 96 色），整体比 Codex 重画的旧干员略淡；没有改色。

## 6. 文件

- 脚本：`tools/spine_px.py`（管线）、`tools/spine_px_review.py`（同屏图 + 录像）；`tools/spine_run_trial/run_trial.js` 新增 `boneScale`（放大指定骨骼）与 `trackBones`（逐帧骨骼像素位置）；`tools/prts_spine.py` 登记 6 名新干员。
- 配置：`tools/spine_run_trial/cfg/ling.src.json`、`ling.json`（rig + 跑步）、`ling_px.json`（动作清单 + 修补）。
- 帧条：`game/art/operators/ling/op_ling_<idle|run|attack|skill|skill_s3|skill_s3_loop|skill_s3_end|hurt|death|entry>@2x.png`，未接入。
