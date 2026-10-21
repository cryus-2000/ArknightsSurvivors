# 115 · Boss 登场名片头像 — 现状、候选与候选 A 实现（2026-10-21）

> 背景：用户反馈 Boss 登场名片上的头像还是「旧画像」，要求查清楚现状并出两个候选方案；用户选 A，已在
> `claude/boss-portrait` 分支实现（提交见 git log，分支不合 main）。

## 1. 现状（10-21 更正）

**更正**：本文档最初调查时漏看了一层目录，误以为 `art/incoming/portraits/` 一张图都没有。实际上 **10 只 Boss 都有一版
10-11 交付的专画头像**（`art/incoming/portraits/boss_<id>.png` 88×88 + `@2x`，`scripts/screens/boss_intro.gd` 正常
加载、`card.portrait.begins_with("portraits/")` 命中，走的是「整张头像」分支，不是缺图回退）。

真正的问题不是「没有头像」，是**这版头像画得太简），基本就是一块深色半身剪影 + 一对发光的眼睛（见
`build/boss_portrait_shots/knight_portrait_check.png`，未入库），辨识度低，用户说的「旧画像」指的是它。

10 只 Boss 当前头像来源：

| Boss id | 名字 | 专画头像文件 | 观感 |
|---|---|---|---|
| path | 塑路者 | `portraits/boss_path.png` | 深色半身剪影 |
| iberia | 圣徒伊比利亚 | `portraits/boss_iberia.png` | 勉强能看（半身正面） |
| carmen | 圣徒卡门 | `portraits/boss_carmen.png` | 勉强能看（同上） |
| bishop | 接潮主教 | `portraits/boss_bishop.png` | 深色半身剪影 |
| archon | 接潮蔑死体 | `portraits/boss_archon.png` | 深色半身剪影 |
| immortal | 接潮斥亡体 | `portraits/boss_immortal.png` | 深色半身剪影 |
| paranoia | "偏执泡影" | `portraits/boss_paranoia.png` | 深色半身剪影 |
| ishar | 伊莎玛拉，腐化之心 | `portraits/boss_ishar.png` | 深色半身剪影 |
| izumik | 伊祖米克，生态泉源 | `portraits/boss_izumik.png` | 深色半身剪影 |
| knight_boss | 最后的骑士 | `portraits/boss_knight_boss.png` | 深色半身剪影 |

## 2. 两个候选（已报用户，用户选 A）

**候选 A · 局内像素本体裁切放大（低成本，不需要新画，已实现）**
不用这版专画头像，改成从战斗帧条（`e.tex` idle 第 0 帧）裁一块头部 / 标志特征的小方块，逐只手动对齐，按整数倍最近邻放大。
优点：今天就能做、不占 Codex 产能，细节比专画头像的全身缩小版多；缺点：终究是战斗姿态裁出来的，不是专门构图的头像。

**候选 B · 按原作立绘口径重新画（需要新素材，暂不做）**
参照 PRTS 对应海嗣 / 敌人的官方立绘或原设定，重新画一版 88×88（+@2x）头肩像，按 docs/104 走「Claude 写单、Codex 交素材」。
10-21 用户定：先不做，A 够用了再说。

## 3. 候选 A 实现记录（10-21，`claude/boss-portrait`）

**改法**：`scripts/screens/boss_intro.gd`
- `PORTRAIT_CROP`：新增 const，10 只 Boss 各一个 `Rect2(x, y, w, h)`，坐标是 idle 帧条第 0 帧（帧条左半张）的 1x 像素坐标，
  逐只对着 `art/incoming/e_<name>.png` 肉眼挑的头部 / 标志特征（骑士头盔 + 寒冷目镜、偏执泡影的红瞳、主教兜帽双眼……）。
- `card_for()`：`PORTRAIT_CROP` 里登记过的 Boss 不再读 `CARDS.portrait`（10-11 那版专画头像暂时弃用，文件不删，留给以后候选
  B 用），改调 `_portrait_source()` 走裁切逻辑。
- `_portrait_tex_1x_key()`：**绕开 @2x**，强制直接读 1x 原图。原因：10-21 排查发现 `e_knight@2x.png` 实际尺寸
  586×293，不是 `e_knight.png`（192×80）干净的 2 倍——`A.tex()` 按文件名优先取 `@2x`、再按固定密度 2.0 换算绘制坐标，
  PORTRAIT_CROP 的裁切框会在错的区域取样（最先这样实现时骑士那张整个糊掉，debug 截图对照才查出来）。
  这个 @2x 尺寸异常本身是另一个美术资产问题，不在本次范围内，没有改 `art/incoming` 下的文件，只是头像裁切这条路径
  不碰它、改读 1x 原图；战斗时的本体绘制不受影响（那条路径走的是另一套密度换算，没有这个 bug 的症状——实机骑士本体
  比例看着是对的，只有我这版新写的裁切代码直接信了 hires_of() 才会取错）。
- `draw_texture_rect_region` 的最近邻：项目 `textures/canvas_textures/default_texture_filter` 本来就是 0（Nearest），
  不用额外设置。

**验证**：`--bossintro=<id>`（10 只逐一跑）+ `--fixed-fps 30` 截图对照，`build/boss_portrait_shots/final_grid.png`
（未入库，已发用户）；`tools/check.py --auto` 本分支改动范围内跑结果见 commit message。只改名片取图/显示，不碰战斗绘制、
不进模拟字段，同 seed 不变。

## 4. 待办

- 10-11 那版专画头像文件（`art/incoming/portraits/boss_*.png`）暂时没人用了，先留着（代码架构支持以后候选 B 直接复用这个
  路径，`portrait` 字段指回 `portraits/boss_<id>` 即可）。
- ~~`e_knight@2x.png` 尺寸异常~~：10-22 已修（codex/art c9f5963a，分支 `claude/knight-strips-fix`）——骑乘 9 条补边到 294、1x 换成 147 的最近邻配对，
  步行 5 条补边到 398（只交 @2x）；1x 换图后骑士裁切框按新图重量为 `Rect2(52, 40, 56, 56)`（骑手 + 坐骑头部）。
  `_portrait_tex_1x_key()` 仍保留：其余 9 只的裁切框都是按各自 1x 量的，改走 @2x 要全部重量，收益不大。
