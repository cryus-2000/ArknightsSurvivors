# 204 · 测试体系方案（模块化快检 + 对账 + 图校验）

> 2026-10-30，测试与验收会话。**只是方案，未实装**，等用户审。起因：用户 10-30「完善的测试体系，效率高的同时模块化，节约快检时间，预防数值与实际没对上、节点没对上」。
> 附两个只读原型（未接入 check.py）：`tools/text_reconcile_scan.py`（扫文本字面数字，约 0.05 秒）、`tools/graph_lint.py`（节点 / 引用图校验，约 0.2 秒）。
> 取证口径：云端 = `git show origin/ci/<sha>:build/ci_check.log`；L26 = 本机主检出 `build/check/quick_1026_041402/*.log`；`timing_report_1015.md` = `build/check/timing_report_1015.md`。取不到实测的标「估计」。

## 0. 结论先行

| 问题 | 现状（实测） | 方案后（目标） |
| --- | --- | --- |
| 分支快检太重 | `--auto` 对 Boss / 藏品 / UI / 公共脚本一律判 full（`check.py:132` 的 else 分支）；分支 full 精简版约 3–6 分钟（估计） | `--changed` 按路径映射，典型改动 1–3 分钟（§2.4） |
| 重复 | 全量 174 个 Godot 进程，三组（manual_all 20 + nodes 20 + blocks_eq 14）占进程耗时 34% | 分支只跑相关干员的那几个；全量留给合入 CI |
| 说明与数值对不上 | 干员文字有 op_text_check；其余约 390 条玩家可见字面数字无人校（§3.2） | 统一对账，静态可求值的进秒级快检 |
| 节点对不上 | 无检查 | graph_lint 0.2 秒；原型已找到 2 条死节点、5 条图标引用缺失（§4.3） |
| 红项 | 无「长期红」；10-29 晚云端一次 6 项红是新回归，其中 prot 11 条已在未合分支修好 | 红项登记制 + 到期转硬失败（§5.4） |

最该先做的三件：**① 红项登记 + 修三项红 ② `--changed` 路径映射 ③ 藏品 / 升级卡对账**（§6）。graph_lint 作为 ① 的附带接入。

## 1. 现状盘点

### 1.1 各层耗时

| 层 | 总耗时 | 依据 |
| --- | --- | --- |
| 云端全量（真全量，jobs=4，缓存未命中） | 472 / 499 / 516 / 546 / 557 / 590 / 600 秒，中位约 540 | `origin/ci/aeef41137` 472、`ci/33ba50979` 499、`ci/b3d466a19` 516、`ci/270b7df9b` 546、`ci/c4f968944` 557、`ci/3091151b0` 590、`ci/7306d6bf1` 600（各自 `build/ci_check.log`） |
| 云端全量，缓存全命中 | 97 秒（157/201 命中） | `ci/fe25b4ecc:build/ci_check.log` |
| 云端金样重录（28 份） | 87 秒 | `ci/aeef41137:build/ci_rerecord.log` |
| 本机全量（`check.py` 无参） | 空闲 456 秒；高负载 793 / 1043 / 1642 秒 | docs/36 §1「6–8 分钟」；`timing_report_1015.md`；L26 日志首尾修改时间差 1043 秒（174 个进程，进程合计 16224 秒） |
| `--auto` 分级 | none 约 0 秒（不开 Godot）；text 约 30 秒；ops 0–2 分钟；缓存全中的 full 52 秒 | docs/36 §1；`cloud-results/m3hp-check:build/m3check/auto.log` 末行 |
| 分支 full 精简（§1.4） | **估计** 3–6 分钟 | 依据：省掉积木等价 28 局与自然流程 2 局，其余照旧；无实测日志 |
| 同种子复现（4 分钟游戏时间 × 2 局） | 单进程 61–230 秒 | `timing_report_1015.md` |
| 金样 TRACE 对照 | 基线命中缓存 0 秒；无缓存一整局 157 秒；**无独立耗时日志，估计** 3–5 分钟（基线 + 候选） | docs/36 §3.2 / §4 |
| 积木等价（14 组 × 2 seed） | L26：14 进程合计 1663 秒；云端重录同样 28 份只需 87 秒 | L26 `blocks_eq_*`；`ci_rerecord.log` |
| 不开 Godot 的静态项 | art_lint 约 10 秒、slim 约 5 秒、op_text / ob_tag / data_lint / cc_lint 各约 1 秒 | `check.py:1217-1236` 注释；`graph_lint` / `text_reconcile_scan` 实测 0.2 / 0.05 秒 |

项数：快检 = 静态约 11 项 + core + 冒烟 20 + 自然流程 2 + nodes 20 + manual_all 20 + prot + repro + native_eq + blocks_eq 14 + SCENE_REGRESSIONS 122（`check.py:954`、`471-483`）。云端 `ci_check.log` 汇总为 157–169 项。

**耗时前 10（L26，本机负载偏高，各进程自报）**

| # | 项 | 秒 |
| --- | --- | --- |
| 1 | ishar_human_ui | 420 |
| 2 | manual_all_kaltsit | 369 |
| 3 | meta | 337 |
| 4 | nodes_skadi | 317 |
| 5 | nodes_saria | 306 |
| 6 | blocks_eq_logos_seed1 | 288 |
| 7 | manual_all_siege | 277 |
| 8 | nodes_lappland | 254 |
| 9 | tour | 251 |
| 10 | response_skill | 246 |

同一冒烟项在不同云端运行里差 3–10 倍（lappland 546 秒对 28 秒），耗时主要受机器负载影响。云端 `ci_check.log` 汇总行只有冒烟与自然流程带单项秒数，**要做云端前 10 须先在 `_run`（`check.py:407`）统一记每项秒数**（§6 第 1 期顺带）。

