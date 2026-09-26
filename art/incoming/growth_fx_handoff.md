# 成长线特效 A2–A12 交接

按 docs/34 §0 / §A / §D 制作，已先合并 main。仅交付这 11 项例外授权特效，A1、B 类和游戏代码未改。

## 接入

22 张横向等宽 PNG，含原尺寸及 @2x，共 94 帧。PX=2；@2x 使用双倍源分辨率但保持相同游戏世界显示尺寸，避免再放大一倍。两档均从生成母图独立采样，非小图插值放大。RGBA 二值透明、1px 深色描边、最近邻过滤，无脚底阴影。

manifest 记录尺寸、锚点、FPS、分段 clips、循环方式和 SHA256。以下帧索引从 0 开始。FPS 为本次建议，可按游戏时长调整。

| 文件主名 | 单帧 @1x | 帧数 | 播放 |
|---|---|---|---|
| fx_mizuki_jelly | 12×16 | 4 | 6fps 循环 |
| fx_wisadel_soul | 20×28 | 6 | 0–3 悬浮 8fps 循环；4–5 俯冲 12fps 单次，不能整条循环 |
| fx_wisadel_mark | 8×12 | 2 | 4fps 循环 |
| fx_suzuran_wisp | 8×12 | 4 | 8fps 循环 |
| proj_suzuran_bigfox | 24×16 | 4 | 10fps 循环，朝右 |
| fx_suzuran_ninetails | 64×48 | 4 | 4fps 循环，底部根点置于人物身后 |
| fx_mon3tr_blade | 16×24 | 2 | 4fps 循环；第二组交给程序镜像 |
| fx_kaltsit_shell | 48×40 | 4 | 6fps 循环 |
| fx_lumen_unit | 12×14 | 5 | 0–3 灯芯 6fps 循环；4 开火约 83ms 后返回循环 |
| fx_skadi_wave | 64×32 | 6 | 14fps 单次，朝右，底部落地 |
| fx_skadi_surge | 80×44 | 6 | 14fps 单次，椭圆中心为作用中心 |

默认中心锚点；九尾与海浪墙使用底部锚点，见 manifest。九尾与护壳用二值透明轮廓保留清楚像素边缘，整体半透明由渲染 modulate 实现：建议九尾 alpha=0.45、护壳=0.5。护壳内部保留透空晶面。最后一帧海浪/涌浪仍有少量水花，播放完需移除实例。

## 验证与来源

使用内置 imagegen 按设定生成原创特效母图，再机械裁切、独立双密度最近邻采样、限定调色板、添加描边。提示词、来源哈希、源切帧坐标见 manifest；完整源任务见 growth_fx_generation.json。九尾返修过尾数及背景；以最终九尾 PNG 为准。

verify-sprites.ps1：22 strips / 94 frames 通过尺寸、透明、描边、边界、色数、帧差异和哈希检查。效果图采用 SkipBaseline（浮空/特效不要求站地）。已检查所有母图及导出总览，单项放大预览一起交付。尚未接入或运行 Godot；请 Claude cherry-pick 后按「有图画图、缺图退回程序版」接入，并以静音实战连拍核对实际大小、透明度与动画时长。
