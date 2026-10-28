# 新增五位干员普通话语音交接（2026-10-12）

## 交付
德克萨斯 texas / char_102_texas；星熊 hoshiguma / char_136_hsguma；安洁莉娜 angelina / char_291_aglina；浊心斯卡蒂 skalter / char_1012_skadi2；能天使 exusiai / char_103_angel。
每位 5 条：entry=CN_023 部署1，skill_1/2/3=CN_025/026/027 作战中1/2/3，battle=CN_028 作战中4。技能编号是沿用项目事件映射，不声称原作台词专属于对应技能。
合计25条、约60.82秒。无闲聊/基建/剧情语音；浊心使用异格默认语音，不是近卫斯卡蒂，也不是时装变体。德克萨斯使用先锋版。

## 接入步骤（Claude）
1. 将本目录根部25个 .ogg 复制到 game/audio/voice/；masters/ 内25个 .wav 复制到 game/audio/voice/masters/（保留 .gdignore）。
2. 把 voice_manifest_additions.json 的 operators 和 clips 合并到 game/audio/voice/voice_manifest.json；按 operator+event 去重。保留原有66条，不用整个替换清单。新增条目保留 source_url 和本批 source_revision。
3. 文件命名对应现有 sfx.gd 动态路径，无需重新编码。保持现有 VOICE_GAP、VOICE_OP_GAP 和各事件冷却，不提高语音频率；battle仅低频触发。
4. 检查五人部署、技能、战斗事件实际调用。运行 tools/check.py，实机验收单句完整性、音量和占线规则后再构建。

## QA（与试听分开）
qa.json：25/25通过。源文件字节数与固定版本索引一致；按CN语种与准确索引切片；WAV为PCM16单声道44.1kHz；OGG为Vorbis单声道44.1kHz、compression_level=0.3，分块编码与既有工具一致。记录母带及OGG哈希；解码采样数不变、有限且非静音。全部时长低于现有8秒上限，最长7.17秒。
未进行逐条听审或Godot实机测试，不把数字QA视为听审通过。本提交只交素材，不改game/，尚未接入主分支。

## 来源
https://github.com/isHarryh/Ark-Voice
固定提交：79584841f7a28f9d029ec2dc1b72444bce87eb1e。索引 voice_data.json 与音轨 voice_cn/ 均来自同一提交；每条源链接及切片区间见清单。完整长音轨未入库。
原始角色及录音权利属于鹰角网络等原权利人；沿用用户已确认的本项目使用范围，不附加授权声明。