### 1.2 重复

| 重复 | 证据 | 处理 |
| --- | --- | --- |
| 同一场景脚本被起多次 Godot | `response_test` 起 9 次（response / response_skill / p2a–p2g）、`synergy_test` 4 次、`boss_trial_ui_test` 2 次、`cam_resize_test` 2 次（`check.py:954` 起） | 每次起进程固定开销数秒，且 `ishar_human_ui` 是全表最慢项（420 秒）。合并为同进程多用例或按参数分组；工作量小 |
| 干员被四个维度各跑一局 | 冒烟 20、nodes 20、manual_all 20、blocks_eq 14，改单干员时分别用该干员开局 | `--changed` 只选该干员的项；nodes + manual_all 合并为同进程两阶段，可再省约 30% 进程数（估计） |
| 冒烟与自然流程 | 冒烟 + 自然流程 22 项云端合计 1763–2498 秒（进程秒） | 分支上已改成「相关人 + 轮换 5 人」（§1.4），保持 |
| 同一断言多处覆盖 | op_text_check 与 card_desc_test 均查占位；prot_test 钉 regen 说明（`prot_test.gd:1871`）、vis_growth 钉卡面关键句（`vis_growth_test.gd:84-109`）是手写字面 | 统一对账后手写字面断言降为「少数关键句」 |
| 孤儿测试 | `game/tests/bgm_memory_test.gd`、`card_desc_fit_test.gd` 在 `tools/*.py` 里无任何引用；108 个 `*_test.gd` 中 2 个未接入 | 接入或删除；`card_desc_fit` 归入藏品组 |
| 非测试混在 tests/ | 196 个 .gd 中约 80 个是 `*_capture / _rec / _probe / _preview / _bench`（文件名统计） | 分目录（`tests/` 与 `tools_capture/`），省去判读成本 |

### 1.3 「长期红」逐个核实

**先修正前提**：`origin/cloud-results/*` 共 617 个分支，里面是整库快照，没有各自的 auto.log / compare.txt；其中 66 个分支的 `build/ci_check.log` 逐字节相同（md5 `bdb829c3…`，158 项 546 秒，继承自基线分支）。所以「≥15 次独立运行」只能靠 `origin/ci/<sha>` 的 8 次独立云端全量 + 本机 `build/check/quick_*`（109 个目录，10-24 至 10-27）。

| 统计 | 结果 |
| --- | --- |
| 云端 8 次的红绿序列 | 红（11 项，10-27 `b3d466a19`）→ 绿 ×3 → 红（3 项，10-28 `3091151b0`）→ 绿 ×2 → 红（6 项，`7306d6bf1`） |
| 连续 ≥3 次红的项 | **0**。云端最长连续红 1 次；本机 109 次里没有项连续红 ≥2 |
| 结论 | 现状是「反复出现的新回归」，不是「长期无人管」；真缺口是没有登记 / 认领机制（§5.4）。三项点名项都是 10-29 晚才在同一次 CI 里一起出现（前一次 `ci/aeef41137` 全绿，command_ai 67 条 0 失败） |

三项点名项逐个核实：

| 项 | 实测 | 原因 | 处置 |
| --- | --- | --- | --- |
| prot_test 11 条 | `ci/7306d6bf1:build/check/quick_1029_143536/prot.log` 共 13 条 FAIL；11 条是满血保护（`prot_test.gd:302/303/338/342/348/361`）、`recall_after`、`guide_r`（1112/1113）、`shade_deg`（1132）、通用 2 秒上限（1235）；另 2 条是招募回复文案（1857/1863，期望 +0.5 实际 +0.15 / 秒） | `082bec20b` 提交说明：docs/178 把 json 的 `fullhp_guard_left/cd` 调成 5% / 60 秒，测试按旧值写；测试还依赖「`Bal._data["protect"]={}` 即代码缺省为关」（`prot_test.gd:43` 起） | **11 条已在分支 `claude/bal-cache-tests` 的 `082bec20b` 修复，未合入 integ-1029**（`git merge-base --is-ancestor 082bec20b HEAD` 为否）。另 2 条回复文案断言须改读 `squad_regen` 缺省 |
| command_ai side 0 | `game/tests/command_ai_test.gd:205`「side 0: old rule」期望 `roam_target(Vector2(40,14))` 的 x<300 且 y 近 0，实际偏离；`ci/aeef41137` 67 条 0 失败，`ci/7306d6bf1` 70 条 1 失败 | `character.gd` 的 `_cmd_side`（约 1943 行）在 `side<=0` 应直接朝队长；嫌疑提交 `f85b34db8` / `aa3c82722` / `89a0a2226`，**未逐一验证** | `082bec20b` 提交说明写「command_ai_test 由指挥会话在 `6cf116560` 补」，先确认是否已修；仍红则登记并交指挥会话 |
| data_lint `spd_all_k_` | `game/scripts/enemies/shot_pool.gd:128` 是 `Bal.v("boss/spd_all_k_" + str(fb.type), 1.0)`，`data_lint.py` 的 `BAL_CALL` 正则（约 129 行）只截到字面前缀，与 json 的 `boss/spd_all_k_ishar` 相似度 ≥0.8 被判「疑似拼错」 | 动态拼键误报；同时 `boss/spd_all_k_ishar` 被算成「无读点」 | 修 lint：以 `_` 结尾或后接 `" +` 的读点按前缀匹配；不修数据 |

另有 3 项在 `ci/7306d6bf1` 红但未留分日志：伊莎玛拉二阶段连段与图案弹幕、偏执泡影连携攻势、`op_pacing`（20 人确认节奏），原因未查清，需云端补推日志才能核。

## 2. 模块化：改动路径 → 受影响检查

### 2.1 现状的问题

