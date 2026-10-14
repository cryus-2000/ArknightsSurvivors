# 钵海收割者受击狂奔返修（2026-10-14）

参考用户提供的原作战斗截图：白色扇状头部、蓝色中心眼、贴地的深蓝身体，以及**一对**深蓝弯镰。受击后只有这对镰肢，不增加第二对。攻击 f1 双镰高举，f2 向前下方劈落，f3 与待机 f0 逐像素一致；苏醒 f3 同样对齐待机 f0。

行为：靠近仍会唤醒，但只有受伤才进入狂奔状态（速度 ×1.45，苏醒展开 0.4 秒）；狂奔时半径 90 的冷蓝波纹积累现有神经损伤，沿用神经爆发后的免疫窗口，不额外叠一套控制。劈砍沿用现有锥形预警、命中与冷却，预警名改为“镰肢劈砍”。苏醒期间不造成接触伤害。

文件：`e_reaper`、`e_reaper_dormant`、`e_reaper_awaken`、`e_reaper_move`、`e_reaper_attack`，每条均有 1x 与 `@2x`。1x 每帧 40×38，@2x 每帧 80×76，脚底 y=37/75；移动 4 帧，攻击 4 帧、f2 命中。全部动作共用 15 个不透明色，透明为二值，朝右。`reaper_preview.gif`、`reaper_lineup.png` 和 `reaper_qa.json` 用于核对。生成草稿仅用于造型参考，导出时按项目尺寸、共用色板和透明度重新整理。

程序接入：`game/data/enemies.json`、`game/scripts/enemies/enemy_ai.gd`、`game/scripts/run/enemies.gd`、`game/scripts/render/world.gd`；测试 `game/tests/reaper_rush_test.tscn`。图鉴从同一敌人数据与实时战斗动作读取，描述已更新。

验证：Godot 4.7.2 无界面运行 `reaper_rush_test.tscn` 输出 `PASS: reaper rush`；图像 QA 10/10 帧条尺寸与二值透明合格，动作总色数 1x/@2x 各 15，待机与收势/苏醒末帧逐像素相同。亮暗并排预览已人工检查，冷蓝镰刀在暗底可辨。
