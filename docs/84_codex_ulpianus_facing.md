# 84 · Codex 返修单：乌尔比安待机条朝向（2026-10-13）

> 给 Codex 的一次性返修单。起因：用户 10-13「选人和图鉴里乌尔比安朝左，别人朝右」。
> 游戏里已经用数据层标记临时修正（见 §3），返修交付后由协调人删掉标记。

## 1. 问题

全部干员帧条约定**朝右**画（docs/64、docs/69「朝右」），战斗中朝左时由程序水平翻转。逐帧检查乌尔比安四条帧条（1x 与 @2x 结论相同）：

| 帧条 | 帧数 | 朝向 | 结论 |
| --- | --- | --- | --- |
| `op_ulpianus_idle` | 4 | **朝左**（脸与视线在左，帽尖与发梢向右飘，锚抱在身前左侧） | **要返修** |
| `op_ulpianus_run` | 6 | 朝右 | 不动 |
| `op_ulpianus_attack` | 5 | 朝右（f0 锚举在身后左上，f2 向右甩出） | 不动 |
| `op_ulpianus_skill` | 7 | 朝右（f1–f2 举锚、f3–f5 向右伸手；f6 帽尖向右） | 不动 |

后果：选人立绘、图鉴、编队小像、HUD 头像直接贴待机第 0 帧，乌尔比安是唯一朝左的；战斗中他站定时和跑步 / 攻击方向相反（停步瞬间转身）。

另外：现在 skill f6 与 idle f0 不是同一张图（f6 朝右、idle 朝左），不满足「skill 末帧 = idle f0」的约定。

其余 17 名干员（安洁莉娜、能天使、艾雅法拉、星熊、艾丽妮、凯尔希、逻各斯、流明、水月、塞雷娅、推进之王、斯卡蒂、浊心斯卡蒂、归溟幽灵鲨、铃兰、德克萨斯、维什戴尔）的 idle / run / attack / skill 都已检查，朝向一致朝右，不需要改。

## 2. 要求

- 重画 `op_ulpianus_idle.png` 与 `op_ulpianus_idle@2x.png`，**朝右**。
- 建议以现在的 skill f6 为 idle f0 的姿势（它已经朝右、锚在身前），其余三帧做呼吸起伏；这样同时满足「skill 末帧 = idle f0」。也可以反过来重画两者，但 skill f6 必须与新 idle f0 一致。
- 不变：4 帧、fps 4、单帧 48×48 / 96×96、二值透明、`#080E18` 外描边（1x 1px / @2x 2px）、配色（与本人其他三条合计 ≤ 24 色）、1x 与 @2x 逐帧对应。
- 脚底锚点：朝右重画后脚底尽量落在帧中线附近；交付时在 handoff 写明 1x 脚底 x（游戏 json 里的 `sprites.idle.foot`，现值 [28,46] 是按朝左原图量的）。
- 只动 `art/incoming/`（以及 handoff / qa / preview / manifest），不改 `game/`。交回时给提交号。

## 3. 游戏里的临时修正（Claude，10-13）

`game/data/characters/ulpianus.json` 的 `sprites.idle` 加了 `"mirror": true`：

- 战斗绘制（`character.gd` 的 `anim_state` / `draw_body_at`、随行召唤物 `op_blocks.gd`、乌尔比安 / 归溟幽灵鲨自己的 `anim_state`）把带标记的帧条当作已翻转处理，翻转标志取反；脚底锚点 foot 仍按源图量，`foot_dx` 随翻转自动换算（x → 帧宽 − x），站定 / 起跑脚底不跳。
- 界面贴图（选人 `title.gd`、图鉴 `gallery.gd`、编队像 / 作战记录 / 开场 `choice_panel.op_idle`、HUD 头像 `Character.portrait`、标题陪伴干员 `title_bg.gd`）用 `A.mirror_strip` 生成的逐帧镜像副本；标题陪伴干员的脚底锚点按 宽 − x 换算。

**返修合入后**：协调人删掉 `ulpianus.json` 里的 `"mirror": true`，同时把 `sprites.idle.foot` 改成新图量得的值。`mirror` 机制本身保留，以后有画反的帧条可同样临时处理。