`plan_auto`（`check.py:90-135`）只认四类路径：docs / 美术 / 数据 json / 角色脚本；其余一律 `full`。Boss 脚本、藏品、UI 等改动在分支上落入「分支 full 精简」。**`--changed` 取代 `plan_auto` 的 else 分支**，保留 none / text / ops 三档语义。

### 2.2 检查项分组（映射的目标集合）

| 组 | 含的项 | 约进程数 | 备注 |
| --- | --- | --- | --- |
| S 静态（不开 Godot） | data_lint、op_text、ob_tag、cc_lint、asset_lint、asset_index、art_lint、slim、enemy_art；新增 graph_lint、text_reconcile | 11 | 恒跑，合计 <30 秒 |
| core | 核心契约 `test_core` | 1 | text 档起恒跑 |
| ops:id | 冒烟·id、nodes_id、manual_all_id、blocks_eq_id（×2 seed）、该干员相关场景（`<id>_*_test`） | 每人约 5–7 | 沿用 ops 档 |
| boss | boss_*（trial、trial_ui、pressure、support、boundary、fx_geometry、variety）、ishar_*、knight_*、paranoia_combos、mid_boss、final_boss_*、izumik_card、beam_audio、final_attack_grains、wisadel_* | 约 28 | 由 SCENE_REGRESSIONS 键名前缀得到 |
| relic | relic_impl、relic_reclassification、vis_growth、card_desc、card_desc_fit、build_affinity、build_progression、merchant_build_offer、economy、event_trade、event_maxhp、node_cards | 12 | |
| ui | ea_ui、op_select、codex、credits、esc_layers、title_menu、touch_move、touch_layout、cam_resize ×2、public_gallery、gallery_demo、settlement、run_stats、meta、meta_mech、roster、tour、save_migrate、medals、cloud_save、look | 约 22 | 各界面冒烟 |
| enemy | enemy_status、enemy_attack_variety、enemy_identity、enemy_prepare、enemy_demo、enemy_pixels、reaper_rush、attack_phases、tide | 9 | |
| command | command_ai、command_wheel、voice_command、friendly_target | 4 | |
| prot | prot_test | 1 | |
| repro | 同种子复现 | 2 局 | 改任何会改战斗结果的脚本才需要 |
| smoke-sample | 冒烟轮换抽样 5 人 + 自然流程 2 局 | 7 | 公共脚本改动用 |

### 2.3 路径映射表（拟放 `tools/check_map.json`）

| 路径 glob | → 检查 | 依据 |
| --- | --- | --- |
| `docs/**`、`**/*.md`、`*.uid`、`*.import` | none | `plan_auto` 现有规则（`check.py:104`） |
| `game/data/characters/<id>.json` | S + core + ops:id + prot（若含 protect 键） | 现有 ops 档；只改说明字段 → text 档（`_json_text_only`） |
| `game/scripts/characters/<id>.gd`、`game/scripts/blocks/seg_<id>*.gd` | S + ops:id | 积木是单继承链（`character.gd:16` 注释）：改 `ob_core / ob_geom / ob_check` 等基座 → 升级为全员 blocks_eq + smoke-sample |
| `game/data/relics.json`、`relic_effects.json`、`game/scripts/core/relic_db.gd` | S + core + relic | `card_desc_test` / `vis_growth_test` / `relic_impl_test` 覆盖面 |
| `game/data/cards.json`、`meta_tree.json`、`medals.json` | S + core + relic + ui | 升级卡 / 局外树消费点 |
| `game/data/events_v2.json`、`waves.json`（events 键） | S + core + relic（event_*、economy） | `endings.gd` 消费 |
| `game/data/waves.json`（非 events）、`enemies.json`、`balance.json` | S + core + enemy + boss + repro + smoke-sample | 波次 / 数值影响整局 |
| `game/scripts/enemies/bosses/**`、`shot_pool.gd`、`game/data/boss*.json` | S + core + boss + prot + repro | prot 查 Boss 来源扣血截断（docs/38 §1.11） |
| `game/scripts/enemies/**`（非 boss） | S + core + enemy + smoke-sample | |
| `game/scripts/screens/**`、`game/scripts/ui/**`、`game/scenes/ui/**` | S + ui | UI 不影响战斗结果，不跑 repro / 冒烟 |
| `game/scripts/command/**` | S + command + smoke-sample | |
| `game/art/**`（干员帧条） | S + ops:id（沿用 `plan_auto` 的命名匹配） | |
| `game/art/**`（其余）、`art/**` | S（asset_*、art_lint、enemy_art） | 贴图不改逻辑 |
| `game/audio/**` | S + ui（menu_bgm）+ boss（beam_audio） | |
| `tools/check.py`、`tools/godot_runner.py`、`tools/check_map.json` | S + core + 每组抽 1 项（自检） | 改测试工具本身；合入 CI 兜底 |
| `tools/**`（其他） | none，除非该工具是某静态项（`op_text_check.py` → op_text 等，映射内显式列出） | |
| **全局公共**：`character.gd`、`game.gd`、`combat.gd`、`squad.gd`、`doctor.gd`、`op_api.gd`、`balance.gd`、`game/scripts/core/**`、`game/scripts/run/**` | **full-branch**（现有精简全量） | `SHARED_CHAR`（`check.py:49`）已列前几个 |
| 未知路径（未被任何规则命中） | S + core + smoke-sample，并打印「未映射路径」 | 保守但不全量；合入 CI 全量兜底 |

规则放数据文件，格式（示意）：

```json
{"rules": [
  {"glob": "game/scripts/enemies/bosses/**", "groups": ["S", "core", "boss", "prot", "repro"]},
  {"glob": "game/data/characters/*.json", "groups": ["S", "core"], "ops_from_stem": true}
],
 "groups": {"boss": {"scene_prefix": ["boss_", "ishar_", "knight_", "final_boss_"]}},
 "escalate": ["game/scripts/characters/character.gd", "game/scripts/game.gd"],
 "unknown": ["S", "core", "smoke-sample"]}
```

