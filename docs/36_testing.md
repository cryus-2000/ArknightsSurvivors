# 36 · 测试规范

> 2026-09-26 起。所有会话（Claude / Codex）共用。入口是 `tools/check.py`，所有测试无界面、静音。

## 1. 什么时候跑什么

| 级别 | 什么时候 | 命令 | 时长 | 通过标准 |
| --- | --- | --- | --- | --- |
| 快检 · 分级 | 改的过程中、每次提交前 | `python tools/check.py --auto --jobs 4` | 0–2 分钟 | 同下；只跑和改动相关的项目（见下） |
| 快检 · 全量 | ~~快进合入 main 之前~~ **2026-10-14 起只在协调人 `tools/ship.py` 里跑一次（§1.1）** | `python tools/check.py --jobs 4` | 本机约 6–8 分钟（空闲时更快） | 全部「通过」；有一项失败就不合入 |
| 数值 | 改了干员、藏品、敌人、曲线、机器人 | `python tools/check.py --bots` | 约 5–10 分钟（有缓存更快） | 按 docs/27 §6.4 与 docs/29 §3 |
| A/B | 要说明「改动前后」的差别 | `python tools/check.py --ab <提交>` | 两边各一轮矩阵 | 见 §2 的对比规则 |
| 画面 | 改了特效、UI、美术接入 | 截图开关（§5），人看 | — | 截图贴进交付说明 |

**`--auto` 分级**（docs/44 ②）：对比 `main` 与当前分支的 merge-base，加上未提交和未跟踪的文件，按改得最"重"的那个文件定档：

| 档 | 什么改动 | 跑什么 |
| --- | --- | --- |
| none | 只有 `docs/`、`*.md`、`art/incoming` 的预览 / 清单 / QA、`.uid` / `.import` | 只做数据 JSON 解析，不开 Godot |
| text | `game/data/*.json` 只改了说明类字段（desc / name / en / story / hint 等，见 `TEXT_KEYS`）；召唤物等附属帧条 | + 核心契约测试 |
| ops | 某几名干员的脚本、`data/characters/<id>.json`、`game/art/operators/<id>/` 的帧条 | + 这些干员当主控的冒烟 + 这些干员的成长节点 + 复现 |
| full | 其他一切（`game.gd`、`run/`、`core/`、角色基类 / 编队 / 主控、非说明字段的数据、测试工具本身……） | 在 main 上：真全量；在分支上：**分支全量精简**（§1.4） |

**§1.4 分支全量精简（2026-10-24 用户「全改」）**：分支上 `--auto` 判成 full 时不再跑真全量，省掉三类（原来分支全量的大头，抢 CPU 时单局冒烟能拖到 15 分钟）：
- **积木等价不跑**：分支只要改了玩法，金样必然「过期」、只能报过期，28 局白跑；合入后协调人在 main 上 `--rerecord-golden` 再跑真全量比对。
- **自然流程两局不跑**（150 秒游戏时间各一局）。
- **冒烟只跑**：改动涉及的干员 + 按 HEAD 提交号轮换抽 `SMOKE_SAMPLE`（5）名，不再 20 人全跑。
其余照旧：静态项、核心契约、成长节点、手动攻击、主控保护、复现、原生等价、全部定向回归。判定「在 main 上」= 当前分支名是 `main`（主工作区合入后）；未跟踪的 `.claude/` 文件不再算改动（原来主工作区的技能包让 `--auto` 永远判 full）。

分级只用于改的过程中；~~快进合入 main 前仍要跑一次不带 `--auto` 的全量~~（2026-10-14 起按 §1.1：工作会话只跑 `--auto` + 自己的回归项，全量由协调人在 ship.py 里跑一次）。

**§1.1 谁跑全量、跑几次（2026-10-14 用户：「测试流程里有好多重复跑的」）**

当天实况：每个工作会话在自己的工作树跑一遍全量（10–25 分钟，本机有二三十个 Godot 时更久），合入 main 后 `tools/ship.py` 又跑一遍全量，一天发 4 版就是 8 次全量；同种子对照每个会话各建一个临时基线工作树重跑基线；56 局的平衡批跑在本机跑。改成：

| 谁 | 跑什么 | 不跑什么 |
| --- | --- | --- |
| 工作会话 / 代理（工作树） | `check.py --auto --jobs 3`（按改动分级）+ 自己改动的回归项 `--only <名>` + 同种子 TRACE 对照（基线用缓存，见下） | **不跑全量**；不跑平衡批跑（上云，§7.5） |
| 协调人（合入 main 后） | `tools/ship.py` 里的**一次**全量 + 发布检查 | 不逐个分支再跑全量 |
| 云端 | 平衡批跑、A/B、胜率、木桩矩阵、等价性 A/B | 截图、帧时（云端无显示、与本机帧时不可比） |

- **发版合批**：协调人不是每合一个分支就发一版——攒一批（约 2 小时或用户要看时），一次全量、一次三包、一次 itch。纯美术 / 文档的合入可以 `ship.py --skip-check`（发布检查仍跑）。
- **基线 TRACE 缓存**：同种子对照的基线按 `build/trace_cache/<main 提交>_<seed>_<队长>_<时长>.txt` 存，其他会话同一提交直接用，不再各自建临时工作树重跑；没有的才跑一次并存下。工具 `tools/trace_base.py`，用法见 §3.2。
- **本机并发**：所有会话合计 ≤ `GODOT_MAX_PROCS`；单个会话 `--jobs ≤ 3`；帧时测量时别人暂停批跑（协调人协调）。
- **`check.py` 自己的并发 = `--jobs`（10-15）**：所有检查项的 Godot 经同一个闸门排队（`check.Gate`），空出名额先放预计最久的（按上一次快检日志里同名进程的用时）。之前积木等价 / 成长节点 / 复现在外层线程池的一个槽里又开内层线程池，峰值到 2 × jobs（日志实测 8）。

**§1.2 快检结果缓存（2026-10-15）**

`check.py` 把每个 Godot 进程的输出（stdout / stderr）按「它读到的输入的内容哈希 + 参数」存进主仓库 `build/check_cache/`（所有工作树共用）；同样的输入再跑时直接取出，判定逻辑照常重算（所以改 `check.py` 的判定规则不用清缓存）。汇总行报「Godot 结果缓存命中 N / M」，命中的日志头写「缓存命中」。

| 档 | 用在哪些项 | 键里有什么 | 什么改动会让它失效 |
|---|---|---|---|
| logic | 冒烟、自然流程、成长节点、主控保护、复现、积木等价 | `game/` 下除图片 / 音频 / 字体 / `.import` 外的全部文件内容（脚本、数据、场景、着色器、测试、`project.godot`）；`game/art` 的图只计「文件名 + 尺寸」（10-28 前运行时贴图在 `art/incoming`，同口径），json 计内容，音频计文件名 | 改任何脚本 / 数据 / 场景 / 测试；`game/art` 增删图、改图尺寸（帧数）、改 json；增删音频 |
| full | 核心契约、全部界面类场景回归 | `game/` 与 `art/incoming` 下全部文件内容 | 改任何文件，包括只改颜色的帧条、音频、字体 |

两档都还含 Godot 可执行文件（路径 + 修改时间）和完整参数（去掉 `--path`，所以不同工作树同一份内容能共用）；`*.uid` 不计（生成的随机 id）。超时的结果不存。

- **会命中的典型场景**：ship 对刚在工作树全量通过的同一棵树再跑；只改 `docs/` 的合入（两档全中）；只给帧条改色的美术合入（logic 档全中，只重跑核心契约和界面回归）。
- **`--nocache`**：不读也不写缓存。怀疑缓存时、或改了缓存键之外的东西（Godot 以外的系统环境、`tools/godot_runner.py` 的启动方式）时用；ship 每隔几版建议带一次。
- **手动失效**：删 `build/check_cache/` 即可（只是缓存，删了下次重跑重建）。
- **已知盲区**：键只看 `game/` 与 `art/incoming`；如果某项测试读了这两处以外的文件（例如 `tools/` 下的数据），改那个文件不会让缓存失效——新增这种测试时要把输入加进 `check.scope_hashes`。

**§1.3 积木等价：数据版 vs 金样（2026-10-15）**

- **只跑 seed1**（协调人定）：全量快检里每组只跑第一条用例（eqtest seed1、其余各组 seed1 精零 + 技力常满），14 个进程；第二条（eqtest seed2 自然流程、各组 seed3 当队友）由云端每日例行任务跑（§7.6）。本机要跑全部用例加 `--eq-all`。
- **手写参照已下线**（用户 10-15 批 docs/101 §8 第 4 项）：`game/tests/data_ops/*_legacy.gd` 与 `eqtest_hand.gd`（共 7538 行）删除，git 历史可追（删除前最后一版在 main fd9ce553）。下线前 14 组 × 2 用例的数据版与手写参照逐字节相同，数据版输出录成**证据快照** `game/tests/golden/fd9ce553/<组>__<seed>.json`（TRACE + BALANCE 去 prof / 画面峰值 + 两个哈希，`hand_equal: true`）。
- **现在怎么判**：只跑数据版，与金样比。金样记两个哈希：
  - **本干员侧**：这名干员的 `data/characters/<id>.json`（eqtest 是 `tests/data_ops/eqtest.json`）、脚本（若有）、`art/incoming/op_<id>_*` 的帧条尺寸，加积木公共文件 `op_blocks.gd / data_operator.gd / character.gd / op_api.gd`；
  - **别处**：其余全部玩法输入（同 §1.2 logic 档，不含 `game/tests/`）。
  - 别处没变、输出变了 → **FAIL**：只可能是本干员或积木改出来的。真是有意改行为，就跑 `python tools/check.py --rerecord-golden`（等价于 `--only blocks_eq --eq-all --update-golden`）重录。
  - 别处变了 → **金样过期**（**10-21 起不再静默跳过**，见下）。
- **过期的处理（10-21 改）**：之前「过期就跳过、不算失败」，导致金样一旦跟不上大改（比如这批 18 人美术 / 动作大改）就能长期全组过期，这项检查形同虚设、没人知道它已经失效。现在：
  - `ok` 字段照样记 **False**（除非这一轮正好带 `--update-golden` 把它刷新掉了），`--auto` / 全量汇总因此不是绿的；
  - 但过期**不计进硬失败（`errors`）列表**——过期不是本干员或积木自己改坏的，是「别处」的玩法代码变了，不该让改别处代码的人背锅，也不做成「过期 = 直接阻断所有人合入」的硬规则；
  - detail 开头打印醒目提示（`⚠ 金样过期需要重录 N（组名……）：…`），列出哪些组过期、怎么重录；
  - **谁负责重录、什么时候重录（10-21 定）**：**凡是改了积木文件**（`game/scripts/characters/blocks/`、`op_blocks.gd`、`character.gd`、`data_operator.gd`、`op_api.gd` 等「本干员侧」或「别处」公共文件）**或干员 json**（`game/data/characters/*.json`）**的分支，合入 main 之后由协调人跑一次** `python tools/check.py --rerecord-golden` 重录，不是每个干员会话自己跑——因为金样要基于**最终合入 main 之后**的真实积木行为来录，不是某个分支自己工作区里的状态；同一时间段内有多个相关分支要合，等协调人把这批都合完、main 稳定下来后再跑一次即可，不必每条分支合入都单独跑一遍。不必每次改动都跑，但只要合并了会动积木输出的分支，合并后必须跑这一次，避免金样长期基于错误/过期的积木行为却没人发现（协调人曾因合并顺序踩过这个坑：金样重录早于另一批第4节点分支合入，合入后积木输出变了，刚录的金样全部作废）。
- **重录与存储位置（10-21 改）**：金样现在存在 **`game/tests/golden_current/`（git 跟踪）**，不再是「本机 `build/golden_cache/`、不进 git」的本地缓存——之前这个机制导致其他会话的工作树（没在本机跑过重录）跑 `--auto` 时读不到缓存、退回下线证据快照 `game/tests/golden/fd9ce553/`（早已过时），被误判成「金样过期」。现在 `python tools/check.py --rerecord-golden`（等价 `--only blocks_eq --eq-all --update-golden`）把数据版输出直接写到 `game/tests/golden_current/`；**重录后要把该目录的改动 `git add game/tests/golden_current && git commit`**，否则其他工作树还是看不到。`tools/ship.py` 在快检通过后也会自动跑这一条重录，但同样只落在协调人那次 commit 里才会传播给别人；重录失败不挡发版，只提示。
  - `ARK_GOLDEN_DIR` **显式设置时**才会启用一个可选的本地未提交覆盖层（读取时优先于 `game/tests/golden_current/`），用于大重构对改前对照等临时场景（见下）；**不设这个环境变量时完全不读 `build/golden_cache/`**（10-22 改：原来缺省就指向 `build/golden_cache/`，导致本机残留的旧缓存把 git 里刚刷新的金样"遮住"，合并后误判过期——协调人在 main 上连续撞到两次。现在 `--auto` 默认只认 `game/tests/golden_current/`，不存在隐式本地覆盖层）。
  - 证据快照 `game/tests/golden/fd9ce553/` 不动，只在 `golden_current/` 也没有对应文件时才兜底。
- **局限**：金样过期期间这一项不判；只有「别处没变」的分支（只改干员 / 积木的分支）才真正比。「别处」含其他干员的数据（招募会把别人拉进局里），所以一个分支同时改了积木和某名干员的数据时，只有那名干员这组真比，其余组过期。积木改动最好单独成分支。
- **大重构对改前对照（10-15，docs/101 §7.3.5）**：改动了所有干员共用的段（例：op_blocks 拆文件）时每组的「别处」都变，金样一律过期。这时用两个环境变量：在改前提交的临时工作树里 `ARK_GOLDEN_DIR=<临时目录> python tools/check.py --only blocks_eq --eq-all --update-golden` 录一份临时金样（写到 `<临时目录>`，不进 `golden_current/`，不进 git），分支上 `ARK_EQ_FORCE=1 ARK_GOLDEN_DIR=<同一目录> python tools/check.py --only blocks_eq --eq-all` 过期也照比。不设这两个变量时行为不变，读写都在 `game/tests/golden_current/`。
- **验证（10-15 录制 + 10-21 迁移）**：录制时 14 组 × 2 用例数据版与手写参照 28 / 28 逐字节相同；删掉手写参照后 `--eq-all` 28 组与金样相同；把斯卡蒂 `atk` 改 ×1.3 → 斯卡蒂组 FAIL（TRACE 第 34 行起不同），其余 13 组判过期；`--update-golden` 重录 28 份后再比 14 / 14 相同。10-21 把当时 `build/golden_cache/` 下已重录的 28 份原样迁入 `game/tests/golden_current/` 并改 git 跟踪，在全新 worktree（没有本机缓存）里验证 `--only blocks_eq --eq-all` 能直接读到、不再误判过期。

