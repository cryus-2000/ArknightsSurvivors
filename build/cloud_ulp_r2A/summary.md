# 乌尔比安 第 2 轮 单人胜率（A 组，当前版本）

代码 = ca238830f（origin/claude/ulpianus-regen-f3b6be 分支头已前进到 0eb5ce16a=艾雅法拉/铃兰开局自保，按任务指定的 ca238830f 测，未用分支头）。参数 --tier=0 --tide=0，高手机器人。

## 乌尔比安单人
- m18（seed 1–24）：17/24 = 70.8%（Wilson 95% 50.8–85.1%），均存活 10:37（637s），死因前 5：corrode ×3、shock_founder ×1、dark ×1、shock_paranoia ×1、wound ×1
- m0（seed 1–16）：7/16 = 43.8%（Wilson 95% 23.1–66.8%），均存活 9:24（564s），死因前 5：corrode ×3、wound ×1、shock_paranoia ×1、mire ×1、bullet ×1

## gapleaders 6 开局 m18（seed 1–16）

| 开局 | n | 胜率 | Wilson 95% | 均存活 | 死因前 3 |
|---|---|---|---|---|---|
| skadi | 16 | 50.0% | 28–72% | 559s | corrode×2、wound×2、dark×1 |
| ulpianus | 16 | 81.2% | 57–93% | 659s | shock_paranoia×1、corrode×1、wound×1 |
| irene | 16 | 25.0% | 10–49% | 557s | corrode×4、wound×3、contact_tracer×2 |
| wisadel | 16 | 68.8% | 44–86% | 600s | atk_reaper×1、contact_tracer×1、contact_founder×1 |
| logos | 16 | 56.2% | 33–77% | 554s | wound×3、contact_reaper×3、corrode×1 |
| eyjafjalla | 16 | 0.0% | 0–19% | 284s | contact_tracer×7、corrode×3、wound×2 |

核对：gapleaders 中乌尔比安 16 局与 a 的 seed 1–16 逐局胜负完全相同。

乌尔比安 m18（a 的 24 局）胜率 70.8%，比其余 5 名开局均值（40.0%）高 30.8 点。

script_errors 局数：1（[(['eyjafjalla'], 16)]；["SCRIPT ERROR: Out of bounds get index '3' (on base: 'Array')"]）
