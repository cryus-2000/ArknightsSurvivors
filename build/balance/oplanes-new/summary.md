# 干员流派矩阵 oplanes-new（代码 5e13af457）

每行 4 seed × expert/normal，--lanes 为该行流派偏好。主控 = 编队首位开局干员。8:00 后承伤 = 机器人曲线 t>480 的 30 秒窗口折算每分钟（未活到 8:00 记 -）。本流派藏品件数 = 终局时按 id 去重。

## multi  `exusiai,wisadel,eyjafjalla`  --lanes E

| 机器人 | 局数 | 胜率 | 均存活 | Boss2 用时中位（击杀/出场） | 8:00 后承伤/分 | 本流派藏品 | 主控伤害占比 |
|---|---|---|---|---|---|---|---|
| expert | 4 | 25% | 7:58 | 38s（2/2） | 158（1 局） | 0.5 | 28% |
| normal | 4 | 0% | 4:48 | -（0/0） | - | 0.8 | 33% |

## melee  `lappland,skadi,irene`  --lanes A

| 机器人 | 局数 | 胜率 | 均存活 | Boss2 用时中位（击杀/出场） | 8:00 后承伤/分 | 本流派藏品 | 主控伤害占比 |
|---|---|---|---|---|---|---|---|
| expert | 4 | 0% | 7:01 | 41s（2/2） | - | 2.8 | 21% |
| normal | 4 | 0% | 5:26 | -（0/0） | - | 0.0 | 26% |

## summon  `wisadel,mizuki,kaltsit`  --lanes B

| 机器人 | 局数 | 胜率 | 均存活 | Boss2 用时中位（击杀/出场） | 8:00 后承伤/分 | 本流派藏品 | 主控伤害占比 |
|---|---|---|---|---|---|---|---|
| expert | 4 | 100% | 12:20 | 40s（7/7） | 124（4 局） | 1.2 | 31% |
| normal | 4 | 0% | 5:08 | -（0/0） | - | 0.2 | 69% |

## control  `angelina,gladiia,texas`  --lanes C

| 机器人 | 局数 | 胜率 | 均存活 | Boss2 用时中位（击杀/出场） | 8:00 后承伤/分 | 本流派藏品 | 主控伤害占比 |
|---|---|---|---|---|---|---|---|
| expert | 4 | 0% | 9:36 | 70s（3/3） | 83（2 局） | 3.2 | 27% |
| normal | 4 | 0% | 5:53 | -（0/2） | - | 1.0 | 32% |

## weak  `logos,mizuki,exusiai`  --lanes D

| 机器人 | 局数 | 胜率 | 均存活 | Boss2 用时中位（击杀/出场） | 8:00 后承伤/分 | 本流派藏品 | 主控伤害占比 |
|---|---|---|---|---|---|---|---|
| expert | 4 | 50% | 8:41 | 36s（4/6） | 280（2 局） | 0.5 | 57% |
| normal | 4 | 0% | 4:50 | -（0/0） | - | 0.5 | 54% |

## guard  `hoshiguma,saria,lumen`  --lanes H

| 机器人 | 局数 | 胜率 | 均存活 | Boss2 用时中位（击杀/出场） | 8:00 后承伤/分 | 本流派藏品 | 主控伤害占比 |
|---|---|---|---|---|---|---|---|
| expert | 4 | 0% | 13:00 | 105s（2/5） | 105（4 局） | 2.0 | 36% |
| normal | 4 | 0% | 7:36 | 96s（1/4） | 201（2 局） | 0.2 | 51% |

## none  `lappland,exusiai,angelina`  --lanes none

| 机器人 | 局数 | 胜率 | 均存活 | Boss2 用时中位（击杀/出场） | 8:00 后承伤/分 | 本流派藏品 | 主控伤害占比 |
|---|---|---|---|---|---|---|---|
| expert | 4 | 0% | 8:27 | 83s（2/4） | 112（2 局） | - | 26% |
| normal | 4 | 0% | 4:35 | -（0/0） | - | - | 34% |

