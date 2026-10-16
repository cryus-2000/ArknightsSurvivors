# 105 干员动画接口：现状架构与交给 Codex 的改造说明（2026-10-17）

给 Codex 的代码任务说明。目标：把干员「技能期间换动作」的两套写法合成一个契约，之后 J 批 17 人接入只填 json、不改代码。Codex 在 `.worktrees/codex-art`（分支 `codex/art`）之外另开分支做代码，规则见 §5。

## 1. 文件与职责

| 文件 | 职责 |
|---|---|
| `game/data/characters/<id>.json` | 每个干员的数据：`sprites`（帧条槽）、`extra_sprites`（非主动作的帧条名单，不列不加载）、`skills[0..2]`（技能数值与 `anim` 字段）、`attack`（含 `flow: free` = 充满即发） |
| `game/scripts/characters/character.gd` | 干员基类：动画状态机、绘制、`validate_operator`（启动时校验 json） |
| `game/scripts/characters/data_operator.gd` | 数据驱动干员（积木）：技能计时 `s_t[i]` / `s_dur[i]`，`skill_active_left(i)` 返回技能剩余秒数（持续型）或剩余发数（次数型） |
| `game/scripts/characters/blocks/seg_*.gd` | 各干员专属段；`seg_mizuki._h3_free_skill` 是「充满即发」技能入口，只走画面 `play_vis_skill(i)` |
| `game/scripts/render/world.gd` | 队长精灵（`g.sprite`，Sprite2D）的帧条切换 `p48_tex(kind)`；队友由 `character.gd` 的 `draw_body` / `_strip` 画 |
| `game/scripts/art.gd` | `A.tex(name)` 从 `art/incoming/<name>@2x.png` 加载（有 @2x 用 @2x，`A.hires_of(tex)` 返回 2）；无 1x 可运行 |
| `game/tests/suzuran_skill_anim_test.gd`、`mizuki_skill_anim_test.gd` | 技能动画逐帧回归，登记在 `tools/check.py` 的 `SCENE_REGRESSIONS` |
| `docs/87 §3.5` | `sprites.skills` 字段说明（现行）；`docs/92` 是 `skill_pose` 的设计（安洁莉娜浮空） |

## 2. 帧条与 json 现状

- 帧条：`art/incoming/op_<id>_<slot>@2x.png`，128×128 一帧、横排，`frames = 宽 / 高`，脚底 `foot` 为 1x 口径 `[32, 60]`（@2x ×2）。`sprites.<slot> = {tex, frames, fps, foot, fire}`，`fire` = 出手帧（零基），只对 attack / 技能起手段有意义。
- 主槽：`idle / run / attack / skill / hurt / death`。其他槽（`skill_s2`、`skill_s3_loop`、`float` …）必须同时列进顶层 `extra_sprites`。
- 水月例外：槽名沿用 `player_*`（`world.gd` 的 `p48_tex` 与 `intro.gd` 写死了 `player_attack_48`），其余干员都是 `op_<id>_*`。

## 3. 技能动画的两套写法（要合并的对象）

### 3.1 `sprites.skills.sN`（docs/87 §3.5，10-16，character.gd 1642 起）
三种形：
- 单条：`{"anim": "skill_s3"}`
- 定格：`{"intro": "attack", "hold": "skill_s2_hold", "hold_ms": 250}`
- 循环：`{"start": {"anim": "skill_s3", "frames": [0,1]}, "loop": "skill_s3_loop", "end": {"anim": "skill_s3", "frames": [0,2]}}`

状态机：`_start_skill_seq(aim, i)`（有出手窗口的技能：起手段决定 `attack_t / fire_t`，出手 = `fire` 帧中点）与 `_start_vis_seq(i)`（`flow: free` 的技能：纯画面，不碰模拟量）；每帧 `_tick_sq(dt)` 推进，`_sq_frame(n)` 取当前帧；`loop` 在 `skill_active_left(i) > 0` 期间循环，归零后播 `end`。起手段 `sq_own` 压过同帧的普攻画面；起手播完后，普攻画面会压过 loop、播完接着循环。

