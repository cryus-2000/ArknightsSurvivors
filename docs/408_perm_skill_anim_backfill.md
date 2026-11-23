# 408 · 永续技能换动作补齐清单（F17，11-23）

> 依据：docs/407 F17 与 §6-7（用户 11-23：技能换动作照原作 Spine 对应轨，**只适用于永久开技能的干员**，老干员也要补齐）。
> 范围：`game/data/characters/*.json` 里 `"permanent": true` 的技能。26 名干员中共 **9 人**有永续技能；91 §0.4 之后加入的 8 人里只有拉普兰德有。
> 原作轨名：本机 `build/prts_ref/_raw/<id>/` 的 PRTS Spine（正面骨骼）用 `tools/spine_run_trial/anims_probe.js` 列出，括号里是时长与 OnAttack 事件时刻。
> 状态：清单协调人 11-23 已看过（6765c2171 合本地 main）；§4 是同日补做的结果。**原作 Spine 轨的序号不一定等于技能序号**（逻各斯就是反的，见 §4），下表「原作对应轨」一栏以 §4 为准。

## 1. 清单

| # | 干员 | 永续技能 | 原作对应轨 | 现状（开技能后实际播什么） | 要做什么 |
|---|---|---|---|---|---|
| 1 | 安洁莉娜 | S2 秘杖·微粒模式 | `Skill1_Begin` 0.50 → `Skill1_Loop` 0.47（OnAttack 0.23）→ `Skill1_End` 0.50。推定 Skill1 = S2、Skill2 = S3（S3 浮空已用 Skill2_*，S1 次数型无状态轨） | 开技能播一次 `skill`（Begin 4 帧 + Loop 1 帧 + End 3 帧压成的施法条），之后普攻 / 待机回到普通 `attack` / `idle` | **补**：新增 `attack_s2` = `Skill1_Loop`（出手帧按 OnAttack 0.23），永续后换播；开技能施法改播完整 `Skill1_Begin`。待机原作无专属轨，保持 `idle` |
| 2 | 凯尔希 | S2 指令：战术协同 | 本体正面骨骼只有 Attack / Idle / Die / Start，无技能轨；Mon3tr 骨骼 `Skill`（13 帧 1 秒，OnAttack 0.367） | Mon3tr 永续后爪击播 `native_m_attack_s2` = 原作 Skill（docs/107，用户 10-20 确认）；本体施法播 `command` | **已完成**，不用改 |
| 3 | 拉普兰德 | S1 日晷 | 原作只有一条 `Skill` 1.33（OnAttack 0.57），各技能共用 | 开技能播 `s1cast`（原作 Attack 段改时长）；永续后普攻仍是 `attack`（Combat） | **保持 Attack，用户 11-07 意见优先于 F17**（协调人 11-23 定）：docs/297 用户明确嫌 S1 出现 Skill 轨 0.5–0.95 秒的「双手平举前推」，以用户具体意见为准，不换 |
| 4 | 逻各斯 | S2 殁亡 | 原作 `Skill_1_Begin` 0.33 → `Skill_1_Idle` 6.67 / `Skill_1_Attack` 1.60（OnAttack 0.43）（**不是** Skill_2_*，见 §4） | 永续后 `seg_logos` 换 `idle_s2` / `attack_s2`，开技能播 `skill_s2` | **已对拍，已是原作对应轨，不重出**（§4） |
| 5 | 流明 | S2 沛霖 | 只有 `Skill_2` 1.33（OnAttack 0.80）施法一次，无循环轨 | 开技能播 `skill_s2` = 原作 Skill_2（`package_kaltsit_lumen_irene.py`） | **已完成**；原作无常驻轨，永续期不换 |
| 6 | 浊心斯卡蒂 | S2 同葬无光之愿 | `Skill_2_Begin` 3.93 → `Skill_2_Loop` 3.33（无 OnAttack，原作本就无普攻动作） | 开技能播 `skill_s2` = Skill_2_Begin 8 帧；之后回到普通漂浮 `idle` / `attack` | **补**：新增 `idle_s2`（= `Skill_2_Loop` 全长循环），永续后待机和普攻（她的普攻就是原地漂浮）都换播它；开技能施法保留 Begin |
| 7 | 铃兰 | S2 儿时的舞乐 | 只有 `Skill2` 1.73（OnAttack 0.80）施法一次，无循环轨 | 开技能播 `skill_s2_intro`（= attack）+ `skill_s2_hold` 定格 250 ms，不是原作 Skill2 | **做**（协调人 11-23）：施法换原作 `Skill2` 整条；永续期原作无常驻轨，不换 |
| 8 | 德克萨斯 | S2 冲锋号令·γ型 | 只有一条 `Skill` 2.17（无事件，举剑插地，本作已用作 S1 剑雨） | 永续后冲刺数值变化，动作不变 | **无原作轨**（原作 S2 是瞬发回费），不做 |
| 9 | 乌尔比安 | S2 必须维系的界限 | `Skill_2_Begin` 0.17 → `Skill_2_Loop` 2.50（攻击）/ `Skill_2_Idle` 6.00（待机）/ `Skill_2_Die` | 永续后普攻换 `attack_s2`（`native_motion.variants perm 1`）；待机仍是普通 `idle` | **补**：新增 `idle_s2` = `Skill_2_Idle`，永续后待机换播；`attack_s2` 对拍结果见 §4 |

