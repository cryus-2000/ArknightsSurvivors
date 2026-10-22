# Codex 全权接手：架构与代码规范（2026-10-22）

> 用户 10-22 定：协调人（Claude）写清架构与规范后，**剩余工作全权交 Codex**（代码 + 美术）。本文是入口：先读这一页，再按链接读原文。Codex 在 `codex/<topic>` 分支改代码（docs/106 §6），做完报提交号；协调人（或用户）合 main、出包、发布。

## 0. 必读顺序（1 小时）

1. `AGENTS.md`（协作铁律：静音、不弹窗、只提交自己的文件、同 seed、快检）→ `docs/41_agent_team.md` §5。
2. `docs/106_codebase_overview_for_codex.md`（代码库总览 + §6 Codex 改代码规则）。
3. `docs/39_code_architecture.md`（目录、模块写法、界面层约定、干员接口层、HUD 缓存层约定 §8）。
4. `docs/126_arch_review_1022.md`（10-22 架构复审：各类内容要碰几处、已做 / 未做清单、§9 测量）。
5. 领域契约：`docs/108_operator_runtime_arch.md`（干员积木 / 动画契约）、`docs/36_testing.md`（测试分层）、`docs/76_language_style.md`（文案）、`docs/37` / `docs/62`（UI 风格 / 动效）、`docs/104`（像素流程）、`docs/33`（双版本发布）。

## 1. 架构一页

- **引擎**：Godot 4.7，GDScript 为主；原生 EnemyCore 原型已合但非主路径。三端：桌面（原生）、网页（itch / B站 Toy，壳在 `build/_web/src`，JS↔GD 桥 `__syCloud` / `__syToy`）。
- **主循环**：`game.gd`（局内总控，开局段已拆到 `run/run_setup.gd`、局终 `run/run_end.gd`）；世界绘制 `render/world.gd` + `render/enemy_atlas.gd`；HUD `screens/hud*.gd`（13 张有序子画布，缓存层 `hud._layer(key, 签名, 绘制函数)`——新块缺省每帧画，想省性能再写签名，docs/39 §8）。
- **数据驱动边界**（docs/126 §1）：干员 `data/characters/<id>.json`（积木语义见 docs/108，`character.gd` → `operator_defs.gd` / `operator_validate.gd`）；敌人 `data/enemies.json`（特殊机制、Boss 登记、名片 / 头像裁切都在 json）；波次 `data/waves.json`；升级卡 `data/cards.json`；藏品 `relics.json` + `relic_effects.json`（代码用 `has_relic('名')`）；局外树 `data/meta_tree.json`；平衡表 `data/balance.json`（`Bal.v`，读不到走缺省，`tools/data_lint.py` 抓拼错键）。
- **局外**：标题 `title.gd` + `title_base.gd` / `title_op_pick.gd` / `title_diff_pick.gd`（菜单在 `title_tiles.gd MENU` 表）；难度 `difficulty_screen.gd`；设置 `settings_shell.gd` + `settings_panel.gd`；寻访 `headhunt.gd`（规则 `core/roster.gd`，由 `tick()` 在主循环判定打开，HUD 只画）；结算 `settlement_screen.gd`；认知塑造 `meta_tree_ui.gd`（规则 `core/meta.gd`）；视觉语言常量 `screens/hh_style.gd`；转场 `headhunt.gd _draw_trans`。
- **存档**：`settings.gd`（`_read_cfg` / 逐版本 `_migrate_progress`，样本测试 `tests/save_migrate_test.gd`）；云存档 `core/cloud_save.gd`（docs/89）。
- **确定性**：玩法随机只用 `g.rng`（`g._shuffle`），画面随机用 `g.vrng`；同 seed TRACE 必须逐行相同（`tools/trace_base.py --here`）；纯画面改动也要跑一局核。

## 2. 代码规范（硬）

1. **不弹窗**：Godot 一律 `--headless`；必须带窗口只走 `tools/godot_runner.py`，静音 `--audio-driver Dummy`。
2. **提交只含自己的文件**；`.gd.uid` 随脚本同一提交；不提交 `game/tests/golden_current`（金样过期由协调人在 main 重录）；不提交 build/、.godot/。
3. **快检**：改游戏代码 / 数据前后跑 `python tools/check.py --auto --jobs 3`，输出进文件看 rc；只允许「积木等价金样过期」一项挂。
4. **命令行参数**只经 `Cfg.dev_args()`（发布包禁止直接读 `OS.get_cmdline_user_args()`，`tools/check_release.py` 会拦）。
5. **界面**：新局外屏 = 一个 `screens/<name>.gd`，`tick()` / `draw()` / `input()` 三入口挂进 title / game 现有调用点；**不往 `hud.gd` 挂逻辑**；视觉用 `hh_style.gd` 常量；文案按 docs/76（队长不写主控；数值在前、一句一条）。
6. **干员 / 敌人 / 藏品**：先用现有积木与 json 字段；要新积木先写 docs/108 契约节再实现；`validate_operator` / `data_lint` 必过。
7. **数值改动**：云端批跑（docs/36 §7.5.1：≥3 份实现 × 56 局均值，单份 ±6 点）；胜率差 < 10 点不下结论；记录进 docs/111 / 116。
8. **风格**：注释 / 文档中文，术语按 docs/76 表；函数短、数据表优先于分支；画面与逻辑分离（渲染层只写纯画面字段）。

## 3. 当前未完成清单（接手即做，按优先级）

| # | 事项 | 现状 / 入口 |
|---|---|---|
| 1 | 主界面 B 版实装 | Claude 界面会话在 `claude/title-b` 做占位版；若未交，Codex 按 docs/125 §7 + `codex_task_title_bg_1022.md`（背景分层契约）自己做；背景美术也是 Codex 的单 |
| 2 | 网页开局掉帧预热 + 自动档封顶「中」 | `claude/web-warmup`（性能会话），未交则 Codex 做：着色器 / 贴图 / 音效在加载页末预热 |
| 3 | 触屏布局 C6 | `claude/touch-layout`（架构会话） |
| 4 | Toy 真机验证 + 发布 | 包 `build/toy/`；SDK 桥 docs/22「Toy 接入」节；用户用 /toy 发布 |
| 5 | 帧率第二轮 | docs/50 §22.4 候选；目标网页手机口径 p95 ≤ 20 ms；绘制侧 SpriteBatch 方向（docs/101） |
| 6 | docs/126 剩余项 | A3 / A4 / A6 / C7（下一个 Boss / 特殊敌人进来时顺手做）、R3 TRACE 加队友聚合（改格式，合批到统一重录时机） |
| 7 | 干员动作复查 | 滑步探针 `tools/probes/anim_slide_probe.py` 余下 622 帧按设计；攻速压缩下帧可读性未查（memory pending-op-pacing-audit） |
| 8 | 语音 | 已接 20 人；寻访不配音；新干员按 `audio/voice/<id>_<key>.ogg` 约定 |

## 4. 发布流程（协调人 / 用户）

`release_all.py --ref <sha>`（三包 + 网页）→ `deploy_itch.py --ref <sha> --apply --confirm <sha>`；对内包 `--only internal`；Toy 包见 docs/22。发布前快检必须 0 失败，`verify_encrypted_game.py` 断言：对外包名册开局 5 人、图鉴按名册锁定；对内包名册 5 人 + 20 凭证、图鉴 / 难度全开。
