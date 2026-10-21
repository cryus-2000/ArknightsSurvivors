# Codex 任务单：干员语音接入（10-22）

用户定：语音接入交给 Codex。按 docs/106 §6 在 `codex/voice` 分支改代码；交付分支提交号 + 触发清单 + 试听样本路径，由协调人审阅合入。本单由 Claude 根据 main aa4aec6f 的现状整理。

## 1. 现状

### 1.1 管线

1. **原始录音**：来源 Ark-Voice 中文语音目录（<https://github.com/isHarryh/Ark-Voice/tree/main/voice_cn>，按 `voice_data.json` 的 PRTS 语音索引切片，`zh_CN`）。每条切片的源干员 id、索引（CN_023 等）、源音轨起止秒、时长、母带 SHA-256 都登记在 `game/audio/voice/voice_manifest.json`。版权与授权口径见 `game/audio/voice/README.md`「素材来源」与 `data/credits.json`「干员语音」：仅用已确认的短片段，台词原文以 PRTS 对应干员「语音记录」页的同索引条目为准，不自编。
2. **母带**：`game/audio/voice/masters/<干员>_<事件>.wav`，单声道 44.1 kHz 16-bit。目录有 `.gdignore`，不导入、不进包。
3. **压缩**：`cd game/tools && python voice_ogg.py`（新交付）或 `python voice_ogg.py 名字…`（重编码指定条目）。10-21 起统一 24 kHz 单声道、`ogg_quality` 0.7（约 57 kbps，`OUT_SR` / `DEFAULT_Q`，见 docs/121）。输出 `game/audio/voice/<干员>_<事件>.ogg`。新交付的 WAV 直接放 `audio/voice/` 并在清单登记（`file` 写 `.wav` + `sha256`），脚本会挪进 `masters/`、生成 OGG、补全清单。
4. **播放**：`game/scripts/sfx.gd` 干员语音段（`func voice(cid, key, queue := false)`，约 560–700 行）。文件按 `res://audio/voice/%s_%s.ogg` % [干员 id, 事件] 现用现加载，缺文件静默跳过。

### 1.2 播放规则（现行，别改）

- 同一时刻只播一条；全队两条之间至少 `VOICE_GAP` 3 秒，同一名干员至少 `VOICE_OP_GAP` 15 秒；每个事件另有冷却 `VOICE_CD`（entry 0、skill_1 45、skill_2 30、skill_3 20、battle 60、w_laugh 75 秒）。
- 不打断正在播的语音。例外（用户 10-12「语音用 1」）：技能语音（skill_1/2/3）可以打断正在说的战斗台词（battle、w_laugh），台词 0.1 秒淡出；部署语音与技能语音互不打断，战斗台词不打断任何语音。核心契约测试 `test_voice_interrupt` 覆盖。
- 占线时部署语音（`queue = true`）排队，其余直接放弃。
- 响度：`VOICE_TRIM`（按干员的 dB 微调），`Voice` 总线由设置里的语音音量控制。

### 1.3 18 人现有条目（91 条）

每人 5 条：`entry`（部署 1，CN_023）、`skill_1/2/3`（作战中 1–3，CN_025–027）、`battle`（作战中 4，CN_028）；维什戴尔另有 `w_laugh`（W 的作战中 4）。

| 干员 | entry | skill_1 | skill_2 | skill_3 | battle | 其他 |
|---|---|---|---|---|---|---|
| 水月、斯卡蒂、推进之王、塞雷娅、铃兰、艾雅法拉、凯尔希、艾丽妮、逻各斯、流明、归溟幽灵鲨、乌尔比安、德克萨斯、星熊、安洁莉娜、浊心斯卡蒂、能天使 | 有 | 有 | 有 | 有 | 有 | — |
| 维什戴尔 | 有 | 有 | 有 | 有 | 有 | `w_laugh` |
| **拉普兰德**（`lappland`，data 已有） | 缺 | 缺 | 缺 | 缺 | 缺 | — |
| **歌蕾蒂娅**（`gladiia`，data 已有） | 缺 | 缺 | 缺 | 缺 | 缺 | — |

所有人都没有：受击 / 倒下、选中 / 编入队伍、闲置、胜利 / 失败类语音（项目一直只取上面五类，**这次也不加**）。

### 1.4 现有触发点

