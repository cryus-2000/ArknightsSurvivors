# 藏品精简快检（claude/relic-trim-r2 7bd89511e）

Godot 4.7.2 headless + Dummy 音频；日志都在 build/cloud_trim/logs/。

## 快检（tools/check.py --only <项>）

| 项 | rc | 结果 |
|---|---|---|
| data_lint | 1 | 失败：balance.json 有 290 个键没有字面读点（提示级）；疑似拼错：代码读的是 `boss/spd_all_k_`（json 里没有，走缺省值），json 里有的是 `boss/spd_all_k_ishar`，但没有代码读它 |
| core | 0 | 通过 |
| relic_reclassification | 0 | 通过 |
| relic_impl | 1 | 断言全过（199 checks, 0 failed），但有 266 条 SCRIPT ERROR，所以判失败（见下） |
| build_affinity | 0 | 通过 |
| build_progression | 0 | 通过 |
| card_desc | 0 | 通过 |
| economy | 0 | 通过 |
| event_trade | 0 | 通过 |
| merchant_build_offer | 0 | 通过 |
| node_cards | 0 | 通过 |
| vis_growth | 1 | `FAIL: #98 高闪相机：编队无控场引爆干员（{  } / ）`：Aff.of_choice 对 #98 返回的 miss 是空串，期望是「编队无控场引爆干员」。#98 现在的效果是 rule ctrl_chain，可能是亲和表没跟上新效果，也可能是测试期望过期 |
| ea_ui | 0 | 通过 |
| run_stats | 0 | 通过 |
| smoke | 0 | 通过 |

relic_impl 日志里的 SCRIPT ERROR（前几条，全部同一种，共 266 条）：
```
SCRIPT ERROR: Invalid access to property or key 'boss' on a base object of type 'Dictionary'.
          at: _trim_on_kill (res://scripts/relic_fx.gd:1683)
              [0] _trim_on_kill (res://scripts/relic_fx.gd:1683)
              [1] on_kill (res://scripts/relic_fx.gd:1401)
              [2] test_docs74 (res://tests/relic_impl_test.gd:498)
              [3] _process (res://tests/relic_impl_test.gd:35)
```
各调用点的次数：relic_impl_test.gd:498 ×59、:500 ×1、:504 ×100、:505 ×100、:508 ×5、:512 ×1。
原因：新加的 `_trim_on_kill` 第一行直接读 `e.boss`，test_docs74 传进来的假敌人字典（例如 `{"dead": false, "type": "runner"}`）没有 boss 键。改法二选一：把这行改成 `e.get("boss", false)`，或者给测试的假敌人补上 `"boss": false`。实战敌人字典都有 boss 键，所以下面 4 局冒烟没有复现。
各项都没有 Parse Error。

## 冒烟 4 局（--balance --bot=master --maxt=420，开局给 19 件指定藏品）

| seed | 队长 | 队友 | SCRIPT ERROR | win | t | 备注 |
|---|---|---|---|---|---|---|
| 1 | skadi | texas,exusiai | 0 | false | 420 | ending standard，藏品 24 |
| 2 | mizuki | logos,angelina | 0 | false | 420 | ending knight，藏品 28 |
| 3 | hoshiguma | specter_unchained,irene | 0 | false | 420 | ending standard，藏品 25 |
| 4 | wisadel | kaltsit,suzuran | 0 | false | 420 | ending standard，藏品 26 |

4 局都打满 maxt=420，win=false 是到时截断，不是阵亡。日志里只有引擎例行 ERROR：shader_compiler custom_samplers，以及退出时的资源 / RID 泄漏，和这次改动无关。
