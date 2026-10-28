# relic-pacing-D 整局对照（组 D）

- 基于 1cc8376c（origin/claude/relic-pacing-ac58a0），只测不改代码
- 共同参数：`--preset starts --bot expert`，seed 1–8，7 个开局编队，单份实现；`--bal=relic/big_extra=1 --bal=relic/chest_rare=1 --bal=relic/wish_rare=2`
- 覆盖生效核对：seed 1 抽查，Boss / 精英小队宝箱 relic_offer 为 4 选项、事件宝箱 3 选项（big_extra=1 生效）
- 每局藏品数 = data.relic_take 条数（含 relicfx 衍生条目）；首件藏品秒 = relic_take 第一条的时间

| 档 | 局数 | 胜率（Wilson 95%） | 均存活秒 | 每局藏品数（全部 / 胜局） | 首件藏品秒（中位） | script_errors 局数 |
|---|---|---|---|---|---|---|
| m0 (`--tier=0 --tide=0`) | 56 | 9/56 = 16.1% [8.7%, 27.8%] | 401 | 5.43 / 11.89 | 121 | 0 |
| m18 (`--tier=0 --tide=0 --meta=18`) | 56 | 19/56 = 33.9% [22.9%, 47.0%] | 560 | 8.00 / 11.32 | 115 | 0 |

原始数据：build/cloud_relic/raw/D_<档>_s<seed0>_*.{json,md}
