# Codex 美术单：事件插图像素重构（event_cg_1026）

> 2026-10-26，用户同意方向（协调人转达）。调研与优先级依据：`docs/156_event_cg.md`；事件链：`docs/154_node_cards.md`。
> 按 `docs/104` 流程：本单只写**范围与验收**，不规定做法。
> **原图不进 git、不进包**：PRTS 原图只在主仓库 `build/event_cg/Avg_pic_rogue_2_<编号>.png` 作内部参照（用户 10-15 授权下载作参照）。交付物是重画的像素图，不得直接提交原图或对原图做整张算法缩放后交付。

## 1. 用途

翻节点卡揭示「不期而遇」后弹出的事件面板（C 版式，`game/scripts/screens/choice_panel.gd` 的 `draw_event_bg`）**左栏插画**。现在那里是灰阶墨色底 + 一枚节点图标，交付后换成本单的插画。

## 2. 规格

| 项 | 要求 |
|---|---|
| 画面尺寸 | **140 × 125 美术像素**，游戏内按 ×4 整数倍显示，占左栏插画框 560 × 500（界面逻辑像素，1280×720 基准）。另交同一张 ×4 放大的预览 PNG |
| 取景 | 原图 16:9，按 560:500（≈1.12:1）裁取，主体位置以 `docs/156` 表「裁出主体」列为准。**下方约 40% 会被压暗、叠事件名与剧情文字**，主体放在上方 60% 内 |
| 边缘 | 插画框是撕纸边，四周约 8 美术像素会被裁掉，不放关键内容 |
| 色数 | 每张 ≤ 64 色，无抖动噪点；透明不需要（整张不透明） |
| 调色 | 与 `docs/37` 水月界面协调：暗部落在藏青三阶（#122844 / #0B1A30 / #060E1E）附近，高光可用青 #60E0E8、泡沫 #C8FFFF；原作的设定色（角色发色、服饰点缀、火光、血色）保留，**设定色优先于界面色**（docs/87 §4.3） |
| 画风 | 与图鉴立绘 / 局内干员 @2x 像素一致：成面色块、2 像素内描边无断口、不散点；以逻各斯定稿 `codex/art a3eb677f` 的干净度为基准 |
| 角色 | 出现的原作角色（水月、博士、猎潮的骑士、深海猎人等）配色与标志饰件对照 PRTS 立绘，不得改设定 |

## 3. 清单与优先级

**P1（结局线，先交这 7 张，按顺序）**

| # | 事件 id | 事件名 | 原作图 | PRTS 文件页 |
|---|---|---|---|---|
| 1 | opening | 开端 | 25 | https://prts.wiki/w/文件:Avg_pic_rogue_2_25.png |
| 2 | madness | 狂徒妄念 | 23 | https://prts.wiki/w/文件:Avg_pic_rogue_2_23.png |
| 3 | knight_stay | 骑士仍在 | 24 | https://prts.wiki/w/文件:Avg_pic_rogue_2_24.png |
| 4 | heart | 深蓝之心 | 26 | https://prts.wiki/w/文件:Avg_pic_rogue_2_26.png |
| 5 | hymn | 赞歌 | 27 | https://prts.wiki/w/文件:Avg_pic_rogue_2_27.png |
| 6 | ritual | 深蓝仪式 | 56 | https://prts.wiki/w/文件:Avg_pic_rogue_2_56.png |
| 7 | ascend | 升华 | 57 | https://prts.wiki/w/文件:Avg_pic_rogue_2_57.png |

**P2（填充卡里最常见）**

| # | 事件 id | 事件名 | 原作图 | PRTS 文件页 |
|---|---|---|---|---|
| 8 | rest | 安全屋（安全的角落卡） | 46 | https://prts.wiki/w/文件:Avg_pic_rogue_2_46.png |
| 9 | wish | 消失的习俗（得偿所愿卡） | 20 | https://prts.wiki/w/文件:Avg_pic_rogue_2_20.png |

**P3（普通不期而遇）**

| # | 事件 id | 事件名 | 原作图 | PRTS 文件页 |
|---|---|---|---|---|
| 10 | glimmer | 残存微光 | 7 | https://prts.wiki/w/文件:Avg_pic_rogue_2_7.png |
| 11 | spark | 点滴星火 | 6 | https://prts.wiki/w/文件:Avg_pic_rogue_2_6.png |
| 12 | singer | 海边的歌者 | 3 | https://prts.wiki/w/文件:Avg_pic_rogue_2_3.png |
| 13 | watcher | 最后的观潮者 | 22 | https://prts.wiki/w/文件:Avg_pic_rogue_2_22.png |
| 14 | legacy | 大海的遗产 | 43 | https://prts.wiki/w/文件:Avg_pic_rogue_2_43.png |
| 15 | survive | 为了生存 | 11 | https://prts.wiki/w/文件:Avg_pic_rogue_2_11.png |
| 16 | tinder | 引火之木 | 34 | https://prts.wiki/w/文件:Avg_pic_rogue_2_34.png |
| 17 | inherit | 继承 | 1 | https://prts.wiki/w/文件:Avg_pic_rogue_2_1.png |
| 18 | meeting | 相逢 | 8 | https://prts.wiki/w/文件:Avg_pic_rogue_2_8.png |

17、18 两张原图画面与事件内容不完全对应（docs/156 §1），放最后；开工前如有疑问先问用户。

## 4. 交付

- 目录：`art/incoming/event_cg_1026/`（分支 `codex/event-cg`）。
- 文件：`<事件 id>.png`（140×125 原尺寸）、`<事件 id>_x4.png`（预览）、`<事件 id>_compare.png`（三列：原图按取景裁切缩小 / 交付原尺寸 ×4 / 交付 ×8 局部，**对照图只放 build/ 或本地，不提交原图像素**）。
- 每批附 `handoff.md`：张数、每张色数、自检记录、未验证项。
- P1 七张一批交，过了再做 P2 / P3。

## 5. 验收（本项目侧，按顺序，前一层不过不进下一层）

1. **人眼**：原尺寸与 ×4 下主体一眼可读；色块成面、轮廓连续、无散点噪；角色配色与 PRTS 立绘一致。
2. **对照原图构图**：取景、主体位置、主要光源与配色与原图一致，主体在上方 60% 内，四周 8 像素无关键内容。
3. **游戏内截图**：接入后用 `--eventtest=<事件 id>` 截电脑与手机（`--touch`）两张，看事件名 / 剧情文字压在下部时是否清楚、撕纸边裁切后主体完整。

通过后由界面会话接入（`choice_panel.draw_event_bg` 读 `event_cg/<事件 id>`），报分支与提交号给协调人合入。
