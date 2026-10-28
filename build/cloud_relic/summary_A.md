# relic-pacing A_base（--bal 退回改前值：elite_drop_chance=0.3 / elite_drop_from=0 / mid1_shift=0 / shop/relic_step=0）

starts 7 编队 × seed 1–8，高手机器人（expert），--tier=0 --tide=0，单份实现。

| 档 | 局数 | 胜率（Wilson 95%） | 均存活秒 | 每局藏品数 全部 / 胜局 | 首件藏品秒（中位） | script_errors 局数 |
|---|---|---|---|---|---|---|
| m0 | 56 | 18/56 = 32.1%（21.4–45.2%） | 488 | 9.8 / 17.3 | 80 | 0 |
| m18 | 56 | 29/56 = 51.8%（39.0–64.3%） | 598 | 12.4 / 16.8 | 80 | 1 |

备注：m18 那 1 局 script_errors 是 wisadel seed 7，1 条 `Out of bounds get index '3' (on base: 'Array')`；这局的数据仍计入上表。