## 2. 汇总

- 永续技能干员 **9 人**。
- 已完成 / 不需要：凯尔希、流明、德克萨斯、逻各斯（4 人；逻各斯对拍后确认）。
- **补 4 人**（11-23 已做，§4）：安洁莉娜、浊心斯卡蒂、乌尔比安、铃兰。
- 不动 1 人：拉普兰德（用户 11-07 意见优先）。

## 3. 做法

1. 帧条走 B 方案（docs/407 O14、B9），从原作轨取帧，各人用自己现有帧条的同一条出图链路（重渲已有槽与现有贴图逐像素对上才用），@2x + @1x 都出。
2. 接入只改数据，新增两处通用画面机制（都只换贴图，不碰 attack_t / fire_t / 朝向，同 seed 不变）：
   - `sprites.perm_pose = {"s2": {"idle": 槽, "attack": 槽}}`（`character.gd _perm_pose`）：该技能永久生效后，待机换播原作持续轨（按 `perm_t` 画面时钟循环，待机 / 普攻来回切不从头播）；普攻换播原作技能攻击轨（帧数与 `attack` 相同时按 attack 的出手帧对齐，否则当循环轨播）。移动中的普攻仍走 `move_attack`。校验 V8 会查 perm_pose 引用的槽。
   - `sprites.skills.sN.tail`（`op_skill_seq.gd`，只对 intro / hold 型）：定格结束后接一段纯画面帧条（`play_vis_anim`），逻辑窗口仍只到定格结束。
3. 只换画面，同种子 TRACE 不变；交付只交一条 mp4（F23–F25）。

## 4. 11-23 补做结果（分支 claude/op-backfill-13c29b）

出图脚本 `tools/probes/package_perm_pose_1123.py`（`--apply` 写贴图与 json，中间件在主仓库 `build/op_backfill/`）。

