# 第六批普通话语音交接（2026-10-22）

用户已看过 20 条选句并确认「没问题」，随后明确「按任务单由 Codex 直接接入」。本分支基于 main `aa4aec6f`，按任务单 `845744b9:art/incoming/codex_task_voice_1022.md` 完成素材及运行时接入，由 Claude 协调人审阅合入。**20 条已确认选句保持不变，无需重新审批选句。** 提交号与验证结果见最终交付记录；本说明不表示已合 main 或发版。

## 交付内容

- 20条 `<id>_command.ogg`：每名现有干员一条已确认的突击回应，逐人台词、原作编号、时长及适用说明见 `COMMAND_SELECTION.md` / `command_selection.json`。
- 拉普兰德 `lappland / char_140_whitew`、歌蕾蒂娅 `gladiia / char_474_glady` 各5条：`entry=CN_023`，`skill_1/2/3=CN_025/026/027`，`battle=CN_028`。沿用项目事件映射，不表示原作台词专属对应技能；拉普兰德在原作只有两个技能。
- 共30条、47.870秒；OGG合计377,178字节，PCM16 WAV母带合计4,223,440字节。仅比较交付片段的母带与OGG，体积减少约91.1%；不是与原始长音轨或旧版OGG的比较。
- 成品统一为24 kHz、单声道、OGG Vorbis，`soundfile compression_level=0.7`，直接调用现有 `game/tools/voice_ogg.py` 的 `encode()`，与 docs/121 现行压缩口径一致。由本次截取的44.1 kHz单声道PCM16 WAV母带直接编码，未拿运行时OGG继续压缩。

## 选句边界

多数是确认、准备就绪或行动回应。没有给角色编造「收到」，没有从长句中拼接字词。每条均按原始完整语音片段切出，保留该片段内原有停顿。

维什戴尔和拉普兰德缺少合适的直接确认词，分别采用原作部署2、选中干员1作为**性格化回应**，在 `command_selection.json` 中标为 `characterful_response`。拉普兰德是对博士的挑衅，不应描述成「收到」；维什戴尔有调侃意味。浊心斯卡蒂的回应约3.94秒，也比其他人长。以上选句已获用户确认；Claude试听核对录音完整性和音量即可，不再发起选句审批。用户确认选句不等于已完成逐条听审。

使用先锋德克萨斯、原版拉普兰德、异格归溟幽灵鲨与异格浊心斯卡蒂的默认普通话音轨；没有混入异格荒芜拉普兰德、普通幽灵鲨、近卫斯卡蒂或时装语音。

## 运行时接入与触发

已将 30 条 OGG 与母带复制到 `game/audio/voice/`，合并清单后 20 人、121 条（原 91 条保持原样，补两人标准事件 10 条、突击回应 20 条）。母带目录保留 `.gdignore`，不导入或进入游戏包。

| 事件 | 触发位置与规则 |
|---|---|
| `entry` | 开局、招募或替换入队，由 `Squad.add()` 调 `Character.entry_started()`；当前无独立 Start 动画，立即请求，部署占线排队，同一实例重复通知不重复请求 |
| `skill_1/2/3` | 沿用 `Character.spend_sp()`；新增两人按 ID 自动加载 |
| `battle` | 沿用 `Squad._battle_voice()` 的有敌人低频闲聊；新增两人按 ID 自动加载 |
| `command` | 成功进入突击，经 `set_stance()` → `_stance_voice()` 请求一名干员；桌面、手柄、触屏与机器人共用入口 |
| 指挥归队 | 仍请求 `entry`，含耐力耗尽自动归队；不使用 `command` |

指挥发声从队长起按编队轮换，排除倒地干员与不会突击的随从；后者当队长时可发声。重复状态、耐力拒绝突击、自动回随行无突击回应。保持 `command/voice_gap` 6 秒节流、全队 3 秒间隔、同干员 15 秒间隔。`command` 单句冷却 6 秒、优先级 1，占线放弃，不排队、不新增打断例外。旧事件冷却与技能仅打断 battle/W 笑声的规则不变；原有 Voice 总线、音量设置与自动测试静音不变。发声选人不使用玩法 RNG。

登场只新增语音钩子，不新增动画。将来有 Start 段时可把即时调用移至起手帧，复用去重。图鉴演示不播，寻访揭示不配语音。未修改数值、干员积木、动画数据或其他音效。

两人五条标准母带实测平均 RMS：拉普兰德 -13.52 dBFS、歌蕾蒂娅 -18.23 dBFS；按现有约 -17 dBFS 目标分别加 `VOICE_TRIM=-3.5/+1.0 dB`。标准十条 OGG 新增 176,824 B（0.169 MiB）；含 20 条回应，本批总新增 377,178 B（0.360 MiB），未重编码旧语音。

### 两人标准语音清单

