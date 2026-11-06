# 292 界面字重对照：现在 vs 原作式（11-06）

用户 11-06：「这个字体有点丑，查一下明日方舟用的什么字体」，看完调研后说「做对照」。

## 明日方舟用的字体（查证情况）

官方没有公开说明，以下来自社区和设计分析，没拆客户端核实：

- **中文正文：思源黑体（Source Han Sans）。** 一份 UI 分析写：干员名用 Heavy、字间距 −100；档案、技能介绍用 Normal，字间距也收紧。来源：[janniewang UI/UX 分析](https://janniewang.net/wp-content/uploads/2023/09/UIUX-analysis-for-Arknights.pdf)、[知乎 TA 视角分析](https://zhuanlan.zhihu.com/p/570566718)、[机核](https://www.gcores.com/articles/135723)。
- **中文标题：宋体类。** 有的说思源宋体，有的说方正准雅宋。方正是商用字体，要买授权。
- **英文和数字：** [PRTS / B站 wiki 字体列表](https://wiki.biligame.com/arknights/%E5%AD%97%E4%BD%93%E5%88%97%E8%A1%A8) 记了基建用 Bender，集成战略各主题有专属字体（水月与深蓝之树是 AgeFonts）。主界面的英文字体没查到可靠来源。

## 我们现在用的

| 用途 | 字体 |
|---|---|
| 桌面中文 | `ui.ttf` = 思源黑体（Noto Sans CJK SC）**Bold**，所有地方一档 |
| 手机中文 | `ui_phone.ttf` = 思源黑体 Medium + Montserrat 数字（11-05） |
| 英文小标签 / 大数字 | Montserrat |
| 衬线 | `serif.ttf` = 思源宋体（Noto Serif SC），用得少 |

字体和原作是同一族。差别在用法：

- **全部一个字重：** 名字、说明、标签都是 Bold。小号字发糊，层级也拉不开。
- **字间距没收紧。**

## 对照开关 `ui/font_ark`（缺省 0）

设成 1 时：

- 名字和标题用思源黑体 **Heavy（900）**，字距收 1 像素（`UI.name_font`）。
  - 已接上的地方：选卡卡名、商店商品名、属性面板的名字和栏目标题、编队成员名、手机属性面板头部和编队名。
- **桌面**正文换成思源黑体 **Regular（400）**（`settings.gd` 换掉 `ui.ttf` 的字体数据）。
- **手机**正文仍是 `ui_phone` 的 Medium。

字体文件由 `tools/make_ui_weight_fonts.py` 从系统的 Noto Sans SC 可变字重版切出，码位和纵向度量都和 `ui.ttf` 相同，换上后排版不跑位：

- `game/fonts/ui_heavy.ttf`，1.2 MB
- `game/fonts/ui_regular.ttf`，1.2 MB

两个文件的 `.import` 还没生成，合入前要在本机导入一次。如果定下来改为缺省开，网页包会多约 2.4 MB；只做桌面的话，网页可以不带 Regular。

截图：GCP `render-font-1106a`（卡牌）、`render-font-1106b`（属性面板），对照图在 `Claude outputs/font_1106/`，已发给用户。

## 要用户定的

1. 用不用原作式。
2. 用的话，范围是只改名字、标题（Heavy），还是正文也换 Regular。
3. 中文字间距要不要再收紧，原作是 −100，约 −10%。