| 干员 | 新 / 换的槽 | 来源与对齐 |
|---|---|---|
| 安洁莉娜 | `skill_s2`（S2 施法，`skills[1].anim`）、`attack_s2`（`perm_pose.s2.attack`） | codex-art `cb_18_prts_native_actions_1017` 原作 8 帧（现有 idle / skill 与 cb 帧在 (32,32) 裁窗逐像素一致）。skill_s2 = `Skill1_Begin` f0–f7，时序抄 skill 槽；attack_s2 = `Skill1_Loop` 取 f0 1 2 4 5 6 7 7（OnAttack 落在源 f4，对到 attack 出手帧 3），96 画布同 attack，时序抄 attack 槽 |
| 浊心斯卡蒂 | `idle_s2`（`perm_pose.s2.idle` 与 `.attack`） | `Skill_2_Loop` 全长 3.33 秒 14 帧，run_trial `cfg/skalter_idle_s2.json`（与现有 36 帧待机同一 cfg；用原 cfg 重渲 Idle 与现有 @2x 逐像素一致） |
| 乌尔比安 | `idle_s2`（`perm_pose.s2.idle`） | `Skill_2_Idle` 6 秒 8 帧（采样时刻同 idle）。@1x 用 make_op_1x 的同一 cfg（`build/op_1x/ulpianus/_cfg/idle_stand.json`，重渲 Idle 与现有 @1x alpha 逐像素一致）；@2x 同 cfg scaleMul ×2（只在 1 倍关时用） |
| 铃兰 | `skill_s2_intro` / `skill_s2_hold` 换图，新 `skill_s2`（`skills.s2.tail`） | 原作 `Skill2` 8 帧：intro = f0、hold = f1（槽规格不动，逻辑窗口 = 1/112 秒 + 250 ms 不变），定格后接 f2–f7（原作逐帧时长，约 1.2 秒，纯画面）。注意：光域扩大的特效仍在施法一开始出（逻辑出手点没动），比原作 OnAttack 0.80 秒早 |

@1x 除乌尔比安外按 make_op_1x ② 2×2 合并（与各人其他技能条同口径），之后跑过 `eye_fix` 瞳色保护。

**对拍**（现有帧条逐帧对 cb_18 原作帧找最吻合的源帧与平移）：

- 逻各斯：`skill_s2` = 原作 `Skill_1_Begin` f0–f7、`idle_s2` = `Skill_1_Idle` f0–f7、`attack_s2` = `Skill_1_Attack` f0–f7，全部 0 像素差；本作 S1「提喻」的 `skill_s1_loop` = 原作 `Skill_2_Loop`（0 像素差）。即原作 Spine 里 Skill_1 是殁亡（永续站姿 + 攻击）、Skill_2 是提喻（无攻击事件的引导）。现状已是原作对应轨，**不重出**；§1 原来按轨名序号推的「Skill_2_Loop」是错的。
- 乌尔比安 `attack_s2`（Codex S2Attack，`cw_ulpianus_skill_pixel_cleanup_1020`）：8 帧里 7 帧最吻合原作 `Skill_2_Loop`（f6 最近 Attack f3），平移一致（约 −34, −31），每帧约 2400–3000 像素差来自 Codex 逐像素修图与 0.1718 世界缩放，不是别的动作。判定：取自 Skill_2_Loop，不重出。

**验证**（11-23）：`check.py --only core / angelina_skill_anim / suzuran_skill_anim / skalter_specter_anim / siege_ulpianus_art / gallery_demo / skill_lifecycle / asset_index` 全过；铃兰、浊心两条测试按新画面改了期望（定格后接 Skill2 余段、S2 永续后待机 = idle_s2）。`art_lint` 的未豁免 FAIL 全在在制的夕 / 菲亚梅塔 / 令 / 傀影 / 黍 / 史尔特尔，本批 4 人没有新增。同种子 TRACE（seed 1、120 秒、`--maxprog --sptest`、基线 6765c217）安洁莉娜 / 浊心斯卡蒂 / 乌尔比安 / 铃兰各 121 行逐行相同。审阅录像：图鉴演示（精二、只放二技能、录像工具 `--shot_hold=8` 拉长生效后的停留），5 人各 10 秒，原速原色，主仓库 `build/op_backfill/perm_s2_demo_1123.mp4`。乌尔比安在演示里一直贴怪普攻，idle_s2 露面很少。
