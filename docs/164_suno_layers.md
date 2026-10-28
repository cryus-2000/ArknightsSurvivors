# 164 · Suno 整首分层配乐（10-27）

> 用户把 Suno 新配乐接进游戏、替换程序合成曲。状态：已实现（分支 `claude/suno-layers`），待用户听。素材 `art/incoming/music_suno/*.zip`（分轨原件不提交）；处理脚本 `tools/suno_layers.py`（同 `tools/suno_track.py` 口径）。标题 / 出发前 / 最终 Boss 整曲是第一批（main 7e8296b92），本批把战斗三段、中期 Boss、最终 Boss 分层、图鉴接上。

## 1. 分轨取舍与分层

每条分轨先量整曲 RMS 与有声占比（`build/suno_stats.json`）：

- **Woodwinds** 全部 ≤ -52 dBFS、有声 ≤ 9%（battle1 -62 dB / 2%）= 底噪，丢。
- **Vocals**：battle1 / battle3 / boss 的 Lead / Backing ≤ -44 dBFS、有声 ≤ 15% = 零星哼唱杂音，丢；battle2 的 Lead -34 dB / Backing -31 dB（有声 29% / 18%）是真的哼唱和声，并进 drive 层；最终 Boss 的 Lead -28 dB（有声 61%）是歌的主唱，放进 p1。
- 层（预混）：battle1–3 = **base**（Keyboard + Strings + Synth + Bass + Other）/ **pulse**（Drums + Percussion）/ **drive**（Guitar + Brass + 哼唱）；中期 Boss = **full**（全部，不分层）；最终 Boss = **p1**（Keyboard + Strings + Synth + Bass + Other + 人声，一阶段就有歌）/ **p2**（Drums + Percussion + Guitar + Brass，半血叠上）；图鉴 = 6 条分轨相加成整曲。

## 2. 处理（`tools/suno_layers.py`）

48 kHz → 32 kHz；去尾部静音；**尾首等功率交叉淡化成无缝循环，长度取整数个小节**（2–3 小节、3.2–4.8 秒，回环点前后拍位不变）；所有层同长度、同一个增益（保持混音比例）；响度按**整曲（全部层开）**对齐：battle −15 / Boss −15 / 图鉴 −17.8 LUFS，最终 Boss p1 单放 −15、全开 −13.5（p2 层再乘一个系数）。实测：battle 全开 −15.10 / −15.10 / −15.13，Boss −15.09，最终 p1 −15.08 / 全开 −13.59，图鉴 −17.81；平静层（base）单放 −17.8 ～ −19.0 LUFS（比全开低 3–4 dB，不会太空）。每层 ogg 编码档位 0.75（约 86 kbps 立体声）。

| 曲目 | 层 | bpm（鼓轨拍频精扫） | 首拍偏移 | 时长 |
|---|---|---|---|---|
| battle1 | base / pulse / drive | 140.805 | 0.363 s | 199.8 s |
| battle2 | 同上 | 145.990 | 0.111 s | 191.5 s |
| battle3 | 同上 | 149.940 | 0.156 s | 206.8 s |
| boss | full | 150.140 | 0.149 s | 185.2 s |
| final | p1 / p2 | 150.455 | 0.298 s | 203.2 s |
| archive | full | 100.005 | 0.179 s | 189.5 s |

bpm / 首拍偏移 / 时长写在 `game/audio/music/suno_layers.json`（脚本生成，sfx.gd 读）。battle2 / boss 的鼓轨自相关会报成半速（73 / 75），按两倍取（146 / 150），小节仍按 4 拍。

## 3. 播放（`sfx.gd`）

- **整首分层**（`lay`）：每首各层各一个 `AudioStreamPlayer`（`loop = true`），**同一时刻 `play(from)`**；`stem_on / stem_vol`（复用乐句式曲目的字段）单独控每层音量；`_lay_tick` 每帧用墙钟算拍号（`(pos − 首拍偏移 + BAR_AHEAD) × bpm / 60`），**每 4 拍（小节线）才把游戏请求的分层同步到 `stem_on`**（进层提前 BAR_AHEAD 淡入，保证重拍满音量；退层同样等小节线，两秒慢收）。网页的 `get_playback_position` 滞后约 1 秒，所以一律按墙钟。
- 战斗强度：lv 0 = base；lv 1 = + pulse；lv 2 = + drive（`set_battle`，`music_director` 不用改）。**危险层**：没有素材（Suno 分轨没有高频紧张层），危险时把 drive 拉出来顶替。
- **战斗换段**（battle1 → 2 → 3）：当前曲放到下一条小节线，新曲在小节线上从头开（淡入 / 淡出速度 6 / 秒 ≈ 0.17 秒，近乎硬切）。Boss / 最终 Boss 进出沿用原来的 pending 逻辑（Boss 登场落在 boss_in 的鼓点上）。最终 Boss 二阶段 = `set_final_phase(true)`，p2 在小节线上叠入。
- ~~回退开关 `balance.json music/suno_layers`~~：10-28 删掉开关、旧 SEQ 乐句拼接代码与旧合成乐句文件（约 9.5 MB）。现在只剩文件缺失回退：某首 Suno 层缺失 → 那首没有配乐（最终 Boss 退回整首 `final_suno`），`suno_archive_full` 缺失 → `archive_v2`。
- 手机网页：**已恢复全部曲目和分层**，移除 `_suno_init` 的只载首层分支及 `MOBILE_MUSIC_MAP`；通过共享 PCM、切曲释放与既有 24 kHz 上下文控制内存，见 §6。桌面继续流式播放。

## 4. 包体

