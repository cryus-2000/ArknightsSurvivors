# 局内贴图规格补齐 · 2026-10-24

交付分支：`codex/world-spec-1024`。本目录是本次总单的唯一交付入口。

10-24 返修 2：商人撤回灰绿材料配色，恢复棕红皮革与锈色；结晶撤回圆蛋轮廓，小结晶逐像素保留旧图形状，大结晶沿同一棱柱结构扩展。见 merchant/reference_check.png 与 gems/shape_check.png。两项重新待审，其余素材不变。

10-24 返修 3：商人补回货包周围的触手卷曲、下垂段和右侧回绕长触手；仅改商人右侧货包区域，保持返修 2 配色。结晶和其他素材未变。

**状态：素材候选；技术检查与人眼验收分开记录。用户外观验收待定，未提交，未接入引擎。** 按 docs/104 §2.6 的“用户一句『过』再 git 提交”保留本地候选；由 Claude 完成 1:1 绘制、平铺、读取 1x 与局内验证。

全部运行图采用原生 1x、alpha 0 / 255。每件连同透明色均不超过 32 色；溟痕整套共享调色板。对照图保留旧素材原色，不受运行素材色数上限约束。无游戏、玩法、判定、尺寸表、原素材或界面素材修改。

## 按顺序看图

先看 [主要重绘项总览](REVIEW_MAIN.png) 与 [C 组压色总览](REVIEW_PROPS.png)。总览直接拼接原生对照图，不对图块额外缩放；细节也可点下面各项。

| 项目 | 主要对照 | 额外检查 | 交接说明 |
|---|---|---|---|
| A 溟痕平铺 | [compare.png](mire/compare.png) | [纯 A 3×3](mire/tile_a_3x3@2x.png)、[四个内角](mire/corners_check@2x.png)、[f1](mire/compare_f1.png) | [HANDOFF](mire/HANDOFF.md) |
| A4 退散 | [六帧旧 / 新](mire/compare_dissolve.png) | [新 1x 帧条](mire/fx_mire_dissolve.png) | 同上 |
| B 商人 | [compare.png](merchant/compare.png) | 水月参考与原生网格见该目录 | [HANDOFF](merchant/HANDOFF.md) |
| C 柱 | [compare.png](prop_pillar/compare.png) | [×8](prop_pillar/compare_8x.png) | [HANDOFF](prop_pillar/HANDOFF.md) |
| C 墙 | [compare.png](prop_wall/compare.png) | [×8](prop_wall/compare_8x.png) | [HANDOFF](prop_wall/HANDOFF.md) |
| C 沉船 | [compare.png](prop_wreck/compare.png) | [×8](prop_wreck/compare_8x.png) | [HANDOFF](prop_wreck/HANDOFF.md) |
| C 岩脊 | [compare.png](terrain_ridge/compare.png) | [×8](terrain_ridge/compare_8x.png) | [HANDOFF](terrain_ridge/HANDOFF.md) |
| C 岩峰 | [compare.png](terrain_peak/compare.png) | [×8](terrain_peak/compare_8x.png) | [HANDOFF](terrain_peak/HANDOFF.md) |
| C 珊瑚 | [compare.png](coral/compare.png) | [×8](coral/compare_8x.png) | [HANDOFF](coral/HANDOFF.md) |
| C 神经弹 | [compare.png](proj_floater_nerve/compare.png) | [×8](proj_floater_nerve/compare_8x.png) | [HANDOFF](proj_floater_nerve/HANDOFF.md) |
| D 经验结晶 | [compare.png](gems/compare.png) | 8×10 / 11×14，分别附 emit | [HANDOFF](gems/HANDOFF.md) |
| E 无人机 | [四帧旧 / 新](drone_laser/compare.png) | [×8](drone_laser/native_grid_x8.png) | [HANDOFF](drone_laser/HANDOFF.md) |

## 接入边界

- 用各目录的原生 PNG；交付中的 `@2x` 是精确整数最近邻版本，不能再叠加半径或非整数缩放。
- 溟痕：tile A/B 各 64×64 两帧；边图 12 片、两帧，完整切片坐标与纹理相位见 mire/HANDOFF。内区 192×192，加 16 px 四边后画布 224×224。变体 B 需配自身 emit。
- 退散：六帧 64×64，中心 (32,32)，保留 8 fps；大范围覆盖与裁切交由 Claude，不把局部效果拉伸到整块溟痕。
- 商人：使用新 `merchant@1x.png`，两帧 48×48；界面的旧 `merchant@2x.png` 保持原样。
- C 组：原图尺寸、帧数、alpha 和锚点逐像素 / 逐项保留，只并色；每个 `palette_map.json` 保留人工选择的逐色映射。
- 结晶：大小分别为 8×10、11×14，淡金白；亮面 emit 不包含轮廓与暗面。
- 无人机：四帧 24×20，保留 0/1 悬浮、2 发射峰值、3 回落。机身暗描边闭合，发射闪光按发光面处理。

## 核验

`QA_SUMMARY.json` 是统一复核结果，包含 15 张主体原生图的尺寸、帧数、色数、alpha、emit 对应、描边与 SHA-256。各目录另有细项 QA 或 manifest。

商人目录保存上一稿试跑旧 `px_lint.py` 的非零历史报告，不是返修稿验证。该调用把两帧作为单图，并采用旧脚底有色行及 @2x 内扩描边规则；返修稿的原生逐帧尺寸、脚底基线、闭合 1 px 外轮廓专项检查通过。不将总表的专项 PASS 表述为所有仓库工具通过。

已检查运行图与静态对照，不将这些检查表述为“引擎接入完成”或“用户外观通过”。没有执行 Godot、TRACE、平衡或发布测试，因本次没有修改代码 / 数据，也没有把新素材接入游戏。后续接入检查由 Claude 按仓库规范进行。

原 `codex/mire-tile` 工作树中的素材只是总单前的本地候选；本目录已包含迁移后的 tile、edge、emit 与新增退散，不要同时合入两处旧交付目录。
