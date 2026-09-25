# squad_batch4 第一部分：流明与灯塔
2026-09-25。已按用户批准的原皮和小提灯装备绘制，内置 imagegen 生成母图，机械切片、量化、二值 alpha 与外轮廓处理。

## 文件与接入
- op_lumen_idle：4 帧，4 fps，循环。
- op_lumen_run：6 帧，10 fps，循环。
- op_lumen_attack：4 帧，12 fps，出手索引 2（从 0 起），向前提灯治疗。
- op_lumen_skill：6 帧，12 fps，出手索引 3（从 0 起），首次高举灯并前倾。
- prop_lighthouse：2 帧，4 fps，帧 0 未亮、帧 1 灯室亮。
- 每条均有基础图和 @2x。人物 48 / 96 px、脚底 (24,46) / (48,92)；塔 64 / 128 px、脚底 (32,60) / (64,120)。
- PNG 不含治疗弹、光柱、地面光域；发射位置以手中小提灯为准，不使用杖顶偏移。
- 技能回到 idle 时，小灯归回身侧；旅行包随移动保留。

## 验证与范围
PASS：10 条，44 帧（包括两种密度），尺寸、二值透明度、边界描边、基线、色板、帧差异、哈希。
检查过像素尺寸预览；Godot 播放、跟随位置与出手判定尚未验证，由 Claude 接入检查。
小跑是紧凑步幅，请着重检查 10fps 下的循环衔接。
这是 batch4 的第一部分，其他四位人物、幽灵鲨替身尚未交付，不要标记整批完成。

## 来源与复现
立绘：https://wiki.biligame.com/arknights/流明
已批准参考哈希见 squad_batch4_reference_approval.json。
本机源图与机械导出脚本：E:/水月/art_staging/batch4/
lumen_master.png 为初稿；lumen_corrected.png 为背景及跑姿修订稿；lighthouse_master.png 为灯塔母图。
export.ps1 为本批专用切片参数；预览中的背景不属于透明 PNG。