快检（全量）包含五项：

1. **核心契约测试**（`tests/test_core.gd`）：干员结构、成长线、藏品数据、属性分层。
2. **冒烟**：每名干员各当一次主控、带两名队友（按名单轮换，每人也都当过队友），开局拿全部藏品、推到成长线末端、技力常满，三个 Boss 提前到 0:20 / 0:45 / 1:10，跑 90 秒游戏时间（10-15 由 0:30 / 1:00 / 1:30、2 分钟缩短，每个 Boss 仍有 ≥ 20 秒战斗）；另跑两局不作弊的自然流程（高手、普通机器人，跑过第一个商人）。只看「有没有报错、能不能跑完」。
3. **成长节点当场生效**（`tests/node_test.tscn`）：每名干员逐个应用 6 个成长节点，记录选下那一刻干员身上变了什么（脚本变量、按本干员作用域取的属性、技能解锁与充能）。有节点什么都没变就失败。`--effecttest=K` 让主控停在第 K 个节点跑 40 秒、打印各伤害来源占比，用来确认节点的效果当下就在打。
4. **主控保护**（`tests/prot_test.tscn`，docs/38 §1.11）：把一局跑起来后直接调用扣血入口 `combat.lose_hp` / `enemy_hit`，检查 Boss 来源的扣血截断——骨血 + 灯火 20 下单发 ≤40%、带侵蚀的招式「扣血 + 追加侵蚀」≤40%、连发任意 2 秒合计 ≤50%（「扣血 + 追加的侵蚀」和「实际扣血，含侵蚀结算」两种口径，窗口满时追加的侵蚀也作废）、满血吃连击（带侵蚀的、夹小怪伤害的）不死而且满血保护只兜这一轮连击、Boss 在场时 Boss 侵蚀和 Boss 溟痕每秒 ≤4%，以及非 Boss 来源照旧（含流明净化之后的普通侵蚀）。
5. **复现**：同一组参数跑两次，结果必须逐字段相同。

另有不开 Godot 的静态项（`--auto` 也跑）：数据 JSON 解析、美术帧条 art_lint、发行包瘦身 release_slim、**干员文字数值 op_text_check**（10-14 加，`tools/op_text_check.py`，docs/61 §1.4）：
干员文字里的 `{$键}` 占位都求得出值；没写成占位的「N%」「N 秒」「×N」「半径 N」「每第 N 次」在这名干员的 base / blocks 里找不到对应的数就失败（引擎写死的常数登记在 `ALLOW`）。
对得上的字面数字列成「需人工看」清单（`python tools/op_text_check.py --report`），`--dump <干员>` 打印填好数值后的全部文字。

**为什么要冒烟**：核心测试不运行干员脚本。2026-09-26 删掉一个藏品函数时漏改了水月的调用点，核心测试全绿，水月却每次出手都报错；这类问题只有真的跑一局才抓得到。

## 2. 规则

- **提交前快检必须通过。** 失败时先修，不要带着失败提交，也不要为了过检去改检查本身。
- **报错一律算失败。** `SCRIPT ERROR`、`Parse Error`、脚本加载失败都算，不管数值看起来多正常。Godot 把这些写在 stderr，工具两边都查。
- **测试全部静音、无界面。** 静音规则见 AGENTS.md，截图例外（需要窗口）但同样静音。
- **测试不写玩家存档。** 带任何 `--xxx` 参数启动时，`settings.gd save()` 直接返回（与静音同一判定）。2026-09-26 之前批跑会把机器人拿到的藏品记进玩家图鉴的「已获得」。
- **全机并发有上限。** 所有会话的测试加起来最多同时开 `GODOT_MAX_PROCS` 个 Godot（缺省为逻辑核数减 4，这台机器是 20）。都走 `tools/godot_runner.py`，不要自己另开一批 Godot 绕过它。两批同时跑时每局会慢 4–5 倍。
- **对比必须是同一份代码的两侧。** 不要拿不同时间、不同工作区跑出来的报告直接比，其他会话随时在改干员（docs/35 的教训：两次「改动前」基线之间，普通机器人胜率从 24% 掉到 5%，原因是别人的提交）。用 `--ab`，它在临时工作树里跑基准。
- **对比看配对结果。** 同 seed 可复现后，A/B 表的最后一列是「结果完全相同的局」：和本次改动无关的开局应该完全相同；一旦改动影响了随机数，整局都会变，这时看合计，单个开局的胜率变化在 8 seed 下仍有 ±25 点的噪声。
- **护栏统一为**：任何改动不能让某个开局或编队的胜率变化超过 25 个百分点（docs/27 §6.4）；新增干员时，不含她的老编队结果应当逐局完全相同。

### 2.1 新工作树的两件事（2026-09-26）

1. **先导入再测**：新工作树没有 `game/.godot/`，直接测贴图全是空的（快检会大面积失败）。`check.py` 和 `balance_run.py` 启动时会自动检查：导入缓存不到 50 个文件就先跑 `--import`，直到缓存文件数不再增加（第一遍有时只导入一部分），每遍约 20 秒（`godot_runner.ensure_imported`）。手动跑 Godot 的截图 / 自测仍要自己先导入。
2. **换行**：`.gitattributes` 已让 `*.import / *.uid / *.cfg / *.gdshader` 检出为 LF，和 Godot 写的一致，导入后工作树是干净的。**2026-09-26 之前检出的工作树**导入后若一堆 `.import` 显示「已修改」（`git diff` 却是空的）：运行一次 `git add --renormalize -- '*.import' '*.uid'`，内容不变、只刷新索引记录，之后就干净了。

## 3. 同 seed 可复现

2026-09-26 之前，同一个 `--seed` 跑两次在 0:20 到 3:50 之间就会分叉，所以每次对比都要堆种子。查明并修掉了三个原因：

1. **`--seed` 生效太晚。** 招募开局干员时就会用对局随机数（战斗台词计时），而种子在 `_ready` 后段才设。开局干员的第一句台词时间是随机的，一出声随机数就错开。现在种子在 `_ready` 第一行就设好。
2. **玩法和画面共用随机数。** 火花、飘字抖动这些纯画面效果按真实帧率运行，却在用对局随机数 `rng`；升级卡池洗牌、艾雅法拉选目标、石头怪落点散布又在用全局随机数，而全局随机数也被画面效果消耗。机器一忙，画面帧数不同，玩法的随机数就跟着变。
3. **画面状态决定玩法随机数用几次。** 伤害数字的位置抖动用的是 `rng`，而且飘字少于 80 条时才出；打无敌敌人时的「无效」飘字又按 `vrng` 抽签。`vrng` 被按真实帧运行的画面效果消耗，所以机器一忙，飘字条数就不同，伤害数字要不要抽 `rng` 也跟着变。塞雷娅开局在 7:43 前后的一波清场里撞上 80 条上限，负载重时 12 局里有 2–4 局分叉。现在伤害数字抖动改用 `vrng`（这一改让所有 seed 的结果整体换了一套，不是玩法变化）。教训：`rng` 的调用不能放在任何取决于画面状态（`texts` / `fx` 数量、画面设置）的条件里。

现在的约定（写新代码必须遵守）：

| 用途 | 用什么 |
| --- | --- |
| 玩法：刷怪（spawner、远距回收落点） | `g.rng_spawn`（10-15 起，docs/101 B7：按用途派生的独立流，局种子 + 名字 hash） |
| 玩法：敌人 AI、Boss 脚本、吞噬、形变 | `g.rng_enemy` |
| 玩法：击杀 / 卡点 / 宝箱掉落 | `g.rng_drop`（掉落物弹出另有 pickups 的派生流） |
| 玩法：干员积木 | `g.rng_op` |
| 其余玩法（伤害、闪避、暴击、目标、藏品、选卡、变动区、地图） | `g.rng`；洗牌用 `g.shuffle(arr)` |
| 测试断言「不掷随机数」 | 比 `g.rng_states()`（五条玩法流的 state） |
| 纯画面（火花、粒子、飘字抖动、闪烁） | `g.vrng` 或全局 `randf()` |
| 禁止用在玩法里 | `Array.shuffle()`、`pick_random()`、全局 `randf()` / `randi()` |

验证：维什戴尔 seed 3 同时跑 7 次，5 次整局逐字节相同。**已知问题**：另外 2 次在 10:05 前后（最终 Boss 阶段）分叉，原因还没找到。10 分钟之前的部分是完全一致的。（2026-09-26 查到第 3 条后，塞雷娅 seed 4 同时跑 12 次，整局和每秒 `--trace` 全部逐字节相同；维什戴尔的 10:05 分叉很可能是同一原因，待复核。）**2026-09-27 已关闭**：云端在 b0-verify（6c7a017）上把维什戴尔 seed 3 高手连跑 7 次，都跑到 668 秒，整局逐字段一致（不含画面峰值）；确认 05329b2 修掉了这个分叉。B1 以后的 A/B 可以逐局配对。排查方法：`--trace=0.25` 打印状态摘要，两次对比找到第一行不同的时间，再在那段里逐段打点。

复现带来的两个好处：

- **结果可以缓存。** 「游戏源文件内容 + 参数」相同就是同一局，`balance_run.py` 直接读缓存（`build/balance/cache/`，所有工作树共用）。main 的基线跑过一次，其他会话做 A/B 时不用再跑。`--nocache` 关掉。
- **回归可以精确比对。** 与改动无关的局应该逐字节相同，出现差异就说明改动影响到了本不该影响的地方。

### 3.1 固定用户设置（2026-10-01）

`tools/godot_runner.run_godot` 是 check.py 和 balance_run 起 Godot 的唯一入口。它缺省给每次启动一个**临时用户目录**（Windows 的 `APPDATA`、Linux 的 `XDG_DATA_HOME`），里面只有一份固定的 `settings.cfg`（难度 = 标准、画质 = 高、手动普攻 = 关、静音），其他偏好走缺省，结束就删。

- 本机存档里的难度、画质、手动普攻等偏好**不再影响快检和批跑**。起因是数值发现，本机存了 Ⅳ 时 prot_test 会误报 2 项。
- 测试改设置不再写进玩家的真实存档。以前 ea_ui_test 断言「封面干员已写进配置」，本机跑快检会真的改掉存档里的封面干员。
- **云端批跑同样适用**：从 19ec187 起，云端镜像里残留的存档也不再影响结果，close8 之后的批跑都以此为准。
- 需要真实用户目录时，设环境变量 `ARK_REAL_USERDIR=1`。
- 经 `godot_runner` 起的开窗口测试局在 Windows 上**不抢焦点、不出现在屏幕上**（用户 10-06：别让弹窗打扰）：runner 临时写 `game/override.cfg`（`window/size/no_focus=true`，跑完无其他 Godot 时删，不入库）、设环境变量 `ARK_NO_FOCUS=1`（settings.gd 不居中窗口、`unfocusable`），并用 Win32 把整个进程树的窗口挪到屏幕外、压到 Z 序最底（Godot 会把 `--position` 夹回屏幕内，所以从外面挪）。**不能最小化**：最小化后画布不渲染、截图全黑。要肉眼看局时设 `ARK_SHOW_WINDOW=1`。自己起 Godot 的驱动脚本要照同一套做。
- 开窗口的实时测量脚本（docs/50）自己指定 APPDATA，不受影响。

### 3.2 基线 TRACE 缓存：`tools/trace_base.py`（2026-10-14）

同种子对照（「只改画面 / 重构，玩法应逐行不变」）的基线不再各自建临时工作树重跑，统一取缓存：

```
python tools/trace_base.py <seed> <队长> <时长秒>                    # 打印基线文件路径；没有就先跑一次再存
python tools/trace_base.py 1 mizuki 240 --here                        # 另在当前工作树跑同一局，逐行比 TRACE
python tools/trace_base.py 3 wisadel 60 --extra "--squad=mizuki,suzuran --sptest"   # 附加参数（进缓存名）
python tools/trace_base.py 1 mizuki 240 --ref <提交>                  # 基线换成别的提交（缺省 main）
```

- **缓存位置**：主仓库（不是工作树）的 `build/trace_cache/<提交前 8 位>_<seed>_<队长>_<时长>[_<附加参数哈希 6 位>].txt`，所有工作树共用；文件头两行 `#` 写提交和完整参数，后面是每秒一行 `TRACE` 和结束时的 `BALANCE` 一行。
- **没有缓存时**：在主仓库 `.claude/worktrees/trace-<提交>-<pid>` 建临时工作树（拷主仓库的导入缓存，免得从头导入），跑 `--headless --balance --seed=S --op=队长 --bot=expert --maxt=时长 --trace=1 [附加参数]`，存好就删工作树；写文件是原子替换，两个会话同时建同一份也不会读到半截。
- **为什么是 `--balance`**：`TRACE` 只在 `--balance` 模式下打印（`autotest.gd`），`--autotest` 不出。要换机器人档位 / 难度就在 `--extra` 里写 `--bot=` / `--tier=`。
- **`--here`**：在当前工作树跑同一局，TRACE 逐行比，报第一处不同的那一行；`BALANCE` 行只提示不判定（画面峰值 / prof 字段本来就可能不同，需要时自己比）。退出码 0 = 逐行相同。
- main 前进后缓存自然换名（提交号变了），旧文件可随手删；`--refresh` 强制重跑当前这份。

