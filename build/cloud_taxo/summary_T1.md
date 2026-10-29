# T1 整局对照：藏品分类统一（docs/197）改后

提交 9def8728025363e3ce5e695c4c089551df22f224（origin/claude/relic-taxonomy）；preset starts（7 编队）× seed 1–8，高手机器人（expert），单份实现；原始数据 build/cloud_taxo/raw/T1_*。

| 档 | 参数 | 局数 | 胜率（Wilson 95%） | 均存活秒 | 每局藏品数（全部） | 每局藏品数（胜局） | script_errors 局数 |
|---|---|---|---|---|---|---|---|
| m0 | `--tier=0 --tide=0` | 56 | 8/56 = 14.3% [7.4%, 25.7%] | 429.7 | 5.84 | 12.00 | 0 |
| m18 | `--tier=0 --tide=0 --meta=18` | 56 | 12/56 = 21.4% [12.7%, 33.8%] | 549.2 | 8.34 | 13.50 | 0 |

藏品数 = data.relic_take 条数。
