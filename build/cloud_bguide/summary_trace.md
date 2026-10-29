# bguide-trace（claude/build-guide 850c5cad5 vs 基线 bfa2bcd0）

## 同 seed TRACE（tools/trace_base.py --here，600 秒）
| 局 | 参数 | rc | TRACE 行数 | 逐行相同 | 首个不同行 |
|---|---|---|---|---|---|
| 1 skalter | --squad=texas,exusiai --tier=0 --tide=0 | 0 | 381 | 是 | 无 |
| 2 mizuki | --bot=master --tier=0 --tide=0 | 0 | 601 | 是 | 无 |
| 3 hoshiguma | --meta=18 --tier=0 --tide=0 | 0 | 601 | 是 | 无 |
| 4 angelina | --bot=master --meta=18 --squad=skadi,kaltsit | 0 | 601 | 是 | 无 |

四局 trace_base.py 都提示“BALANCE 行有差异，多半是画面峰值 / prof 字段”（脚本只提示不判定）；本次没有逐字段比 BALANCE 行（--here 侧输出不入缓存）。局 1 只有 381 行，基线与本分支一致（同样提前结束）。

## 快检（tools/check.py --only <项>）
| 项 | rc | 结果 |
|---|---|---|
| data_lint | 0 | 通过 |
| core | 0 | 通过，4183 checks, 0 failed |
| build_affinity | 0 | 通过，failures=0 |
| build_progression | 0 | 通过，failures=0 |
| economy | 0 | 通过，0 failures |
| event_trade | 0 | 通过，0 failures |
| merchant_build_offer | 0 | 通过，failures=0 |
| relic_impl | 0 | 通过，failures=0 |
| node_cards | 0 | 通过，0 failures |
| smoke | 0 | 23 项全过，162 秒 |

所有日志无 SCRIPT ERROR。另：导入后出现未入库的 game/scripts/run/build_guide.gd.uid，需在本机补交。
