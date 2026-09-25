# EW 武器修正

依据用户提供的原作武器拆解参考图，替换此前通用黑色圆筒炮：银灰扁长主体、浅色雕纹、红色机构、尖锐前端与侧向棱片。在48px中以轮廓和明暗色块表达雕纹，无法逐线复刻细小纹饰。

更新 op_wisadel_idle/run/attack/skill.png，共22帧。单帧48×48、脚底(24,46)、24色共享色板、alpha0/255、#080E18描边。帧数4/6/5/7与fps4/10/14/12不变，普攻出手索引2、技能索引4不变。

同步更新第二批manifest、QA、预览与角色总览；未修改游戏代码。程序无需调整切帧参数，接入后仍需游戏内验收。

使用内置image_gen；原稿为 exec-6b1c0312-b045-4515-a76d-e4deed218a80.png，位于本机 Codex generated_images/01a08159-bde5-7d50-b7e0-571e2eeb3a31/。本记录取代 squad_sources.md 中维什戴尔旧武器原稿的当前交付地位，旧记录保留作为历史。

提示词核心：Match the first weapon reference's bottom assembled silhouette: ornate silver-grey elongated rectangular crossbow-like launcher, silver relief scrollwork, red mechanical core, pointed fins and narrow forward blade/prong. No cylindrical bazooka, only one weapon. Preserve Wisadel's existing chibi costume. Four rows with4/6/5/7 frames, right-facing attacks, transparent pixel art,24colors. No projectiles, muzzle fire or effects.

校验覆盖：文件尺寸、帧数、不同帧、二值透明、24色、深色轮廓、画布边缘透明和逐帧底部基线。详细结果见 squad_batch2_qa.json。