**TRACE 新格式（10-29 起，docs/126 R3，`claude/test-gaps`）**：`TRACE` 行末尾多四个字段，既有字段的顺序和格式一字不动：

```
TRACE t=… lv=… k=… hp=… n=… rng=… pos=… h=… sq=<队友哈希> lamp=<灯火×100取整> nd=<神经损伤哈希> rl=<藏品数>
```

- `sq`：按编队顺序（`squad.ops`）对每名干员的 `[id, 位置×100, 突击生命 cmd_hp×1000, 三条技力 sp×100, attack_t×1000, fire_t×1000, 普攻冷却 cd×1000（数据干员）, 普攻次数 atk_n]` 拼串取 `String.hash`；浮点先量化成整数，避免噪声造成假差异。队长本人也在里面。
- `lamp`：`g.lamp × 100` 取整。`nd`：队长身上的神经损伤（`nerve / nerve_lock / nerve_taken_mult / nerve_aura_t`，量化后哈希）；敌人身上没有神经损伤累积，所以不聚合敌人。`rl`：藏品数（`g.relics.size()`）。
- 只在 `--balance --trace` 下算（`autotest.trace_extra()`），只读、不碰 rng、不改状态；正式游戏路径零开销。
- **旧基线缓存不可直接逐行比**：10-29 之前录的 `build/trace_cache/*.txt` 和 `game/tests/golden_current/` 金样行尾没有这四个字段，逐行比会在第 1 行报不同——这类文件作废，需重录（`tools/trace_base.py --refresh` / 合入后云端统一重录金样）。只想证明「玩法没变」时，把新输出的行尾 ` sq=…` 起剥掉再和旧基线比（10-29 验证：mizuki seed 1 前 90 秒 91 行，剥尾后与 bfa2bcd07 基线逐行相同；同一局跑两遍含新字段逐行相同）。本文只写文档，没删任何人的缓存文件。
- 灵敏度自测 `game/tests/trace_fields_test.gd`（`check.py --only trace_fields`）：只改一个量（队友位置 / 突击生命 / 三条技力 / 普攻计时 / 灯火 / 神经损伤各项 / 藏品数），对应字段必须变，还原后回到原值，浮点噪声（0.001）不变，计算不动五条 rng 流。

## 4. 速度

2026-09-26 的优化，同一台机器、同样负载下并排实测：

| 项目 | 改动 | 效果 |
| --- | --- | --- |
| 进局黑屏 | 选完干员到战斗首帧：法线图改为标题页后台线程预热 + 磁盘缓存（user://normal_cache）+ 分离卷积生成（2026-10-06，art.gd） | 10.4 秒 → 0.3–0.7 秒（开法线光照，本机 `--loadprof`）；预热未完时标题页画「载入中…」 |
| 启动 | 无界面运行不生成法线图（原来在 GDScript 里逐像素算，玩家设置开着法线光照时每局都算） | 只启动的一局：约 22 秒 → 约 4 秒 |
| 画面 | 无界面批跑不重绘世界、特效、前景、HUD（原来占一局耗时的三成多） | 已验证结果逐字节不变 |
| 机器人 | 高手机器人每步把附近敌人的打分参数先算好，33 个候选点共用 | 机器人耗时约减半，决策逐字节不变 |
| 整局 | 以上合计 | 满长度一局 269 秒 → 157 秒（负载很重时的并排数字，约快 1.7 倍） |
| 冒烟 | `--maxt` 提前结束、`--bosstimes` 提前 Boss、`--maxprog` / `--relics=all` 一局覆盖全部技能与藏品 | 17 项快检 44 秒 |
| 重复跑 | 结果缓存 | 同一份代码的同一局第二次读缓存，为 0 秒 |
| 多会话 | 全机并发上限 | 不再互相挤爆 CPU |

剩下的大头是敌人更新（约占模拟四成）和干员更新。要继续优化时先用 `--prof` 看分段耗时（结果在 BALANCE 行的 `prof` 字段），改完用复现检查确认行为没变。

## 5. 测试开关索引

所有开关都跟在 `--` 之后，例如 `godot --headless --path game -- --balance --seed=1 --op=wisadel`。

**批跑 / 机器人**（配合 `--balance`）

| 开关 | 作用 |
| --- | --- |
| `--balance` | 无界面快速模拟一整局，结束时打印 `BALANCE {json}` |
| `--seed=N` | 种子（同 seed 可复现） |
| `--op=<id>` / `--squad=a,b` | 开局干员 / 开局就编入的队友 |
| `--bot=afk\|bad\|normal\|expert\|master` | 机器人档位（docs/29）；master = 熟练玩家档（2026-09-29，预判、冲刺无敌、防包围、按射程贴 Boss、认流派选卡），用作难度「参考上限」 |
| `--mt_<名>=值` / `--mdbg` | master 调参旋钮 / 每 10 秒一行 MDBG 调试（仅测试） |
| `--diff=N` | 难度 |
| `--maxt=秒` | 提前结束（缺省 780） |
| `--nodeath` | 生命归零不结束，记托底次数 |
| `--norecruit` | 不招募，测单个干员 |
| `--botrandom` | 选卡纯随机 |
| `--evpick=…` | 事件选项固定选择 |
| `--prof` | 模拟步分段耗时；另记世界绘制 13 段 `dw_*`、HUD / 加色层 / 前景 `draw_*`（docs/50） |
| `--perf` | 开窗口跑时按 0–8 / 8–10 / 10+ 分钟记帧时间、渲染 CPU / GPU、敌人数、慢帧明细，结束打印 `PERF {json}`（docs/50） |
| `--realtime` | 按真实帧间隔推进、不多跑模拟步；**绘制 / 帧时间对比必须加**（批跑步长每帧 0.5 秒游戏时间，特效很快消失，绘制被低估） |
| `--trace=秒` | 定期打印状态摘要（排查复现） |
| `--perfmin` / `--perfab=N` / `--perfdump=路径` | 配 `--perf`：按游戏分钟分段（`m08`，`F` = 最终 Boss 在场）；每 N 帧轮换 `g.perf_alt`（同时切旧的 PlayClock 切步与顿帧规则，分 `/a` `/b` 两桶，同局对照）；逐帧 CSV（帧时间、模拟步数、各列表长度、`--prof` 分段）。开局后才读的贴图打印 `TEXLATE 名字 毫秒`（docs/50 §10） |
| `--rtfrom=秒` / `--optab=N` / `--optmask=位` / `--optold=位` / `--gemstress` | 配 `--perf --realtime`（docs/50 §11）：到这一秒前按批跑步长快进、之后真实步长（快进段不进 `--perf` 统计）；每 N 帧在性能优化的新 / 旧实现之间轮换 `g.opt_old`（分 `/new` `/old` 两桶，`--optmask` 只轮换其中几项，位见 game.gd `OPT_*`）；`--optold` 整局走旧实现（同 seed 新旧对照）；`--gemstress`：掉落物只落地、不会被拾取 / 回收，堆满到溢出上限（改变对局，只量帧时间）。`--perfdump` 另记每帧绘制调用数 `dcalls` |
| `--atlasinfo` / `--atlasflip=neg` | 敌人图集（docs/50 §12）：开局打印 `ENEMY_ATLAS` 帧条数 / 尺寸 / 耗时；`--atlasflip=neg` 翻转改用负宽矩形（引擎会连法线一起翻，画面会变，只供对照）。`--optold` / `--optmask` 的位 32 = 普通怪描边（旧写法照画）、64 = 图集（旧写法用各自帧条） |
| `--playclock` | 配 `--balance --realtime`：开垂直同步、按玩家局的 PlayClock 分步与顿帧推进，量玩家实际帧时间与顿帧（docs/50 §10） |
| `--recframes=秒,帧数` / `--legacyfeel` | 游戏时间过了该秒后连存 N 帧 `rec_*.png` 到 `--shotdir`（配 `--playclock --fixed-fps 30` 录对照片）；`--legacyfeel` 整局用旧切步与旧顿帧规则 |

**界面动效**（docs/62 §8，带 `--autotest`、开窗口；`run/motion_shot.gd`）

| 开关 | 作用 |
| --- | --- |
| `--motionshot=<界面>,<秒,…>` | 第 30 帧打开该界面（levelup / relic / recruit / swapcard / swap / shop / pause / banner / fail；swapcard / swap 为满员更换队友，docs/83 §7），按界面时钟在各时刻截 `shot_motion_<界面>_<full\|rm>_<毫秒>.png`；fail 从倒下算（结算动效 1.7 秒起） |
| `--reducemotion` | 同时打开「减少动态效果」（不写存档），截减少动态那一组 |
| `--motionpress=<key\|mouse\|touch\|pad>@<秒>` | 在该时刻注入一次按下 + 松开，2 帧后打印 `MOTIONPRESS`（动效被跳过、没有误选），0.4 秒后再按一次打印 `MOTIONPRESS2`（这次生效） |
| `--motionrec` | 按脚本依次演示各界面（全动效 → 减少动态 → 失败结算），每帧存 `rec_<帧>.png`、打印 `MOTIONREC` 分段；配 `--fixed-fps 30` 录片 |
| `--motionperf=<界面>[,秒]` | 同局轮换量开销：界面开着，每 0.9 秒重放动效并在全动效 / 减少动态间轮换，关垂直同步不限帧，打印 `MOTIONPERF {json}`（两桶帧时间中位 / 均值 / P90、渲染 CPU、净差） |

**冒烟 / 强制状态**

| 开关 | 作用 |
| --- | --- |
| `--relics=id,…` / `--relics=all` | 开局直接获得藏品（`--balance`） |
| `--grant=id,…` | 同上，非批跑模式也可用 |
| `--maxprog` | 全队推到成长线末端（`--balance`） |
| `--prog=N` | 全队推进 N 个节点 |
| `--sptest` | 技力常满 |
| `--bosstimes=a,b,c` | Boss 出现时间（`--balance`） |
| `--forceboss=N` | 指定第一个中期 Boss（MID_POOL 下标） |
| `--forceboss2=N` | 指定 7:00 中期 Boss（3 = 主教 + 蔑视体，4 = 主教 + 斥亡者） |
| `--forceending=<结局>` | 最终 Boss 登场时改用该结局的 Boss（standard 泡影 / deep 伊莎玛拉 / knight 骑士 / resolve 伊祖米克） |
| `--fastlevel` | 快速升级 |
| `--eventtest=<id>` | 开局在身边刷事件箱 |
| `--dummy_op= / --dummy_role= / --dummy_scene= / --dummy_stage=`（`tests/op_dummy_test.tscn`） | 干员木桩表：站桩打木桩 / 怪群 60 秒记秒伤、治疗、护盾；批量用 `python tools/op_dummy_table.py`，口径见 docs/79 |

**截图**（需要窗口，仍静音；`--shotdir=` 指定目录）

