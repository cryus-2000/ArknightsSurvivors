# 39 · 代码结构与界面分层

> 2026-09-26 架构整理：`game.gd` 从 7013 行拆到约 1250 行，按职责分成 run / screens / render 三层；
> 干员经 `characters/op_api.gd` 调用主场景。视觉风格（配色、组件、字体）见 docs/37，测试见 docs/36。

## 1. 目录一览（`game/scripts/`）

| 目录 / 文件 | 职责 | 在 game.gd 里的字段 |
| --- | --- | --- |
| `game.gd` | **状态与调度**：对局状态变量（生命、灯火、敌人列表、编队……）、`_ready` 初始化、主循环 `_update` 调度各模块、输入分发、属性同步 `_sync_stats`、对局随机数 `_shuffle` | — |
| `run/spawner.gd` | 刷怪：波次、精英、宝箱、拟态箱 | `spawner` |
| `run/enemies.gd` | 敌人逐帧更新、状态、敌方弹幕；空间网格与索敌（query / nearest / arc_hit / densest_point） | `enemies_sys` |
| `run/combat.gd` | 战斗结算：对敌伤害、击杀、主控受击、治疗、神经损伤、缩圈 | `combat` |
| `run/weapons.gd` | 医疗无人机、玩家侧子弹 | `weapons_sys` |
| `run/pickups.gd` | 掉落与拾取、经验与升级触发 | `pickups` |
| `run/progression.gd` | 升级卡池、藏品候选与发放、选中结算 | `progression` |
| `run/shop.gd` | 商人出现、货架、定价、购买（逻辑） | `shop_sys` |
| `run/music_director.gd` | 局内配乐调度 | `music_dir` |
| `run/demo.gd` | 图鉴攻击演示 / 精英化演出里的实机演示 | `demo_sys` |
| `run/autotest.gd` | 自动测试与平衡机器人（只在带测试参数时运行） | `autotest_sys` |
| `render/world.gd` | 世界绘制（2.5D 纵深排序）、主控 / 博士动画与手感；`game.gd._draw` 只转发到这里 | `world` |
| `render/vfx.gd` | 特效帧条、刀光、火花、飘字、横幅、屏幕震动、加色层 | `vfx` |
| `screens/hud.gd` | 局内 HUD，并按 `state` 分派到下列界面 | `hud_view` |
| `screens/choice_panel.gd` | 弹窗框架（面板、布局、标题、按钮、提示）与选卡界面 | `panel_ui` |
| `screens/shop_screen.gd` | 商店界面 | `shop_ui` |
| `screens/elite_show.gd` | 精英化 / 解锁演出 | `show_screen` |
| `screens/intro.gd` | 开场演出与新手教程 | `intro_screen` |
| `screens/stats_panel.gd` | 属性面板（Tab） | `stats_screen` |
| `screens/result.gd` | 结算 | `result_screen` |
| `ui.gd` | 界面主题与控件（语义色、字体、面板、按钮、进度条……），docs/37 | 常量 `UI` |
| `characters/op_api.gd` | 干员 → 主场景的接口层（索敌、伤害、治疗、特效、飘字、绘制） | 干员基类的父类 |
| 已有的独立模块 | `boss_ai.gd`、`enemies/enemy_ai.gd`、`relic_fx.gd`、`endings.gd`、`world/map.gd`、`allies/knight.gd`、`characters/*`、`core/*` | — |

## 2. 模块写法

- 每个模块 `extends RefCounted`，持有带类型的 `g: Game`（`const Game = preload("res://scripts/game.gd")`）。带类型意味着 `var x := g.ppos` 能推断类型、成员名拼错在加载时就报错。
- 在 `game.gd` 里以成员变量持有：`var spawner = Spawner.new(self)`（成员初始化时就建好，`_ready` 之前也能用）。
- 读写对局状态一律 `g.xxx`；访问 `game.gd` 的常量 / 枚举用 `Game.PX`、`Game.S.PLAY`（常量表达式，参数默认值里也合法）。
- 模块之间互相调用走 `g.<字段>.<函数>`，例如 `g.combat.damage(e, dmg)`、`g.vfx.show_banner("…")`。
- 只被本模块使用的状态可以放在模块里（如 `run/music_director.gd` 的配乐状态）；**被多个模块或其他脚本读的状态留在 `game.gd`**。
- 被 `set(name, …)` / `get("name")` 按字符串访问的变量（如 `STAT_SYNC` 表里的 `enemy_hp_mult`）必须留在 `game.gd`。

## 3. 界面层约定（screens/）

