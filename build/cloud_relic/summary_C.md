# 藏品节奏组 C_strong（elite_drop_chance=0.1，shop/relic_step=1.5）

commit 876a973（origin/claude/relic-pacing-ac58a0）；--preset starts（7 编队）× seed 1–8，expert 机器人，--tier=0 --tide=0，单份实现。--bal 覆盖已核对生效（Bal.v 读回 0.1 / 1.5，缺省是 0.15 / 1.0）。

| 档 | 局数 | 胜率（Wilson 95%） | 均存活秒 | 每局藏品数 全部 / 胜局 | 首件藏品秒（中位） | script_errors 局数 |
|---|---|---|---|---|---|---|
| m0（--tier=0 --tide=0） | 56 | 3/56 = 5.4%（1.8–14.6%） | 396 | 4.59 / 10.67 | 121（5 局未拿藏品） | 0 |
| m18（+ --meta=18） | 56 | 16/56 = 28.6%（18.4–41.5%） | 543 | 6.93 / 10.25 | 115（2 局未拿藏品） | 0 |

原始数据：build/cloud_relic/raw/C_<档>_s<1|5>_*.json / .md。
