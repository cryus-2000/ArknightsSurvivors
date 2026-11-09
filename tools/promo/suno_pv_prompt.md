# PV 配乐：术曲风 Suno 提示词（11-08）

项目里现有的 Suno 曲（战斗 1–3、中期 / 最终 Boss、Swarm Theme、Tree of Evolution、Último Caballo）都是无词或哼唱的游戏配乐，没有术曲风的，所以 PV 要新生成一首。生成后把整曲（最好连分轨）放到主仓库 `art/incoming/music_suno/pv_theme/`，按整曲重剪，不再拼接。

## Style

```
vocaloid style j-rock, denpa energy, 180 bpm, D minor, high-pitched synthetic female vocal with light autotune, fast rapid-fire lyrics, bright piano riff hook, distorted guitars, driving double-time drums, slap bass, glitchy vocal chops, sudden full stops before drops, big catchy chorus, anime game opening, energetic and bittersweet, deep sea theme
```

## Exclude

```
male vocals, rap, slow tempo, ballad, orchestral, ambient, lo-fi, long intro, fade out ending
```

## 结构（Lyrics 栏；方括号是段落标签，歌词由用户填）

```
[Intro: piano hook alone, 4 bars]
[Intro: full band hits, 4 bars]
[Verse]
（歌词）
[Pre-Chorus: build up, drums thin out]
（歌词）
[Stop: one bar of silence]
[Chorus: full band, catchy hook]
（歌词）
[Break: drums drop, piano and vocal only]
（歌词）
[Final Chorus: key up, full band]
（歌词）
[Outro: one hard hit, then stop]
```

## 剪法

PV 从 Intro 一直用到第一段 Chorus 结束（约 60 秒），中间不剪。镜头只在小节线上切：Intro / Verse 每 2 小节一镜，Pre-Chorus 每小节一镜，Stop 那一小节黑屏，Chorus 每小节一镜、重拍对终结技冲击帧，标题压在 Chorus 最后一个重拍上。