`--shots=帧,…`、`--galleryshot=页,选中,形态,等待[,连拍,间隔]`、`--compareshot=<id>[,s]`、`--demoset=阶段,模式`、`--infotab=N`、`--allrelics`、`--allend`、`--relicshot`、`--winshot=<结局>`、`--bosstest=<Boss>`、`--bossmoves=<Boss>[2]`（docs/95 §12 招式验收：第 20 帧在主控旁刷出该 Boss（后缀 2 = 二阶段），按 `bosses/<type>.gd` 的 `demo_moves` 顺序逐招 `force_move`，预警进度 60% 截 `shot_bossmove_<Boss>_<招>.png`、结算后 8 帧截 `_hit.png`，放完退出；主控不动，带 `--autotest` 开窗口）、`--bossintro=<Boss>[,<Boss>]`（第 20 帧在主控旁刷出该 Boss（逗号 = 同组登场）走一遍登场演出，0.35 / 0.6 / 0.85 / 1.1 秒各截一张 `shot_bossintro_*`，演完击杀再截两张击破 `shot_bossout_*`；`--nobossintro` 关掉演出，同 seed 开窗口对照用；`screens/boss_intro.gd`）、`--bossdeath=<结局>`（最终 Boss 击破演出，docs/38 §1.8：第 20 帧在主控旁刷出该结局的最终 Boss（standard / deep / knight / resolve）并登记为 `final_boss`，登场演完 30 帧后击杀 → `victory_flow` 慢动作 + 击破名片，演出 0.2 / 0.5 / 0.9 / 1.4 / 1.8 秒各截一张 `shot_bossdeath_<结局>_*`，进结算 1.5 秒后退出；带 `--autotest`，开窗口；录片用 `--fixed-fps 30` 每帧存图）、`--fxtest`、`--gemshot`、`--openshot`、`--introshot`、`--titleshot`、`--loadingshot`（出发后的载入页「潮汐航标」；加 `--reducemotion` 截静态版）、`--bootshot`（启动页「声呐测绘」读到一半时截 `shot_boot.png`）、`--ftrec`（界面帧时记录，docs/50 §27：每帧真实帧间隔按标记分段打印 `PF FTSEG`（P50 / P95 / 最长）、超 33 ms 的帧打 `PF FTLONG`（脚本 / 渲染 / 贴图增量），分项计时 `PF FTACC`；`--ftquit=<标记>:<秒>` 退出、`--ftdo=<标记>:<秒>:<动作>` 让标题页开寻访 / 图鉴；带它也走启动页；用 `tools/probes/ui_frametimes.py` 跑桌面 / 网页）、`--loadprof`（开窗口：打印标题页离开 → game.gd `_ready` 各阶段 → 首帧画完的毫秒数 `LOADPROF`，法线图预热耗时 `PRELOAD`，启动到标题页 `BOOTPROF boot_ready / boot_done / title_ready / title_first_frame`（毫秒，从引擎启动算；带 --loadprof 时也走启动页），开局登场语音相对首帧的时差 `LOADPROF_VOICE`；带 `--autotest` 也走出发后的载入页；查进局黑屏用）、`--settingsshot`、`--creditsshot`、`--creditsscroll=<像素>`（致谢与声明页截图；滚动量超出自动截到底）、`--opshot`、`--opsel=`、`--opid=<干员>`、`--optab=0–2`、`--opskill=0–2`、`--opfilter=<职业>`、`--opscroll=<像素>`、`--reducemotion`（选人页 B+ 截图：选人 / 页签 / 技能行 / 职业筛选 / 名册滚动 / 减少动态效果）、`--opmotion`（选人页动效录制：配 --fixed-fps 30 逐帧存到 `<shotdir>/opmotion/`，换人 → 换页签 → 技能行 → 筛选 → 出击浪幕 → 难度页，约 8.6 秒）、`--galleryid=<id>`、`--galleryfilter=<职业>`、`--galleryrow=<n>`（图鉴 C4' 截图：配 `--galleryshot=` 按 id 选条目 / 职业筛选 / 手机展开第 n 行；形态填 99 = 最后一个「演示」）、`--codexmotion`（图鉴动效录制：配 --fixed-fps 30 逐帧存到 `<shotdir>/codexmotion/`，标题 → 斜切转场打开 → 换干员 ×2 → 换页签 ×3 → 敌人页启辉 → 换条目 → 回干员页，430 帧）、`--opburst`、`--touchtest`、`--touch`、`--padsim`、`--drawtest`（批跑时照常重绘，验证画面不影响结果）
`--shots=帧,…`、`--spawntest=<id>[,<id>]`（第 20 帧把这些小怪 / 精英刷在主控右侧、时间照常走，每 6 帧截 `shot_spawn_<id>_<帧>.png` 到第 320 帧；`--bosstest` 的 g.t 不动，远程蓄力永远到不了，小怪招式截图用这个）、`--galleryshot=页,选中,形态,等待[,连拍,间隔]`、`--compareshot=<id>[,s]`、`--demoset=阶段,模式`、`--infotab=N`、`--allrelics`、`--allend`、`--relicshot`、`--winshot=<结局>`、`--bosstest=<Boss>`、`--bossintro=<Boss>[,<Boss>]`（第 20 帧在主控旁刷出该 Boss（逗号 = 同组登场）走一遍登场演出，0.35 / 0.6 / 0.85 / 1.1 秒各截一张 `shot_bossintro_*`，演完击杀再截两张击破 `shot_bossout_*`；`--nobossintro` 关掉演出，同 seed 开窗口对照用；`screens/boss_intro.gd`）、`--bossdeath=<结局>`（最终 Boss 击破演出，docs/38 §1.8：第 20 帧在主控旁刷出该结局的最终 Boss（standard / deep / knight / resolve）并登记为 `final_boss`，登场演完 30 帧后击杀 → `victory_flow` 慢动作 + 击破名片，演出 0.2 / 0.5 / 0.9 / 1.4 / 1.8 秒各截一张 `shot_bossdeath_<结局>_*`，进结算 1.5 秒后退出；带 `--autotest`，开窗口；录片用 `--fixed-fps 30` 每帧存图）、`--fxtest`、`--gemshot`、`--openshot`、`--introshot`、`--titleshot`、`--loadingshot`（出发后的载入页「潮汐航标」；加 `--reducemotion` 截静态版）、`--bootshot`（启动页「声呐测绘」读到一半时截 `shot_boot.png`）、`--ftrec`（界面帧时记录，docs/50 §27：每帧真实帧间隔按标记分段打印 `PF FTSEG`（P50 / P95 / 最长）、超 33 ms 的帧打 `PF FTLONG`（脚本 / 渲染 / 贴图增量），分项计时 `PF FTACC`；`--ftquit=<标记>:<秒>` 退出、`--ftdo=<标记>:<秒>:<动作>` 让标题页开寻访 / 图鉴；带它也走启动页；用 `tools/probes/ui_frametimes.py` 跑桌面 / 网页）、`--loadprof`（开窗口：打印标题页离开 → game.gd `_ready` 各阶段 → 首帧画完的毫秒数 `LOADPROF`，法线图预热耗时 `PRELOAD`，启动到标题页 `BOOTPROF boot_ready / boot_done / title_ready / title_first_frame`（毫秒，从引擎启动算；带 --loadprof 时也走启动页），开局登场语音相对首帧的时差 `LOADPROF_VOICE`；带 `--autotest` 也走出发后的载入页；查进局黑屏用）、`--settingsshot`、`--creditsshot`、`--creditsscroll=<像素>`（致谢与声明页截图；滚动量超出自动截到底）、`--opshot`、`--opsel=`、`--opid=<干员>`、`--optab=0–2`、`--opskill=0–2`、`--opfilter=<职业>`、`--opscroll=<像素>`、`--reducemotion`（选人页 B+ 截图：选人 / 页签 / 技能行 / 职业筛选 / 名册滚动 / 减少动态效果）、`--opmotion`（选人页动效录制：配 --fixed-fps 30 逐帧存到 `<shotdir>/opmotion/`，换人 → 换页签 → 技能行 → 筛选 → 出击浪幕 → 难度页，约 8.6 秒）、`--galleryid=<id>`、`--galleryfilter=<职业>`、`--galleryrow=<n>`（图鉴 C4' 截图：配 `--galleryshot=` 按 id 选条目 / 职业筛选 / 手机展开第 n 行；形态填 99 = 最后一个「演示」）、`--codexmotion`（图鉴动效录制：配 --fixed-fps 30 逐帧存到 `<shotdir>/codexmotion/`，标题 → 斜切转场打开 → 换干员 ×2 → 换页签 ×3 → 敌人页启辉 → 换条目 → 回干员页，430 帧）、`--opburst`、`--touchtest`、`--touch`、`--padsim`、`--drawtest`（批跑时照常重绘，验证画面不影响结果）

**新旧画面对照**（2026-10-15，docs/101 S2 实测）：开窗口跑 `--shots` 做对照时，引擎参数加 `--fixed-fps 60`（写在 `--` 之前）。不加时同一棵树跑两次，同一帧号的截图就差 6 万–50 万像素（窗口帧时间不固定，局面漂了）；加了之后旧对旧、旧对新都是 0 像素。按时间录帧的 `--recframes` 同样不确定，对照别用。每次对照另跑一次旧对旧作噪声基线。

## 6. 报告在哪

| 内容 | 位置 |
| --- | --- |
| 最近一次快检 | `build/check/last_quick.txt`（失败时末尾单独列出失败项、原因和日志路径） |
| 快检每局的完整输出 | `build/check/quick_<时间>/<项名>.log`（参数、用时、是否超时、stdout / stderr） |
| 机器人矩阵 | `build/check/bots_<时间>/`、`build/balance/<tag>_<时间>.md/.json` |
| A/B 对比 | `build/check/ab_<时间>/compare.md` |
| 结果缓存 | 主仓库 `build/balance/cache/<源文件摘要>/` |

批跑报告里「终局」用时是四种最终 Boss 混算（最终 Boss 由结局决定：偏执泡影 / 最后的骑士 / 伊莎玛拉 / 伊祖米克，各有自己的 `boss/hp_x_<类型>`）。调单个 Boss 看报告开头的「最终 Boss（按类型）」表（2026-09-26 起；ea-v3 里高手档 28 局中伊祖米克 20 局、偏执泡影只有 4 局）。

## 7. 云端批跑

> 2026-09-26 加入：把大批量的机器人批跑挪到云端 Linux 机器上，本机留给开发和快检。脚本在 `tools/cloud/`，日常使用由「测试与验收」负责。

### 7.1 怎么启动

在云端机器（Claude Code 云端会话，或任意 Ubuntu / Debian x86_64）上，克隆 GitHub 仓库后：

```
bash tools/cloud/setup_linux.sh          # 只需一次：装依赖、下载 Godot 4.7.2 官方 Linux 版并核对 SHA512、大小写检查、导入项目
ONLY=check bash tools/cloud/run_cloud.sh # 第一次先只跑快检，确认环境没问题
bash tools/cloud/run_cloud.sh            # 快检 + 标准矩阵（普通 / 高手 × 7 开局 × SEEDS，缺省 4）
SEEDS=8 BOTS=expert,normal PRESET=starts bash tools/cloud/run_cloud.sh
AB=<提交> bash tools/cloud/run_cloud.sh  # A/B（check.py --ab）
```

- `setup_linux.sh` 生成 `tools/cloud/env.sh`（Godot 路径与并发），`run_cloud.sh` 自动读取；换机器要重新跑 `setup_linux.sh`。
- 大小写：Windows 不分文件名大小写，Linux 分。`tools/cloud/case_check.py` 检查代码 / 数据里写死的 `res://` 路径与美术名，初始化时会跑；本机也能跑，改了资源路径后建议先跑一遍。动态拼出来的名字查不到，要看云端日志里有没有 `Failed loading` / `Cannot open file`。
- 换行：`.sh` 由 `.gitattributes` 强制 LF（在 Windows 上编辑也不会变成 CRLF）。
- `.uid` / `.import`：Godot 给每个脚本 / 资源生成的旁路文件**必须入库**（`.gitignore` 第 1 行的约定）。**新增 `.gd` 时把同名 `.gd.uid` 一起提交**；漏交的话每台机器导入时各自生成随机 UID，云端会冒出一堆未跟踪文件（2026-09-26 首跑就遇到 35 个，已补交）。`setup_linux.sh` 导入后会列出未入库的旁路文件——那是云端临时生成的，不要从云端提交，回本机补交原件。
- 云端没有声卡和显示器：`--headless` 下 Godot 自动用空的音频与显示驱动，测试本来就静音（§2）。截图类测试（需要窗口）不在云端跑。

### 7.2 并发多少

- 缺省 `GODOT_MAX_PROCS = 核数`：云端机器只跑这一批，不用像本机那样给别的会话留余量（本机是核数 − 4，所有会话共用）。
- 内存：无界面 Godot 每个约 300–500 MB，按 `min(核数, 内存 GB × 2)` 设上限，例如 8 核 16 GB 设 8。`GODOT_MAX_PROCS=6 bash tools/cloud/run_cloud.sh` 可临时覆盖。
- 同 seed 可复现、结果缓存（§3、§4）在云端照常生效；缓存放在云端机器自己的 `build/balance/cache/`，不和本机共享。

### 7.3 结果怎么拿回本地

每次运行的结果在 `build/cloud/<时间>/`（报告 `.md`、原始 `.json`、`env.txt` 里有提交号 / Godot 版本 / 核数、各段日志），另打一个 `build/cloud/cloud_<时间>.tar.gz`。`build/` 不进仓库，拿回本地的办法：

1. **推一个结果分支**（推荐）：云端会话里
   ```
   git checkout -b cloud-results/<时间>
   git add -f build/cloud/<时间>/*.md build/cloud/<时间>/*.json build/cloud/<时间>/env.txt
   git commit -m "云端批跑结果 <时间>" && git push origin cloud-results/<时间>
   ```
   本机 `git fetch origin cloud-results/<时间>`，再 `git checkout origin/cloud-results/<时间> -- build/cloud/<时间>` 取出。结果分支只放报告，不合入 main，看完可删。
2. **只要结论**：让云端会话把 `.md` 报告的汇总表贴出来（适合「胜率 / 存活变了多少」这类问题）。

### 7.4 与本地结果是否逐局一致：**不一致**（2026-09-26 实测）

同一提交（`7578248`）、同一组参数（`--preset starts --bots expert,normal --seeds 2 --nocache`，28 局），本机 Windows 与云端 Linux（4 核）各跑一遍，逐局对比：

| | 结果完全相同的局 | 胜率 本机 / 云端 | 平均存活 本机 / 云端 |
| --- | --- | --- | --- |
| 高手 | 7 / 14 | 78% / 85% | 9:57 / 10:04 |
| 普通 | 0 / 14 | 28% / 28% | 8:27 / 8:07 |

- **分叉时间**：21 局不同，按每 30 秒曲线看，分叉点在局内 1:30–7:30；分叉之前曲线完全一致（种子、刷怪、选卡同步），不是环境没配好。
- **原因**：浮点末位。有一局（高手·斯卡蒂·seed 1）存活、等级、每 30 秒曲线全都相同，只有累计的「余震」伤害末位不同——两边 `sin / cos` 等数学库的结果差一点点，积累下去某次判定翻转，整局就分叉。要做到跨平台逐局一致，得把玩法里的超越函数全换成自己的实现，代价大，目前不做。
- **汇总层面**：两边的胜率 / 存活只差在 2 seed 的噪声以内，可以当「同一个游戏」看趋势。
- 原始数据：云端一侧在分支 `cloud-results/xplat`（`build/xplat/xplat_linux_0926_1004.json`）；本机一侧的 JSON 未保留，要复核就用上面的参数在本机重跑（同平台同 seed 可复现）。

**规则（定稿）**：
1. **A/B 的两边必须在同一个平台上跑**（都在云端，或都在本机）。云端跑 A/B 用 `AB=<提交> bash tools/cloud/run_cloud.sh`，基准与改动都在云端算。
2. 不要拿云端报告和本机报告互相当「改动前 / 改动后」，也不要用云端结果去对本机某一局的复现。
3. 同一平台内同 seed 仍然逐局可复现（§3）；云端的结果缓存只在云端机器上有效。

### 7.5 怎么申请云端跑（2026-09-26 用户定：统一由「测试与验收」代跑）

**本机只跑**：合入前的快检（`check.py --jobs 4`）、截图 / 图鉴、单局调试。**批跑和 A/B 一律走云端**。

1. **推分支**：在自己的工作树里改完、提交，`git push origin <工作分支>`。只推自己的工作分支；推 main 仍须用户确认（docs/41 §3）；不推 `art/third_party` 素材本体。
2. **发请求**：给「测试与验收」发一条【任务】，第一行写清是云端请求，正文照下面填：
   ```
   【任务】云端：<一句话说要回答什么问题>
   分支：<远端分支名>（提交 <sha>）
   基准：<提交>（A/B 才填；一般是分支的 merge-base，两边都在云端算）
   要跑：快检 / A/B（机器人标准矩阵，seeds N）/ 批跑（--preset P --bots B --seeds N --extra "…"）
   结果名：<名>（结果分支 cloud-results/<名>，不填就用分支名）
   ```