## mismatch  `lappland,skadi,irene`  --lanes E

| 机器人 | 局数 | 胜率 | 均存活 | Boss2 用时中位（击杀/出场） | 8:00 后承伤/分 | 本流派藏品 | 主控伤害占比 |
|---|---|---|---|---|---|---|---|
| expert | 4 | 50% | 9:57 | 47s（4/4） | 199（3 局） | 0.5 | 18% |
| normal | 4 | 0% | 5:13 | -（0/0） | - | 0.5 | 27% |

## 8 行总表

| 行 | 编队 | 流派 | 机器人 | 局数 | 胜率 | 均存活 | Boss2 用时中位（击杀/出场） | 8:00 后承伤/分 | 本流派藏品 | 主控伤害占比 |
|---|---|---|---|---|---|---|---|---|---|---|
| multi | exusiai,wisadel,eyjafjalla | E | expert | 4 | 25% | 7:58 | 38s（2/2） | 158（1 局） | 0.5 | 28% |
| multi | exusiai,wisadel,eyjafjalla | E | normal | 4 | 0% | 4:48 | -（0/0） | - | 0.8 | 33% |
| melee | lappland,skadi,irene | A | expert | 4 | 0% | 7:01 | 41s（2/2） | - | 2.8 | 21% |
| melee | lappland,skadi,irene | A | normal | 4 | 0% | 5:26 | -（0/0） | - | 0.0 | 26% |
| summon | wisadel,mizuki,kaltsit | B | expert | 4 | 100% | 12:20 | 40s（7/7） | 124（4 局） | 1.2 | 31% |
| summon | wisadel,mizuki,kaltsit | B | normal | 4 | 0% | 5:08 | -（0/0） | - | 0.2 | 69% |
| control | angelina,gladiia,texas | C | expert | 4 | 0% | 9:36 | 70s（3/3） | 83（2 局） | 3.2 | 27% |
| control | angelina,gladiia,texas | C | normal | 4 | 0% | 5:53 | -（0/2） | - | 1.0 | 32% |
| weak | logos,mizuki,exusiai | D | expert | 4 | 50% | 8:41 | 36s（4/6） | 280（2 局） | 0.5 | 57% |
| weak | logos,mizuki,exusiai | D | normal | 4 | 0% | 4:50 | -（0/0） | - | 0.5 | 54% |
| guard | hoshiguma,saria,lumen | H | expert | 4 | 0% | 13:00 | 105s（2/5） | 105（4 局） | 2.0 | 36% |
| guard | hoshiguma,saria,lumen | H | normal | 4 | 0% | 7:36 | 96s（1/4） | 201（2 局） | 0.2 | 51% |
| none | lappland,exusiai,angelina | none | expert | 4 | 0% | 8:27 | 83s（2/4） | 112（2 局） | - | 26% |
| none | lappland,exusiai,angelina | none | normal | 4 | 0% | 4:35 | -（0/0） | - | - | 34% |
| mismatch | lappland,skadi,irene | E | expert | 4 | 50% | 9:57 | 47s（4/4） | 199（3 局） | 0.5 | 18% |
| mismatch | lappland,skadi,irene | E | normal | 4 | 0% | 5:13 | -（0/0） | - | 0.5 | 27% |

## script_errors

全部 64 局 script_errors = 0。

## 备注

- guard expert 4 局全部 13:00 超时未通关（终 Boss 平均剩余 63%），均存活 13:00 不代表通关；Boss1 用时中位 300s（3/4 击杀），Boss2 仅 2/5 击杀。
- summon expert 4/4 通关，是 8 行中唯一 expert 胜率 ≥ 50% 且稳定的组合；normal 全部行 0% 胜率。
- 各行原始报告见同目录 `<tag>_1027_*.md / .json`，运行日志 `<tag>.log`。
