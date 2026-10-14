# docs/97 B · 水月技能

新交 player_skill（1x / @2x）：48×48、8 帧、12fps、出手 f3；蓄力→举伞→出手→保持→收回；首末帧引用本批 idle f0。四瓣帽徽、束发、宽松裤型、全黑袜和直向倒刺伞尖列入 op_fix_character_constraints.md。

既有 idle / run / attack_48 同步统一色板与描边，保留帧数和 fps；idle 整体左移 2 个逻辑像素调整脚底，不单独移动头部。每人这四组动作共享 ≤24 色。白色加入中间调，亮部降低至约 27%，HSL 0.483。

新技能由内置 imagegen 根据既有已确认 idle / attack 绘制；两次局部修正四瓣帽徽及伞尖倒刺。源文件路径和哈希记录 manifest。后期仅切帧、尺寸 / 脚底注册、共用色板量化、二值透明、闭合描边及严格首末帧匹配。举伞最高帧缩放适配画布，防止伞尖裁切。

## QA
指定命令 `python tools/art_lint.py --ops mizuki --no-images`，未豁免 FAIL = 0。当前 roster 没有新技能，另用同一 lint_op 加入 player_skill 的完整配置检查；独立结果 op_fix_b_skill_qa.json，未豁免 FAIL = 0、skill_end PASS。不得把默认报告中技能项的空白理解为已检查。

剩余明度 WARN：受光变亮约 18%，高于当前脚本上限 12%；docs/97 给出的最低目标是 ≥5%。未改工具阈值，报告保留真实 WARN。近黑比例约25%，亮部27%，颜色、透明度、两圈描边均通过。

## 接入与预览
只交素材，不改 game/。Claude 需把 player_skill 注册为 8帧12fps、fire3、foot[24,46]，否则游戏仍复用攻击。manifest 含 SHA256 / 尺寸 / 帧数 / fps。
preview.gif 是素材时间轴预览，非游戏实装；lineup 包含斯卡蒂、浊心斯卡蒂和流明参照的亮暗两行。
