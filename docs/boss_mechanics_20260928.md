# Boss 机制与特效交接（2026-09-28）

本轮在现有 Boss AI 中加入三种可辨认的攻击节奏，沿用现有预警、伤害和绘制管线；特效由 `render/world.gd` 绘制，并复用现有的冰击与水花贴图。

| Boss | 新机制 | 可见反馈 |
| --- | --- | --- |
| 最后的骑士 | 先标出冰线，短暂延迟后沿冰线冲锋追击；冰线命中附带寒冷 | 锯齿冰脊、冰屑、冲锋预警与冰击 |
| 接潮主教组合 | 一方假死时，另一方沿生命连接周期反击；双方同时假死仍按原规则倒下 | 双层弯曲潮线、逆流光点和命中水花 |
| 伊莎玛拉 | 变身时记录未被压制的之泪；二阶段开场由这些位置同时发射泪滴共鸣。已压制的之泪不参与 | 变身连线、同步预警、潮线与水花 |

图鉴文字已同步。测试入口：`启动测试版.cmd` → Boss 演练；图鉴的对应 Boss 条目可查看攻击说明与演示。自动检查：`python tools/check.py --only boss_variety`；完整检查：`python tools/check.py --jobs 4`。预览截图由 `game/tests/boss_variety_test.gd --capture-ui` 生成到 `build/ea_knight_frost_hunt.png`、`build/ea_bishop_life_link.png`、`build/ea_ishar_tear_echo.png`，`build/` 仅供本机检查，不随源码提交。
