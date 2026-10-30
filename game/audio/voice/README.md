# 干员语音素材交接

语言：普通话（简体中文）。每位当前编队干员提供部署语音、三条作战技能语音、一条额外战斗台词及一条突击回应；另外提供 W 的短笑声。2026-10-22 第六批后共 121 条：20 名干员 × 6 + W 笑声。源长音轨和临时解码工具不随项目提交；`masters/` 保存 WAV 母带，游戏播放同名 OGG，`voice_manifest.json` 登记来源与事件。

**10-29 扩充（docs/190）**：每人按触发类别分池——入队 `entry` 4 句、突击 `command` 4 句、技能（三槽共用）4 句、战斗闲聊 `battle` 3 句，新增 110 条 `<干员>_<池>_<n>.ogg`（全部原作整段语音，`tools/voice_more_1029.py` 生成），池表在 `voice_pools.json`。`sfx.gd` 事件名只决定用哪个池，池内洗牌不重复、同一句 60 秒内不重复；冷却 / 打断 / 间隔规则不变。同日起**指挥归队不再播语音**。下面的「事件映射」是每类第一句（原有文件）。

**10-30 终结技固定语音（docs/205 §2.2）**：每人终结技说一句用户选定的原句，`game/data/ult_audio.json` 的 `voice` 写文件主名；新切 4 条 `<干员>_ult.ogg`（`tools/voice_ult_1030.py`），7 人那句从原池撤掉并用已有原句补位。

## 事件映射

| 文件后缀 | 原语音索引 | 现行触发事件 |
|---|---|---|
| `_entry.ogg` | `CN_023`，部署 1 | 每次加入编队经 `Character.entry_started()` 请求一次；指挥归队另可请求 |
| `_skill_1.ogg` | `CN_025`，作战中 1 | 干员第 1 个技能释放时 |
| `_skill_2.ogg` | `CN_026`，作战中 2 | 干员第 2 个技能释放时 |
| `_skill_3.ogg` | `CN_027`，作战中 3 | 干员第 3 个技能释放时 |
| `_battle.ogg` | `CN_028`，作战中 4 | 身边有敌人时的低频战斗台词，单句冷却 60 秒 |
| `_command.ogg` | 逐人选定，见第六批 `COMMAND_SELECTION.md` | 成功进入突击时，当前编队轮流一人回应 |
| `wisadel_w_laugh.ogg` | W（`char_113_cqbw`）`CN_028` | 维什戴尔专属的低频笑声事件 |

`voice_manifest.json` 记录每段的源干员、索引、原音轨区间、剪辑时长、母带的 SHA-256，以及 OGG 的编码档位 `ogg_quality`。母带均为单声道 44.1 kHz、16-bit PCM WAV。

## 格式与新语音交付

游戏读 `audio/voice/<干员>_<事件>.ogg`（OGG Vorbis 单声道 24 kHz，`game/scripts/sfx.gd`）。WAV 母带放在仓库 `art/source/voice/`（10-28 从 `masters/` 移出 game/，docs/189），不导入也不进包。10-21 起现行压缩规格为 24 kHz、`soundfile compression_level=0.7`，见 docs/121。第六批直接由新截取的 44.1 kHz PCM16 母带调用现有编码器生成，未重编码旧 91 条。

交付新语音：把 `<干员>_<事件>.wav` 放进本目录，并在清单里登记（`file` 写 `.wav`，附 `sha256`），然后运行 `cd game/tools && python voice_ogg.py`。脚本会把 WAV 挪进 `art/source/voice/`、生成 OGG，并更新清单；新语音默认用 0.7 档。核心契约测试（`tests/test_core.gd`）检查每条都有可加载的 OGG、本目录没有遗留的 WAV；`voice_command_test` 检查 121 条、20 人与指挥调度。

## 接入

语音走 `Voice` 总线和设置中的语音音量；技能语音从 `Character.spend_sp()` 触发。部署时排队，战斗台词与 W 笑声加较长限流；资源缺失时静默跳过。标题页保留原作语音来源和非官方、非商业同人声明。

当前没有独立部署 Start 动画，`Squad.add()` 即时调用 `Character.entry_started()`。同一实例重复通知不会重复请求；后续接入 Start 段时可把调用移到起手帧。图鉴演示不播。寻访揭示不调用语音。

突击回应使用用户 10-22 已确认的 20 条完整原句（`art/archive/incoming_1028/voice_batch6_1022/COMMAND_SELECTION.md`）。`Squad._stance_voice()` 从队长起按编队轮换，排除倒地干员及 `command.roam=false` 的随从；后者当队长时可回应。重复设置相同状态、耐力不足而拒绝突击、自动回随行均不请求；归队仍用 `entry`。指挥请求另按 `command/voice_gap` 6 秒节流，不消耗玩法 RNG。

### 现行播放规则（`game/scripts/sfx.gd` 干员语音段）

- 同一时刻只播一条；两条之间全队至少隔 `VOICE_GAP`（3 秒），同一名干员至少隔 `VOICE_OP_GAP`（15 秒），每句另有冷却 `VOICE_CD`。占线时部署语音排队，其余直接放弃。
- 不打断正在播的语音（用户 2026-09-26）。**例外（用户 2026-10-12「语音用1」，方案 A）**：技能语音（skill_1/2/3）可以打断正在说的战斗台词（battle、W 笑声）：台词 0.1 秒淡出，技能语音立即开播，全队间隔从打断时刻起算。部署语音与技能语音之间仍互不打断，战斗台词不打断任何语音；台词播完后的静默间隔里技能语音照旧放弃。核心契约测试 `test_voice_interrupt` 覆盖这几条。
- `command` 单句冷却 6 秒、优先级 1，占线直接放弃，不进入部署队列；仍受上述全队 3 秒和干员 15 秒间隔约束。没有新增打断例外：`command` 不属于可被技能打断的战斗台词。

## 素材来源

索引与中文长音轨来自 [Ark-Voice 中文语音目录](https://github.com/isHarryh/Ark-Voice/tree/main/voice_cn)，切片边界取自其 `voice_data.json`（`zh_CN`，数据描述日期 2025-02-02）。该仓库注明原始语音版权归上海鹰角网络有限公司所有。本项目仅按作者已确认的授权使用所列短片段；所有角色与原始录音仍归原权利人所有。

第六批来源固定于 Ark-Voice `79584841f7a28f9d029ec2dc1b72444bce87eb1e`，台词文本固定于 ArknightsGameData `e8588a82074bf695aa3849959037dd2de7e6e5cf`；新增条目附源 URL、采样边界、文本键及母带/OGG SHA-256。选句已获用户确认，数字 QA 不代表逐条人工听审。两名新增干员仍沿用项目 `skill_1/2/3` 事件映射；拉普兰德原作只有两个技能，三个事件文件并非原作技能对应声明。