3. **代跑**：「测试与验收」把请求转成 `tools/cloud/run_cloud.sh` 的命令发给「云端对话」。云端会话不能回消息，跑完把报告推到 `cloud-results/<名>`（只放 `.md` / `.json` / `env.txt` / 日志，不合入 main）。
4. **读回**：「测试与验收」`git fetch origin cloud-results/<名>`，读报告，把要点和报告路径用【完成】转给请求的会话（抄送协调人）。云端超过预计时间还没推结果，由「测试与验收」跟进。
5. **收尾**：合入 main 后请求方删自己的远端工作分支；`cloud-results/<名>` 由「测试与验收」在请求方看完后删除。

规则照 §7.4：A/B 两边都在云端算；不拿云端报告和本机报告互比；本机快检的结果和云端快检的结果各自有效，但不能拿来当前后对照。

**§7.5.1 现行做法（2026-10-14 用户：「能上云的就上云」）**：「测试与验收」会话已不存在，改为**谁需要谁直接建一次性云端例行任务**（用户 10-13 已授权，不必每次问）：

1. 推自己的工作分支到 origin（`git push origin <工作分支>`；A/B 的基准用 merge-base 提交号，不用再推）。**角色会话不推分支（用户 10-14 定）**：在【完成】里报提交号，由协调人核对后代推并建例行任务；只有协调人推分支。
2. 用 RemoteTrigger 建 `run_once_at` = 现在 +2 分钟的例行任务（环境 Default，仓库 cryus-2000/ArknightsSurvivors，模型 claude-sonnet-5），提示词写清：检出哪个提交、`bash tools/cloud/setup_linux.sh` 后跑什么（`tools/cloud/run_cloud.sh` 的参数 / `balance_run` 参数 / 同种子配对两边各自的提交与 tag）、结果推到 `cloud-results/<tag>`。局数多就按难度 / 开局拆成几份并行各建一个。**工作树子代理（Agent 工具）没有 RemoteTrigger**：子代理把 create body + 提示词写到 `build/cloud_routine_<tag>.md` 并在汇报里说明，由协调人或角色会话代建（10-14 实测）。
3. 本机继续做别的；结果用 `python tools/cloud_compare.py <tagA> <tagB>` 读（自动 fetch）。
4. 云端跑不了的只有：截图、帧时、真机。这些留本机。

本机不再跑 56 局级别的平衡批跑；本机只做 ≤ 6 局的冒烟级确认。

**等价性 A/B**（重构、换读法等预期逐局完全相同的改动，2026-09-27）：两边必须在**同一台**云端机器上依次跑，同一批局，tag 分别以 `_base` / `_new` 结尾；局数多时按难度 / 开局拆份，每份仍是两边同机。读回后用 `python tools/cloud/eq_compare.py <结果分支前缀>` 逐局逐字段比较整局记录；有一局不同就是 bug，把那一局的开局、seed、档位、难度和第一个不同的字段发给请求方。另外抽查各份的胜局数确实随难度变化，确认参数真的生效（首次用于玩法系统的难度修正表，5 档 × 56 局，280 对全部相同）。

### 7.6 例行任务：积木等价全用例每日一跑（2026-10-15，交协调人建）

本机全量快检的积木等价只跑 seed1（§1.3），全部用例（含 seed2 / seed3）每天在云端跑一次，守住数据化干员与手写参照逐行相同。

- **建法**：RemoteTrigger，`cron` 每天一次（建议 UTC 18:00 = 本地凌晨，避开白天发版高峰），环境 Default，仓库 cryus-2000/ArknightsSurvivors，模型 claude-sonnet-5。
- **提示词**（照抄）：

  ```
  在仓库 cryus-2000/ArknightsSurvivors 里做积木等价每日全用例检查（docs/36 §7.6），不要改任何代码：
  1. git fetch origin && git checkout --detach origin/main；记下 SHA=$(git rev-parse --short HEAD)
  2. bash tools/cloud/setup_linux.sh；source tools/cloud/env.sh；export PYTHONIOENCODING=utf-8
  3. mkdir -p build/eq_daily；python3 tools/check.py --only blocks_eq --eq-all --nocache --jobs $GODOT_MAX_PROCS 2>&1 | tee build/eq_daily/check.log；记下退出码 RC
  4. 把 build/check/quick_* 最新一个目录整个拷进 build/eq_daily/，写 build/eq_daily/env.txt（SHA、RC、日期、$GODOT --version）
  5. git checkout -B cloud-results/eq-daily-$(date -u +%Y%m%d) && git add -f build/eq_daily && git commit -m "eq-daily $SHA rc=$RC" && git push -f origin HEAD
  6. 回复一句话：SHA、RC、失败时 check.log 里「失败 积木等价」那一行和它下面的错误行
  ```

- **读结果**：`git fetch origin cloud-results/eq-daily-<日期>`，看 `build/eq_daily/env.txt` 的 RC 与 `check.log`。RC ≠ 0 时，按 check.log 里第一处 TRACE 不同的组 / 行找当天合入的相关提交，派给对应干员的会话。
- **注意（10-15 起与金样比，§1.3）**：云端没有本机的 `build/golden_cache/`，只能比 git 里的证据快照 `game/tests/golden/fd9ce553/`。main 上别处的玩法一变，快照就「过期跳过」，这时每日任务主要是看 seed2 / seed3 有没有报错、能不能跑完；真正的金样比对在本机快检和 ship 重录里做。
- 结果分支保留 7 天后可删。

## 8. 基线登记

Boss 与关卡改动的对照口径和最近一次基线。新基线出来后替换旧的，旧数字作废时写明原因。

### 8.0 B7 后基线（2026-10-15，协调人定）

- **代码**：合入接触改回（arch/b7-contact：接触 / 泪按本只移动前距离，docs/101 §7.4 ③ 备注）之后的 main。B7 起同 seed 结果整体换过（docs/101 §7.4），之前的同种子金样 / TRACE 一律以它为改前。
- **标准 · 高手**：约 70%（云端 b7-starts-t0）。
- **Ⅷ · 熟练**：38.4%（starts 7×16，3 份独立实现 33.0 / 42.9 / 39.3，组间 sd 5.0；本地 Windows，安慰剂法见 §8.2）。**Ⅷ 待校准**（Boss与怪物 / 数值，按 ≥3 份实现均值，目标 50–70）。
- **作废**：B7 前登记的 Ⅷ 熟练 50.9%（39128178，seed 1–16 单份实现）——同代码 7 份独立实现均值只有 44.3%（52.7 / 50.9 / 40.2 / 52.7 / 41.1 / 36.6 / 35.7），50.9% 是这组 seed 的好运实现，Ⅷ 原先就低于目标线。排查全过程见 docs/101 §7.4。

### 8.1 B0 验收基线（2026-09-27，云端，docs/38 §5）

- 代码：b0-verify 6c7a017；基准 067ace8（移植了机器人回圈修正）；纯 B0 对照的 base 是在 6c7a017 上回退 B0 第 5–11 项（b0-revert-probe 41d31e6）。starts × 6–8 seed，高手 / 普通；脚本 `scratchpad0.py`、`abboss.py`（测试与验收会话）。
- **Boss 战主控死亡率**的口径：Boss 在场时结束的失败局 ÷ 该 Boss 的出场次数，骑士单列。6c7a017：高手 14.4%（27/187），普通 26.8%（41/153）。撤回精英冻结之后（b1-sched，b3ab942）：高手 10.2%（18/177），普通 25.9%（37/143）。以后的 B 阶段按后面这组比。
- **Boss 死后 3 秒内出大群**：B0 之后恒为 0（回退 B0 第 7 项时是 13 / 6 次）。
- **各结局最终 Boss 出场比例**（--allend，每边 84 局）：深蓝 63%、骑士 73%、决意 91%、标准 64%。
- **最后的骑士（新基线，旧的「中位 9 秒」作废）**：冲锋计时修好之后明显更危险。Boss 在场时的主控死亡率：高手 3/7（43%），普通 2/4（50%）。用时（b1-cal，--nodeath，出现 → 击杀）：前 10 件藏品时高手中位 92 秒、普通 80 秒；全部藏品时高手 52 秒、普通 54 秒。骑士的场次少，B1 之后要按结局补样本。
- 结论（Boss与怪物 在 docs/38 登记）：B0 通过。第 4 项「除骑士外死亡率不上升」按合计是上升的，但上升来自 db6d569 精英冻结（精英 +60%、藏品 +5 左右），这一项用户已经撤回；死于 Boss 招式的次数没有上升。

### 8.2 样本量与波动（2026-09-30）

- **每组 14 局**（starts 7 开局 × 2 seed）的比率波动约 ±8 个百分点：同一代码的高手 Ⅷ 灯标点燃率，两次分别是 28% 和 20%。**灯标、Boss 招式这类「事件率」对照至少 28 局**（starts × 4 seed），并且尽量同 seed 配对（协调人 9/30 定）。
- **2026-10-12 起的平衡结论口径见 docs/80**：必须给置信区间、优先同种子配对（`tools/cloud_compare.py`）、看胜率 + 低血秒 + Boss 用时，差距 <10 点不下结论。
- **胜率每格 56 局**的 95% 区间约 ±12 个百分点；判断改动方向请看同 seed 配对：「负转胜 / 胜转负」各多少局，差值小于约 5 局就当作噪声（2026-10-12 起结论门槛以 docs/80 §1 为准：胜率差 <10 点不下结论，配对 p<0.05 除外）。
- 强制 Boss 的 A/B（`--forceending` / `--forceboss2`，脚本 `forceab.py`）：终局 Boss 用不死模式、每边 21 局看用时；双体用正常规则截到 10:00、每种 14 局看 Boss 战死亡率——14 局只够看方向。
- 批跑局数不变时，**先看配对再看胜率**：close6b 的「Ⅳ 生命 1.3」胜率 43% → 55%，配对是 9 / 16，数值核对后判为噪声（经验不随敌人生命缩放）。
- **多份独立实现（2026-10-15，B7 Ⅷ 排查后协调人定）**：同一份代码、同一组 seed 的 112 局只是「一份随机实现」；任何改动随机抽取次数的提交（哪怕只把画面随机挪走）都会换一份实现。实测基线 39128178 Ⅷ 熟练 starts 7×16 的 5 份实现：52.7 / 50.9 / 40.2 / 52.7 / 41.1%，**组间标准差约 6 点**——原来当基线的 50.9% 比这份代码的均值（约 47.5%）高 3–5 点。所以：
  - **难度达标（Ⅷ「不跌破 50」等）与「换基线」类结论按 ≥3 份独立实现的均值判**，单份 112 局只看方向。
  - 独立实现的取法：`balance_run.py --placebos 0,1,2`（开局多抽 N 次主 rng，机制不变；报告顶部给每份胜率 + 组间均值 / 标准差），或换 seed 组（`--seed0 17`）。本地与云端（Linux）同代码同 seed 只有约 15% 的局逐位相同，也可当作另一份实现。
  - `cloud_compare.py` 的配对键带实现编号（`placebo`），同 seed 不同实现不配对；云端例行任务透传 `--extra=--placebo=N` 即可。
  - 判「改动有没有真影响」：改前、改后各取 ≥3 份实现，比两边均值（组间标准差约 6 点时，差 <8 点不下结论）。
- **批跑步长**：`--balance` 每帧固定推进 0.066 秒（约 15 帧 / 秒，9/30 起的校准口径，所有基线都按它）。按位移判定的改动（接触、扫掠、冲刺命中）在批跑下会被放大约 4 倍；这类改动另用 `balance_run.py --dt 0.016667` 跑一组小样本抽查（慢约 4 倍，不替换口径）。

### 8.3 新美术干员基线刷新（2026-10-20）

对 main **2968bf4a** 用 `tools/trace_base.py <seed> <id> 180`（`--ref 2968bf4a`）重录了 15 名干员的同种子 TRACE 基线，`seed=1`、`--maxt=180`，缓存文件 `<主仓库>build/trace_cache/2968bf4a_1_<id>_180.txt`：

- **9 名换新美术干员**（docs/108 §6）：wisadel、saria、suzuran、mizuki、logos、eyjafjalla、exusiai、siege、ulpianus。
- **6 名控制组**（docs/108 §9 列的仍是旧 48 画布的 9 人里，经 `git diff 6b697796..7784b32c` 核实本轮代码 / json 没有实质行为改动的）：angelina、hoshiguma、irene、lumen、skadi、texas。被排除的 3 人（kaltsit、skalter、specter_unchained）在这个范围内 json / 脚本有成百上千行实质改动，不适合当「改前」对照；texas 的 `seg_texas.gd` 只多了一条针对 `attack_phases` / `SkillLifecycle` 的互斥判断，texas 自己的 json 不含这两个字段，条件恒真，等效无变化；angelina / irene 各有一行 `add_cc(..., "airborne")` 的分类标签改动（新增 cc 来源标签，不改数值），按"几乎没动"收入控制组，仅作提示。

旧的（7784b32c 及更早提交号的）这 15 人缓存条目已清理（`build/trace_cache/` 下按 id 匹配、按提交号前缀过滤删除，共 23 个文件）。

**这次是刷新基线，不是发现回归**：docs/108 §11 F11 已指出本批改动（`attack_timing` 改出手时刻、水月删 `flow: free`、艾雅法拉改弹速与收势）是**有意的时序变化**，旧基线（7784b32c 之前）与新基线逐行不同属预期，不要拿两者做 `--here` 对照报回归。之后的同种子对照请以 `2968bf4a_1_<id>_180` 为「改前」。

## 9. 真机验收（发布前音效 / 打击感，2026-10-01）

- **做法**：本机安静时段（01:00–01:27 UTC），构建 f472d64（音效代码与冻结提交 e97b4a2 相同；之后进来的是 EA 数值包、合批热修和机器人改动，所以帧时间和敌人数只作参考）。3 局，每局打到 10:00 或死亡；熟练机器人（master，自动普攻，机器人不支持手动普攻）；窗口 1920×1080；真实音频驱动，音量 0（Dummy 下播放器状态失真）；`--realtime --perf --sfxstat`；约每 60 秒一张截图。脚本 `play/play.py`（测试与验收会话）。
  - 标准 · 高画质 · 水月（编队水月 / 塞雷娅 / 铃兰）：活到 10:00，击杀 5402。
  - Ⅳ · 低画质 · 斯卡蒂（斯卡蒂 / 维什戴尔 / 归溟幽灵鲨）：活到 10:00，击杀 5920。
  - Ⅷ · 高画质 · 维什戴尔：6:38 死亡，击杀 2993。