目的：以后改界面（再换一套风格、调布局、加新面板）只动 `screens/` 与 `ui.gd`，不碰玩法。

1. **一个界面一个文件**，负责这个界面的布局与绘制；配色、字体、控件只用 `ui.gd`（docs/37），不在界面里硬写颜色常量。
2. **只读状态**：界面从 `g` 读对局状态来画，不在绘制里改状态（计时、动画插值这类纯展示状态除外）。
3. **操作走逻辑层**：按钮 / 选卡 / 购买回调调用 `run/` 的函数（`g.progression.pick(i)`、`g.shop_sys.buy(i)`），界面自己不结算。
4. **分派在 HUD**：`screens/hud.gd` 的 `draw()` 按 `g.state` 把全屏界面交给对应模块画；新增一个全屏界面 = 新文件 + 在这里加一个分支 + `game.gd` 加一个字段。
5. **弹窗框架共用**：面板节点、标题、按钮、提示在 `screens/choice_panel.gd`（`g.panel_ui.button(...)` 等），商店等弹窗复用它。

## 4. 干员接口层（characters/op_api.gd）

干员脚本调用主场景的能力（索敌、伤害、治疗、特效、飘字、绘制）一律走 `op_api.gd` 的方法，不直接调用 `g._xxx` 或各模块。
主场景内部怎么拆、函数怎么改名，只改 `op_api.gd` 一处；本次拆分里敌人 / 战斗 / 特效三次搬家，13 名干员脚本一行没动。
读写公共状态（`g.ppos`、`g.enemies`、`g.stats`、`g.hitstop`、`g.t`）与 `g.draw_*` 仍直接用 `g`。

**技能期间播哪套动作（2026-09-26，`characters/character.gd`）**：技能缺省播 `skill` 帧条；想借用别的帧条（例如放技能时播普攻动作）：
- 数据（推荐）：干员 JSON 的 `skills[i]` 加 `"anim": "attack"`（值必须是该干员 `sprites` 里有的帧条名，校验不过会报错）。
- 代码：干员脚本重写 `skill_anim(i) -> String` 按状态决定；或者 `start_skill(aim, idx, dur, fire_at, "attack")` 临时指定。
- 普攻同理：`start_attack(aim, dur, fire_at, "attack_spin")` 让这一击改播别的帧条（出手仍调 `_release`），缺图退回 attack 条（2026-09-26，斯卡蒂潮汐回旋斩）。
- 出手时机按实际播放那套帧条的 `fps / fire` 算；那套帧条缺图时退回 `skill` 条。`act_kind` 仍是逻辑类型（`"skill"` = 出手调 `_release_skill`），
  `act_anim` 才是正在播的帧条——判断「是不是在放技能」继续用 `act_kind == "skill"`。

**手动技能的钩子（2026-09-26，契约 v2.3，`characters/character.gd`，fc39bc9）**：手动技能只对**主控**生效，当队友一律自动。
这些是「游戏调用干员」方向的虚函数，干员脚本按需重写（所以放在基类，不在 op_api.gd）：

| 函数 | 作用 | 缺省 / 写法 |
| --- | --- | --- |
| `is_manual(i)` | 技能 i 此刻是否手动 | `is_leader` 且 JSON `mode == "manual"`；`charge_skills`、`manual_index`、HUD 角标、按键路由都走它。JSON 校验仍按 `mode` 计数（每名干员至多 1 个） |
| `manual_ready(i)` | 现在能否释放 | 已解锁、充满、不在生效中、在场且没在出手。重写写法：`return super(i) and <额外条件>`（乌尔比安：锚已收回、400 内有敌人） |
| `manual_block_reason(i) -> String` | 充能已满却放不了、而且等也没用时的提示原因 | 缺省 `""`：表示只是稍等，按键先记下 |
| `press_manual(i) -> String` | 按键入口（`doctor.try_manual_skill` 调它） | 正在出手时先记下按键，1 秒内满足条件就放（`MANUAL_BUF` / `manual_buf`，每帧在 `tick_sp` 末尾处理）；返回给玩家看的提示 |
| `bot_wants_manual(i) -> bool` | 平衡机器人什么时候按 | 缺省：主控生命 < `balance.json bot/manual_hp`；`run/autotest.gd` 调它。想和改成手动前的批跑数据可比，就重写成「就绪即放」 |