`check.py --changed <base>`：`git diff --name-only <base>...HEAD` 加未提交 / 未跟踪（沿用 `changed_files()`，`check.py:60`）→ 逐文件查规则 → 取分组并集 → 打印「改动文件 → 命中规则 → 选中项数」。`--auto` 作为别名指向 `--changed main`；全量只在合入 CI（`tools/ship.py` / `ci/<sha>`）。

**防漏自检**：每个 SCENE_REGRESSIONS 键必须至少属于一个组（check.py 启动时校验，未归组打印警告并标「仅全量跑」）；新增测试忘记归组 = 快检不跑，CI 兜底。

### 2.4 预计本地快检耗时

基准：云端全量中位 540 秒（jobs=4）；单项耗时按 L26 的一半估计（L26 负载高）。**以下均为估计，非实测；第 1 期用 `_run` 每项计时校准。**

| 典型改动 | 现状 | `--changed` 选中 | 预计 |
| --- | --- | --- | --- |
| 改单干员 json 数值 | ops 档 0–2 分钟 | S + core + 1 人 5–7 项 + prot | 约 1.5–2.5 分钟（略增，多了该人场景测试） |
| 改单干员 json 说明字段 | text 档约 30 秒 | S + core | 约 30 秒（不变） |
| 改 Boss 脚本 | 分支 full 精简 3–6 分钟（估计） | S + core + boss 约 28 项 + prot + repro | 约 3–4 分钟（省掉冒烟 5 人 / nodes / manual_all / 自然流程） |
| 改藏品 json | 3–6 分钟 | S + core + relic 12 项 | **约 1–1.5 分钟** |
| 改 UI 脚本 | 3–6 分钟 | S + ui 约 22 项（无战斗局） | **约 1.5–2 分钟** |
| 改文案 / 说明 | none–text | S + core | 约 30 秒 |
| 改公共脚本（character.gd 等） | 3–6 分钟 | 同（升级为大集合） | 不变；合并重复进程再省 10–15% |
| 改工具（check.py 等） | 3–6 分钟 | S + core + 每组 1 项 | 约 1 分钟 |

加权（假设近期提交里 UI / 藏品 / 文案占约一半）：**本地快检平均从约 3–6 分钟降到约 1.5–2.5 分钟**。

## 3. 「数值与实际对不上」统一对账

### 3.1 现状：各写各的

| 文本类 | 谁校 / 校什么 | 位置 |
| --- | --- | --- |
| 干员普攻 / 技能 / 天赋 / 成长 / 图鉴 | `op_text_check.py`：`{$表达式}` 必须在 base 求得出值（`text_eval` :61、`fill_line` :129）；字面「N% / N 秒 / ×N / 半径 N / 每第 N 次」必须在 base / blocks 里有对应值（`literal_numbers` :269、`check_op` :292，ALLOW 白名单 :36）；`iter_texts` :150 只取 attack / skills / talent / progression / gallery / blocks.banner | `check.py:172`、`tools/op_text_check.py` |
| 占位残留（不查数对不对） | `card_desc_test.gd`：成长 / 藏品 `display_desc` / 招募卡填充后无残留 `{}` | `card_desc_test.gd:39`、`:82` |
| 排版放得下 | `card_desc_fit_test.gd`（**未接入 check.py**） | `card_desc_fit_test.gd:11` |
| 少数字面断言 | `vis_growth_test.gd:84-109` 可见成长藏品卡面关键句；`prot_test.gd:1871/1888` regen / armor 两张升级卡；`relic_impl_test.gd:539/544` 熔铸 | 手写 |
| 局外节点 / 勋章 | 只查 name / desc / cost 非空（`meta_test.gd:49`、`medals_test.gd:64`） | 不查内容 |
| 数据引用 | `data_lint.py`：重复键、waves 引用、balance 键拼写 | `check.py:186` |

占位的填充实现各一份：`doctor.gd:399`（升级卡 `passive_desc`）、`relic_db.gd:32`（藏品 `fill_desc`）、`intro.gd:466`（指南 `fill_numbers`）、`character.gd` `fill_text`（干员）。四套填充 = 四处对账缺口。

### 3.2 实际扫描结果（`tools/text_reconcile_scan.py`，只读 json，约 0.05 秒）

「字面」= 含数字、无占位，并排除 `S3 / E2 / T1` 类标识、年份时刻、`docs/NN`、`第N次`、「」内专名后仍有数字的条数（只扫阿拉伯数字，「三选一」「两倍」类汉字数字未扫）。

| 类别 | 总条 | 含数字 | 含占位 | 字面 | 现有校验 |
| --- | --- | --- | --- | --- | --- |
| 藏品·`relic_effects.json` desc（实际卡面） | 254 | 244 | 10 | **243** | 无（仅 vis_growth 少量手写） |
| 藏品·`relics.json` adapt（缺省说明，多被上条覆盖） | 265 | 215 | 0 | 205 | 无 |
| 藏品·`relics.json` original（原作原文，不显示） | 265 | 238 | 0 | 238 | 不需要 |
| 事件·选项 desc | 93 | 62 | 0 | **62** | 无 |
| 局外·认知塑造节点 desc | 84 | 40 | 0 | **40** | 无（只查非空） |
| 升级卡 passives / fillers desc | 19 | 19 | 0 | **19** | 仅 regen / armor 2 张 |
| 干员·response / leader 等其它 desc | 20 | 17 | 2 | **16** | 无（不在 `iter_texts`） |
| 开局指南 guide | 40 | 12 | 4 | **8** | 无（有 `{键}` 机制但未用满） |
| 敌人 desc | 26 | 8 | 0 | **8** | 无 |
| 蚀刻章 desc | 9 | 3 | 0 | **3** | 无 |
| 练习编队 label | 6 | 3 | 0 | **3** | 无 |
| 干员·普攻 / 技能 / 天赋 / 成长（含精英化节点） | 362 | 310 | 331 | 65 | **op_text_check** |
| 合计（脚本口径，含不显示的 original 与图鉴等） | 1699 | | | **910** | |

