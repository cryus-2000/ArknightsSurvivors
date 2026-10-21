# 121 网页包压音频（10-21）

网页包实测 43.1 MiB（B站 Toy 上限 50 MB），音频占七成多，用户定先压音频。本篇：全部音频文件的包内大小表、这次的压缩做法、对比样本与实导结果。不改播放代码，只改源文件；同 seed 无关。

## 1. 做法

- **BGM**（`audio/music/*.ogg`，71 个，立体声 44.1 kHz）：没有母带（`gen_music.py` / `gen_music_battle.py` 直接写 OGG），解码后按 soundfile `compression_level` 0.70 重新编码（原 0.45 / 0.62 / 0.66；压后 65–105 kbps），只在变小时替换，帧数逐个核对与原文件相同（乐句式曲目按帧接缝）。两份生成脚本的编码档位同步改成 0.70。保留立体声。
- **语音**（`audio/voice/*.ogg`，91 条，原本就是单声道 44.1 kHz、平均约 98 kbps）：协调人补充「语音优先、人声 48–64 kbps 够」。从 `audio/voice/masters/` 的 WAV 母带重编码（不叠加有损）：重采样到 24 kHz（人声 12 kHz 以内够用）+ 档位 0.7，平均约 57 kbps。`voice_ogg.py` 加 `OUT_SR = 24000`、缺省档 0.7，清单每条 `ogg_quality` 统一 0.7、`format` 写明 24 kHz；以后改档位直接 `voice_ogg.py --all`。只靠降档（不降采样率）在 44.1 kHz 下最低也有 60 kbps。首尾静音合计 8.2 秒（4%），去掉只省约 0.06 MiB，还会改变语音起播时机，没做。
- **音效**（`audio/sfx/*.wav`，162 个，导入时已是 QOA）：不动。
- 工具：`game/tools/shrink_audio.py`（缺省先写 `build/audio_shrink/stage/` 核对，`--apply` 写进游戏）。

注意：改了源音频后 `check.py --auto` 不会自动重新导入已有缓存的文件，要先 `godot --headless --path game --import`，否则测的是旧的导入结果。

## 2. 对比样本（`build/audio_shrink/`，压前 `_before`、压后 `_after`，各约 10 秒 WAV）

| 样本 | 内容 |
|---|---|
| `bgm_title_*` | 标题曲 20–30 秒（123 → 75 kbps） |
| `bgm_archive_v2_*` | 图鉴曲 10–20 秒（码率最高的一首，165 → 102 kbps） |
| `bgm_battle1_A_mix_*` | 战斗曲 A 句激战三层叠在一起（局内实际听到的样子） |
| `voice_skalter_skill_3_*`、`voice_siege_skill_1_*`、`voice_saria_skill_2_*` | 语音最长一条与两条中等长度（压后 24 kHz、约 57 kbps） |

音效这次没改，没出对比样本。

## 3. 包内音频（按压前大小排序）

包内大小取 `game/.godot/imported/` 里导出的文件（OGG 原样进包，WAV 导入成 QOA）。语音 WAV 母带（`audio/voice/masters/`，16.7 MiB）目录里有 `.gdignore`，不导入也不进包（实导的 pck 里查过，没有 masters 路径）；「语音占 24.5 MiB」的口径应是把母带算进去了，网页包里的语音压前只有 2.55 MiB。

| 用途 | 文件数 | 压前（MiB） | 压后（MiB） | 省 |
|---|---|---|---|---|
| BGM | 71 | 18.28 | 13.62 | 4.66 |
| 语音 | 91 | 2.55 | 1.48 | 1.07 |
| 音效 | 162 | 2.25 | 2.25 | 0.00 |
| 合计 | 324 | 23.08 | 17.34 | 5.74 |