**对精英 / Boss 的伤害倍率（2026-09-27，`characters/character.gd` 的 `vs_elite()`，928a18a）**：干员 JSON `base.vs_elite`，缺省 1。只从干员 JSON 读：balance.json 的 operators 段只管 atk / aspd / range / skill_power，覆盖不了它。
- 自动生效：`melee_hit`，以及转调它的 `area_hit`，命中 `e.elite or e.boss` 时伤害乘它。
- 不自动生效：干员自己推进的弹体、持续伤害、直接调 `deal_damage` 的伤害——要在生成弹体或结算时自己乘 `vs_elite()`（铃兰狐火是这么做的）。
  给新干员加这个键之前，先查清它的主要伤害走哪条路。现有：铃兰 2.5、塞雷娅 2.2（数值 b1-cal，开局主控打中期 Boss 太慢）。

**跑步动画与脚底对齐（2026-09-27，run-anim，5ab3a9a）**：
- `foot_dx(st, flip = null)`（character.gd）：帧条按帧宽居中画；该动作 `sprites.<kind>.foot[0]`（缺省用 `sprites.foot`）偏离帧中心时，把画的位置横向挪回，让各动作的脚都落在 `pos` 上。`draw_body`、残影、`draw_body_at` 都走它；新增画本体的路径也要用它，否则跑停、转身会横跳。
- 跑步相位 `run_ph`：帧率 = 帧条 fps × clamp(实际移速 / `RUN_REF` 150, 0.6, 2.0)，帧条按主控基础移速画。跑 / 停带滞回：起跑 `RUN_ENTER` 40，停下 `RUN_EXIT` 20。
- `_start_action` 直接设 `anim_kind = act_anim`（原来置空，每次起手会闪一帧待机）。
- `squad.side`（-1..1）：编队站位的左右，`_slot_offset` 按它镜像；主控转身时约 0.8 秒平滑换边（原来瞬间镜像，队友会横穿）。要取队友站位就调 `_slot_offset`，不要自己按 `g.facing` 镜像。
- 博士（render/world.gd）不再叠代码起伏，只靠跑步帧条自带步频（04b141c）。

## 5. 搬运工具 `tools/split_module.py`

按函数名把 `game.gd` 里的一组函数整段搬到新模块（或追加到已有模块）：自动给主场景成员加 `g.` / `Game.`、
把只被搬走代码使用的变量与常量一起搬走、改写 `game.gd` 与其他脚本的调用。用法见文件头；先 `--dry` 看报告
（「不认识的标识符」需要人看），搬完跑 `python tools/check.py`，再用 `--ab` 确认逐局相同。

已知限制：
- 只认 `g.` / `game.` / `_g.` 写法的外部调用，其他变量名（如 `tests/pad_sim.gd` 的 `sc.`）会列出「注意」，需手工改。
- 函数里叫 `g` 的局部变量会被改名为 `g_item`，避免遮住模块的 `g`。
- 引擎回调（`_draw`、`_process`、`_input`）要留在 `game.gd`，搬走后在原处写一行转发。

## 6. 验证记录（2026-09-26）

- 每一步：快检（docs/36）通过；界面步骤另跑 `--padsim`（标题 → 开场 → 教程 → 暂停 / 设置 → 属性面板 → 选卡）并截图目视（教程、商店、事件选卡、结算、属性面板、对局 HUD 与世界）。
- 整体 A/B：基准 = 拆分前的 main（`64376e5`）+ 期间合入的玩法修复（`0dc2270` 成长节点），即临时提交 `2b40d43`；
  标准矩阵（普通 / 高手 × 7 开局 × 4 seed）**54 / 56 局逐字段相同**，胜率、平均存活、等级合计完全一致。
  另 2 局都是塞雷娅开局（普通·seed 4、高手·seed 3）。复查：拆分后的提交 `853c006` 与拆分中途的 `b8d481f` 单独跑都与基准相同（t=542）；
  同一份代码并发 12 份跑同一局，10 份 t=542、2 份 t=552——**是这一局在高负载下本身不能严格复现**，与拆分无关（已另开排查任务）。

## 7. 敌人字典字段校验

`run/spawner.gd check_enemy()`：以 `new_enemy()` 的字段为模板，测试运行（带 `--xxx` 参数）时检查每个加入 `g.enemies` 的字典，
缺字段直接 `assert` 失败（输出 `SCRIPT ERROR: Assertion failed`，快检记为失败；导出的正式版不执行 assert）。
第一次运行就查出补给箱字典少了 `weak / aggro / corr_t / corr_dmg` 四个字段（各处读取时都带了同值默认，所以之前没出错），已补齐。
另起炉灶拼敌人字典时（新的宝箱、召唤物……）先走 `spawn_enemy()`，或者在 append 之后调一次 `check_enemy(e, "来源")`。