去掉 original（238，不显示）、adapt（205，多被盖住）与干员类已校验（约 65）后，**玩家可见且无人校验的字面数字约 390 条**（藏品 243 + 事件 62 + 局外 40 + 升级卡 19 + response/leader 16 + 指南 / 敌人 / 勋章 / 练习编队 14）；若 adapt 也算则约 590。

**已有实例（对不上）**：`cards.json` `passives.regen` 写「+0.4 / 秒」，卡面实际值读 `balance` 的 `sustain/regen_card`，缺省 0.6（扫描时顺手发现，未逐条核其余卡）；`prot_test.gd:1857/1863` 招募界面写的回复 +0.5 实际 +0.15（`ci/7306d6bf1`）。

### 3.3 设计：同一套「读参数 → 求值 → 比对」

**数据格式**——每条说明二选一：

1. **占位**：`{$键}` / `{键}`，取值来源在条目里声明，如 `"vals": {"hp": "effects.0.value", "t": "balance:sustain/regen_card"}`；渲染值由框架求出，不再手抄。
2. **校验声明**：字面数字保留，旁边写 `check`，如 `"check": [{"num": 20, "from": "effects.0.value"}, {"num": 8, "from": "value*100", "unit": "%"}]`；声明缺失的字面数字报「未声明」。

**三档求值，逐类可行性**

| 档 | 做法 | 耗时 | 适用类 | 可行性 |
| --- | --- | --- | --- | --- |
| A 纯静态 | `tools/text_reconcile.py` 读 json（含 balance 缺省）求值；数字与参数比对口径沿用 `op_text_check` 已有的等价形式（原值、×100、(v−1)×100、(1−v)×100、1/v） | 秒级，不开 Godot | 升级卡、局外树、勋章、练习编队、敌人 desc、指南、藏品里 effects 为单字段加成的条目（占藏品 desc 的多少为**估计**，须先抽样 20 条验证） | 高 |
| B 纯函数求值 | `game/tests/reconcile_test.gd` 单进程调现有填充函数（`doctor.passive_desc`、`RelicDB.fill_desc`、`fill_numbers`），渲染结果与 A 档静态值比对，证明「渲染出来的字」等于静态值 | <10 秒 | 占位类（A 档只证数据，B 档证渲染没偏） | 高 |
| C 必须跑一遍 | 小场景触发效果，读结算值（事件 `mult`、触发概率、冷却）与说明比对 | 每类一个小场景 | 事件结算、概率 / 触发类藏品 | 中；首期只对事件抽 5–10 条 |

**统一入口**：`tools/text_reconcile.py`（静态，进快检 S 组，改 `game/data/**` 触发）+ `game/tests/reconcile_test.gd`（B 档，进 relic / ui 组）。`op_text_check` 保留不动，作为干员适配器接入同一汇总；输出统一为 `类别 / 文件:键路径 / 说明里的数 / 求得的值 / 判定`。

**覆盖率指标**：已声明（占位或 check）的可见字面数字 ÷ 可见数字总数；当前已校约 65 条干员字面，加占位类另计，可见无人校约 390 条；目标第 3 期末 ≥70%，之后 ≥90%（余下为 C 档触发类）。

**误报风险**：藏品 desc 里常含「上限 N」「N 层」等与 effects 键名不同的口径，需一次性人工建映射；`check` 声明缺失先 warn 不 fail，满一个周期再升 fail。

## 4. 「节点对不上」可达性 / 引用完整性（`tools/graph_lint.py`）

### 4.1 建模方式

- **干员成长线**：`characters/<id>.json` 的 `progression` 线性数组，`character.advance()` 顺序推进（`character.gd:811`），`node_view` 解析生效视图（`:862-866` 无条件应用 `alt`；`:867` 起处理 `branch` / `routes`）。可达 id = 各路线下的生效 id 并集；`blocks.progression.<id>`、`node:<id>` 条件、`bot` 缺省路线都必须落在集合内。
- **技能解锁**：`skill_unlocked(i) = elite >= i`（`character.gd:788`），S2 对应 elite level 1，S3 对应 level 2。检查缺 elite 节点、顺序错、`skill_active:N` 超技能数。
- **局外树**：`meta_tree.json` `nodes[].req` 为前置边，`order` 为顺序；检查缺前置、成环、不在 `order`、星图（`meta_roots.json`）与节点不一致。
- **事件**：选项是否灰掉只由 `endings.gd` 的 `_blocked`（约 641 行）与 `_req_ok`（:296）决定；静态判每事件至少一个永不灰的选项。
- **键引用**：藏品 / 卡 / 敌人 / 技能 id；`icon` / `tex` 查 `game/art/index.json`（含 `@2x` 后缀与 `art.gd` 的 `ALIAS`）；`res://` 路径查文件；`$变量` 查 base（含 `operator_defs.gd:42-51` 注入的 `k_atk/k_pow/k_kill`）。

### 4.2 规则清单

