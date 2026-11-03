# 归溟幽灵鲨 pixelfx 放开版 TRACE 对比（fx/px_unleashed 0 / 1）

commit: e7e25ca4 归溟幽灵鲨终结技 / 连携件改调样板 u.px_strip（docs/242 §14.15），删掉本地过渡辅助 _specter_ul_strip
seed=13 --bot=expert --nodeath --trace=1，5 组 × 2（K=0/1），共 10 局。

| 组 | TRACE 行数 | 结果 | 第一处不同（.trace 文件行号） | SCRIPT ERROR/Parse Error（K=0 / K=1） |
|---|---|---|---|---|
| late  | 561 | 不同 | 562/562（.trace 共 562 行，561 TRACE + 1 BALANCE，差异在末行 BALANCE） | 0 / 0 |
| ult   | 241 | 不同 | 242/242（.trace 共 242 行，241 TRACE + 1 BALANCE，差异在末行 BALANCE） | 0 / 0 |
| skill | 241 | 不同 | 242/242（同上） | 0 / 0 |
| elegy | 241 | 不同 | 242/242（同上） | 0 / 0 |
| link  | 241 | 不同 | 242/242（同上） | 0 / 0 |

## 结论

- 5 组全部一致：所有 `^TRACE` 行在 K=0 / K=1 之间逐行完全一致（late 561 行、其余各 241 行，diff 对 TRACE 部分为空）。
- 5 组全部在**唯一一处**出现差异：每组 `.trace` 文件的最后一行（`^BALANCE` 汇总行）。逐组对该行 JSON 做字段级 diff，差异全部集中在 `bot.peak_min` / `bot.peak`（按分钟采样的峰值统计数组里的数值项），其余字段（含 `boss_hp`、`bosses`、`armor_cf`、`allies` 等）一致。
  - late: 14 处字段差异，均在 `bot.peak_min[i][3]`/`[4]`
  - ult: 10 处，同上，另含 `bot.peak[3]`
  - skill / elegy / link: 各 6 处，同上，另含 `bot.peak[3]`
- 未见任何 `SCRIPT ERROR` / `Parse Error`：10 份 stdout 全部为 0。
- 原始输出行数（含引擎日志）10 份两两相等：late 817、ult 346、skill 321、elegy 347、link 304（0/1 两次完全相同）。

**结论：TRACE 战斗日志逐行一致（符合预期：开关不应改变确定性战斗序列），仅末尾 BALANCE 汇总行里的按分钟峰值统计（`bot.peak_min`/`bot.peak`）有差异，且无脚本报错。** 该差异是否可接受（例如峰值统计采样本身对时间窗口边界敏感，或与开关确实改变了某些数值从而影响峰值落点）需要人工判断，本次只做事实比对，未做代码修改。