| 事件 | 触发位置 | 规则 |
|---|---|---|
| `entry` 部署 | `squad.gd` `add()`：干员加入本局时（开局 + 招募），`voice(cid, "entry", true)` 排队 | 图鉴演示（`g.demo_op`）不播 |
| `skill_1/2/3` | `character.gd` `spend_sp(i)`：任何技能发动 | 演示不播 |
| `battle` / `w_laugh` 闲聊 | `squad.gd` `_battle_voice`：每人 30–55 秒一次（`g.vrng`），身边 300 内有敌人才说；维什戴尔四成换 W 笑声 | — |
| 指挥模式突击 / 归队 | `squad.gd` `_stance_voice(s)`（10-22 已有初版）：编队轮流一人（队长起），突击播 `battle`、归队播 `entry`，另按 `command/voice_gap` 6 秒节流 | docs/114 §8.3 |

## 2. 要做

### ① 拉普兰德、歌蕾蒂娅语音

- 与 18 人同一套：`entry`（部署 1，CN_023）、`skill_1/2/3`（作战中 1–3，CN_025–027）、`battle`（作战中 4，CN_028），每人 5 条。源干员 id 预计为拉普兰德 `char_140_whitew`、歌蕾蒂娅 `char_474_glady`（以 Ark-Voice `voice_data.json` 为准）。切片边界按 `voice_data.json`，台词以 PRTS 语音记录同索引为准；某条缺失或超过 `VOICE_MAX_LEN` 8 秒时在交付说明里写明，不拿别的索引顶替。
- 母带 WAV 按 1.1 第 3 步交付并跑 `voice_ogg.py`；清单补 `operators` 映射与 10 条 `clips`。
- 触发不用改代码（按 id 自动找文件）；`VOICE_TRIM` 视响度补两项（与现有人声对齐，±4 dB 以内）。

### ② 指挥模式出击 / 归队语音

- 按 docs/114 §8.3 的每人选句表核对 `_stance_voice`：轮流、优先队长、节流（`command/voice_gap` 6 秒 + 语音通道原有间隔）。表里补上拉普兰德、歌蕾蒂娅两行（会不会突击看干员 json 的 `command.roam`，医疗 / 辅助默认 false，docs/114 §1）。
- 「不会突击」的干员（辅助 / 医疗等）只在当队长时开口，与表一致。

### ③ 登场动画（Start 轨）播登场语音

- 当前 main 的干员动画里还没有部署登场段（`native_motion` / `character.gd` 只有技能的 start / enter / loop / end）。登场段（原作 Spine `Start`）接入后：在登场段开播那一帧播 `entry`，同时把 `squad.add()` 里的直接播放改成「有登场段的干员交给登场段播，没有的照旧」，保证每名干员每次入队只播一次。
- 如果 Codex 接这单时登场段仍未接入，先在 `Character` 上留一个「登场开始」钩子（只调 `Sfx.voice(id, "entry", true)`），不改画面。

### ④ 寻访揭示

- 用户定：寻访揭示**不配语音**，只用音效。不要在寻访界面加任何 `voice` 调用。

## 3. 规则

- **只改语音相关**：`audio/voice/` 下的新 OGG / WAV 母带 / 清单 / README、`sfx.gd` 干员语音段、`squad.gd` 与 `character.gd` 里的语音触发几行。不碰积木（`characters/blocks/`）、数值（`balance.json`、`data/characters/*.json` 的数值字段）与动画数据。
- **同 seed 不变**：语音只用 `g.vrng` 或墙钟，不读 `g.rng`。
- **测试一律静音**：`python tools/check.py --auto` 0 失败（自带 `--audio-driver Dummy`，别加会出声的测试模式）；改了 OGG 后先 `godot --headless --path game --import` 再跑，否则测的是旧导入。
- **包体**：网页包 37.2 MiB（10-21 实导，docs/121）/ B站 Toy 上限 50 MB；语音现 1.48 MiB（91 条，平均每人约 0.08 MiB）。两人新增预计约 0.17 MiB，超过 0.3 MiB 先说明。
- **语言风格**：README / 清单 / 交付说明里的中文按 docs/76；台词只引 PRTS 可查的原文，不改写。

## 4. 交付

1. `codex/voice` 分支提交号（单独提交，不混别的改动）。
2. 触发清单：每条新语音 → 文件名、源索引、时长、在哪个事件触发；指挥模式两行补表；登场语音的接法。
3. 试听样本：两名新干员 10 条 OGG 的路径（`game/audio/voice/`），另把它们按顺序拼成一个 WAV 放主仓库 `build/voice_1022/`，方便用户一次听完。
4. `--auto` 结果（项数 / 失败数）与新增包体大小。