| 规则 | 检查 | 为什么 | 误报风险 |
| --- | --- | --- | --- |
| R1 | `routes` 键与 `branch` 路线一致；`routes` 前有 `branch`；`bot` 在路线内；每人最多一个 `branch` | 路线 id 对不上则选路线后节点 5 走错或不生效 | 低 |
| R2 | 节点 id 在所有路线生效视图里都不出现（死节点）；`blocks.progression` 有无对应节点的积木；元成长节点不在 `order` / 星图不一致 | 死节点 = 策划以为存在、玩家选不到 | 中：保留作回退的顶层旧线会命中，需 `allow_dead` 白名单 |
| R3 | 缺 elite 节点 / 顺序错；`node:<id>` 指向不可达；`skill_active:N` 超界；`meta_tree` 前置缺失 / 成环 | 精一挂 S3 这类依赖断链 | 低 |
| R4 | 事件无选项；所有选项都带 `need` 或负 `hp_pct`（可能全灰）；`after_cross` 超路口数 | 玩家卡在事件里无路可选 | 中：`_option_ok`（藏品满级过滤）静态判不了，未覆盖 |
| R5 | 引用键与资源存在：`requires.relic` / `doctor_passive`、`$变量`、`icon/tex`、`sfx`、`res://`、事件的藏品 id / 稀有度 / lane / `next`、waves 敌人 id、`relic_effects` ↔ `relics.json` 互查、`relic_<id>` 图标 | 缺图标显示空；缺 id 运行时静默 | 中：动态拼名的资源查不到，靠白名单 |
| R6 | 事件插画 `art/event_cg/hi/<cg 或 id>.webp` 缺失 | 运行时降级为无插画，不是错 | 低；只提示不判失败 |
| R9 | 语音键两位干员都没有 ogg | 运行时静默 | 本次 0 条 |

脚本内置小型 JSON 扫描器取行号，输出 `文件:行号 [键路径] 说明`；有命中退出码 1；`--verbose` 全列。实测 0.07–0.23 秒（含 Python 启动约 0.9 秒）。

### 4.3 现状扫描：真问题

| # | 问题 | 位置 | 说明 |
| --- | --- | --- | --- |
| 1 | **安洁莉娜「致密」在现行成长线选不到**（死节点 + 死积木） | `game/data/characters/angelina.json:455-467`（`id: dense`，带 `alt` 指向 `wide`） | `character.gd:862-866` 的 `node_view` 无条件应用 `alt`，节点 2 恒为「引力扩散」。`levelup/branch` 开关在 `4825643b0`（10-29 死开关清理第 2 批）里被删，`alt` 变恒生效。连带死数据：`blocks.progression.dense`（`angelina.json:863`）、`base.n2_dmg`（`:52`）；docs/120 第 9、240 行与 `angelina.json:69` 的 `_branch` 注释仍写「开关开 / 关」。对战斗数值无影响（×1.15 已拆进路线节点 `route_dmg`），属数据遗留 |
| 2 | 同类：`progression[4]` 顶层 `id: lock` 永不生效 | `angelina.json:501`；死积木 `:890`（在用的是 `lockb`，`:991`） | 节点 4 的 `branch` 一定选路线，节点 5 恒走 `routes` 的 `pull4/lock2` |
| 3 | 路线图标指向不存在的贴图（2 干员 4 处） | `game/data/characters/mizuki.json:515`（`skill_mizuki_s1`）、`:521`（`skill_mizuki_s2`）；`specter_unchained.json:620`（`skill_specter_s1`）、`:626`（`skill_specter_s2`） | 索引里只有 `skill_specter_unchained_s1/s2`；水月技能卡用通用 `skill_s1/s2`；路线卡现在显示空图标 |
| 4 | 藏品 265 缺图标 | `game/data/relics.json:3186`（`items[264]`） | 索引里没有 `relic_265`，而 `relic_effects.json:4583` 有它的效果定义 |

脚本 21 条命中 = R2 2 条 + R5 5 条 + R6 14 条（事件插画，软缺失）。R1 / R3 / R4：0 命中；`meta_tree` 42 个节点前置、`order`、星图全部一致；15 + 15 个事件每个都至少有一个永不灰的选项。R6 的 14 条是 `events_v2.json` 里无插画 webp 的事件（task、expedition、vanguard、sellout、boxes、shelter、craft、wish_v2、penance、dream、feeding、feeding_2、homecoming、scholar），是否补美术待确认。**其余干员只有安洁莉娜用 `alt`**。

脚本曾误报并已修：`$k_pow/$k_atk/$k_kill` 白名单、`sfx` 的 wav 命名口径（`op_<干员>_<kind>.wav`）、waves 的敌人 id 层级。

## 5. 测试卫生

### 5.1 Bal 缓存还原

`082bec20b`（分支 `claude/bal-cache-tests`）：`balance.gd` 新增 `Bal.clear_cache()`；`command_wheel_cases`、`prot_test` 在还原后清缓存，`prot_test.ok()` 每条断言后清一次。**尚未合入 integ-1029**。

| 问题 | 方案 |
| --- | --- |
| 合并 | 协调人 cherry-pick `082bec20b`（只动 `balance.gd`、2 个测试、docs/199）；别用 `reset --soft main` 整理（见记忆） |
| 其他持有 sec / `_data` 引用的测试 | 19 个文件引用 `Bal._data / Bal.set / Bal.sec`（grep `game/tests/`），逐个核；统一测试夹具 `BalGuard`：进入时快照 `_data`，退出时还原并 `clear_cache()`；`ok()` 不再每条清缓存 |
| 防再犯 | core 之后加断言：每个测试进程结束时 `Bal` 数据哈希与启动时一致，否则该测试红（成本 <1 秒） |

### 5.2 互相污染