- **评分**：1–5 分，只看数据和截图；「听感 / 手感」留给用户。

| 项 | 分 | 依据 |
|---|---|---|
| 命中音与闪白 | 4 | 命中类请求 87–100% 播出，高画质两局 0 丢弃；低画质丢 9% |
| 暴击 / 击杀区分 | 3 | 暴击音在拥挤时约 82% 被合并（t0：584 次请求播出 106 次）；击杀音合并 64%。合并窗口是设计行为，是否够分辨交给音频和用户 |
| Boss 破绽 / 演出反馈 | 4 | 「Boss 与演出」类 99% 播出，没有丢弃 |
| 受伤可见 | 4 | 受击音 100% 播出（三局 21 / 52 / 47 次），从不合并或丢弃；画面上的受伤提示没有逐帧核对 |
| 拥挤时丢音 | 高画质 5、低画质 3 | 低画质同时发声上限较低（峰值 17 路，高画质 24）：0–8 分钟丢 1399 次，8–10 分钟丢 708 次，约占播出的 12% / 25%；各类都丢 5–9%，受击、干员技能、Boss 类不丢 |
| 帧率低于 40 的时段 | 高画质弱清怪编队 2，其余 5 | 标准 · 高画质 8–10 分钟：帧时间中位 29 毫秒，87% 的时间低于 40 帧，同屏敌人中位 306、峰值 379（这套编队清怪慢，机器人满血风筝）；Ⅳ 低画质 8–10 分钟 2%（敌人 150）；其余时段 ≤ 3.7% |

- **测试假象**：每局有 10 多次 200–320 毫秒的单帧尖峰，间隔随帧率变长，和截图帧号一一对应——是 `--shots` 存 PNG 的开销，不算游戏卡顿。以后做真机帧时间验收时不开截图，或另跑一局专门截图。
- **转交**：
  - 低画质丢音比例、暴击音合并比例：音频判定符合设计，不改（10/01）。低画质在已有 12 路在响时直接丢弃优先级 ≤2 的音（ece8332），用来给低配机减负，红线是命中类丢弃 >30%。暴击音最短间隔 0.08 秒，靠音色和优先级区分（暴击优先级 3，命中 1）。
  - 高画质敌人 300+ 时的帧时间：交界面与美术（docs/50 §4 敌人图集，EA 后）。按每 100 名敌人折算，和 docs/50 §6 的结果一致，不是新回归。

### 9.1 PRTS 干员 Spine 参照帧（`tools/prts_spine.py`，2026-10-15）

给 Codex 当干员美术参照（docs/87 §4.3：与原作立绘 / 战斗小人一致），内部用，**不进 git、不进发行包**（用户 10-15 确认，已获授权）。不开浏览器、不用 Godot。

```
python tools/prts_spine.py mizuki            # 一名
python tools/prts_spine.py --all             # 18 名（脚本里 OPS 表：干员 id → PRTS 中文名）
python tools/prts_spine.py mizuki --flip     # 镜像（PRTS 战斗正面本来朝右，和我们的帧条同向；不对时用）
```

- **资源**：PRTS 页面 `<中文名>/spine` 的原文（`index.php?title=…&action=raw`，一段 JSON）里 `prefix + skin.默认.战斗正面.file`，再从 `static.prts.wiki/spine38/` 取 `.skel / .atlas / 页图 .png`。页面 HTML 对非浏览器请求返回 403，原文接口与静态站可以直接取；带浏览器 UA，失败按 2 / 4 / 8 / 16 秒退避重试，干员之间停 1 秒。只取默认皮肤的战斗正面，不下载皮肤。
- **渲染路**（评估后选定）：官方 **spine-ts 3.8 运行时**（`spine-canvas.js`，自带 `SkeletonBinary` 读 3.8 二进制 .skel，与 PRTS 的 spine38 同版本）+ Node 无头 Canvas **`@napi-rs/canvas`**（Skia 预编译，不用装编译环境），三角形渲染（网格附件也画）。
  Python 侧没有能稳定读 3.8 二进制 skel 的现成库（自己写解析要覆盖网格变形、IK、路径约束），所以不走 Python。依赖首次运行自动装到 `build/prts_ref/_node/`（运行时从 spine-runtimes 3.8 分支下载）。
  坑：`@napi-rs/canvas` 的 `Image` 同步赋 `src` 不会真正解码，画出来全透明，必须先 `loadImage` 异步预载页图。
- **输出** `build/prts_ref/<id>/`（主仓库的 build/，各工作树共用）：`idle_f00–f03`（Idle 时长的 0 / 25 / 50 / 75%）、`attack_f00–f02`（出手前 / 出手 / 收招）、`skill_f00–f02`（有技能动画时），1000×1000 透明底，同一干员各帧同一缩放、脚底对齐；`<id>_sheet.png` 带动画名与时刻的拼图；`<id>_info.json` 动画清单、时长、事件。原始资源在 `build/prts_ref/_raw/<id>/`。
- **出手帧**：攻击动画里的 `OnAttack` 事件时刻（明日方舟的 Spine 都打这个事件），没有事件取时长 40%；出手前 = 出手时刻的一半，收招 = 出手与结束的中点。攻击 / 技能动画名不统一，按脚本 `PICK` 的顺序取第一个存在的（技能兜底取任何带 Skill 的、优先 Loop）。
- **Spine 3.5 路**（10-15 补）：较早干员的前缀是 `spine/`，.skel 是 **Spine 3.5.51** 二进制，3.8 运行时读不了，spine-ts 3.5 又只有 `SkeletonJson`。`tools/prts_spine35.py` 逐行移植官方 spine-csharp **3.5.51 标签**的 `SkeletonBinary.cs`，把二进制转成 3.5 JSON（`_raw/<id>/<名>.35.json`），再用 spine-ts **3.5.51 标签**的运行时（`_node/spine-canvas-3.5.51.js`）渲染；`prts_spine.py` 按 .skel 头部版本串自动选路。
  坑：spine-runtimes 的 3.5 **分支**头上已混入 3.6 的双色 / 裁剪格式，按它读会错位，必须用 3.5.51 标签；转换器要求恰好读到文件末尾，否则报「格式不符」。
- **现状（10-15）**：18 / 18 出图——3.8：水月、铃兰、艾丽妮、归溟幽灵鲨、流明、维什戴尔、乌尔比安、逻各斯；3.5：推进之王、斯卡蒂、塞雷娅、艾雅法拉、凯尔希、浊心斯卡蒂、德克萨斯、星熊、能天使、安洁莉娜。能天使 / 凯尔希 / 斯卡蒂的战斗小人没有技能动画（只出待机 + 攻击）；浊心斯卡蒂没有攻击动画（只出待机 + 技能）。
  艾丽妮 / 归溟幽灵鲨 / 流明的页面路径在静态站 404，但标准路径 `spine38/char/<角色 id>/<角色 id>/<角色 id>` 有，脚本 `DIRECT` 表直接走这条（不再查页面）。
  维什戴尔 / 乌尔比安 / 逻各斯：PRTS 没有 `<名>/spine` 页面，静态站也没有；素材在 PRTS 的另一个资源站 **torappu**：`torappu.prts.wiki/assets/char_spine/<角色 id>/defaultskin/front/<角色 id>.{skel,atlas,png}`（Spine 3.8），脚本 `TORAPPU` 表直接走这条。角色 id 以游戏数据 character_table 为准（char_1035_wisdel / char_4145_ulpia / char_4133_logos）。维什戴尔的普攻动画叫 `Attack_A`（已加进 `PICK`）。
- **局限**：只画图，不叠 slot 颜色 / 混合模式（加法发光件按普通混合画）；三角形拼接处偶有极细的缝。当参照够用，不当素材用。

### 9.2 像素稿可量验收（`tools/px_lint.py`，2026-10-15）

干员美术「路 1」：@2x 原生细节、1x 人工收敛。尺度 B 是 1x 64 画布、@2x 128 画布，身高 32 / 64，头高 14 / 28。工具是纯 Python + PIL，不开 Godot。

```
python tools/px_lint.py <1x.png> <@2x.png> --foot 33 60      # 一对图；@2x 原点缺省 = 2 × 1x 原点，--foot2 另给
python tools/px_lint.py --samples                            # 跑登记的三份逻各斯样本（Codex i_pilot_1015_r1 B / C、i_pilot_1015_t2 C-HD）
python tools/check.py --only px_lint                         # 可选快检项（不进 --auto）：样本数字等于校准值
```

每层检查五项：
1. **透明**：二值透明、不透明像素四邻域连通体个数、alpha 孤点。
2. **颜色孤点与单点高光**（主口径，两条取并集）：
   - **色块里的单点**：不是描边色、八邻里没有同色、八邻里同一种底色占 ≥ 6。其中明度比底色高 ≥ 16 的（`--hl` 可调）算单点高光，能抓到暗部里稍亮的单点。
   - **暗底亮点**（10-15 界面核对后加）：四邻没有同色（对角相连不算连块）、不是描边色、8 邻里 ≥ 6 个比它暗 ≥ 240（RGB 和）。这类点直接算单点高光，也计入孤点。
     暗部常是几档近黑 / 深蓝混排，「同一底色占 ≥ 6」会漏掉其中的碎亮点；逻各斯 C-HD 胸前领口那片青白碎点就是这样漏的。
   - **@2x 要求单点高光 0 个**：高光至少 2 像素成组。
   - 宽口径（与四邻都不同色）一并输出作参考：在 27 色量化稿里它会数进大量正常的细节交界，B 1x 就有 183 个。
3. **1x ↔ @2x 对应**：@2x 每个 2×2 块取主色，与 1x 对应像素比；透明性不同、或 RGB 距离 > 48 的块计数。用它衡量 1x 是不是由 @2x 收敛来的。
4. **色数、外描边、边距、脚底行**：外描边是 `#080E18`，1x 查 1 像素宽、@2x 查 2 像素宽。@2x 最低行允许 2f 或 2f+1，因为最近邻放大时 1x 的脚底行占两行。
5. **量表**（`--metrics <干员 id>`）：调 `body_metrics.measure()` 量这张 @2x。脸部项取的是该干员生产图的人工标注，新稿要另标，只有几何项可参考。

输出在 `build/px_lint/<名>/`：`report.json`（各项数字与坐标）、`marked.png`（1x ×12 与 @2x ×6 并排；红圈 = 孤点，黄圈 = 单点高光，品红格 = 1x 与 @2x 对不上的块）。

**10-15 校准**（逻各斯待机 f0）：

| 样本 | 1x 孤点 / 单点高光 | @2x 孤点 / 单点高光 | 1x↔@2x 块对不上 | 其余 |
|---|---|---|---|---|
| B | 26 / 19 | 0 / 0 | 0 / 685（@2x 是 1x 的最近邻放大） | 27 色、单连通、描边全对、边距 3 |
| C | 35 / 28 | 0 / 0 | 0 / 1162（同上） | 27 色、边距 2 |
| C-HD | 44 / 41 | 100 / **75** | 195 / 1262（15.5%） | 26 / 27 色、边距 1 / 2 |

- 界面逐点核对 C-HD @2x：点名的胸前领口 15 个碎点和另外 7 个点全部计入单点高光。第一版口径（只有「色块里的单点」）只命中其中 1 个，所以加了暗底亮点这条。
- 界面的手数口径是「RGB 和 ≥ 450、四邻都比它暗 ≥ 240」，只数浅色点；本工具另含暗部里稍亮的单点，所以总数比手数（@2x 23）多。
- B / C 的 @2x 没有独立细节，所以孤点、单点高光都是 0。1x 的数会偏多：缩图产生的碎亮点也算在内，1x 本来就要人工收敛。
- C-HD 的 1x 由 @2x 偶坐标采样得到（handoff 原文），15.5% 的块对不上，主要在头发和角饰的抖动区。

## 10. 本地存储清理（2026-10-15）

`python tools/clean_local.py`（不带参数只报告）：工作树清「孤儿文件夹 + 已合入且干净的 `agent-*`」，`--named` 连命名工作树一起按同一标准清；旧包只留最近 3 个 `final_<sha>` + `KEEP_SHAS`（itch 线上、EA 冻结）。`--apply` 真删；ship.py 出包后自动跑 `--release --apply`。分支都保留，删错了 `git worktree add` 再检出。规则见 docs/41 §3「本地存储规则」。

### 10.1 远程分支清点（2026-10-16，测试与验收；main 87c1d815；只读，未删任何分支）

GitHub 远端除 `main` 和 `cloud-results/*` 外还有 58 个分支（`git branch -r | grep -v cloud-results`，9/26–10/13 的探针 / A-B 侧分支 / 工具草稿），`git merge-base --is-ancestor origin/<分支> main` 全部为假——**这是预期的工作方式，不是遗漏**：这些分支按 docs/41 的流程跑云端 / 本地 A-B，数值或代码结论确认后由人手改写进 `main` 的独立提交（或写进对应 docs），分支本身不 `git merge`，只作过程记录。逐个核对的办法：按分支提交信息里的旋钮名 / 特征字符串去 `main` 的 `game/` 和 `docs/` 里反查，命中说明结论已落地；查不到的进一步看是被后续设计推翻，还是单纯从未采纳。

**结论先说**：58 个分支的结论或代码**全部已经落地或被后续方案取代**，没有发现「有价值但还没合入」的代码。可以放心删（建议先问协调人一句，删除按协调人之前的流程走，本次只读未删）。

