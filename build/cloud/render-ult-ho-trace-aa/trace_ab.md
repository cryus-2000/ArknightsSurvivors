# 同种子 TRACE 对比

A：`--bal=ult/px_plane_hoshiguma=0`　B：`--bal=ult/px_plane_hoshiguma=0`　共用：`--squad=saria,exusiai --nodeath --maxprog --bal=ult/bot_n=1 --bal=ult/test_swarm_at=30.3 --bal=ult/test_swarm_every=6 --bal=ult/test_fill_at=31.5 --realtime --playclock --rtfrom=27`

| 局 | A 行数 | B 行数 | 结果 | 第一处差异 |
|---|---|---|---|---|
| hoshiguma 种子 3 40 秒 | 41 | 41 | **有差异** | 第 35 行：A `TRACE t=34.00 lv=3 k=105 hp=140.40 n=13 rng=3185651335901228707/201631784411482364/-2978028381407171661/-177584972758040` / B `TRACE t=34.00 lv=3 k=105 hp=140.40 n=13 rng=3185651335901228707/201631784411482364/-2978028381407171661/-177584972758040` |
