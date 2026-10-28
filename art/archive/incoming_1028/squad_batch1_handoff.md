# 编队美术第一批：博士

依据 `docs/24_squad_art_brief.md`（96c2311，2026-09-25 的 48px 约定）。

新增 4 条 / 16 帧，保留原有 `doctor.png` 与 `doctor@2x.png`。

| 文件 | 单帧 | 帧数 | fps | 播放 |
|---|---|---|---|---|
| doctor_idle.png | 48×48 | 4 | 4 | 循环 |
| doctor_run.png | 48×48 | 6 | 10 | 循环 |
| doctor_hurt.png | 48×48 | 2 | 10 | 单次 |
| doctor_death.png | 48×48 | 4 | 6 | 单次并停末帧 |

脚底锚点 `(24,46)`；正面略朝右，运行向右，左向交给程序镜像。死亡依次为失衡、跪倒、侧倒、静止，整条使用相同缩放比例，不能把末帧重新拉高。

`squad_batch1_manifest.json` 包含尺寸、帧数、fps、循环规则和 SHA256；`squad_batch1_preview.png` 展示所有帧；`squad_batch1_qa.json` 记录逐帧包围盒与像素哈希。所有图片为 RGBA PNG，alpha 0/255，角色共24色，外沿为 #080E18，画布边缘透明，无重复帧。

本批不含可选的 doctor_command，不新增 @2x。未修改 game/；尚未进行游戏内验收。
