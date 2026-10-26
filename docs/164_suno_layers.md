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
- **回退开关**：`balance.json music/suno_layers`（缺省 1；0 = 回到旧的 SEQ 乐句拼接、`archive_v2`、`final_suno` 整首）。旧文件与旧代码都在。
- 手机网页：`_suno_init` 只载入各曲第一层（底层 / 整曲 / p1），沿用 `MOBILE_MUSIC_MAP`（battle2 / 3 → battle1，final → boss）；`sample_mem_mb` 已把分层曲目的流算进内存估计。**fps-first 的「按需加载 + 用完释放 + 手机降采样」方案落地后要在它上面对接**（已给 fps-first 会话发消息问分支与接口，回复后再接；三层同时解码约 51 MB × 3 / 曲，桌面是流式不解码）。

## 4. 包体

- 新增 13 个 ogg 共约 26.7 MiB（桌面包 / 仓库）。网页包导出时 `tools/web_audio.py drop_unused_music` 把被取代的旧文件不打进去（battle*_A–E_*、danger、boss_A–D_full、final_A–D_p1/p2、final_suno、archive_v2，约 13.6 MiB；`suno_layers.json` 或任一层缺失时不删）。
- **网页包估计**：B 档（配乐 22.6 MiB）约 46–47 MiB，C 档（19.2 MiB）约 43 MiB——比 docs/121 §4 的 33.4 MiB 大 10–13 MiB，远超 25 MiB 目标，接近 Toy 50 MB 线。要压只能继续降码率 / 层数（pulse 改单声道、手机网页不带 pulse / drive），这是产品取舍，没做。

## 5. 验证

- `tests/suno_layers_test.tscn`（`check.py --only suno_layers`）：五首载入、层数、同长度（±3 ms）、bpm 合理；战斗 lv 0 → 1 → 2 → 危险 → 回 0 在小节线上开关层；战斗换段最多等一小节且新曲从头；Boss 在放；最终 Boss 一阶段只开 p1、二阶段叠 p2；回战斗不残留。另跑 core / menu_bgm / repro / boss_trial 通过。
- 演示 mp4（`tools/suno_layers_demo.py`，主仓库 `build/suno_layers/suno_layers_demo.mp4`）：战斗从平静 → 交战 → 激战 → 回平静 → 换段 → Boss → 最终 Boss 一阶段 → 半血二阶段，**带声音**。声音是离线渲染（同一套调度逻辑搬到 Python 混同一批 ogg，Master 限幅 −0.5 dB、vol_target −4 dB），不是游戏里直接录的：自动测试 / 录制一律静音 Master（AGENTS.md 硬规定）。
