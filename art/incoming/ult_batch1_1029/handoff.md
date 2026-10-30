# 终结技第一批 · 用户批准提交的关键帧快照

2026-10-29 用户要求「先提交一下这一波」。本次提交仅含这批16项、32张@2x关键帧及审阅/重建材料；完整动画和游戏接入另行进行。分支codex/art，由协调人审阅合入。

## 最终口径

- 剑雨原样复用当前游戏余像剑雨优先调用的fx_texas_sword_drop@2x.png。源帧0、4，源尺寸24×80、锚点(12,76)；仅平移(20,148)放入64×224画布，锚点(32,224)。可见颜色与alpha覆盖逐像素一致。
- 海嗣由原作Start/Skill附件按原层序合成。光束采用稳定青绿细芯和深红粗糙外层，编织波纹已撤换；当前审阅线宽80（上一版40，翻倍），长度304与原骨架口部起点一致。贴图帧尺寸仍为192×80；review_draw_width=80是接入粗细参考，不是已改游戏参数。
- 熔毁使用原作Mon3tr Skill_2关键姿态作对位依据，以C_Body_III骨骼确定核心。独立破甲爆发层不包含本体；本体仅出现在审阅合图。重构使用原作Start附件和结构光路径，不使用生成的召唤物本体。
- 巨锚来自原作Spine武器附件，排除链条，逐件在同一网格像素化。90°代表角度由同一成图严格旋转，未重画形状。附件及像素部件证据在references/native_anchor。
- 能天使为白热小芯、橙红碎火花，锁定框保留中心空白；海嗣水纹为蓝黑水体、青色破碎边，少量深红共鸣边。
- 六个拼接段端点色值与覆盖已一致。弧段有30°参考角及参考半径，沿圆摆放时按目标半径统一缩放，仍需在实际引擎采样下验收。

## 交付与查看

keyframes/：16项×2张关键帧。manifest.json记录尺寸、原点、目标帧段、代表帧号、哈希、原作来源与预算。previews/与review.html为静态审阅；beam_scene_r2.json等记录对位。文件名中的r2/r3属于过程编号，当前粗细以manifest.review_draw_width=80为准。

内置imagegen用于独立特效候选，提示词见prompts.json、revision2_prompts.json与revision3_prompt.json；原生本体与巨锚使用原始附件构造。已撤出的生成本体、旧失败稿与原始下载包留在本地，不纳入本次交付，精确文件清单见delivery_files.json。

## 检查

最新独立核验见commit_verification.json，核验脚本verify_delivery.py：32张PNG的尺寸/二值透明/哈希；6段×2帧的端点覆盖；巨锚90°旋转；当前剑雨源像素复用；线宽80、口部起点与长度；审阅页本地资源完整性；单文件5MiB及全批30MiB目标预算。

当前32张关键帧理论RGBA共4.328125MiB；目标完整帧条理论RGBA共17.5234375MiB。这是尺寸预算，不是实机显存或帧率结果。静态图已展示并获本次提交授权，完整动画、动态消失、扫射时序、低画质与实机验收尚未完成。

## 重建环境

本机运行python -X utf8 export_keyframes.py可重建，顺序包含refine_keyframes.py、seaborn_review.py、revision2_scenes.py、revision3_review.py。Python Pillow/numpy、Node Canvas、Spine runtime与当前游戏纹理为现有依赖。

重建还读取本机的de_summon_style_alignment_1020原生附件、art/reference/summons_spine_20261020骨架源，以及E:/ArknightsSurvivors主工作区的当前游戏素材；这些全局既有输入不在本次提交范围，来源/哈希记在manifest和原生附件证据中。纯查看review.html和使用已交付关键帧不需要运行重建脚本。不要把“本机可重建”理解为全新克隆可无外部输入重建。

接入时保留原骨架本体独立绘制，避免把审阅合图当作运行贴图；海嗣前/后层帧数不同，完整动画阶段须明确播放映射。Codex本次未改game、未合并main。