| # | 文件 | 用途 | 格式 | 采样率 / 声道 | 时长 | 包内大小 压前 → 压后（KB） | 码率 压前 → 压后（kbps） |
|---|---|---|---|---|---|---|---|
| 1 | `music/title.ogg` | BGM | OGG | 44100 Hz / 立体声 | 112.0 s | 1688 → 1024 | 123 → 75 |
| 2 | `music/archive_v2.ogg` | BGM | OGG | 44100 Hz / 立体声 | 73.8 s | 1487 → 916 | 165 → 102 |
| 3 | `music/deploy.ogg` | BGM | OGG | 44100 Hz / 立体声 | 75.8 s | 1324 → 784 | 143 → 85 |
| 4 | `music/win_loop.ogg` | BGM | OGG | 44100 Hz / 立体声 | 64.0 s | 999 → 572 | 128 → 73 |
| 5 | `music/lose_loop.ogg` | BGM | OGG | 44100 Hz / 立体声 | 35.6 s | 421 → 290 | 97 → 67 |
| 6 | `music/shop.ogg` | BGM | OGG | 44100 Hz / 立体声 | 20.9 s | 375 → 226 | 147 → 89 |
| 7 | `music/battle2_D_drive.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 219 → 190 | 119 → 104 |
| 8 | `music/battle1_D_drive.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 219 → 190 | 119 → 104 |
| 9 | `music/battle1_E_base.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 214 → 146 | 117 → 79 |
| 10 | `music/battle2_E_base.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 214 → 145 | 117 → 79 |
| 11 | `music/battle2_B_base.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 213 → 145 | 116 → 79 |
| 12 | `music/battle1_B_base.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 212 → 146 | 116 → 79 |
| 13 | `music/battle3_D_drive.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 212 → 184 | 120 → 104 |
| 14 | `music/battle2_A_base.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 210 → 144 | 115 → 78 |
| 15 | `music/battle1_A_base.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 210 → 143 | 114 → 78 |
| 16 | `music/boss_D_full.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 210 → 189 | 118 → 107 |
| 17 | `music/battle2_E_pulse.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 209 → 187 | 114 → 102 |
| 18 | `music/battle2_A_pulse.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 208 → 187 | 113 → 102 |
| 19 | `music/battle2_B_pulse.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 206 → 188 | 113 → 102 |
| 20 | `music/final_A_p1.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 206 → 170 | 116 → 96 |
| 21 | `music/battle1_B_pulse.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 205 → 186 | 112 → 101 |
| 22 | `music/boss_C_full.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 205 → 178 | 116 → 100 |
| 23 | `music/battle2_E_drive.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 204 → 168 | 111 → 91 |
| 24 | `music/battle1_A_pulse.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 204 → 189 | 111 → 103 |
| 25 | `music/battle1_E_pulse.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 204 → 184 | 111 → 101 |
| 26 | `music/final_B_p1.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 203 → 165 | 115 → 93 |
| 27 | `music/final_D_p1.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 203 → 177 | 115 → 100 |
| 28 | `music/battle1_E_drive.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 203 → 150 | 111 → 82 |
| 29 | `music/battle1_C_pulse.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 203 → 192 | 111 → 104 |
| 30 | `music/boss_A_full.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 203 → 182 | 115 → 103 |
| 31 | `music/battle2_C_pulse.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 203 → 190 | 110 → 104 |
| 32 | `music/final_C_p1.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 203 → 175 | 115 → 99 |
| 33 | `music/boss_B_full.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 203 → 175 | 114 → 99 |
| 34 | `music/battle1_B_drive.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 202 → 151 | 110 → 82 |
| 35 | `music/battle2_B_drive.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 202 → 151 | 110 → 82 |
| 36 | `music/battle3_E_base.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 202 → 137 | 114 → 77 |
| 37 | `music/battle2_A_drive.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 202 → 153 | 110 → 83 |
| 38 | `music/battle1_A_drive.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 201 → 170 | 109 → 93 |
| 39 | `music/battle3_E_drive.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 200 → 149 | 113 → 84 |
| 40 | `music/battle3_A_drive.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 200 → 154 | 113 → 87 |
| 41 | `music/battle2_D_pulse.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 200 → 181 | 109 → 99 |
| 42 | `music/battle3_B_drive.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 200 → 151 | 113 → 85 |
| 43 | `music/battle3_B_base.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 199 → 138 | 112 → 78 |
| 44 | `music/battle1_D_pulse.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 199 → 181 | 108 → 99 |
| 45 | `music/battle3_E_pulse.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 198 → 178 | 112 → 100 |
| 46 | `music/battle3_A_pulse.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 198 → 180 | 112 → 101 |
| 47 | `music/battle3_B_pulse.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 198 → 180 | 112 → 102 |
| 48 | `music/battle2_C_drive.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 198 → 151 | 108 → 82 |
| 49 | `music/battle3_C_drive.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 197 → 148 | 111 → 83 |
| 50 | `music/final_C_p2.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 197 → 173 | 111 → 98 |
| 51 | `music/final_D_p2.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 197 → 158 | 111 → 89 |
| 52 | `music/battle3_A_base.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 197 → 129 | 111 → 73 |
| 53 | `music/battle1_C_drive.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 196 → 150 | 107 → 82 |
| 54 | `music/final_A_p2.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 195 → 163 | 110 → 92 |
| 55 | `music/final_B_p2.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 194 → 166 | 110 → 94 |
| 56 | `music/battle3_C_pulse.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 192 → 180 | 108 → 101 |
| 57 | `music/battle3_D_pulse.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 191 → 173 | 108 → 98 |
| 58 | `music/opening.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 181 → 133 | 99 → 73 |
| 59 | `music/battle2_danger.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 169 → 128 | 92 → 70 |
| 60 | `music/battle1_danger.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 168 → 126 | 92 → 68 |
| 61 | `music/battle3_danger.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 166 → 127 | 94 → 72 |
| 62 | `music/battle2_C_base.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 157 → 129 | 86 → 70 |
| 63 | `music/battle1_C_base.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 155 → 147 | 84 → 80 |
| 64 | `music/battle3_C_base.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 154 → 127 | 87 → 72 |
| 65 | `music/win.ogg` | BGM | OGG | 44100 Hz / 立体声 | 13.0 s | 148 → 95 | 93 → 60 |
| 66 | `music/battle2_D_base.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 148 → 129 | 81 → 70 |
| 67 | `music/lose.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 147 → 98 | 80 → 53 |
| 68 | `music/battle1_D_base.ogg` | BGM | OGG | 44100 Hz / 立体声 | 15.0 s | 146 → 128 | 80 → 70 |
| 69 | `music/battle3_D_base.ogg` | BGM | OGG | 44100 Hz / 立体声 | 14.5 s | 143 → 123 | 81 → 70 |
| 70 | `music/boss_down.ogg` | BGM | OGG | 44100 Hz / 立体声 | 9.0 s | 97 → 68 | 89 → 61 |
| 71 | `voice/skalter_skill_3.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 7.2 s | 95 → 45 | 108 → 51 |
| 72 | `music/boss_in.ogg` | BGM | OGG | 44100 Hz / 立体声 | 6.5 s | 83 → 65 | 105 → 82 |
| 73 | `voice/skalter_battle.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 5.9 s | 80 → 38 | 111 → 53 |
| 74 | `voice/skalter_entry.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 5.5 s | 74 → 35 | 111 → 53 |
| 75 | `voice/hoshiguma_battle.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 5.6 s | 73 → 35 | 106 → 51 |
| 76 | `voice/lumen_skill_2.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 5.1 s | 70 → 33 | 113 → 53 |
| 77 | `voice/skalter_skill_1.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 4.2 s | 60 → 28 | 116 → 55 |
| 78 | `voice/skalter_skill_2.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 3.9 s | 56 → 27 | 116 → 57 |
| 79 | `voice/specter_unchained_battle.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 5.0 s | 55 → 34 | 90 → 55 |
| 80 | `voice/lumen_battle.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 4.7 s | 52 → 28 | 90 → 49 |
| 81 | `voice/angelina_battle.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 3.2 s | 50 → 24 | 131 → 61 |
| 82 | `voice/hoshiguma_skill_2.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 3.6 s | 50 → 25 | 113 → 55 |
| 83 | `voice/wisadel_skill_3.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 6.3 s | 48 → 33 | 62 → 43 |
| 84 | `voice/wisadel_battle.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 5.4 s | 46 → 31 | 69 → 47 |
| 85 | `voice/mizuki_skill_3.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 3.1 s | 44 → 24 | 117 → 63 |
| 86 | `sfx/op_lumen_s3.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 2.4 s | 42 → 42 | 144 → 144 |
| 87 | `sfx/hunt_warn.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 2.4 s | 42 → 42 | 144 → 144 |
| 88 | `voice/skadi_skill_1.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 3.9 s | 42 → 26 | 87 → 54 |
| 89 | `voice/skadi_skill_2.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 3.4 s | 41 → 24 | 98 → 57 |
| 90 | `voice/wisadel_skill_1.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 4.3 s | 41 → 27 | 76 → 52 |
| 91 | `voice/lumen_skill_3.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 2.8 s | 40 → 19 | 118 → 55 |
| 92 | `sfx/op_irene_s3.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 2.3 s | 40 → 40 | 144 → 144 |
| 93 | `voice/lumen_skill_1.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 2.5 s | 40 → 19 | 132 → 62 |
| 94 | `voice/ulpianus_battle.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 3.2 s | 39 → 24 | 99 → 60 |
| 95 | `voice/specter_unchained_entry.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 2.6 s | 39 → 21 | 120 → 64 |
| 96 | `sfx/op_logos_s3.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 2.2 s | 39 → 39 | 144 → 144 |
| 97 | `voice/skadi_skill_3.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 3.4 s | 37 → 22 | 87 → 52 |
| 98 | `voice/ulpianus_entry.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.9 s | 36 → 16 | 151 → 69 |
| 99 | `sfx/izu_wave_count.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 2.0 s | 35 → 35 | 144 → 144 |
| 100 | `voice/angelina_entry.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 2.3 s | 35 → 17 | 125 → 61 |
| 101 | `voice/wisadel_entry.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 3.9 s | 34 → 24 | 73 → 51 |
| 102 | `voice/mizuki_battle.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 3.3 s | 34 → 24 | 85 → 61 |
| 103 | `voice/angelina_skill_3.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 2.0 s | 33 → 17 | 139 → 69 |
| 104 | `voice/suzuran_entry.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 2.3 s | 33 → 18 | 120 → 66 |
| 105 | `sfx/op_suzuran_s3.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.9 s | 33 → 33 | 145 → 145 |
| 106 | `voice/angelina_skill_1.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.8 s | 33 → 16 | 146 → 71 |
| 107 | `sfx/op_mizuki_s3.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.9 s | 33 → 33 | 144 → 144 |
| 108 | `sfx/cue_global_start.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.8 s | 32 → 32 | 145 → 145 |
| 109 | `voice/wisadel_w_laugh.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 3.0 s | 31 → 20 | 87 → 56 |
| 110 | `voice/angelina_skill_2.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.7 s | 31 → 15 | 146 → 72 |
| 111 | `voice/siege_skill_3.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 2.8 s | 31 → 21 | 91 → 62 |
| 112 | `sfx/op_eyjafjalla_s3.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.7 s | 30 → 30 | 145 → 145 |
| 113 | `voice/skadi_battle.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 2.9 s | 30 → 20 | 83 → 55 |
| 114 | `voice/irene_skill_3.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 2.3 s | 29 → 18 | 107 → 64 |
| 115 | `sfx/op_suzuran_s2.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.6 s | 29 → 29 | 145 → 145 |
| 116 | `sfx/op_skadi_s3.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.6 s | 28 → 28 | 145 → 145 |
| 117 | `sfx/cue_global_hit.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.6 s | 28 → 28 | 145 → 145 |
| 118 | `sfx/hunt_close.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.6 s | 28 → 28 | 145 → 145 |
| 119 | `voice/specter_unchained_skill_3.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 2.5 s | 28 → 18 | 92 → 61 |
| 120 | `voice/texas_skill_2.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.7 s | 27 → 14 | 134 → 68 |
| 121 | `voice/ulpianus_skill_3.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.8 s | 27 → 17 | 121 → 75 |
| 122 | `voice/mizuki_entry.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 2.0 s | 27 → 16 | 112 → 68 |
| 123 | `sfx/op_lumen_s2.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.5 s | 27 → 27 | 145 → 145 |
| 124 | `voice/irene_battle.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 2.2 s | 27 → 17 | 100 → 65 |
| 125 | `sfx/op_ulpianus_s2.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.5 s | 27 → 27 | 145 → 145 |
| 126 | `sfx/cocoon_revive.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.5 s | 27 → 27 | 145 → 145 |
| 127 | `voice/saria_skill_1.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 2.5 s | 26 → 18 | 86 → 59 |
| 128 | `voice/irene_skill_1.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 2.0 s | 26 → 16 | 107 → 65 |
| 129 | `voice/siege_skill_1.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 2.3 s | 26 → 18 | 91 → 64 |
| 130 | `sfx/op_kaltsit_s3.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.4 s | 25 → 25 | 145 → 145 |
| 131 | `sfx/op_logos_s2.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.4 s | 25 → 25 | 145 → 145 |
| 132 | `voice/wisadel_skill_2.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 2.4 s | 25 → 18 | 86 → 61 |
| 133 | `sfx/cocoon_form.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.4 s | 25 → 25 | 145 → 145 |
| 134 | `sfx/cue_phase_start.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.4 s | 25 → 25 | 145 → 145 |
| 135 | `sfx/lamp_out.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.4 s | 25 → 25 | 145 → 145 |
| 136 | `sfx/start.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.4 s | 25 → 25 | 145 → 145 |
| 137 | `voice/hoshiguma_skill_1.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.4 s | 25 → 13 | 145 → 75 |
| 138 | `voice/irene_skill_2.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.9 s | 24 → 16 | 103 → 66 |
| 139 | `sfx/op_mizuki_s1.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.3 s | 23 → 23 | 145 → 145 |
| 140 | `sfx/beacon_lit.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.3 s | 23 → 23 | 145 → 145 |
| 141 | `sfx/lamp_empty.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.3 s | 23 → 23 | 145 → 145 |
| 142 | `sfx/stake_hit.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.3 s | 23 → 23 | 145 → 145 |
| 143 | `sfx/op_specter_unchained_s3.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.3 s | 23 → 23 | 145 → 145 |
| 144 | `voice/irene_entry.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.6 s | 23 → 14 | 115 → 73 |
| 145 | `voice/eyjafjalla_skill_2.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.6 s | 22 → 13 | 114 → 68 |
| 146 | `voice/texas_skill_3.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.3 s | 22 → 11 | 142 → 72 |
| 147 | `voice/logos_battle.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 2.2 s | 22 → 15 | 84 → 56 |
| 148 | `sfx/op_specter_unchained_s2.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.2 s | 22 → 22 | 145 → 145 |
| 149 | `voice/logos_skill_2.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 2.0 s | 22 → 15 | 87 → 60 |
| 150 | `sfx/op_saria_s3.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.2 s | 22 → 22 | 145 → 145 |
| 151 | `voice/suzuran_skill_2.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.8 s | 21 → 15 | 99 → 70 |
| 152 | `sfx/hunt_break.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.2 s | 21 → 21 | 145 → 145 |
| 153 | `sfx/ishar_land_break.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.2 s | 21 → 21 | 145 → 145 |
| 154 | `sfx/mire_clear.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.2 s | 21 → 21 | 145 → 145 |
| 155 | `sfx/roar.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.2 s | 21 → 21 | 145 → 145 |
| 156 | `sfx/op_logos_s1.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.2 s | 21 → 21 | 145 → 145 |
| 157 | `voice/hoshiguma_skill_3.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.1 s | 21 → 11 | 156 → 81 |
| 158 | `voice/eyjafjalla_skill_1.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.2 s | 21 → 11 | 140 → 75 |
| 159 | `sfx/op_skadi_s2.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.1 s | 20 → 20 | 145 → 145 |
| 160 | `voice/logos_skill_1.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.8 s | 20 → 13 | 92 → 60 |
| 161 | `sfx/op_lumen_s1.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.1 s | 20 → 20 | 146 → 146 |
| 162 | `voice/exusiai_battle.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.1 s | 20 → 11 | 152 → 80 |
| 163 | `voice/kaltsit_entry.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.1 s | 20 → 11 | 153 → 85 |
| 164 | `voice/hoshiguma_entry.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.1 s | 20 → 11 | 152 → 84 |
| 165 | `voice/eyjafjalla_entry.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.2 s | 20 → 11 | 137 → 77 |
| 166 | `sfx/beacon_end.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.1 s | 20 → 20 | 146 → 146 |
| 167 | `sfx/izu_lamp_lit.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.1 s | 20 → 20 | 146 → 146 |
| 168 | `sfx/nerve_burst.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.1 s | 20 → 20 | 146 → 146 |
| 169 | `sfx/op_wisadel_big.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.1 s | 20 → 20 | 146 → 146 |
| 170 | `sfx/shell_break.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.1 s | 20 → 20 | 146 → 146 |
| 171 | `voice/ulpianus_skill_2.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.6 s | 19 → 14 | 102 → 73 |
| 172 | `voice/logos_skill_3.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.9 s | 19 → 13 | 82 → 56 |
| 173 | `sfx/op_wisadel_s3.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.0 s | 18 → 18 | 146 → 146 |
| 174 | `voice/exusiai_skill_2.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.0 s | 18 → 10 | 143 → 81 |
| 175 | `voice/eyjafjalla_battle.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.2 s | 18 → 11 | 120 → 76 |
| 176 | `sfx/beacon_fizzle.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.0 s | 18 → 18 | 146 → 146 |
| 177 | `sfx/break_open.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.0 s | 18 → 18 | 146 → 146 |
| 178 | `sfx/cue_charge_start.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.0 s | 18 → 18 | 146 → 146 |
| 179 | `sfx/paranoia_land_break.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.0 s | 18 → 18 | 146 → 146 |
| 180 | `sfx/skill.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.0 s | 18 → 18 | 146 → 146 |
| 181 | `sfx/ulp_charge_loop.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.0 s | 18 → 18 | 146 → 146 |
| 182 | `sfx/op_siege_s3.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 1.0 s | 18 → 18 | 146 → 146 |
| 183 | `voice/siege_battle.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.4 s | 17 → 13 | 106 → 78 |
| 184 | `voice/exusiai_skill_1.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 0.9 s | 17 → 10 | 149 → 82 |
| 185 | `voice/saria_skill_2.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.2 s | 17 → 11 | 116 → 76 |
| 186 | `voice/specter_unchained_skill_1.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.4 s | 17 → 12 | 98 → 71 |
| 187 | `voice/lumen_entry.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 0.9 s | 17 → 10 | 148 → 90 |
| 188 | `voice/ulpianus_skill_1.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.5 s | 17 → 13 | 95 → 72 |
| 189 | `voice/eyjafjalla_skill_3.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.4 s | 17 → 12 | 99 → 72 |
| 190 | `voice/specter_unchained_skill_2.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.2 s | 17 → 11 | 117 → 78 |
| 191 | `sfx/op_specter_unchained_s1.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.9 s | 16 → 16 | 146 → 146 |
| 192 | `sfx/op_siege_s1.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.9 s | 16 → 16 | 146 → 146 |
| 193 | `sfx/op_ulpianus_big.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.9 s | 16 → 16 | 146 → 146 |
| 194 | `sfx/apop_pause.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.9 s | 16 → 16 | 146 → 146 |
| 195 | `sfx/boss_archon.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.9 s | 16 → 16 | 146 → 146 |
| 196 | `sfx/boss_bishop.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.9 s | 16 → 16 | 146 → 146 |
| 197 | `sfx/boss_carmen.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.9 s | 16 → 16 | 146 → 146 |
| 198 | `sfx/boss_iberia.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.9 s | 16 → 16 | 146 → 146 |
| 199 | `sfx/boss_immortal.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.9 s | 16 → 16 | 146 → 146 |
| 200 | `sfx/boss_ishar.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.9 s | 16 → 16 | 146 → 146 |
| 201 | `sfx/boss_izumik.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.9 s | 16 → 16 | 146 → 146 |
| 202 | `sfx/boss_knight_boss.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.9 s | 16 → 16 | 146 → 146 |
| 203 | `sfx/boss_paranoia.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.9 s | 16 → 16 | 146 → 146 |
| 204 | `sfx/boss_path.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.9 s | 16 → 16 | 146 → 146 |
| 205 | `sfx/cue_beam_start.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.9 s | 16 → 16 | 146 → 146 |
| 206 | `sfx/cue_land_start.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.9 s | 16 → 16 | 146 → 146 |
| 207 | `sfx/knight_frost.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.9 s | 16 → 16 | 146 → 146 |
| 208 | `sfx/levelup.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.9 s | 16 → 16 | 146 → 146 |
| 209 | `sfx/stake_shatter.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.9 s | 16 → 16 | 146 → 146 |
| 210 | `sfx/op_mizuki_s2.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.9 s | 16 → 16 | 146 → 146 |
| 211 | `sfx/op_lumen_big.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.9 s | 16 → 16 | 146 → 146 |
| 212 | `sfx/op_kaltsit_s2.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.9 s | 16 → 16 | 146 → 146 |
| 213 | `voice/texas_entry.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 0.9 s | 16 → 9 | 138 → 77 |
| 214 | `voice/logos_entry.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.1 s | 15 → 11 | 117 → 81 |
| 215 | `voice/mizuki_skill_2.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 0.7 s | 15 → 9 | 175 → 99 |
| 216 | `voice/mizuki_skill_1.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 0.9 s | 15 → 10 | 131 → 88 |
| 217 | `sfx/op_saria_s2.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.8 s | 15 → 15 | 146 → 146 |
| 218 | `sfx/hurt_heavy.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.8 s | 15 → 15 | 147 → 147 |
| 219 | `sfx/op_eyjafjalla_s1.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.8 s | 15 → 15 | 147 → 147 |
| 220 | `voice/texas_battle.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 0.8 s | 15 → 8 | 145 → 80 |
| 221 | `sfx/op_wisadel_s2.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.8 s | 15 → 15 | 147 → 147 |
| 222 | `sfx/op_eyjafjalla_s2.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.8 s | 14 → 14 | 147 → 147 |
| 223 | `sfx/apop_resume.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.8 s | 14 → 14 | 147 → 147 |
| 224 | `sfx/cue_beam_hit.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.8 s | 14 → 14 | 147 → 147 |
| 225 | `sfx/cue_land_hit.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.8 s | 14 → 14 | 147 → 147 |
| 226 | `sfx/enemy_screech.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.8 s | 14 → 14 | 147 → 147 |
| 227 | `sfx/izu_absorb.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.8 s | 14 → 14 | 147 → 147 |
| 228 | `sfx/relic.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.8 s | 14 → 14 | 147 → 147 |
| 229 | `sfx/ulp_release.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.8 s | 14 → 14 | 147 → 147 |
| 230 | `voice/suzuran_skill_1.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.1 s | 14 → 11 | 108 → 85 |
| 231 | `sfx/op_ulpianus_s1.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.8 s | 14 → 14 | 149 → 147 |
| 232 | `voice/exusiai_skill_3.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 0.7 s | 14 → 8 | 160 → 93 |
| 233 | `voice/skadi_entry.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 1.1 s | 14 → 10 | 107 → 80 |
| 234 | `voice/exusiai_entry.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 0.8 s | 14 → 8 | 137 → 81 |
| 235 | `voice/texas_skill_1.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 0.9 s | 14 → 8 | 127 → 75 |
| 236 | `sfx/op_saria_s1.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.7 s | 13 → 13 | 147 → 147 |
| 237 | `voice/kaltsit_skill_2.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 0.9 s | 13 → 10 | 114 → 85 |
| 238 | `sfx/op_irene_big.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.7 s | 13 → 13 | 147 → 147 |
| 239 | `sfx/op_skadi_s1.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.7 s | 13 → 13 | 147 → 147 |
| 240 | `voice/saria_skill_3.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 0.6 s | 13 → 8 | 164 → 102 |
| 241 | `sfx/op_irene_s2.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.7 s | 13 → 13 | 147 → 147 |
| 242 | `sfx/bishop_panic.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.7 s | 13 → 13 | 147 → 147 |
| 243 | `sfx/carmen_sword.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.7 s | 13 → 13 | 147 → 147 |
| 244 | `sfx/cue_charge_hit.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.7 s | 13 → 13 | 147 → 147 |
| 245 | `sfx/op_kaltsit_big.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.7 s | 13 → 13 | 147 → 147 |
| 246 | `sfx/op_skadi_big.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.7 s | 13 → 13 | 147 → 147 |
| 247 | `sfx/op_wisadel_hit.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.7 s | 13 → 13 | 147 → 147 |
| 248 | `voice/suzuran_battle.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 0.8 s | 13 → 10 | 122 → 93 |
| 249 | `voice/saria_battle.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 0.7 s | 12 → 8 | 150 → 97 |
| 250 | `sfx/op_ulpianus_s3.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.7 s | 12 → 12 | 151 → 148 |
| 251 | `sfx/knight_charge.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.7 s | 12 → 12 | 148 → 148 |
| 252 | `sfx/op_irene_s1.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.6 s | 12 → 12 | 148 → 148 |
| 253 | `voice/siege_skill_2.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 0.5 s | 12 → 7 | 192 → 120 |
| 254 | `voice/siege_entry.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 0.6 s | 11 → 7 | 171 → 110 |
| 255 | `voice/kaltsit_skill_1.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 0.6 s | 11 → 7 | 169 → 109 |
| 256 | `sfx/op_exusiai_big.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.6 s | 11 → 11 | 148 → 148 |
| 257 | `voice/suzuran_skill_3.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 0.7 s | 11 → 9 | 129 → 102 |
| 258 | `voice/kaltsit_skill_3.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 0.6 s | 11 → 7 | 151 → 103 |
| 259 | `sfx/boom.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.6 s | 11 → 11 | 148 → 148 |
| 260 | `sfx/op_kaltsit_heal.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.6 s | 11 → 11 | 148 → 148 |
| 261 | `sfx/op_siege_big.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.6 s | 11 → 11 | 148 → 148 |
| 262 | `sfx/op_suzuran_s1.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.6 s | 11 → 11 | 148 → 148 |
| 263 | `sfx/swing_heavy.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.6 s | 11 → 11 | 148 → 148 |
| 264 | `voice/saria_entry.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 0.5 s | 11 → 7 | 176 → 121 |
| 265 | `voice/kaltsit_battle.ogg` | 语音 | OGG | 44100 Hz / 单声道 | 0.4 s | 10 → 6 | 222 → 142 |
| 266 | `sfx/cue_melee_start.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.5 s | 9 → 9 | 149 → 149 |
| 267 | `sfx/op_eyjafjalla_big.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.5 s | 9 → 9 | 149 → 149 |
| 268 | `sfx/op_wisadel_quake.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.5 s | 9 → 9 | 149 → 149 |
| 269 | `sfx/kill_shell.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.5 s | 9 → 9 | 150 → 150 |
| 270 | `sfx/op_wisadel_atk.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.5 s | 9 → 9 | 150 → 150 |
| 271 | `sfx/enemy_elite.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.5 s | 8 → 8 | 150 → 150 |
| 272 | `sfx/heartbeat_hi.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.5 s | 8 → 8 | 150 → 150 |
| 273 | `sfx/mire_splat.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.5 s | 8 → 8 | 150 → 150 |
| 274 | `sfx/oil.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.5 s | 8 → 8 | 150 → 150 |
| 275 | `sfx/kill_big.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.4 s | 8 → 8 | 150 → 150 |
| 276 | `sfx/cue_melee_hit.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.4 s | 7 → 7 | 151 → 151 |
| 277 | `sfx/enemy_acid.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.4 s | 7 → 7 | 151 → 151 |
| 278 | `sfx/knight_stab.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.4 s | 7 → 7 | 151 → 151 |
| 279 | `sfx/op_kaltsit_s1.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.4 s | 7 → 7 | 151 → 151 |
| 280 | `sfx/op_wisadel_s1.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.4 s | 7 → 7 | 151 → 151 |
| 281 | `sfx/heartbeat.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.4 s | 7 → 7 | 152 → 152 |
| 282 | `sfx/op_ulpianus_atk.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.4 s | 7 → 7 | 152 → 152 |
| 283 | `sfx/beacon_tick.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.3 s | 6 → 6 | 152 → 152 |
| 284 | `sfx/enemy_nerve.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.3 s | 6 → 6 | 152 → 152 |
| 285 | `sfx/op_eyjafjalla_hit.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.3 s | 6 → 6 | 152 → 152 |
| 286 | `sfx/op_hoshiguma_hit.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.3 s | 6 → 6 | 152 → 152 |
| 287 | `sfx/op_siege_hit.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.3 s | 6 → 6 | 152 → 152 |
| 288 | `sfx/tentacle.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.3 s | 6 → 6 | 152 → 152 |
| 289 | `sfx/enemy_spit.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.3 s | 6 → 6 | 152 → 152 |
| 290 | `sfx/op_siege_s2.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.3 s | 6 → 6 | 152 → 152 |
| 291 | `sfx/break_hit.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.3 s | 6 → 6 | 153 → 153 |
| 292 | `sfx/op_logos_big.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.3 s | 6 → 6 | 153 → 153 |
| 293 | `sfx/op_lumen_atk.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.3 s | 6 → 6 | 153 → 153 |
| 294 | `sfx/op_suzuran_atk.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.3 s | 6 → 6 | 153 → 153 |
| 295 | `sfx/hurt.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.3 s | 5 → 5 | 154 → 154 |
| 296 | `sfx/op_specter_unchained_atk.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.3 s | 5 → 5 | 154 → 154 |
| 297 | `sfx/enemy_bite.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.3 s | 5 → 5 | 155 → 155 |
| 298 | `sfx/op_exusiai_atk.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.3 s | 5 → 5 | 155 → 155 |
| 299 | `sfx/op_skadi_atk.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.3 s | 5 → 5 | 155 → 155 |
| 300 | `sfx/op_lumen_hit.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.2 s | 5 → 5 | 156 → 156 |
| 301 | `sfx/dodge.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.2 s | 4 → 4 | 157 → 157 |
| 302 | `sfx/op_eyjafjalla_atk.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.2 s | 4 → 4 | 157 → 157 |
| 303 | `sfx/op_logos_atk.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.2 s | 4 → 4 | 157 → 157 |
| 304 | `sfx/op_texas_atk.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.2 s | 4 → 4 | 157 → 157 |
| 305 | `sfx/op_saria_hit.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.2 s | 4 → 4 | 158 → 158 |
| 306 | `sfx/op_siege_atk.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.2 s | 4 → 4 | 158 → 158 |
| 307 | `sfx/op_suzuran_hit.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.2 s | 4 → 4 | 158 → 158 |
| 308 | `sfx/swing.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.2 s | 4 → 4 | 158 → 158 |
| 309 | `sfx/op_irene_atk.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.2 s | 4 → 4 | 160 → 160 |
| 310 | `sfx/crit_tick.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.2 s | 4 → 4 | 160 → 160 |
| 311 | `sfx/kill.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.2 s | 4 → 4 | 160 → 160 |
| 312 | `sfx/op_skadi_hit.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.2 s | 4 → 4 | 160 → 160 |
| 313 | `sfx/op_mizuki_atk.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.2 s | 3 → 3 | 161 → 161 |
| 314 | `sfx/op_kaltsit_atk.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.1 s | 3 → 3 | 163 → 163 |
| 315 | `sfx/op_logos_hit.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.1 s | 3 → 3 | 164 → 164 |
| 316 | `sfx/hit.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.1 s | 2 → 2 | 170 → 170 |
| 317 | `sfx/op_exusiai_hit.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.1 s | 2 → 2 | 170 → 170 |
| 318 | `sfx/op_irene_hit.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.1 s | 2 → 2 | 170 → 170 |
| 319 | `sfx/op_saria_atk.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.1 s | 2 → 2 | 170 → 170 |
| 320 | `sfx/ui_ok.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.1 s | 2 → 2 | 170 → 170 |
| 321 | `sfx/op_mizuki_hit.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.1 s | 2 → 2 | 174 → 174 |
| 322 | `sfx/atk_gate.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.1 s | 2 → 2 | 182 → 182 |
| 323 | `sfx/pickup.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.1 s | 2 → 2 | 188 → 188 |
| 324 | `sfx/ui_move.wav` | 音效 | WAV→QOA | 44100 Hz / 单声道 | 0.0 s | 1 → 1 | 223 → 223 |

## 4. 实导网页包（tools/export_web.py）

| | 源码 | 网页包总大小 | index.pck（未压缩） |
|---|---|---|---|
| 压前 | main 420871c6 | 43.1 MiB | 35.79 MiB |
| 只压 BGM（中间版） | 878e3134 | 38.2 MiB | 30.91 MiB |
| 压后 | f6799933（BGM + 语音 24 kHz） | 37.2 MiB | 30.06 MiB |

## 5. 估算：网页版语音按编队按需加载、不进启动包（只估不做）

- 现状：`sfx.gd._voice_stream` 已是用到才从 pck 里加载，引擎层面就是按需；问题只在下载——pck 是一整块，语音跟着启动包下。
- 要改：① 导出预设 exclude_filter 加 `audio/voice/*.ogg`，`export_web.py` 把这 91 个 OGG 原样拷到输出目录；② `sfx.gd` 网页版在 pck 里找不到时改用 HTTPRequest 取文件、`AudioStreamOggVorbis.load_from_buffer` 解出来缓存，编队变化（招募 / 开局）时预取这几名干员的 5 条；第一次没取到就跳过这条（语音本来就允许放弃）；桌面 / 手机原生包不变。约 60–90 行 GDScript + 15 行导出脚本 + 一个离线测试，半天左右。
- 收益：启动包少 1.48 MiB（压后语音全部），首屏下载快约 4%。**但不减上传总量**：B站 Toy 的 50 MB 是整个包的文件总量（docs/99 第 6 条），语音拆成单独文件仍算在里面，对「超不超 50 MB」没有帮助。建议不做，除非以后要单独优化首屏加载时间。
