# bguide-T0 summary（改前 850c5cad5，master 机器人，starts 7 编队 × seed 1–8）

`--bot master` 由 balance_run.py 直接接受（未走 --extra）。档：m0 = `--tier=0 --tide=0`；m18 = `--tier=0 --tide=0 --meta=18`。

| 档 | 局数 | 胜率 (Wilson 95%) | 平均存活秒 | 藏品数 全部均值 | 藏品数 胜局均值 | script_errors |
|---|---|---|---|---|---|---|
| m0 | 56 | 22/56 = 39.3% [27.6%, 52.4%] | 606.5 | 9.89 | 13.82 | 0 |
| m18 | 56 | 32/56 = 57.1% [44.1%, 69.2%] | 660.7 | 11.77 | 14.00 | 0 |

缺 data 的记录：m0 0，m18 0。存活秒 = data.t（13:00 上限 780 s）；藏品数 = data.relic_take 条数。

## 按编队（胜局数 / 8）

| 编队 | m0 胜 | m0 均存活 | m18 胜 | m18 均存活 |
|---|---|---|---|---|
| eyjafjalla | 1/8 | 396 | 1/8 | 496 |
| kaltsit | 1/8 | 639 | 2/8 | 591 |
| mizuki | 4/8 | 601 | 7/8 | 725 |
| saria | 4/8 | 728 | 5/8 | 747 |
| skadi | 8/8 | 695 | 7/8 | 678 |
| suzuran | 0/8 | 477 | 5/8 | 685 |
| wisadel | 4/8 | 711 | 5/8 | 703 |

逐局数据：build/cloud_bguide/runs_T0.csv；原始报告：build/cloud_bguide/raw/
