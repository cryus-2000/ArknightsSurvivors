# 编队三批美术：来源与制作记录

2026-09-25，使用内置 image_gen 生成动作原稿，再做透明背景清理、切帧、像素尺寸适配、24色共享色板与锚点校验。没有使用 API/CLI 回退。所有交付PNG在本目录，游戏不依赖下面的原稿路径。

用户给的立绘分别对应推进之王、斯卡蒂、塞雷娅、维什戴尔、艾雅法拉、凯尔希、铃兰；第8张与第7张为同一张铃兰。博士参考此前已交付的兜帽博士。Mon3tr补充参考链接见第三批handoff。

## 最终采用的原稿

原稿目录：`C:/Users/colafax/.codex/generated_images/01a08159-bde5-7d50-b7e0-571e2eeb3a31/`。每个编号对应 `exec-<编号>.png`，供本机追溯；未采用的迭代图不属于交付素材。

| 角色 / 动作 | 原稿编号 |
|---|---|
| 博士四组 | 9d3ad51f-e568-4895-9425-2920759dc2b0 |
| 维什戴尔待机、跑步 | 0f8138c8-68da-409d-bb75-56a50fa79519 |
| 维什戴尔普攻、技能（单炮修正版） | 3465beb8-104f-42a4-b250-3c2f821e7ac7 |
| 推进之王 | 4e829d16-e2f7-4eff-9277-4464dc89af6a |
| 斯卡蒂 | 49aefd30-58c4-4331-bc34-f049bd2ce2b0 |
| 塞雷娅 | 7bee82d6-d973-4c88-9858-9e442e674d4a |
| 艾雅法拉 | 3de52723-bd52-46e0-9c7a-93000fe0ff6c |
| 凯尔希 | d8f6bb9e-e4ef-4638-b0c4-ae6be0fd804f |
| 铃兰 | a4f287ee-b337-4fc3-913c-c55299c1fc21 |
| Mon3tr | baffd8c4-a3d3-414d-bd2d-5542def10697 |

## 生成提示要点

共同提示：Faithful to supplied costume reference. Cute readable chibi pixel art, about 2.3 heads tall. Hard #080E18 outline and 24-color clusters, transparent background. Equal-height horizontal rows with requested frame counts, same character scale, full weapons within cells, clear gaps, right-facing action. No text, borders, ground shadows, projectiles, glows or attack effects. Final game cell48x48 with standing body about34px; Mon3tr64x64.

- Doctor: preserve concealed face, navy hood coat, cyan markings and grey shirt. Four idle frames; six short-stride running frames with coat sway; two hurt frames leaning back and protecting face; four death frames stumble, kneel, side fall, lie still. Fallen frames retain standing scale.
- Wisadel idle/run: white-silver hair, horns, red-black jacket and shorts, boots, one large right-shoulder cannon. Four idle and six running steps.
- Wisadel firing revision: costume only from illustration, no back-mounted equipment, wings, backpack or diagonal gun. Precisely one cannon held in both hands and braced on shoulder. Five poses aim, brace, recoil, recoil hold, recover. Seven heavy firing poses ready, raise, lower muzzle, raise barrel, strong recoil, hold, recover. No muzzle flash.
- Siege: tawny lion ears/tail, blonde hair, white fur collar, red-lined black jacket, grey top, short dark bottom and ankle boots. Four idle, six running, four one-handed hammer swing, six two-handed overhead slam poses.
- Skadi: long silver hair tied low, black angular wide hat with teal lining, dark coat, red belt, thigh-high boots, greatsword. Four idle, six run, five horizontal sword attack poses, seven overhead heavy slash poses.
- Saria: silver hair, small dark-orange horns, white long coat with black-orange trim, dark dress/boots, large rectangular diamond-pattern shield and injection hammer. Four idle, six run, four shield-bash poses, six protective shield-raise poses. No shield glow.
- Eyjafjalla: brown long hair, curled sheep horns, pink eyes, grey mauve dress, white coat/red lining, dark stockings and boots, thin dark staff. Four idle, six run, four casting poses, eight charged staff-cast poses. No fire/lava.
- Kaltsit: short white hair, dark-tipped lynx ears, green eyes, chartreuse dress, white long medical coat/black panels, ankle boots, terminal and vial. Four idle, six run, four healing gestures, six summoning/pointing gestures. No summoned creature in these frames.
- Suzuran: blonde bob, large fox ears, cyan headband, green eyes, multiple golden tails, white/navy/lavender dress, white stockings, dark shoes, ornate star-ring staff. Four idle, six run, four staff-wave poses, six raised-staff/open-hand domain-cast poses. No domain effect.
- Mon3tr: original summon, not humanoid operator; dark crystalline skeletal dragon, angular snout, spined arched back, two huge blade foreclaws, segmented tail and pale yellowgreen facets. Four idle, six scuttling poses, four claw strike poses. No detached crystals, red ring, slash FX or aura.

## 像素整理与验证

原稿不是可直接导入的帧条。逐行识别完整角色后统一输出等宽横向PNG，清除伪透明棋盘格/白底，alpha强制二值。按脚部位置校准横向中心；大武器在画布内适配，保留身体中心比例。博士死亡整条统一比例。Mon3tr原稿待机朝左，导出时已镜像成右向。

每个角色的所有动画共同量化到24色（包含描边），外沿明确为1px #080E18。校验图像大小、帧数、alpha、画布边界透明、基线、轮廓色、各帧非空且不同；逐帧像素摘要与每文件SHA256见QA和manifest。透明背景像素不计入角色色数。

程序接入使用manifest中的锚点，不要从每帧可见包围盒重新取中心。本次仅交付美术，游戏内视觉与动画事件验证交由Claude接入后完成。
