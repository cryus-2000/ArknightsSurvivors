# 藏品节奏补偿第二轮 · 组 G（高手机器人，starts 7 编队 × seed 1–8，单份实现）

旋钮：`--bal=relic/elite_drop_chance=0.2 --bal=shop/relic_step=0.5 --bal=relic/big_extra=1 --bal=relic/chest_rare=1 --bal=relic/wish_rare=2`；分支 1cc8376c（origin/claude/relic-pacing-ac58a0）。覆盖已在引擎内核对生效。

| 档 | 局数 | 胜率（Wilson 95%） | 均存活秒 | 每局藏品数 全部 / 胜局 | 首件藏品秒（中位） | script_errors 局数 |
|---|---|---|---|---|---|---|
| m0（--tier=0 --tide=0） | 56 | 10/56 = 18%（10–30%） | 394 | 5.91 / 14.30 | 121（5 局无藏品） | 0 |
| m18（--tier=0 --tide=0 --meta=18） | 56 | 21/56 = 38%（26–51%） | 560 | 8.64 / 12.86 | 115（2 局无藏品） | 0 |

原始数据：build/cloud_relic/raw/G_*.json / .md
