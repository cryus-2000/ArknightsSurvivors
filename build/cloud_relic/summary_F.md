# 藏品节奏补偿第二轮 · 组 F（2026-10-28）

基线 1cc8376c（origin/claude/relic-pacing-ac58a0），高手机器人，preset starts（7 编队）× seed 1–8，每档 56 局。
共同覆盖：`--bal=shop/relic_step=0.5 --bal=relic/big_extra=1 --bal=relic/chest_rare=1 --bal=relic/wish_rare=2`（已单独核对 Bal.v 读到 0.5 / 1 / 1 / 2，不带时为 1 / 0 / 0 / 0）。
档：m0 = `--tier=0 --tide=0`；m18 = `--tier=0 --tide=0 --meta=18`。

| 档 | 局数 | 胜率（Wilson 95%） | 均存活秒 | 每局藏品数（全部 / 胜局） | 首件藏品秒（中位） | script_errors 局数 |
|---|---|---|---|---|---|---|
| m0 | 56 | 7/56 = 12.5% [6.2%, 23.6%] | 386 | 5.48 / 13.43 | 121（51 局有藏品） | 0 |
| m18 | 56 | 22/56 = 39.3% [27.6%, 52.4%] | 565 | 8.16 / 11.73 | 115（54 局有藏品） | 0 |

原始数据：build/cloud_relic/raw/F_<档>_s<seed0>_*.json（每份 2 个 seed × 7 编队）。藏品数 = data.relic_take 条数；首件 = relic_take 最早时间。
