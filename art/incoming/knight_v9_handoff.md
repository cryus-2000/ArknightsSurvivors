# 二结局「最后的骑士」美术接入（V9）

本批新增最后的骑士与罗辛南特的游戏命名资产：7 张 PNG，26 帧。`e_knight.png` 直接复用此前确认的 `bosses/boss_last_knight_mounted_idle.png`，其余动画以同一骑乘造型为参考绘制。横向等宽帧条、朝右、透明背景、二值 alpha；游戏内 2× 最近邻采样。逐文件尺寸、速度、循环方式、锚点、SHA-256 见 `knight_v9_manifest.json`。

| 文件 | 单帧×帧数 | 用途 |
|---|---:|---|
| `e_knight.png` | 96×80 ×2 | 骑乘待机，3 fps 循环 |
| `e_knight_move.png` | 96×80 ×4 | 罗辛南特奔跑，8 fps 循环 |
| `e_knight_attack.png` | 96×80 ×4 | 长枪蓄力、刺击、收招，10 fps 单次；第 3 帧命中 |
| `e_knight_charge.png` | 96×80 ×4 | 压低身位、冲刺、横向突进、制动，10 fps 单次；第 3 帧主冲锋段 |
| `e_knight_death.png` | 96×80 ×4 | 倒地、崩散，6 fps 单次；最终阶段死亡时使用 |
| `fx_knight_rebirth.png` | 80×80 ×4 | 寒冰重生环，10 fps 单次；中心锚点 `(40,40)` |
| `fx_knight_impact.png` | 48×48 ×4 | 枪尖冰霜命中，12 fps 单次；中心锚点 `(24,24)` |

本体帧锚点 `(48,77)`，朝左时水平镜像；不要把整张 96×80 图当作碰撞盒。冲锋和刺击均以第 3 帧（从零数为 2）作为结算／特效触发建议，预警、实际位移、伤害、冻结时长和无敌窗口仍由游戏逻辑控制。二阶段重生可复用同一骑乘本体并叠加 `fx_knight_rebirth.png`，避免把此前的步行造型草案错误地当作原作二阶段。原 `bosses/boss_last_knight_idle.png` 保留为未接入的步行草案。

**开发侧待接入**：目前 `game/scripts/data.gd` 的 `ENDINGS` 只有结局一，`ENEMIES` 也没有 `knight`。Claude 需添加二结局选择／触发条件、`knight` Boss 数据、纹理加载和动画状态机，并把以上帧条导入 `game/art/px/`。本提交仅新增美术，不改 `game/`。若二阶段会重生，第一次血量归零播放冰环并恢复指定生命值；最终死亡才播放 `e_knight_death.png`。具体数值与路线条件由开发侧按游戏设定决定。

`knight_v9_preview.png` 供美术审查，不作为运行时资源。制作过程使用内置 imagegen 生成动作原稿，再机械缩放、去背景、量化、描边；没有把原作图集直接放进游戏。原有骑乘待机草案参考见 `docs/07_boss_art_handoff.md`。
