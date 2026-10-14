# docs/97 E 批交接

仅 art/incoming；未修改 game。水月已在 B 批及淡粉瞳色修正提交中处理。

## 修改
安洁莉娜加深暗部；艾丽妮披风和袖口增加中间调；推进之王增加受光层次；铃兰降低亮部并调整待机侧向，技能末帧同步。凯尔希撤回误伤肤色的整图调色，从原帧恢复浅肤色及白发，仅处理下部中性白大衣阴影。

## 实测（1x 单位）
|角色|站立高|idle 脚底 x|交付帧条合计色数|
|---|---:|---:|---:|
|angelina|36.0|23.5|23|
|irene|31.5|25.25|23|
|kaltsit|35.0|25.25|23|
|siege|38.5|23.75|23|
|suzuran|33.5|23.75|23|

## QA
运行 python tools/art_lint.py --ops angelina,irene,kaltsit,siege,suzuran,mizuki --no-images。未豁免 FAIL 0，已有豁免 2（安洁莉娜浮空、铃兰朝向），WARN 8。详见 op_fix_e_qa.json。
凯尔希：HSL 0.602、亮部 75%，保留明度 WARN；优先保留用户要求的原肤色、白发，未达到全图明度目标。艾丽妮近黑 27%；其余受光增益及旧脚底配置警告均如实保留。脚底 json 调整按 docs/97 F 由 Claude 处理。
未进行引擎验收；此批为素材交付，不代表接入。

## 预览
op_fix_e_preview.gif 为动作预览；op_fix_e_lineup.png 为明/暗两行，附斯卡蒂、浊心斯卡蒂、流明参照。QA 数据与预览分文件。
