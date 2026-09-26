# Boss 重做 P1：最后的骑士 / 伊莎玛拉动画美术交接

依据：`docs/38_boss_redesign.md` §6、`docs/06_git_collaboration.md`。仅交付 `art/incoming/` 的 Boss 人物帧条及本说明、清单与预览；没有修改游戏代码。

| 文件前缀 | 单帧尺寸 | 帧数 | 播放建议 | 动作 |
|---|---:|---:|---|---|
| `e_knight_plant` | 96×80 | 4 | 一次 | 举枪、落枪、枪尖触地、冰墙升起 |
| `e_knight_charge_form` | 96×80 | 4 | 循环 | 骑士压低、枪平举，罗辛南特四相奔跑 |
| `e_ishar_transform` | 80×80 | 6 | 一次 | 人形被白色分节甲壳包覆，卷曲为海嗣，最后两帧不再有人形 |
| `e_ishar_t` | 80×80 | 2 | 循环 | 白壳金棘海嗣悬浮待机，甲壳和棘鳍轻微摆动 |
| `e_ishar_t_move` | 80×80 | 4 | 循环 | 卷曲、伸展、前滑、收回的悬浮移动 |
| `e_ishar_t_attack` | 80×80 | 4 | 一次 | 蓄力、张开青色裂纹、头部前冲、收回 |

每条帧条都有同名 `@2x.png`（每帧宽高翻倍）。图片位于 `art/incoming/` 根目录，横向均分，朝右，透明 RGBA，二值 alpha，底版 2px `#080E18` 外描边，高清版 4px。所有帧在自身画格内，底部对齐且保留透明边距。`e_ishar_t.png` 是待机条名，无 `_idle` 后缀。

伊莎玛拉变身形态按用户提供的实机截图修正：卷曲的白灰色分节甲壳、金色钩状棘鳍、向右下方的尖甲壳头、青色锯齿裂纹。**变身后不是人形**；旧版高冠、双鳍、人形裙摆稿已由本次同名素材替换。未改骑士两条动画。

预览：`art/incoming/boss_p1_knight_preview.png`、`art/incoming/boss_p1_ishar_preview.png`，深蓝背景按 @2x 尺寸展示；`art/incoming/boss_p1_manifest.json` 记录尺寸、帧数与每张 PNG 的 SHA-256；`art/incoming/boss_p1_qa.json` 记录逐帧非透明像素计数。

导出后核验 12 条帧条：确切尺寸、帧数、SHA-256、二值 alpha、无紫色抠底残留及画布边缘透明。目视检查了两张深海背景预览。此交付没有进行游戏内接入或 Godot 播放测试。骑士 `_plant` 的第 4 帧包含冰墙视觉；若代码同时绘制独立 `prop_ice_wall`，请错开显示时机以免叠出两面冰墙。
