# bguide-T1 summary

- 改后 = d6079bee3（claude/build-guide，bot 改调 build_guide.main_lane）
- preset starts（7 编队）× seed 1–8 × 2 档 = 112 局，master 机器人（balance_run.py 原生接受 --bot master）
- m0 = `--tier=0 --tide=0`；m18 = `--tier=0 --tide=0 --meta=18`

| 档 | 局数 | 胜率 (Wilson 95%) | 平均存活秒 | 藏品数/局 全部 | 藏品数/局 胜局 | script_errors |
|---|---|---|---|---|---|---|
| m0 | 56 | 20/56 = 35.7% [24.5%, 48.8%] | 603.1 | 9.66 | 14.35 | 0 |
| m18 | 56 | 35/56 = 62.5% [49.4%, 74.0%] | 660.5 | 11.62 | 13.43 | 0 |

逐局明细：build/cloud_bguide/runs_T1.csv；原始报告：build/cloud_bguide/raw/。