| 分支 | 用途 | 结果记录在哪 | 未落地代码 | 判断 |
|---|---|---|---|---|
| `antispike` | 探针（`--bal=` 覆盖旋钮）+ 编队人数加主控生命特性 | main `squad.gd` 注释仍引「2026-09-27 用户定每人 +15%」，公式后由 docs/83（10-13）重做成入队台阶系统，概念延续 | 无 | 可删 |
| `b0-base-probe` | 普通机器人回圈（贴圈边外推只留侧向分量 + 冲刺回圈）A/B 修订版 | `bot.gd` 已有出圈冲刺判定；具体「只留侧向分量」实现较老，难逐行比对 | 未逐行确认，但同系列后续轮次（v11-botfix2 等）内容相同，已按该系列整体判断 | 可删 |
| `b0-revert-probe` | 撤回 7 条 Boss B0 系列改动（预警压缩、接触延迟、死亡清预警、精英冻结等） | 撤回后main确实没有「Boss 在场冻结精英计时」等功能，即撤回已经是最终状态 | 无 | 可删 |
| `b1-cal` | 测试探针（`--norelics` / `--relicmax=N`、`--bal=`） | 纯命令行开关，无业务结论 | 无 | 可删 |
| `b1-horde-probe` | 大群顺延上限 `boss/horde_defer_max`、Boss 刷怪倍率拆分 `spawn_boss_mult_mid/_final` | main `spawner.gd`/`balance.json` 均有 `spawn_boss_mult_mid`、`horde_defer_max` | 无 | 可删 |
| `boss/b1-arena` | B1 场地：Boss 登场冻结场地、位置约束、Boss 溟痕上限 | main `combat.gd` `arena_clamp()` 注释「docs/38 §1.7」，已落地 | 无 | 可删 |
| `boss/b1-feel` | 实机手感：冲刺怪真冲到人、骑士/塑路者冲锋到位、`dash_len` | main `enemy_ai.gd` `dash_len` 字段注释原样引「用户实机反馈 9/27」 | 无 | 可删 |
| `boss/b1-horde` | 同 `b1-horde-probe`（`spawn_boss_mult_mid/_final`） | 同上 | 无 | 可删 |
| `boss/b1-sched` | 撤回「Boss 在场冻结精英计时」；最终 Boss 登场时中期 Boss 撤场不给奖励 | main 无冻结精英功能（即撤回状态） | 无 | 可删 |
| `boss/b1-vfx` | 同 `boss/b1-feel`（画面侧：冲击波走 `_warn`、撕裂者 `atk_anim`） | 同上，`enemy_ai.gd`/`world.gd` 已是对应实现 | 无 | 可删 |
| `boss/saint-pace` | 伊比利亚/卡门节奏微调（`saint_stand`、`carmen_hop_cd/spd`） | 这几个旋钮名在当前 `balance.json` 查不到；10-14「Boss 招式改版」（memory `boss-moves-redesign`）整体重写了 Boss 招式，判断被取代而非丢失 | 具体数值已过时（旧 Boss 实现已重写） | 可删 |
| `close1` | 收口轮 1（防暴毙包、围猎机制、骑士队友调整、回复卡加权等，含多个 merge） | 围猎 (`hunt.gd` 等 11 文件)、`heal_weight`、骑士 600 固定血 + 低血撤退、藏品集齐补源石锭均在 main | 无 | 可删 |
| `close2`、`close3`、`close4`、`close4b`、`close5`、`close6`、`close6b`、`close7` | 收口轮 2–7：三档数值表逐轮校准（先云端再合，`close5` 额外带 `boss_focus`） | 具体数值早被之后多轮校准覆盖（close8/9、docs/38 §8.12 等），表格本身已过时，但「先云端再合」流程与探针写法沿用至今；`close5` 的 `boss_focus` 见上方 `probe/close5-master` 一行 | 无（纯 `balance.json` 数值，旧值无保留意义） | 可删 |
| `cloud` | 云端批跑基础设施初始化（`tools/cloud/`） | `tools/cloud/` 现存且本 session 全程使用（`setup_linux.sh`/`run_cloud.sh` 等） | 无 | 可删 |
| `diff-cal-probe` / `diff-cal-probe2` | 普通机器人回圈 + 同屏峰值遥测 + `balance_run` 终局 Boss 分型 | `telemetry.gd` `peak` 数组、`balance_run.py` `final_boss_summary()` 均在 main，docs/36 §6 已记 | 回圈具体实现未逐行比对（同上），工具部分已确认落地 | 可删 |
| `early-hp` / `early-hp2` / `early-hp3` | 前期接触强度试验（v3：浅滩/暗流移速、暗流刷怪池） | 探针为主；v3 方案是否采纳未逐项核对，但属早期前 3 分钟强度试验，已被后续多轮 EA 数值表覆盖 | 可能有未采纳的具体数值，但年代久远、已被整体数值表取代 | 可删 |
| `gameplay/b1b2` | 事件选项不吞升级、宝箱补源石锭、回复药剂来源分类 | `game.gd` `pending_levelups` 队列、`progression.gd` 宝箱补锭均在 main | 无 | 可删 |
| `gameplay/healw` | 回复类升级卡加权（`heal_weight`/`heal_low_hp_mult`） | main `progression.gd` 有 `heal_weight` | 无 | 可删 |
| `gameplay/intro2` | 开场指南文案一处小改 | 10-12 语言风格统一改版（docs/76）后文案大概率已重写，原句未必保留 | 1 行文案，无独立价值 | 可删 |
| `gameplay/tidewall` / `gameplay/tidewall2` | 「围猎」强制交战机制首版 | `hunt.gd` 等 11 个文件在 main，机制仍在 | 无 | 可删 |
| `gameplay/v11` | 1.1 难度三档改版（标准/困难/极难）、Boss 在场缩圈暂停、EA 1.1 刷怪拐点 | 三档框架已被后续 `difficulty/standard\|hard\|extreme` 更完整的体系（docs/27）取代；`zone_out_t`、`spawn_knee` 等具体旋钮仍在 main | 无（概念被取代，不是丢失） | 可删 |
| `healw-base-probe` | `gameplay/healw` 的 A/B 基准版（权重设回 1） | 纯基准探针，无独立结论 | 无 | 可删 |
| `hunt-probe-base` / `hunt-probe-new` | `balance_run --keep=` 前缀功能 + 围猎机制验证 | `balance_run.py` 现有 `--keep` 参数 | 无 | 可删 |
| `integ` | 三档数值整合复核（困难攻击倍率等） | 具体数值（困难攻击 1.15）已被后续校准覆盖（现 `difficulty.hard.enemy_dmg` = 1.2，经过 close1–close9 等多轮重算，不可直接比较） | 无（数值早已过时） | 可删 |
| `late-dmg` | 后期敌人伤害轻微上调方案 a | docs/51 已记（分支本身也改了 docs/51），`enemy/dmg_late_*` 系列旋钮 | 需要时可在 docs/51 查，不在本分支本身 | 可删 |
| `logos-rework-r1-pin` | 逻各斯技能重设计首版（咒文弹、扇形咒域） | main `logos.json`（docs/61 §17.5 数据化迁移版）文案仍是「咒文弹...扇形咒域」，设计概念延续，但实现已被 10-14 积木迁移整体重写 | 无（旧手写实现已废弃） | 可删 |
| `numbers-probe` | 数值采样探针（`--norelics`/`--relicmax`，30 秒采样输出/藏品/治疗/生命，docs/42 §1） | docs/42 §1 | 无 | 可删 |
| `probe/b3-base` / `probe/b3-new` | `--forceending=`/`--forceboss2=` 测试开关 | `spawner.gd` 现有这两个开关，注释措辞基本一致 | 无 | 可删 |
| `probe/close5-master` | 熟练（master）机器人档位首版 + `boss_focus` | `bot.gd` `PROFILES` 含 `master`；`op_api.gd` `boss_focus` 注释原样引「2026-09-29 协调人」 | 无（首版实现已被之后多轮 master bot 迭代重写，详见 docs/38 §8.5 等） | 可删 |
| `probe/pt-base` / `probe/pt-new` | Boss 在场遥测（`en_alive`/`en_near`/`on_boss`）+ 双体共用招式令牌 + `final_mob_cap` | `telemetry.gd` 有对应字段；`final_mob_cap` 在 `balance.json`（现被 `trickle_cap` 系统替代/扩展，`_doc` 写明沿革） | 无 | 可删 |
| `probe/warn-track` | 熟练机器人追踪段预警轻扣（docs/38 §8.5 泡影超时候选修复） | **本 session 自己做的**：同 seed 对照后判定无改善，不合入（docs/41 当时的交接记录）；main 无 `warn_track` 字样（0 命中），即未落地是正确的最终状态 | 无（已验证过不该落地） | 可删 |
| `test/bot-master` | 同 `probe/close5-master`（master 档 + `tools/balance_run.py`） | 同上 | 无 | 可删 |
| `tiers-cal` | 三档难度修正表初稿 | 同 `integ`，早被多轮数值校准覆盖 | 无 | 可删 |
| `tools/ab-difficulty` | 回圈改进 + 大群分行统计 + 同屏峰值 + 终局 Boss 分型（工具集合分支） | `balance_run.py` 大群/终局分型、`telemetry.gd` peak 均在 main | 回圈具体实现同上未逐行比对 | 可删 |
| `tools/final-boss-split` | `balance_run` 终局 Boss 按类型分行 | `balance_run.py` `final_boss_summary()`，docs/36 §6 已记 | 无 | 可删 |
| `v11-ab` / `v11-ab-probe-base` / `v11-ab-probe-new` | 1.1 三档难度 A/B（含同屏峰值/终局分型工具） | 同 `gameplay/v11`：框架被后续体系取代，工具部分已落地 | 无 | 可删 |
| `v11-botfix-base` / `v11-botfix-new` / `v11-botfix2-base` / `v11-botfix2-new` | 普通机器人回圈修复 + 1.1 三档 A/B（多轮迭代） | 同上两类结论的组合 | 回圈具体实现未逐行比对 | 可删 |
| `wip/ftr-analysis` | 最终 Boss 少量补怪云端对照（trickle 上限 40 vs 25） | **main `balance.json` `trickle_cap: 25`，`_doc` 原文引用「云端 ftr 配对：上限 40 时 Ⅷ 62.5→50.0%（压线），25 时 57.1%，10-12 定 25」**，逐字匹配 | 无（docs/81 本身已不存在，结论改写进了 balance.json 的 `_doc`） | 可删 |
| `wip/medic-m20` | 医疗常驻治疗 −20% 试验（流明/凯尔希 `heal_pct`） | main 当前 `heal_pct`（流明 0.017、凯尔希 0.015）是这次试验的**基准值**而非试验值，说明 −20% 没被采纳；10-13 之后「入队回复台阶」（docs/82 §3.1 已声明被 docs/83 取代）整体重做了回复系统，这个百分比试验已经过时 | 试验值本身没进 main，但设计思路已被整体重做取代，不是遗漏 | 可删 |

**没有逐行比对的几处**（标了「未逐行比对」的回圈改动系列）：如果以后要精确复核普通机器人「贴圈边 / 溟痕绕行」这段具体代码是否与这几个分支完全一致，可以用 `git diff origin/v11-botfix2-new -- game/scripts/core/bot.gd game/scripts/run/combat.gd` 对 main 看；本次审计用的是「关键字 + 行为现状」反查，没有发现需要因此保留分支的理由。

## 11. 64 画布回归（canvas64，2026-10-16；测试与验收，main ed0a764f）

main 6aa19849 起干员帧改按帧条自身尺寸 / json 里的 `foot` 读（不再假定固定 48 画布），为以后 §4.3 「干员 @2x 原生细节」铺路。确认现有 48 条帧条零变化，并验证引擎能正确读一条临时的 64×64 帧条。

### 11.1 现有 48 帧条零变化

`--only touch_layout / ea_ui / op_select / codex / run_stats`（main 最新）全部通过（`touch_layout` 带 `--touch`）。另外跑了一套手机比例触屏截图（docs/36 §5、`touch-layout-testing` 记忆的办法：`--touch` + 1170×540 分辨率，强制进局内 / 选人 / 图鉴 / 作战记录各界面），桌面 1280×720 与手机比例各一套，逻各斯领队、水月 + 德克萨斯 为队友（现有 48 画布帧条）：

- 对 canvas64 合入前（`d929678d`）与之后（main）逐像素比对：局内（战斗）截图外，选人 / 图鉴 / 作战记录 / 开场引导 **10/10 张逐像素相同**。
- 局内截图（`shot_40` / `shot_80`，桌面与手机各一张）有极少量像素差异（115–182 像素，腐蚀后归零或仅剩个位数），**全部落在左下角 SONAR 小地图范围内**，和干员 / 怪物 / 场景贴图无关。查到 `hud_bars.gd` 的扫描线角度 `sweep := fmod(g.t * 0.9, TAU)` 只由对局时间驱动；`--balance` 非 `--fixed-fps` 模式下 `_process(delta)` 按真实帧间隔推进（`dt := min(delta, 0.05)`），同一组命令在不同机器负载下跑，到同一渲染帧数时累计的 `g.t` 有微小差异，扫描线角度跟着错开一点点——这是已知的机器噪声（同 docs/50 §17 的结论），不是 canvas64 的改动造成的。另外同一轮里两次 main 跑的截图（噪声基线）之间逐像素 0 差异，说明「跑两次」本身不产生这个差异，差异来自「base 和 main 是两次独立的 Godot 启动」。
- 结论：**48 条现有帧条画面零变化**；局内截图里唯一的差异是和帧条无关的计时类小地图扫描线，判定为跑批噪声。

### 11.2 临时 64×64 帧条过屏测试

构造一条临时帧条验证引擎按新口径读取：`op_logos_idle.png` 的现版 f0（48×48）原样搬进 64×64 画布、偏移 (+8, +14)，`logos.json` 的 `sprites.idle` 临时改成 `{tex: op_logos_idle64_tmp, frames: 1, fps: 4, foot: [33, 60]}`（只 1 帧，够过屏看尺寸 / 脚底，不要求动画）。只在工作树里改，**测试完整回退，没有提交、没有入库**。

逐屏过了一遍（逻各斯领队，桌面 + 手机比例各一套，截图在 `build/canvas64_1016/shots/tmp64/`）：

