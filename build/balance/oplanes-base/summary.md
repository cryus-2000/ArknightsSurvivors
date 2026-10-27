# 干员流派矩阵 · base（docs/179 §6 第 5 条）

代码 = origin/main d88b56b56；每格 --seeds 4，机器人 expert / normal；Godot --headless --audio-driver Dummy。
列：胜率 / 平均存活 / Boss2 用时中位（击杀/出场，7:00 前后出场的中期 Boss）/ 8:00 后承伤（每分钟，只算活过 8:00 的局）/ 本流派藏品件数（按 id 去重）/ 主控（开局干员）伤害占比。

## multi — exusiai,wisadel,eyjafjalla · 流派 E（远程·火力）

| 机器人 | 局数 | 胜率 | 均存活 | Boss2 用时中位 | 8:00 后承伤 | 本流派藏品 | 主控伤害占比 |
|---|---|---|---|---|---|---|---|
| expert | 4 | 25% | 8:46 | 25s（3/5） | 242/分 | 1.5 | 26% |
| normal | 4 | 0% | 4:40 | -（0/1） | - | 0.5 | 42% |

## melee — lappland,skadi,irene · 流派 A（前锋·近战）

| 机器人 | 局数 | 胜率 | 均存活 | Boss2 用时中位 | 8:00 后承伤 | 本流派藏品 | 主控伤害占比 |
|---|---|---|---|---|---|---|---|
| expert | 4 | 50% | 11:18 | 79s（7/8） | 148/分 | 1.5 | 15% |
| normal | 4 | 0% | 4:46 | -（0/0） | - | 1.0 | 28% |

## summon — wisadel,mizuki,kaltsit · 流派 B（追击·召唤）

| 机器人 | 局数 | 胜率 | 均存活 | Boss2 用时中位 | 8:00 后承伤 | 本流派藏品 | 主控伤害占比 |
|---|---|---|---|---|---|---|---|
| expert | 4 | 50% | 10:50 | 29s（5/5） | 74/分 | 0.5 | 67% |
| normal | 4 | 0% | 6:40 | 31s（1/2） | - | 0.5 | 72% |

## control — angelina,gladiia,texas · 流派 C（控制·技能循环）

| 机器人 | 局数 | 胜率 | 均存活 | Boss2 用时中位 | 8:00 后承伤 | 本流派藏品 | 主控伤害占比 |
|---|---|---|---|---|---|---|---|
| expert | 4 | 25% | 12:40 | 132s（6/7） | 70/分 | 4.5 | 27% |
| normal | 4 | 0% | 3:14 | -（0/0） | - | 1.0 | 35% |

## weak — logos,mizuki,exusiai · 流派 D（收割·弱点）

| 机器人 | 局数 | 胜率 | 均存活 | Boss2 用时中位 | 8:00 后承伤 | 本流派藏品 | 主控伤害占比 |
|---|---|---|---|---|---|---|---|
| expert | 4 | 75% | 10:24 | 43s（7/7） | 139/分 | 1.5 | 56% |
| normal | 4 | 0% | 5:51 | -（0/1） | - | 0.0 | 44% |

## guard — hoshiguma,saria,lumen · 流派 H（守护·续航）

| 机器人 | 局数 | 胜率 | 均存活 | Boss2 用时中位 | 8:00 后承伤 | 本流派藏品 | 主控伤害占比 |
|---|---|---|---|---|---|---|---|
| expert | 4 | 0% | 13:00 | -（0/7） | 75/分 | 2.0 | 48% |
| normal | 4 | 0% | 13:00 | 96s（1/6） | 197/分 | 1.8 | 64% |

## none — lappland,exusiai,angelina · 流派 none（不偏好）

| 机器人 | 局数 | 胜率 | 均存活 | Boss2 用时中位 | 8:00 后承伤 | 本流派藏品 | 主控伤害占比 |
|---|---|---|---|---|---|---|---|
| expert | 4 | 75% | 10:25 | 38s（4/4） | 96/分 | - | 31% |
| normal | 4 | 0% | 4:58 | -（0/0） | - | - | 28% |

## mismatch — lappland,skadi,irene · 流派 E（远程·火力）

| 机器人 | 局数 | 胜率 | 均存活 | Boss2 用时中位 | 8:00 后承伤 | 本流派藏品 | 主控伤害占比 |
|---|---|---|---|---|---|---|---|
| expert | 4 | 50% | 11:21 | 137s（5/8） | 97/分 | 0.5 | 17% |
| normal | 4 | 0% | 5:25 | -（0/1） | - | 1.0 | 29% |

## 8 行总表

| 行 | 编队 | 流派 | 机器人 | 局数 | 胜率 | 均存活 | Boss2 用时中位 | 8:00 后承伤 | 本流派藏品 | 主控伤害占比 |
|---|---|---|---|---|---|---|---|---|---|---|
| multi | exusiai,wisadel,eyjafjalla | E | expert | 4 | 25% | 8:46 | 25s（3/5） | 242/分 | 1.5 | 26% |
| multi | exusiai,wisadel,eyjafjalla | E | normal | 4 | 0% | 4:40 | -（0/1） | - | 0.5 | 42% |
| melee | lappland,skadi,irene | A | expert | 4 | 50% | 11:18 | 79s（7/8） | 148/分 | 1.5 | 15% |
| melee | lappland,skadi,irene | A | normal | 4 | 0% | 4:46 | -（0/0） | - | 1.0 | 28% |
| summon | wisadel,mizuki,kaltsit | B | expert | 4 | 50% | 10:50 | 29s（5/5） | 74/分 | 0.5 | 67% |
| summon | wisadel,mizuki,kaltsit | B | normal | 4 | 0% | 6:40 | 31s（1/2） | - | 0.5 | 72% |
| control | angelina,gladiia,texas | C | expert | 4 | 25% | 12:40 | 132s（6/7） | 70/分 | 4.5 | 27% |
| control | angelina,gladiia,texas | C | normal | 4 | 0% | 3:14 | -（0/0） | - | 1.0 | 35% |
| weak | logos,mizuki,exusiai | D | expert | 4 | 75% | 10:24 | 43s（7/7） | 139/分 | 1.5 | 56% |
| weak | logos,mizuki,exusiai | D | normal | 4 | 0% | 5:51 | -（0/1） | - | 0.0 | 44% |
| guard | hoshiguma,saria,lumen | H | expert | 4 | 0% | 13:00 | -（0/7） | 75/分 | 2.0 | 48% |
| guard | hoshiguma,saria,lumen | H | normal | 4 | 0% | 13:00 | 96s（1/6） | 197/分 | 1.8 | 64% |
| none | lappland,exusiai,angelina | none | expert | 4 | 75% | 10:25 | 38s（4/4） | 96/分 | - | 31% |
| none | lappland,exusiai,angelina | none | normal | 4 | 0% | 4:58 | -（0/0） | - | - | 28% |
| mismatch | lappland,skadi,irene | E | expert | 4 | 50% | 11:21 | 137s（5/8） | 97/分 | 0.5 | 17% |
| mismatch | lappland,skadi,irene | E | normal | 4 | 0% | 5:25 | -（0/1） | - | 1.0 | 29% |

## script_errors

全部 64 局 script_errors = 0。
