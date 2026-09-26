# Boss 重做 P1：最后的骑士 / 伊莎玛拉动画美术交接

依据：`docs/38_boss_redesign.md` §6、`docs/06_git_collaboration.md`。仅交付 `art/incoming/` 的 Boss 人物帧条及本说明、清单与预览；没有修改游戏代码。

| 文件前缀 | 单帧尺寸 | 帧数 | 播放建议 | 动作 |
|---|---:|---:|---|---|
| `e_knight_plant` | 96×80 | 4 | 一次 | 举枪、落枪、枪尖触地、冰墙升起 |
| `e_knight_charge_form` | 96×80 | 4 | 循环 | 骑士压低、枪平举，罗辛南特四相奔跑 |
| `e_ishar_transform` | 80×80 | 6 | 一次 | 从现有本体渐变为高冠、双鳍、海色裙摆的形态 |
| `e_ishar_t` | 80×80 | 2 | 循环 | 变身形态待机 |
| `e_ishar_t_move` | 80×80 | 4 | 循环 | 变身形态漂移 |
| `e_ishar_t_attack` | 80×80 | 4 | 一次 | 蓄势、展开、歌唱光环、消散 |

每条帧条都有同名 `@2x.png`（每帧宽高翻倍）。图片位于 `art/incoming/` 根目录，横向均分，朝右，透明 RGBA，二值 alpha，底版 2px `#080E18` 外描边，高清版 4px。所有帧在自身画格内，底部对齐且保留透明边距。`e_ishar_t.png` 是待机条名，无 `_idle` 后缀。

预览：`art/incoming/boss_p1_knight_preview.png`、`art/incoming/boss_p1_ishar_preview.png`，深蓝背景按 @2x 尺寸展示；`art/incoming/boss_p1_manifest.json` 记录尺寸、帧数与每张 PNG 的 SHA-256；`art/incoming/boss_p1_qa.json` 记录逐帧非透明像素计数。

导出后核验 12 条帧条：确切尺寸、帧数、SHA-256、二值 alpha、无紫色抠底残留及画布边缘透明。目视检查了两张深海背景预览。此交付没有进行游戏内接入或 Godot 播放测试。骑士 `_plant` 的第 4 帧包含冰墙视觉；若代码同时绘制独立 `prop_ice_wall`，请错开显示时机以免叠出两面冰墙。