### 3.2 `sprites.skill_pose`（docs/92，10-13，character.gd 1827 起，首例安洁莉娜 S3）
`{"skill": 2, "in": "float_in", "out": "float_in", "out_rev": true, "map": {"idle": "float", "run": "float_move", "attack": "float_attack"}, "shadow": 0.7, ...}`：技能生效期把 idle / run / attack 三个主槽整体换成另一组帧条，进出各播一条，影子缩淡。`_pose_c / _pose_len / _pose_up / _pose_kind` 负责。

两套重叠：3.2 的 `map.idle` ≈ 3.1 的 `loop`，`in / out` ≈ `start / end`；3.2 多了 `run / attack` 映射和影子，3.1 多了 `hold`、`frames` 子段和出手窗口语义。云端正在做的「`skills.sN.attack` 槽」（分支 `cloud/skill-attack-slot`）是把 3.2 的 `map.attack` 补进 3.1。

## 4. 目标契约（改完后唯一入口）

```json
"skills": {
  "s1": {"anim": "skill"},                                   // 单条，fire 按该条
  "s2": {"start": {"anim": "skill_s2", "frames": [0,1]},     // 起手段（出手窗口 / fire 只看这里）
         "loop": "skill_s2_loop",                            // 持续期待机（skill_active_left > 0）
         "run": "skill_s2_loop",                             // 持续期移动（可选，缺省 = loop）
         "attack": "skill_s2_attack",                        // 持续期普攻变体（可选，缺省 = 普通 attack 压过 loop）
         "end": {"anim": "skill_s2", "frames": [2]},         // 收势（可选）
         "shadow": 0.7, "shadow_a": 0.55},                   // 可选，从 skill_pose 迁来
  "s3": {"intro": "attack", "hold": "skill_s2_hold", "hold_ms": 250}
}
```
- `skill_pose` 整个删除：安洁莉娜改写成 `s3: {start: float_in, loop: float, run: float_move, attack: float_attack, end: {anim: float_in, reverse: true}, shadow: 0.7}`；`out_rev` 变成 `end.reverse`。
- `validate_operator` 校验：键 s1–s3；引用的帧条在 `sprites` 且列进 `extra_sprites`；`frames` 子段不越界；`skill_pose` 出现即报错（指向本节）。
- 没写 `skills` 的干员照旧：单条 `sprites.skill`。

## 5. 做法与验收（Codex 必读）

1. 分支：从 `main` 开 `codex/anim-contract`，只改 `character.gd`、安洁莉娜 json、docs/87 §3.5、docs/92（标「已并入 §3.5」）、测试。不动帧条、不动其他干员 json。
2. **同 seed 不变**：动画只影响画面；`python tools/trace_base.py 1 angelina 240 --here` 与 `… 1 mizuki 240 --here` 退出码 0（逐行相同）。出手窗口语义（起手段决定 `attack_t / fire_t`）不许变。
3. 回归：把安洁莉娜浮空写成 `tests/angelina_skill_anim_test.gd`（登记 `check.py SCENE_REGRESSIONS`，照 `mizuki_skill_anim_test` 的写法：逐帧推进，断言各阶段 `anim_state()` 的槽名 / 帧号 / 影子系数），铃兰 / 水月现有两份回归照样通过。
4. `python tools/check.py --auto` 0 失败（Windows 本机：Godot 在 `E:\Godot_v4.7.2-stable_win64.exe\…console.exe`，静音 `--audio-driver Dummy`；Linux 用 `tools/cloud/setup_linux.sh`）。
5. 截图不是 Codex 的事：合入后由界面与美术在本机截安洁莉娜 S3 / 水月 S2 的局内图验收。
6. 交付：提交说明写「改了什么 / 同 seed 结论 / 快检结果」，报分支 + 提交号，不合 `main`、不推别的分支。
7. 先等 `cloud/skill-attack-slot` 合入 main 再开工（它加的 `attack` 槽是本契约的一部分，避免冲突）。