| 共享资源 | 现状 | 处理 |
| --- | --- | --- |
| `user://`（存档） | 仅 3 个测试直接引用（`pad_sim.gd:34`、`save_migrate_test.gd:3`、`touch_layout_test.gd:7`），声明不碰 settings.cfg | `godot_runner` 层给所有测试进程统一注入临时 user 目录，一次性消灭 |
| `runs.jsonl` 玩家对局记录 | `15c761f4d` 已修：tests/ 下场景一律拦下 | 加一条回归：测试结束时 user 目录 `runs.jsonl` 大小不变 |
| build 缓存（`_cache_key`，`check.py:347`） | key 含 args + scope 哈希；`LOGIC_TAGS`（`:281`）决定逻辑 / 全量哈希 | 风险：scope 哈希漏依赖而命中旧缓存。每次全量随机取 3 项绕过缓存重跑比对 |
| 全局单例（`Bal`、`Cfg`…） | 每个测试一个 Godot 进程，天然隔离；污染只发生在**同进程多用例**的测试（`prot_test` 417 条、`card_desc_test`） | 夹具还原（§5.1）；合并重复进程（§1.2）前先有夹具 |

### 5.3 随机种子

`game/tests/` 里未走 `g.rng` 的随机相关调用共 21 处：仅 `sprite_batch_bench.gd:70`（`randf() < 0.01`，性能基准）是全局随机；其余为带种子的 `RandomNumberGenerator`（`gem_size_capture`、`grains_bench`）或 `game.shuffle(...)`（`build_affinity_test.gd:150/164/177`，走 game 的 rng，随 `--seed`）。**测试面种子基本规范，不需大修；`sprite_batch_bench` 不进检查。** 游戏脚本里的未走 `g.rng` 随机是另一条审计，不在本方案内（复现项已覆盖表现：同参数两次结果须逐字段相同）。

### 5.4 红项登记制度（`tools/known_red.json`）

```json
{"items": [
  {"name": "主控保护 prot_test 满血保护 11 条", "since": "2026-10-29", "owner": "测试与验收",
   "reason": "docs/178 调值，测试钉旧值；修复见 082bec20b，待合入", "due": "2026-11-02"}
]}
```

| 规则 | 行为 |
| --- | --- |
| 项名对上汇总里的失败项 | 汇总单列「已知红（N 项）」，不算新失败；退出码为 0 当且仅当失败全在登记且未过期 |
| `due` 过期仍红 | 变硬失败，输出「已知红 X 已过期 N 天，负责人 Y」 |
| 登记项实际已绿 | 提示「可从 known_red.json 删除」，不失败 |
| 无 owner / 无 due | 加载时直接报错：不允许无人认领 |
| 最长期限 | 14 天；续期须改文件，可 diff 审查 |
| 谁改 | 任何会话可新增；删除由负责人；协调人合入时扫一眼 |

CI（`ci/<sha>`）汇总同样读该文件；`last_quick.txt` 末尾打印「已知红 / 过期红」两行供推送使用。

## 6. 分期

| 期 | 做什么 | 工作量 | 风险 | 验收（可量化） |
| --- | --- | --- | --- | --- |
| **1** | 红项登记（`known_red.json` + check.py 汇总，约 60 行）；`_run` 统一记每项秒数进汇总；修三项点名红（合入 `082bec20b`、data_lint 前缀豁免、command_ai 核实）；接入孤儿测试 2 个；`graph_lint.py` 进 S 组（原型已有） | 1 会话 / 1 天 | 低：只加不删。graph_lint 现有 7 条硬命中（R2 2 + R5 5）需先修数据或进白名单，否则快检第一次就红 | 云端全量红项 = 0（已知红单列）；汇总含每项耗时；graph_lint 进快检且 <1 秒；孤儿测试 0 |
| **2** | `--changed` + `tools/check_map.json`（§2.3）；SCENE_REGRESSIONS 归组自检；合并重复进程（response ×9、synergy ×4 起） | 1–2 会话 / 2 天 | 中：漏映射导致该跑的没跑。缓解：未知路径保守跑 core + smoke-sample；合入 CI 全量兜底；上线首周 `--changed` 与 `--auto` 并行输出两份计划对照 | 5 类典型改动本地快检实测中位：改藏品 ≤1.5 分钟、改 UI ≤2 分钟、改 Boss ≤4 分钟；`--changed` 漏选率（对照合入 CI 的红项）0 次 / 首 20 次合入 |
| **3** | `text_reconcile.py` 静态对账：藏品 243 + 升级卡 19 + 局外 40 + 勋章 / 练习编队 / 敌人 / 指南；`reconcile_test.gd` B 档；四套填充函数收敛 | 2 会话 / 3–4 天 | 中：藏品 desc 口径多，一次性建 check 声明工作量大（估计约一半可由 effects 键自动推出，其余人工）；先 warn 后 fail | 覆盖率 ≥70%；回归注入：把一张卡的 value 改 10% 能被报出；A 档全程 <10 秒 |

**先做的三件（按收益）**：期 1 红项登记 + 修三项红（低风险，让云端回到全绿并杜绝无人认领）→ 期 2 `--changed`（直接回答「节约快检时间」）→ 期 3 藏品 / 升级卡对账（直接回答「数值与实际对不上」）。

## 7. 未决

1. 3 项在 `ci/7306d6bf1` 红但无分日志（伊莎玛拉二阶段、偏执泡影、op_pacing）：需云端补推日志才能定因。
2. 安洁莉娜「致密」：设计决定恢复可选还是删（本方案只出报警）。
3. 事件插画 14 张：美术是否补，决定 R6 是否升级为错。
4. `--changed` 取代 `--auto` 的口径：涉及 docs/36 §1 与 AGENTS.md 里 `--auto` 的写法；AGENTS.md 属入口文件，改动须用户直接确认。
5. 文档编号 204 取自本分支视角；合入时若撞号由协调人顺延。

## 8. 实装记录与白名单（第 1 期，10-30）

