# docs/97 C · 七人技能收招对齐

用户本次确认：连同待机与技能统一压到24色。因此本批交七人 idle / skill 的 1x 与 @2x（28 PNG）。艾丽妮、凯尔希、塞雷娅、斯卡蒂、维什戴尔、安洁莉娜、星熊；逻各斯和流明已在 A 批完成。

每人的本批待机与技能共用 ≤24 色，技能最后一帧逐像素复制本批 idle f0。其他技能帧与待机帧仅做机械色板收敛 / 描边校正，未重画动作和武器；未动跑步、攻击等其他动作。已符合24色的安洁莉娜与星熊保留原色板。

## QA
`python tools/art_lint.py --ops irene,kaltsit,saria,skadi,wisadel,angelina,hoshiguma --no-images`：未豁免 FAIL = 0，既有豁免 FAIL = 2（斯卡蒂跑步、安洁莉娜浮空）。七人的 skill_end 全部 PASS。本批逐人身高 / 脚底 x / 两动作色数见 manifest measurements。

仍有19项 WARN：其他动作遗留的总色数、脚底配置偏移、呼吸幅度、明度与 D 批待修的1x/2x对位等，全部原样记录在 QA；没有因只改两条就宣称整个人物总色数已≤24。明度的指定对象后续 E 批处理；配置脚底偏移依工单交由 Claude，不改 game/。

## 预览
preview.gif：七人 idle 与 skill 的本批素材循环，深色底；lineup：七人及斯卡蒂 / 浊心斯卡蒂 / 流明参照，亮暗两行、脚底对齐。预览不是游戏录屏。

只交 art/incoming，未接入 main；帧数 / fps / fire 保持原配置，manifest 列明 SHA256。
