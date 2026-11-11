# 335 · 全流程 debug 与内存释放测试（11-12）

用户原话：「进行一轮全部的 debug 和测试，确保所有的流程都是没问题的，内存都是正常释放的」。基线：`claude/integ-1111`（577f916b1）。

## 1. 结果摘要

| 项 | 结论 |
|---|---|
| 全量快检（GCP `ci-flowdbg-1112`，提交 7533d409d） | 210 项通过、0 失败（含本轮新增 2 项）；结果分支 `cloud-results/ci-flowdbg-1112` |
| 反复进出 10 轮内存释放 | 发现并修了 1 处泄漏（见 §3）；修后节点数、孤儿节点、资源数、静态内存全部持平 |
| 对外版 | 发行包原来带着 `auto_play.gd`、`god_suite.gd`（只有 `bot.gd` 被剔除），已一并剔除；加密包验证探针新增「测试脚本不在包里、无敌 / 自动开关恒关」 |

## 2. 新增自动化（都进快检 `SCENE_REGRESSIONS`，`check_map.json` 归「界面」组）

- `lifecycle_cycle`（`tests/lifecycle_cycle_test.gd`）：同一进程内 10 轮「标题（选人 / 难度 / 图鉴 / 寻访 / 认知塑造 / 蚀刻章 / 设置 / 操作说明 / 致谢 / Boss 演练各开关）→ 销毁标题 → 开局跑一小段 → 暂停 / 设置 / 属性 / 胜利结算 / 作战记录 / 对局记录 / 失败结算 → 销毁对局」。每轮读 `Performance` 的节点数、孤儿节点、对象数、资源数、静态内存和 `Art._cache` 条数，第 2 轮作基线：节点 ≤ +8、资源 ≤ +40、贴图缓存 ≤ +4、孤儿节点必须为 0、静态内存 ≤ 105%。调试参数：`--cycles=N`、`--titleonly`、`--gameonly`、`--screen=<屏名|none>`、`--orphans`（打印孤儿节点）。
- `flow_sweep`（`tests/flow_sweep_test.gd`）：设置面板每一行各向调一次后还原、性能报告页与触屏布局页能开能关回设置、五个标签页逐个切、返回行；局内暂停菜单的设置 / 指南 / 演示 / 属性 / 继续各走一次。

## 3. 发现并修好的问题

1. **选卡面板「婉拒」按钮每局漏一个孤儿节点**（`screens/choice_panel.gd`）：`decline_btn` 在面板构造时 `Button.new()`，只有强制招募时才挂进树，其余局从头到尾是不在树上的节点，对局销毁时没人释放——每开一局漏一个 `Button`（再来一局、回标题再开局都累加）。新增 `release()`，`game._exit_tree` 里调用。测试里修前 10 轮孤儿节点 0→10，修后恒 0。
2. **发行包带着测试功能脚本**：`export_presets.cfg` 只剔除 `bot.gd`，`run/auto_play.gd`（自动模式）与 `core/god_suite.gd`（四 Boss 连测）仍在对外 / 对内包里（都有 `Cfg.test_god` 之类开关挡着，正式包跑不到，但不该在包里）。已加进 `release_slim.DEV_SCRIPTS` 与两个导出预设；`export_web.py --god` 把三者都保留。为此 `perf_report.gd` 的静态 `preload(god_suite)` 改成 `Cfg.test_suite()` 下的运行时 `load`，`game.gd` 加载 `auto_play.gd` 前先判 `Cfg.test_auto()`（否则发行包里 `load` 返回空会崩）。
3. 加密包验证探针（`tools/verify_encrypted_game.py`）新增：`bot / auto_play / god_suite / autotest / motion_shot / ult_bench` 在包内都不存在、`test_god / test_auto / test_suite / test_loop` 恒为假。本轮对 36e153822 导出的对外加密包跑过：通过，包体 pck 105.34 MB，打包后启动正常。

## 4. 内存读数说明

- 每轮对象数仍缓慢上涨，但不是泄漏：`ui.gd` 的 `_rbox_cache`（上限 400）与 `_wrap_cache`（上限 512）在前几十轮才填满。选人页单屏 40 轮对象数 2536 → 2817，后段增速趋近 0，静态内存 40 轮只 +0.9 MiB。对象数容差因此放宽到 +450，节点 / 孤儿 / 资源保持严格。
- 无头测试用 Dummy 渲染器，显存读数恒为 0；贴图驻留靠 `Art._cache` 条数与 `PF RUNRELEASE` 日志（每局释放 1100+ 张）间接看。真实显存与 WASM 堆只能在网页 / 真机的性能报告里看（docs/333 的 `boss=all` 连测，iPhone 已稳定 286 MiB）。

## 5. 流程覆盖对照

| 流程 | 覆盖 |
|---|---|
| 标题与各屏进出 | `ui_smoke`、`lifecycle_cycle`、`title_menu_input`（键鼠 / 手柄 / 触屏） |
| 开局、升级 / 藏品 / 招募 / 商人 / 事件 / 精英化 | 机器人矩阵与每干员冒烟（自然流程）、`recruit_offer`、`merchant_build_offer`、各专项回归 |
| 中期 / 最终 Boss | `boss_*`、`mid_boss`、`route_knight` 等回归；iPhone 四 Boss 连测（docs/333） |
| 胜利 / 阵亡结算、作战记录、对局记录 | `ui_smoke`、`run_stats_test`、`lifecycle_cycle` |
| 暂停菜单、设置每一项 | `flow_sweep`（新）、`ui_smoke` |
| 新手引导、Boss 演练 | `onboard_forced`、`tour`、`boss_trial`、`boss_trial_ui` |
| 触屏 / 手柄 | `touch_layout`、`touch_move`、`touch_command`、`event_touch_layout`、`shop_touch_layout`、`title_menu_input`、`op_select_input` |

## 6. 没做 / 没修

- **「再来一局 / 回标题」的真换场景路径**（`reload_current_scene` / `change_scene_to_file`）无头测试里会杀掉测试自身，只测了对局销毁与重建（lifecycle_cycle），换场景本身靠桌面手玩与手机连测（局间整页重载）。
- **对外版「打完一局」**：发行包不带机器人，没法无人值守跑完；本轮只做了加密包验证探针 + 启动冒烟，一整局的玩法靠同源代码的调试版冒烟 / 机器人矩阵覆盖。需要时由真人在对外包里打一局。
- **网页 / 真机的反复进出读数**：本轮没有部署新的无敌包，没拿到网页端局外界面反复进出后的 WASM 堆曲线；建议下一版无敌包合入后在 iPhone 上用 `?auto=1&boss=all` 之外再手点几轮「图鉴 / 寻访 → 标题」对照。
- 全量批跑里金样重录输出（`golden/`）未提交，按口径由协调人合入后统一重录。