| 干员 | 文件 | 原作索引 | 时长（秒） | 触发 |
|---|---|---|---:|---|
| 拉普兰德 | `lappland_entry.ogg` | CN_023 | 1.095 | 入队登场 / 指挥归队 |
| 拉普兰德 | `lappland_skill_1.ogg` | CN_025 | 3.505 | 一技能 |
| 拉普兰德 | `lappland_skill_2.ogg` | CN_026 | 1.305 | 二技能 |
| 拉普兰德 | `lappland_skill_3.ogg` | CN_027 | 1.435 | 三技能（项目事件映射） |
| 拉普兰德 | `lappland_battle.ogg` | CN_028 | 1.285 | 低频战斗台词 |
| 歌蕾蒂娅 | `gladiia_entry.ogg` | CN_023 | 0.845 | 入队登场 / 指挥归队 |
| 歌蕾蒂娅 | `gladiia_skill_1.ogg` | CN_025 | 3.490 | 一技能 |
| 歌蕾蒂娅 | `gladiia_skill_2.ogg` | CN_026 | 5.000 | 二技能 |
| 歌蕾蒂娅 | `gladiia_skill_3.ogg` | CN_027 | 4.360 | 三技能（项目事件映射） |
| 歌蕾蒂娅 | `gladiia_battle.ogg` | CN_028 | 2.270 | 低频战斗台词 |

20 条突击回应的文件名、原句、索引、时长见 `COMMAND_SELECTION.md`；121 条运行时清单逐项记录事件及来源。新两人十条标准语音的串联试听位于主仓库 `build/voice_1022/lappland_gladiia_standard10.wav`（每条间隔 1 秒，顺序：拉普兰德 entry、skill_1、skill_2、skill_3、battle，再歌蕾蒂娅同顺序）；同目录 `audition_order.json` 记录起点。不自动播放。

## 已完成的音频QA及限制

`qa.json`：30/30通过源音轨字节数与固定版索引对照、采样边界范围检查、WAV/OGG格式检查、完整解码、有限值/非静音、重采样帧数、时长一致性检查。每条母带、OGG及源长音轨均记录SHA-256；最长5.000秒，全部低于现有8秒上限。

`qa.json` 是截取、压缩阶段的快照，其中 `gameplay_integration=not_performed` 指该阶段尚未接入；后续运行时接入与验证结果如下。

### 仓库验证

- 语音专项：接入前 65 项、59 个预期失败；接入后 77 项、0 失败，统一快检内再次通过。
- 核心契约：3,240 项、0 失败；20 名干员冒烟及全部场景检查通过，Godot 日志无 SCRIPT ERROR / Parse Error。
- 同 seed：固定基线 `aa4aec6f`，seed 3，斯卡蒂带拉普兰德、歌蕾蒂娅，60 秒，5/20/35 秒切换指挥；61 行 TRACE 逐行一致。`trace_base` 对 BALANCE 的性能字段仅提示，不作为相等断言。
- `python tools/check.py --auto --jobs 3`：111 项，110 项通过，唯一未通过为「积木等价」的 14 组金样输入哈希过期。没有将此结果写成全绿。另读取本次已生成的 14 组输出，逐组与现有金样对照，TRACE 及去除性能字段后的战斗统计全部一致。
- 按 docs/36 §1.3，金样过期不计入真实失败列表、不阻断交接；由协调人在最终合入 main 后统一 `python tools/check.py --rerecord-golden`，本分支没有修改金样或检查判定。
- 初次完整运行结束后发现 Python 缺 `fontTools`，补齐任务本地依赖后完成汇总；137/137 条 Godot 结果按相同输入命中缓存，没有重复运行整批。快检记录、14 组额外比对与 ZIP 哈希记录随外层交付保存。

尚未逐条人工听审。数字 QA 与静音运行不能替代局内听感验收。新增 `voice_command_test` 覆盖全部 20 个 command 可加载、121 条事件映射、两人各五事件、轮换/资格/拒绝/重复/节流、登场去重及原有占线/间隔规则；完整快检、同 seed TRACE 与提交号见外层交付记录。

## 来源

- 音轨与切片索引：[Ark-Voice](https://github.com/isHarryh/Ark-Voice)，固定提交 `79584841f7a28f9d029ec2dc1b72444bce87eb1e`，`voice_cn/` 与 `voice_data.json` 来自同一提交。索引描述日期为2025-02-02。20条长音轨完整下载并逐个核对索引中的字节数，只将选定短片段交付入库。
- 台词原文：[ArknightsGameData charword_table](https://github.com/Kengxxiao/ArknightsGameData/blob/master/zh_CN/gamedata/excel/charword_table.json)。本次下载后冻结实际文件版本，精确提交、源URL及 `charWords` 键见清单的 `text_source_revision` / 每条 `text_source_url`、`text_source_key`。
- 两名新增干员的选定回应及十条标准语音原文另与 [拉普兰德语音记录](https://prts.wiki/w/拉普兰德/语音记录)、[歌蕾蒂娅语音记录](https://prts.wiki/w/歌蕾蒂娅/语音记录) 核对。清单逐人附PRTS链接；没有声称全部20人都逐页交叉核对。
- 原作角色、录音版权仍归原权利人；沿用用户本次指定的本项目使用范围，本交付不附加授权声明。