- 新增 13 个 ogg 共约 26.7 MiB（桌面包 / 仓库）。网页包导出时 `tools/web_audio.py drop_unused_music` 把被取代的旧文件不打进去（battle*_A–E_*、danger、boss_A–D_full、final_A–D_p1/p2、final_suno、archive_v2，约 13.6 MiB；`suno_layers.json` 或任一层缺失时不删）。
- 初次接入时估计网页包约 46–47 MiB；**后续导出压缩已调整**，现行 B 档配乐 16.75 MiB，见 §6。本次没有删曲、删层、改为单声道或缩短循环。

## 5. 验证

- `tests/suno_layers_test.tscn`（`check.py --only suno_layers`）：五首载入、层数、同长度（±3 ms）、bpm 合理；战斗 lv 0 → 1 → 2 → 危险 → 回 0 在小节线上开关层；战斗换段最多等一小节且新曲从头；Boss 在放；最终 Boss 一阶段只开 p1、二阶段叠 p2；回战斗不残留。另跑 core / menu_bgm / repro / boss_trial 通过。
- 演示 mp4（`tools/suno_layers_demo.py`，主仓库 `build/suno_layers/suno_layers_demo.mp4`）：战斗从平静 → 交战 → 激战 → 回平静 → 换段 → Boss → 最终 Boss 一阶段 → 半血二阶段，**带声音**。声音是离线渲染（同一套调度逻辑搬到 Python 混同一批 ogg，Master 限幅 −0.5 dB、vol_target −4 dB），不是游戏里直接录的：自动测试 / 录制一律静音 Master（AGENTS.md 硬规定）。

## 6. 完整配乐的压缩与内存回收（10-27，codex/bgm-memory）

用户要求压缩 BGM、解决内存占用；按此前授权只做定向检查，不跑整套快检。范围是网页导出与音频生命周期，仓库 OGG 和桌面音质保留。

- `web_audio.py`：A / B / C 配乐采样率上限分别为 32 / 24 / 22.05 kHz，其余 Vorbis 档位沿用；保留立体声、全部层和完整曲长，只替换更小的结果。这是有损压缩；B 档不保留 12 kHz 以上频率，不宣称听感无损。23 个文件时长误差均 ≤ 一个输出采样点，同曲各层保持等长，商人循环偏移仍为 22.058889 秒。
- 同一组在用配乐：仓库源文件 **35.57 MiB**，此前网页 B 档 **23.19 MiB**，新 B 档 **16.75 MiB**（比原 B 档减少 **27.8%**）。这是 OGG 总大小，不是完整网页包大小；旧替代曲排除规则沿用。
- `engine_patch.py`：Godot 4.7.2 原先每次播放 / 恢复 / 循环都会复制整段 PCM；现在播放器共享样本，播放位置、音高、总线仍独立。释放接口保护正在播放或暂停的样本；内存统计对样本表与播放节点持有的缓冲去重。锚点不匹配时导出失败，旧补丁可升级，重复执行不重复注入。
- `sfx.gd`：`lay / seq / groups` 共用流清单。分层曲也记录最后播放时间，完全淡出并经过 3 秒宽限后释放；局外曲目同样回收，`menu_pos` 保留以供续播。移除手机裁层与替曲。首段预热改在 `title.gd` 实际开始载入时排队，开场引子期间保留；后续整首分层曲不推测性预载，取消旧音乐队列时保留音效队列。开播前先注册全部层，再同时播放，避免逐层解码拉开起点。
- 普通 Windows / Web 与加密 Windows 的导出预设加入 `audio/music/*.json`，确保分层配置进入包。

### 浏览器实测

Godot 4.7.2、无窗口静音 Edge、手机视口与触屏仿真、24 kHz 上下文，实际 Sfx + 完整配乐的独立导出探针。基线 `946920f40` 也开启全部层、使用同一批压缩素材；两版均计样本表与播放节点持有的**唯一 AudioBuffer PCM**，不沿用旧版漏计播放副本的指标。

| 切曲后稳定值（MiB） | 基线 | 修复后 |
|---|---:|---:|
| 战斗一 | 219.45 | 109.73 |
| 战斗二 | 320.08 | 105.18 |
| 战斗三 | 442.06 | 113.58 |
| 中期 Boss | 396.31 | 33.91 |
| 最终 Boss | 511.23 | 74.42 |
| 商人 | 473.41 | 18.30 |
| 回到标题（经过图鉴 / 选人） | 580.09 | 36.62 |
| 重回战斗一再进商人 | 473.41 | 18.30 |
| 全流程观测峰值（每秒采样） | 619.78 | 218.75 |

`tests/bgm_memory_test.tscn` 覆盖菜单 → 载入 → 引子 → 战斗、12 次切曲、全部层、预热、淡出释放、释放后再播、暂停保护 / 恢复无额外 PCM、最终 Boss 二阶段。修复版 **0 failures / 0 SCRIPT ERROR**；基线按同样回收要求产生 120 项失败，复现旧问题。Python 五项压缩 / 补丁 / 导出回归与原有 Suno、菜单续播回归通过。Suno 测试先停止长曲解码再退出，消除资源仍在使用的退出错误；菜单测试仍有既有的一个 ObjectDB 退出警告。

证据在工作分支目录 `build/bgm_memory/compression.json`、`build/bgm_memory/{suno_layers,menu_bgm}.log`、`output/playwright/bgm-memory-{fixed,baseline}.json`。这是音频独立探针，不含整局贴图、WASM 堆、音效 / 语音及解码临时分配；不能将 218.75 MiB 当成整局总峰值。未做手机真机试听 / 整局内存验收，首次解码长曲的卡顿也未据此宣称解决。
