# 流明 pixelfx 放开版 TRACE 对比（commit 08adf67e8）

种子 seed=13，bot=expert，nodeath，maxprog，sptest，trace=1。对比开关 `fx/px_unleashed` 0 / 1。

| 组 | 参数 | TRACE 行数 (0/1) | diff | SCRIPT ERROR/Parse Error (0/1) |
|---|---|---|---|---|
| late | --op=hoshiguma --squad=lumen,siege --maxt=560 | 561 / 561 | same | 0 / 0 |
| lead | --op=lumen --squad=hoshiguma,siege --maxt=300 | 301 / 301 | same | 0 / 0 |
| ult  | --op=lumen --squad=hoshiguma,siege --maxt=240 --bal=ult/test_fill_at=20 | 241 / 241 | same | 0 / 0 |

结论：三组在 `fx/px_unleashed` 开 / 关下 TRACE 逐行一致，无 SCRIPT ERROR / Parse Error。
