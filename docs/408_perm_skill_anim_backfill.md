# 408 · 永续技能换动作补齐清单（F17，11-23）

> 依据：docs/407 F17 与 §6-7（用户 11-23：技能换动作照原作 Spine 对应轨，**只适用于永久开技能的干员**，老干员也要补齐）。
> 范围：`game/data/characters/*.json` 里 `"permanent": true` 的技能。26 名干员中共 **9 人**有永续技能；91 §0.4 之后加入的 8 人里只有拉普兰德有。
> 原作轨名：本机 `build/prts_ref/_raw/<id>/` 的 PRTS Spine（正面骨骼）用 `tools/spine_run_trial/anims_probe.js` 列出，括号里是时长与 OnAttack 事件时刻。
> 状态：**只出清单，等协调人看过再动手做动画**；没有原作常驻轨的不自编。

## 1. 清单

| # | 干员 | 永续技能 | 原作对应轨 | 现状（开技能后实际播什么） | 要做什么 |
|---|---|---|---|---|---|
| 1 | 安洁莉娜 | S2 秘杖·微粒模式 | `Skill1_Begin` 0.50 → `Skill1_Loop` 0.47（OnAttack 0.23）→ `Skill1_End` 0.50。推定 Skill1 = S2、Skill2 = S3（S3 浮空已用 Skill2_*，S1 次数型无状态轨） | 开技能播一次 `skill`（Begin 4 帧 + Loop 1 帧 + End 3 帧压成的施法条），之后普攻 / 待机回到普通 `attack` / `idle` | **补**：新增 `attack_s2` = `Skill1_Loop`（出手帧按 OnAttack 0.23），永续后经 `native_motion.variants {slot: attack, perm: 1, use: attack_s2}` 换播；开技能施法改播完整 `Skill1_Begin`。待机原作无专属轨，保持 `idle` |
| 2 | 凯尔希 | S2 指令：战术协同 | 本体正面骨骼只有 Attack / Idle / Die / Start，无技能轨；Mon3tr 骨骼 `Skill`（13 帧 1 秒，OnAttack 0.367） | Mon3tr 永续后爪击播 `native_m_attack_s2` = 原作 Skill（docs/107，用户 10-20 确认）；本体施法播 `command` | **已完成**，不用改 |
| 3 | 拉普兰德 | S1 日晷 | 原作只有一条 `Skill` 1.33（OnAttack 0.57），各技能共用 | 开技能播 `s1cast`（原作 Attack 段改时长）；永续后普攻仍是 `attack`（Combat） | **待用户定**：按 F17 永续期普攻应换 `Skill`，但 docs/297 用户 11-07 嫌 S1 出现「双手平举前推」（就是 Skill 轨 0.5–0.95 秒的蹲身前推），已改回 Attack。两条口径冲突，先不动 |
| 4 | 逻各斯 | S2 殁亡 | `Skill_2_Begin` 0.17 → `Skill_2_Loop` 1.00 → `Skill_2_End` 0.27；另有 `Skill_Down_2_*` 同长（低姿版） | 永续后 `seg_logos` 换 `idle_s2` / `attack_s2`，开技能播 `skill_s2`（docs/36 实测有效） | **只核对**：帧条是 10 月 Codex 批次（423eff5aa）入库，没记是否取自原作 Skill_2_Loop；对拍一次，不是就按原作轨重出 |
| 5 | 流明 | S2 沛霖 | 只有 `Skill_2` 1.33（OnAttack 0.80）施法一次，无循环轨 | 开技能播 `skill_s2` = 原作 Skill_2（`package_kaltsit_lumen_irene.py`） | **已完成**；原作无常驻轨，永续期不换 |
| 6 | 浊心斯卡蒂 | S2 同葬无光之愿 | `Skill_2_Begin` 3.93 → `Skill_2_Loop` 3.33（无 OnAttack，原作本就无普攻动作） | 开技能播 `skill_s2` = Skill_2_Begin 8 帧；之后回到普通漂浮 `idle` / `attack` | **补**：新增 `idle_s2`（= `Skill_2_Loop` 全长循环），永续后待机和普攻（她的普攻就是原地漂浮）都换播它；开技能施法保留 Begin |
| 7 | 铃兰 | S2 儿时的舞乐 | 只有 `Skill2` 1.73（OnAttack 0.80）施法一次，无循环轨 | 开技能播 `skill_s2_intro`（= attack）+ `skill_s2_hold` 定格 250 ms，不是原作 Skill2 | **可选**：原作无常驻轨，永续期不换；施法一下可换成原作 `Skill2` 整条（1 条帧条） |
| 8 | 德克萨斯 | S2 冲锋号令·γ型 | 只有一条 `Skill` 2.17（无事件，举剑插地，本作已用作 S1 剑雨） | 永续后冲刺数值变化，动作不变 | **无原作轨**（原作 S2 是瞬发回费），不做 |
| 9 | 乌尔比安 | S2 必须维系的界限 | `Skill_2_Begin` 0.17 → `Skill_2_Loop` 2.50（攻击）/ `Skill_2_Idle` 6.00（待机）/ `Skill_2_Die` | 永续后普攻换 `attack_s2`（`native_motion.variants perm 1`）；待机仍是普通 `idle` | **补**：新增 `idle_s2` = `Skill_2_Idle`，永续后待机换播；`attack_s2`（Codex S2Attack）顺带对拍是否等于 Skill_2_Loop |

## 2. 汇总

- 永续技能干员 **9 人**。
- 已完成 / 不需要：凯尔希、流明、德克萨斯（3 人）。
- **需补 3 人**：安洁莉娜（attack_s2 + 完整 Begin）、浊心斯卡蒂（idle_s2）、乌尔比安（idle_s2）。
- 待用户定 1 人：拉普兰德（F17 与 docs/297 冲突）。
- 只核对 1 人：逻各斯；可选 1 人：铃兰（施法换原作 Skill2）。

## 3. 动手时的做法（协调人点头后）

1. 帧条走 B 方案（docs/407 O14、B9）：`tools/spine_px.py` / 各 `tools/probes/package_*.py` 同一口径从原作轨取帧，尺度 ≈ 78 @2x（O13），@2x + @1x 都出。
2. 接入只改数据：`sprites.<slot>` + `native_motion.variants`（`perm` 为零基技能序号，S2 = 1）；待机换条现有适配器只支持普攻槽，`idle_s2` 要看 `native_motion.gd` 是否支持 idle 变体，不支持就照逻各斯 `hw_native_body_state` 的做法加一处。
3. 只换画面，同种子 TRACE 应不变；交付按 F23–F25 只交一条 mp4。
