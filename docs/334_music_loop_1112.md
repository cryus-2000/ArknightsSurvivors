# 334 配乐循环验收（11-12）

用户：「一般肉鸽大部分时候的配乐是循环的，我们现在满足这个条件吗？当然切换 Boss 和转阶段的时候不算」。

结论：**满足**。每首会循环的曲子桌面、网页都无缝循环，播完不会停、不会整段静音。查出两处，已修：
1. 出商店战斗曲从头放（一局三个商人 = 战斗曲前奏重放三遍，来回进出时只听得到开头）→ 改成接着放；
2. 网页 AAC 的编码器预滚（1024 样本 ≈ 32 ms）：Chromium 解码会去掉、逐样本对齐；若某浏览器（iOS Safari 无法在本机测）没去掉，每圈会有 32 ms 空档 + 跳接 → JS 自己判断并平移循环点。

分支 `claude/music-loop`（基于 `claude/music-debounce` 4de938507，含配乐防抖）。

## 1. 各场景配乐

时长 = 原 OGG 秒数；循环 = 播到尾回到哪里；无缝 = 下面三种实测都过。桌面 / 网页一致 = 网页 web_music.js 回环与原 OGG 逐样本对齐。

| 场景 | 曲目（文件） | 时长 | 循环 | 回环无缝 | 桌面 / 网页一致 | 问题 |
|---|---|---|---|---|---|---|
| 标题 / 设置 / 操作说明 / 致谢；结算（胜 / 负同曲） | title（title.ogg） | 200.00 | 是，回 0 | 是 | 是 | — |
| 图鉴 | archive（suno_archive_full.ogg） | 189.52 | 是，回 0 | 是 | 是 | — |
| 选人 / 难度 / Boss 演练 | deploy（deploy.ogg） | 192.96 | 是，回 0 | 是 | 是 | — |
| 开场动画 | opening（opening.ogg） | 15.00 | **否**（设计：播完即停，接战斗一） | — | 是（主包样本） | — |
| 局内 0–1 级威胁 | battle1（3 层） | 199.75 | 是，回 0；三层偏差 ≤ 12 ms | 是 | 是 | 出商店从头放（已修） |
| 局内 2–3 级威胁 | battle2（3 层） | 191.47 | 同上 | 是 | 是 | 同上 |
| 局内 4+ 级威胁 | battle3（3 层） | 206.76 | 同上 | 是 | 是 | 同上 |
| 商人 | shop（shop.ogg） | 99.95 | 是，前奏只播一次，回 22.06 秒（loop_offset） | 是 | 是 | — |
| 中期 Boss | boss（suno_boss_full） | 185.20 | 是，回 0 | 是 | 是 | — |
| 最终 Boss 结局一 | final（p1 / p2 两层） | 203.21 | 是，回 0；二阶段叠 p2 | 是 | 是 | — |
| 最终 Boss 结局二 | final_knight（2 层） | 233.51 | 同上 | 是 | 是 | — |
| 最终 Boss 结局三 | final_ishar（2 层） | 210.34 | 同上 | 是 | 是 | — |
| 最终 Boss 结局四 | final_izumik（2 层） | 204.83 | 同上 | 是 | 是 | — |
| 事件 / 选卡 / 暂停 | 不换曲，当前曲目照放（低通压到 1800 Hz） | — | — | — | — | — |
| Boss 登场 / 击破 | boss_in / boss_down 叠加短句 | 短 | 否（设计：叠在曲上一次性） | — | — | — |

没用到的文件：archive_v2.ogg（suno_archive_full 在时被取代）、final_suno.ogg（分层 final 在时被取代；它的回环频谱跳变偏高，若将来退回要重做循环点）。

导入设置里只有 shop 是 loop=true，其余 loop=false——不影响：sfx.gd 载入时一律 `ov.loop = true`（opening 除外），shop 另设 loop_offset = SHOP_LOOP。

## 2. 实测

- **原曲离线**（scratchpad seam.py）：头尾无静音；回环处样本跳变都低于曲中相邻样本差的 99.9 分位，频谱跳变在曲中相邻帧的正常范围内（分层曲按全部层相加算）。Suno 曲由 tools/suno_layers.py 在尾首做过整数小节的等功率交叉淡化，本来就是循环版。
- **桌面引擎**（`game/tests/music_loop_test`，无头 + Dummy 驱动）：走 Sfx.play_music 真路径，各层一起 seek 到曲尾前 2 秒，连续两次回绕 = 每首循环两次；12 首都回绕到 0（商人 22.06）、播放器全程在播、层间偏差 ≤ 12 ms。商人另按真实时间放满 210 秒：两次回到 22.06，一直在播。开场引子 15.02 秒后自停。
- **桌面回环录音**（Music 总线 AudioEffectCapture → `tools/music_loop_check.py`）：回环前后两段与原曲的互相关 ≥ 0.995，两段的位置差与循环长度相差 ≤ 0.02 ms（无多出 / 少掉的时间），回环点 ±50 ms 电平与原曲同（0 dB，无空档），残差 −15 ~ −33 dB。12 / 12 无缝。
- **网页**（真的 web_music.js + OfflineAudioContext，曲尾前 2 秒开播渲染 4 秒，对照同上下文解码的原 OGG；Chromium 156）：回环前后残差 −18 ~ −45 dB（AAC 编码噪声量级、逐样本对齐），回环点电平 −0.1 ~ −1.5 dB（无空档）。模拟「没去掉预滚」：不修时回环点 −155 dB 空档 + 前后错位；修后与去掉时完全一样。
- **配乐防抖之后**：tests/music_shop_flip_test 照旧 解码 2 次、复用 59 次（接着放不增加解码）。网页端出商店时战斗曲解码缓冲还在（防抖），从记下的位置 start。

## 3. 改动

- `sfx.gd`：`shop_resume` 进商店时记战斗曲 `_lay_pos`，出商店回同一首 `_start(..., from=pos)`；换到别的曲目就作废。Boss 倒下回战斗仍从头缓缓回来（设计，不变）。
- `web_music.py`：web_music.json 每首加 `pre`（1024 / 采样率）。`sfx.gd _wm_sync` 把它作为播放项第 7 位交给 JS。
- `web_music.js`：解码后若缓冲比原曲长出 ≥ pre（去掉预滚时只多尾部补齐、< pre），循环起止与起播位置一起后移 pre。旧包没有 pre 字段 = 0，行为不变。

## 4. 没有好循环点的曲子

无。全部已在用的曲子回环无缝；唯一偏高的是未使用的 final_suno.ogg（建议：真要用就按 150.455 BPM 取整数小节重做尾首交叉淡化，与 suno_layers.py 同法）。

## 5. 跑法

```
godot --headless --audio-driver Dummy --path game res://tests/music_loop_test.tscn          # 全部曲目 seek 两次 + 开场 + 商人接着放
godot --headless --audio-driver Dummy --path game res://tests/music_loop_test.tscn -- --mloop_real=shop   # 真实时间放满两轮
python tools/music_loop_check.py   # 读 build/music_loop/cap_*.wav
```
