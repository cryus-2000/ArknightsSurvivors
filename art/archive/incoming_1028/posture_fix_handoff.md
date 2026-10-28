# 流明 / Logos 头颈姿态修正

修正两人 idle/run/attack/skill 中头部前伸、下巴前探的姿态。保留流明提灯、挎包与 Logos 骨笔。交付 48px 及 96px 两档，共 16 张帧条、84 帧。文件名、帧数、FPS、事件帧、脚底锚点保持原约定，可直接替换 art/incoming 对应文件。

姿态规则见 character_posture_constraints.md，已同步到本机 pixel-sprite-pipeline SKILL.md。

验证：verify-sprites.ps1 全部通过，包括尺寸、二值透明、描边、调色板、基线及逐帧差异。已检查放大帧表；尚未运行 Godot 实机验证。姿态生成有轻微像素和衣摆差异，非逐像素保持旧稿。

预览：posture_fix_lumen_preview.png、posture_fix_logos_preview.png。
QA：posture_fix_qa.json；完整接入参数及文件哈希：posture_fix_manifest.json。

母图生成于 2026-09-26，通过现有母图作参考进行局部头颈姿态编辑，再用既有导出器机械裁切、调色板约束和描边。原始母图本机暂存 E:/水月/posture_fix_20260926/。
