# trim T0（改前 7306d6bf1）master 机器人 — 藏品精简配对基线

检出 7306d6bf1（claude/integ-1029）；starts 7 编队 × seed 1–8 × 2 档；`--tier=0 --tide=0`（m18 加 `--meta=18`）。

分类：改打法 = trim:"play"，或含 trigger/spawn/status/rule/growth 且 lane≠economy、稀有度≠结局/遭诅古物；纯属性 = effects 全为 stat；填充 = filler:true；停用 = pool:false。本提交数据里尚无 trim/filler/pool 字段，故填充 / 停用恒为 0；其余（如 on_gain+stat、经济类 rule）不计入两类。

| 档 | 局数 | 胜率（Wilson 95%） | 平均存活秒 | 每局藏品（全部 / 胜局） | 改打法 件/局（占比） | 纯属性 件/局（占比） | 填充 件/局 | 停用 件/局 | script_errors |
|---|---|---|---|---|---|---|---|---|---|
| m0 | 56 | 19/56 = 33.9%（22.9%–47.0%） | 564.0 | 6.95 / 12.26 | 2.93（42.2%） | 3.16（45.5%） | 0.00 | 0.00 | 0 |
| m18 | 56 | 34/56 = 60.7%（47.6%–72.4%） | 666.4 | 10.43 / 12.71 | 4.29（41.1%） | 4.80（46.1%） | 0.00 | 0.00 | 0 |

逐局：build/cloud_trim/runs_T0_master.csv；原始：build/cloud_trim/raw/