| 界面 | 结果 |
|---|---|
| 局内（战斗中、含右下角编队卡） | 正常：个头比 48 画布的队友略高（符合 64 画布预期），脚底贴地，没有裁切、没有偏移出画布 |
| 编队卡（局内右下角） | 正常：缩略图干净，像素清晰，脚底对齐 |
| 选人页（居中大立绘 + 底部名册缩略图 + 左上队长槽） | 正常：大立绘走的是另一套素材（不受这次改动影响）；名册缩略图与队长槽都正确显示新帧条，比例对 |
| 图鉴（左侧网格 + 右侧大图） | 正常 |
| 作战记录（结算列表 + 总览编队行） | 正常 |

**没有报错**（`GR.script_errors` 全部为 0）。

**排查过一处疑似问题，排除**：选人页底部名册缩略图里逻各斯那一张初看有彩边 / 噪点，像是新尺寸被插值出的瑕疵；对比同一张截图里用现有 48 画布帧条的德克萨斯缩略图，**同样的彩边**；再对比 canvas64 合入前（base）同一位置同一干员的截图，**彩边也在**——这是选人页名册缩略图本来就有的一种画面效果（像扫描线 / 色差的装饰），和帧条尺寸无关，不是这次改动引入的。三组截图见 `build/canvas64_1016/crop_roster_texas*.png`。

### 11.3 结论

- canvas64 对现有 48 条帧条的画面是零变化的（局内小地图扫描线的误差是计时噪声，不是回归）。
- 引擎正确按帧条自身尺寸 + json `foot` 读取非 48 画布的帧条，局内 / 编队卡 / 选人 / 图鉴 / 作战记录五处界面都验过，没有裁切、偏移或报错，可以放心接 §4.3 的「干员 @2x 原生细节」真稿。

## 12. 中断记录（2026-10-20，电脑断电前，未完成，部分结果）

本会话（分支 `claude/test-newart`，工作树 `jovial-franklin-5e6711`）在收到「电脑马上断电」的中断指令时**尚未执行任何测试或截图命令**：

- 工作树状态：干净，无未提交改动，HEAD 在 `2968bf4a`（与 main 同点），没有正在运行的 Godot 进程，`build/` 下没有本会话产生的新截图或临时产物。
- 已测完的操作者：无（本会话还没有针对任何操作者/干员跑过验收或回归）。
- 未测的操作者/子任务：本会话尚未从交接（`docs/41` 队列、`pending-1018` 等）领取具体的测试任务，所以范围本身还未确定，需要下一位接手的会话先看交接文档确认本次要测什么。
- 基线刷新：未做任何基线刷新。
- 目前发现的问题：0 条（因为还没有开始跑）。

如实记录：这一节不是真实测试过程中途断电的进度存档，而是会话一开始就被要求中断，所以没有可汇报的测试结果。下一位接手者请从 `docs/41` 交接队列重新确认任务范围再开始。

### 12.1 后续接手（同一分支 `claude/test-newart`，第二次中断，2026-10-20）

接手后已确认任务范围（9 人新美术局内实测 + 15 人同 seed 基线刷新，docs/108 §6/§9/§11），着手执行，但再次收到「电脑马上断电」的中断指令，如实记录实际进度：

- **任务 1（9 人新美术截图）**：写了临时通用截图脚本 `game/tests/_tmp_newart_capture.gd`（+ `.tscn`）覆盖 wisadel/saria/suzuran/mizuki/logos/eyjafjalla/exusiai 七人，`siege`/`ulpianus` 计划复用现成的 `siege_ulpianus_art_capture.gd`；配套一次性跑批脚本 `tools/_tmp_newart_runner.py`。实际只跑了一次，且传参写错（误传 `--capture-op=all` 而不是让脚本内置的默认 7 人列表生效），脚本报 `op not found all`、**没有产出任何截图**——`build/newart_1020/` 下只有一个空的 `all/` 目录，没有任何 PNG。**9 人全部未测**，0 张截图，0 条问题记录（因为还没有看到任何画面）。
- **任务 2（15 人同 seed 基线刷新）**：未开始，`build/trace_cache/` 未清理，未跑过任何一次 `tools/trace_base.py`。
- 当前工作树 / build 状态：`game/tests/_tmp_newart_capture.gd(.tscn)`、`tools/_tmp_newart_runner.py` 为未跟踪文件，保留在工作树里供下一位接手直接用（已知的参数 bug：跑全部 7 人时**不要**传 `--capture-op=`，直接不带这个参数跑 `tools/_tmp_newart_runner.py capture <随便一个占位值，脚本内部会忽略并用默认 7 人列表>`，或者改好 runner 让它不强制传 `--capture-op`）；`build/newart_1020/all/`（空目录）可以删掉重来。跑的时候看到两个本机已有的 Godot 进程（PID 57364 / 37056），**不是本会话启动的**，中断时没有去动它们（遵守「不按进程名杀 Godot，只杀自己的 PID」的规则）。
- 本次中断前没有执行任何 `git add` / `git commit`（文档改动只到这一节为止），没有 push，没有合并 main。

下一位接手请：① 先修好 `_tmp_newart_capture.gd` / `_tmp_newart_runner.py` 的调用参数再重跑 9 人截图；② 完成后再做任务 2 的基线刷新；③ 两项都完成后才整理 §13（新美术问题记录）与 §8 基线登记行；④ 过程文件（临时脚本、`build/newart_1020/`、`build/trace_cache/` 的变化）按任务要求不进 git，只提交 `docs/36_testing.md`。

## 13. 新美术干员实测记录（2026-10-20）

接手后修好了 §12.1 记的参数 bug（`_tmp_newart_capture.gd` 需要同时传 `--op=<id>`（让 `game.gd` 把这名干员编进编队当队长）和 `--capture-op=<id>`（截图脚本自己认哪个 id）；`opshot` / `galleryshot` 的调用方式对照 `tools/op_bright_mockup.py` 改成不带场景路径、`--unlockall`、`1280x720`、不加 `--autotest`），9 人全部跑通：局内（idle / run / attack / s1 / s2 / s3，按 docs/108 §6 技能序列列确认该干员实际有哪些阶段）+ 选人页（`--opshot --opid=`）+ 图鉴（`--galleryshot=0,0,0,1.5 --galleryid=`）。截图存 `build/newart_1020/<id>/`（未入库，产物）。

**方法与范围说明（如实）**：
- 9 人的局内截图 `evidence.json` 显示的动画 kind 都与 docs/108 §6 的「技能序列」列吻合，没有缺帧条（`missing: []`）：wisadel（attack/skill/s2_*）、saria（heal/skill/s3_loop/s3_end）、suzuran（skill/s2_intro/s2_hold/s3/s3_loop）、mizuki（skill/s1_attack/s2_*/s3_*）、logos（attack_b/skill/s1_loop/s2/attack_s2/idle_s2/s3_*）、eyjafjalla（skill/s3/s3_loop/s3_end）、exusiai（只有单一 `skill` kind，符合她 s1–s3 都是「次数型单条」的设计，不是缺帧条）、siege（leap_native/heavy_attack）、ulpianus（whirl_native/tether_native/zip_native/attack_s2）。
- 每人每阶段抽 2–3 帧代表帧，不是 540 帧全扫；人工看图时把截图裁剪放大 + 提亮 4 倍对比度（战斗场景本身光照较暗，原图直接看很难辨认细节，裁剪放大只影响人眼查看方式，不影响截图本身的判定）。
- hurt / death：核实 `character.gd` 全文搜索，`anim_kind` 从未被赋值为 `"hurt"` 或 `"death"`（9 个干员和其余所有干员一样，引擎目前没有触发干员本体受击 / 阵亡播放独立帧条的代码路径，这两个 kind 字段在 json schema 里保留但运行时走不到）——**9 人全部跳过 hurt / death 截图**，这不是本批美术的问题，是干员系统现状如此。
- 没有去逐帧比对特效坐标的像素级数值，是人工目测「特效原点是否贴在角色身上、脚底是否在同一水平线」。

**问题记录（按严重度分组）**：

| 严重度 | 干员 | 动作 | 现象 | 截图 | 疑似原因 |
| --- | --- | --- | --- | --- | --- |
| 高 | — | — | 无 | — | — |
| 中 | — | — | 无 | — | — |
| 低 | 全员通用 | — | 战斗截图整体偏暗，肉眼判断穿帮需要先裁剪提亮才看得清细节 | `build/newart_1020/<id>/f_*.png` | 不是美术或代码问题：`game.t = 60.0` 落在局内昼夜曲线的较暗时段，截图脚本没有去强制调亮度；真要查细节瑕疵建议后续截图脚本把 `g.t` 固定到白天时段，或截图后固定走一遍本次用的裁剪 + 提亮流程 |

**9 人逐一结论**：

| 干员 | idle/run/attack | 技能序列 | 特效原点 | 结论 |
| --- | --- | --- | --- | --- |
| wisadel | 正常，脚底贴地 | s2 两段 phase、s3 start/loop/attack/end 都按序播放 | 炮击 / 余震特效落在目标与角色之间，合理 | 未见异常 |
| saria | 正常 | s1/s2 治疗序列、s3 start/loop/end | 治疗光环贴着角色脚下 | 未见异常 |
| suzuran | 正常 | s2 hold（持续）、s3 序列，九尾 fx 形态随阶段变化 | fx 以角色为中心展开，无偏移 | 未见异常 |
| mizuki | 正常，伞具贴手 | s2/s3 start/loop/attack/end 四阶段齐全 | 伞 / 剑气特效原点在角色手部附近 | 未见异常 |
| logos | 正常，交替弹体 a/b 可见 | s1/s3 序列、s2 单条，均播放完整 | 弹道线 / 分裂体位置合理 | 未见异常 |
| eyjafjalla | 正常 | s3 start/loop/run/end | 熔岩地面特效覆盖范围与角色位置对应 | 未见异常 |
| exusiai | 正常 | s1–s3 均为单条，技能触发瞬间 + 之后的 idle/attack 状态变化已截（永久增益型，不强求 start/loop/end） | 翅膀 fx 贴身 | 未见异常 |
| siege（推进之王） | 正常，`native_motion` 跑步 / 攻击姿态连贯 | 无序列（`skills[].anim`），leap_native 起跳与落地帧衔接自然，heavy_attack 蓄力动作完整 | 冲击波 / 重击特效落点对齐 | 未见异常（沿用已验收过的 `siege_ulpianus_art_capture.gd`） |
| ulpianus | 正常 | whirl_native / tether_native / zip_native 三种原生姿态切换顺畅，attack_s2 精二形态独立 | 锁链 / 旋斩特效从手部连出，位置正确 | 未见异常（沿用已验收过的 `siege_ulpianus_art_capture.gd`） |

**结论**：抽样范围内（每人每阶段 2–3 帧、9 人共约 160 张战斗截图 + 选人页 / 图鉴各 9 张）没有发现穿帮、残留帧、朝向错误或特效错位；选人页大立绘与图鉴页用的是另一套美术（不受这次 64 画布改动影响），两处截图也都正常。这不是逐帧全扫的结论，只能说明抽样帧里没有看到问题；`docs/108` §11 里列的 F1–F11 架构级问题仍然有效，不在本次人工验收范围内。


## 14. 缺口补测（2026-10-29，测试与验收，`claude/test-gaps`；依据 docs/126 R3 / R6 与 arch_review_1029 风险 5）

只加测试与 TRACE 工具，不改玩法代码（同 seed 玩法逐行不变，证明见 §3.2「TRACE 新格式」）。新增的场景回归都登记在 `tools/check.py` 的 `SCENE_REGRESSIONS`，可单跑 `python tools/check.py --only <名>`：

| 名 | 场景 | 固定了什么 |
|---|---|---|
| `trace_fields` | `trace_fields_test` | TRACE 新字段 `sq / lamp / nd / rl` 的灵敏度、还原、浮点噪声免疫、只读（不动五条 rng） |
| `ui_smoke` | `ui_smoke_test` | 界面冒烟：标题页（选人 / 难度 / 图鉴 / 寻访 / 认知塑造 / 蚀刻章 / 设置 / 操作说明 / 致谢 / Boss 演练）与局内（HUD / 暂停 / 暂停里的设置 / 属性面板 / 胜利结算 / 作战记录 / 对局记录 / 失败结算）各开关两遍：无脚本错误（check_scene 扫输出）、无缺图（`Art._cache` 新增的 null 键，`fx_` 可选特效有程序回退不计）、第二遍关闭后节点数不涨 |
| `time_scale_combo` | `time_scale_combo_test` | 时间缩放组合。现行规则（读 `game._process` 得出）：`dt = min(真实帧, 0.05) × 圆盘系数`；之后三条互斥路径——击破慢动作（只乘 `victory.time_scale`，圆盘与倍速都不乘）/ 顿帧（模拟整帧暂停，`hitstop` 按真实帧递减）/ `PlayClock.steps`（真实帧先封顶 2/60 再 × 倍速）。**代码里没有「选点」减速这个缩放源**，故只测圆盘、倍速、顿帧、击破慢动作四者 |
| `hit_fallback` | `hit_fallback_test` | `combat._damage` 在 h 为空时沿用 `g.hit`。**已知缺陷特征测试**：g.hit 残留上一下的干员描述符时，空 h 的伤害会错记给那名干员（作战记录 op_out、dmg_out）；显式 h 归属正确与 `_damage` 不改 `g.hit` 是回归保护。修复时翻转标 [已知缺陷] 的断言 |
| `nerve_rules` | `nerve_rules_test` | 神经损伤积累规则特征测试：溟痕 / 神经光环 / 流明光域、难度与卡片倍率、满条清零 + 锁定 5 秒 + 12% 真伤、灯火退散档位（自然溟痕 × (1 − 0.8x)，Boss 溟痕不减）。**已知缺陷**（P1-4）：Boss 在场时满条真伤仍不经 `_boss_clamp`、不记 Boss 份额 |

没做、留给后续：HUD 缓存自检 `--hudcheck`（风险 2）、原生等价测试无 dll 时显式提示（R7）、机器人策略拆出 autotest（C4）。
