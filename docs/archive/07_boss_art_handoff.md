# Boss 首轮美术交接（2026-09-24）

本轮范围：全部 Boss 本体、两帧待机及必要形态，供造型确认。共 15 张帧条、30 帧。未制作移动、攻击、装弹、冲锋、死亡、复活动画或技能 FX；未改游戏代码。

素材在 art/incoming/bosses/。boss_preview.html 可本地打开循环预览；boss_preview.png 为实际像素放大总览。boss_manifest.json 是机器可读尺寸清单。

| 角色/形态 | 文件 | 单帧 | 帧数 |
|---|---|---|---|
| 最后的骑士 与罗辛南特 | boss_last_knight_mounted_idle.png | 96×80 | 2 |
| 圣徒卡门 | boss_carmen_idle.png | 64×64 | 2 |
| 圣徒伊比利亚 | boss_iberia_idle.png | 64×64 | 2 |
| 接潮主教 | boss_tide_bishop_idle.png | 64×64 | 2 |
| 接潮主教 假死 | boss_tide_bishop_feign.png | 64×64 | 2 |
| 接潮蔑死体 | boss_tide_defier_idle.png | 80×80 | 2 |
| 接潮蔑死体 假死 | boss_tide_defier_feign.png | 80×80 | 2 |
| 接潮斥亡体 | boss_tide_rebuker_idle.png | 80×80 | 2 |
| 接潮斥亡体 假死 | boss_tide_rebuker_feign.png | 80×80 | 2 |
| 塑路者 | boss_pathshaper_idle.png | 80×80 | 2 |
| 延命塑路者 | boss_lifeshaper_idle.png | 80×80 | 2 |
| 塑路者分形 | pathshaper_fractal_idle.png | 32×32 | 2 |
| 偏执泡影 一阶段 | boss_paranoia_phase1_idle.png | 80×80 | 2 |
| 偏执泡影 二阶段草案 | boss_paranoia_phase2_idle.png | 80×80 | 2 |
| 最后的骑士 步行造型草案 | boss_last_knight_idle.png | 64×64 | 2 |

## 接入约定

- PNG RGBA，精灵 alpha 仅 0/255，无抗锯齿；外轮廓采用 #080E18。
- 每张横向一行，从左向右两帧，建议 2 fps 循环，nearest 采样，关闭 mipmaps。
- 底部留空 2–3 像素；可采用底部中心 pivot。碰撞范围由游戏单独定义，不能照整张纹理大小设置。
- 主教在两组关卡复用同一套。feign 是静止蜷伏/跪伏的假死造型，不能作为假死转换动作。
- 枪械、法杖、长枪随本体绘制，未拆成可独立旋转的武器贴图。
- 最后的骑士提供带罗辛南特的合体与额外步行造型；并不据此声明原作阶段与下马形态一一对应。阶段逻辑需开发侧按原作核对。
- 偏执泡影二阶段的展开幅度、假死姿势和骑士步行全身细节为基于参考的首轮像素化草案，需要用户确认，不声称逐像素复刻原作战斗模型。
- 本轮待机为两个离散姿势，不是骨骼动画。确认轮廓后再统一更细致的运动节奏。

## 参考与制作

参考 PRTS 同名敌人页面，以及 Aceship/Arknight-Images 敌人头像；骑士同时参考 PRTS 的公开 Spine 图集。生成完整像素造型后机械缩放、去背景、清理游离碎片、加描边并检查。未将原作头像或 Spine 图集直接交付为游戏素材。

- https://prts.wiki/w/圣徒卡门
- https://prts.wiki/w/圣徒伊比利亚
- https://prts.wiki/w/接潮主教
- https://prts.wiki/w/接潮蔑死体
- https://prts.wiki/w/接潮斥亡体
- https://prts.wiki/w/塑路者
- https://prts.wiki/w/延命塑路者
- https://prts.wiki/w/“偏执泡影”
- https://prts.wiki/w/最后的骑士

## 检查

15 张帧条均检查尺寸、非空帧、两帧存在差异、二值透明度、边缘留空，并人工检查总览。HTML 为本地预览文件；尚未做 Godot 运行接入验证。