| 项 | 做法 / 实测 |
| --- | --- |
| 红项登记 | `tools/known_red.py` + `tools/known_red.json`；check.py 汇总单列「已知红」，过期仍红转硬失败，owner / reason / due 缺一报错，期限 ≤ 14 天 |
| 每项耗时 | `_run` 累计占用 Godot 的秒数（不含排队）；汇总每项后缀 `[N 秒]`，末尾「耗时前 10」，另写 `build/check/last_quick.json` |
| prot 11 条 | 合入 `082bec20b`（cherry-pick，实际为 `79158f570`）。冲突：integ-1029 已撤回 Bal.v 缓存（`87e0d852f`），故 `Bal.clear_cache()` 只留空操作入口，docs/199 不恢复。`--only prot`：400 checks 0 failed（40 秒） |
| command_ai side 0 | 本分支实测 `COMMAND_AI checks=70 failures=0`（6 秒）：那条红来自 Bal 读取缓存（`6cf116560` 的原因说明），缓存撤回后本线不红，**不动**；`6cf116560` 仍在 `claude/command-point`，若缓存日后恢复需带上 |
| data_lint `spd_all_k_` | `BAL_CALL` 捕获「字面后跟 `+`」，按前缀处理：不进拼错比对，json 里同前缀的叶子不算未读 |
| 孤儿测试 | `card_desc_fit_test.gd`（`--script` 式）接入 SCENE_REGRESSIONS，`check_scene` 支持 `.gd` 测试，实测 `cut=0 failures=0`（4 秒）。`bgm_memory_test` 是网页导出后在浏览器里跑的（文件头注释），不是 headless 测试，**不接入**，登记为「仅网页手测」 |
| graph_lint | 进快检 S 组（`--only graph_lint`），实测约 1 秒（含启动）；R6 / R9 只提示 |
| 云端分项日志 | `tools/cloud/ci_pack.sh`：跑 check.py 后把本次 `quick_*/` 每项日志收进 `build/ci_logs/`，与 `ci_check.log` 一起推回结果分支。之前 `ci/<sha>` 只推汇总，红项无分日志；**触发云端任务的提示词需改为调用该脚本**（该提示词不在仓库，协调人处） |

**白名单与待办清单**（`known_red.json`，到期 2026-11-12，到期仍在则快检硬失败）

| 命中 | 负责 | 说明 |
| --- | --- | --- |
| `angelina.json:455` 致密节点被 `alt` 恒覆盖，现行成长线选不到 | 成长会话 | 恢复可选还是删由设计定；连带 `blocks.progression.dense`（:863）、`base.n2_dmg`（:52）、docs/120 与 `_branch` 注释 |
| `angelina.json:501` 节点 4 顶层 `lock` 永不生效 | 成长会话 | 死积木 `:890`，在用的是 `lockb`（:991） |
| `mizuki.json:515 / 521` 路线图标 `skill_mizuki_s1 / s2` 缺 | 界面 / 美术会话 | 技能卡用通用 `skill_s1/s2`，路线卡图标为空 |
| `specter_unchained.json:620 / 626` 路线图标 `skill_specter_s1 / s2` 缺 | 界面 / 美术会话 | 索引里是 `skill_specter_unchained_s1/s2` |
| `relics.json:3186` 藏品 265 缺 `relic_265` 图标 | 界面 / 美术会话 | `relic_effects.json:4583` 已有效果定义 |

## 9. 第 2 期实装记录（`--changed`，10-30）

| 项 | 做法 / 实测 |
| --- | --- |
| 入口 | `check.py --changed [BASE]`；`--auto` 保留为别名；`--explain` 只打印计划并对照旧 `--auto` 计划；`--assume-files a,b` 假定这些文件被改了（量耗时 / 演示）。用法写进 docs/36 §1.5，AGENTS.md / CLAUDE.md 未动 |
| 基线 | 缺省 = `origin/claude/integ-1029` / `origin/main` / `main` 里离 HEAD 最近的 merge-base（`default_base`）。旧口径只和 main 比，在集成分支上切出的工作树会得到 11913 个「改动文件」，永远是全量 |
| 规则 | `tools/check_map.json`：先匹配先生效的 glob 规则 + `escalate`（全局公共文件 → 分支全量）+ `unknown`（core + 抽样冒烟，并点名未映射路径）+ 场景分组 + 干员场景（还按场景参数里的 `--op/--squad` 自动关联，如 mizuki 改动会带上含 mizuki 的 response_p2e / synergy 场景）。引擎 `tools/check_plan.py` |
| 自检 | `check_map` 静态项：123 个场景回归键全部归组，规则里的组名、场景名都存在；新增回归项没归组即报错 |
| 实测（`--changed --assume-files`，jobs 2，`--nocache`，机器有其他会话在跑 Godot） | 改藏品 `relic_effects.json`：25 项 **82 秒**；改 UI `hud.gd`：38 项 **136 秒**；改单干员 `mizuki.json`：26 项 **144 秒**；改 Boss `ishar.gd`：36 项 **153 秒**。四次均 0 失败 |
| 与方案预计 | 方案估计 藏品 1–1.5 分钟 / UI 1.5–2 分钟 / 单干员 1.5–2.5 分钟 / Boss 3–4 分钟；实测落在区间内或更低（Boss 2.6 分钟、藏品 1.4 分钟）。这些时间含约 11 个静态项（art_lint 约 35–41 秒是最大一项） |
| 合并重复进程 | **没做**：response ×9 / synergy ×4 等每个用例是独立的编队 / 干员配置，要合并得在一个 SceneTree 里反复拆建整局，风险大于收益（单进程启动固定开销只有数秒，慢的是各自的 90–400 秒局内流程）。改成「按改动只选相关用例」：`--changed` 靠干员关联只跑含该干员的 response / synergy 用例，这才是实际省时的部分 |
| 未做（留给后续） | `ishar_human_ui` 单项 420 秒（L26）仍是最慢项，和 `boss_trial_ui` 是同一脚本带不同参数，值得单独看为什么慢 |
