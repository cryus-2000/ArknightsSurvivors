# 组 E：藏品节奏补偿（big_extra=2 chest_extra=1 chest_rare=1 wish_rare=3）

commit 1cc8376c（origin/claude/relic-pacing-ac58a0），--preset starts（7 编队）× seed 1–8，--bot expert，--tier=0 --tide=0，单份实现；每档 56 局。

| 档 | 局数 | 胜局 | 胜率（Wilson 95%） | 均存活秒 | 每局藏品数 全部 / 胜局 | 首件藏品秒（中位） | script_errors 局数 |
|---|---|---|---|---|---|---|---|
| m0（--tier=0 --tide=0） | 56 | 12 | 21.4%（12.7–33.8%） | 435 | 5.57 / 10.83 | 121（51 局有藏品） | 0 |
| m18（+ --meta=18） | 56 | 15 | 26.8%（17.0–39.6%） | 542 | 7.39 / 11.80 | 115（54 局有藏品） | 0 |

藏品数 = data.relic_take 条数；首件藏品秒 = relic_take 第一条的时间，只计拿过藏品的局。原始数据在 build/cloud_relic/raw/。
