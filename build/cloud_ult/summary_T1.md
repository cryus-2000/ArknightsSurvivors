# ult-T1 云端同种子配对结果（docs/198，T1 = 终结技开）

- 提交基线：f21805ed7（origin/claude/ult-proto）
- 设置：preset starts（7 开局）× seed 1–8，expert 机器人，每档按 seed 拆 4 份（seed0 1/3/5/7，seeds 2）
- 胜率区间为 Wilson 95%；ult / cult / combo 为每局 data.ult 对应字段的均值

| 档 | extra | 局数 | 胜率（Wilson 95%） | 均存活秒 | script_errors | ult 均值 | cult 均值 | combo 均值 |
|---|---|---|---|---|---|---|---|---|
| m0 | `--tier=0 --tide=0 --bal=ult/on=1` | 56 | 12/56 = 21.4%（12.7–33.8%） | 472.1 | 0 | 2.39 | 0.07 | 6.73 |
| m18 | `--tier=0 --tide=0 --meta=18 --bal=ult/on=1` | 56 | 20/56 = 35.7%（24.5–48.8%） | 561.9 | 0 | 2.75 | 0.07 | 5.73 |
