# 第三方开放许可特效素材（2026-09-25 下载）

> 用途：干员特效的底稿 / 参考，魔改后再进 `art/incoming/fx_*`。本目录**不入库**（.gitignore），只有本 README 入库；每个包目录里有 `SOURCE.txt`（来源 + 许可 + 下载日期）。
> 我们的像素密度：人物 48px 放大 2 倍显示（@2x 通道下 96px 原图）。特效帧条建议做成 32–64px、按 2 倍显示；100px 以上的"高密度"素材要缩到 1 倍显示或重采样。
> 许可共同点：全部允许在非商业同人游戏里使用和修改；差别只在能否商用、要不要署名、**都不允许把素材本身再分发**（所以不进 git）。

## 分类与用途

| 目录 | 包 | 内容（尺寸） | 许可 | 建议给谁 |
|---|---|---|---|---|
| `holy_light/pimen_holy_vfx_01_02` | Pimen · Holy Spell Effect（用户购买） | VFX 01：光束 起手 2 帧 + 循环 8 帧 + 命中 7 帧，32px；VFX 02：**16 帧圣光光柱**，48px | 个人 / 商用可、可修改、不得转售 | **铃兰**光域光柱、**塞雷娅**钙质化 / 治疗；金色可直接用 |
| `holy_light/craftpix_free_magic_effects` | CraftPix · Free Pixel Magic Sprite Effects | 10 组 72px 帧条（治疗、光环、星落、闪现、藤蔓、石化…）+ 10 个 32px 图标 | CraftPix 免费许可（含商用）、可修改、不得转发 | 治疗十字 / 光环底稿；图标可当技能小图标参考 |
| `fire_lava/codemanu_pixel_effects` | CodeManu · Free Pixel Effects Pack | 20 个 100px 特效，8×8 帧网格：fire、bluefire、sunburn、felspell、weaponhit、magicspell、vortex… | CC-BY 4.0 / 公有领域 | **艾雅法拉**火山弹爆炸（fire / sunburn）、**维什戴尔**爆炸（weaponhit）；需缩小 + 重调色 |
| `fire_lava/codemanu_vfx_spritemancer` | CodeManu · Free VFX asset pack（192 MB） | 22 个特效，437px 单帧、30 / 60 fps、带 SpriteMancer 工程（.smp） | 公有领域 | 高分辨率参考；工程文件可改参数重导出 |
| `fire_lava/bdragon1727_free_effect_bullet_16x16` | BDragon1727 · Free Effect and Bullet 16×16 | 4 张 576×208 图集（火 / 水 / 绿 / 紫），16px 网格：火舌、弹道、小爆 | 非商用免费、可修改、不得转售 | 密度最贴合：**铃兰**狐火弹、**艾雅法拉**点燃火舌、炮口火 |
| `fire_lava/bdragon1727_effect_fx_part1` | BDragon1727 · Effect and FX Pixel Part 1（免费版） | 13 张 832–960×576 图集，64px 网格 | 同上 | 中型火焰 / 冲击 |
| `fire_lava/lamecke_lava_volcano_32` | lamecke · Lava Volcano 32×32 | 3 帧 32px 火山 | 随意付费 | 参考用，量太少 |
| `explosion/aklingon_explosions_vfx` | a_klingon · Explosions VFX | 14 个爆炸 / 烟 / 火花（explosionbig 800×132 等，含 gif 预览） | CC0（下载页确认） | **维什戴尔**余震 / 殉爆、通用爆炸 |
| `generic_fx/xyezawr_free_pack_1/2/3` | XYEzawr · Free Pixel Effects Pack #1–#3 | 单帧 100px PNG 序列（#1 约 180 帧 / #2 360 / #3 360）：光、火、雷、冲击 | 免费（含商用）、可修改、无需署名、不得转售 | 通用命中、圣光小闪；序列帧要自己拼条 |
| `generic_fx/oga_pixel_art_spells` | OGA · Pixel Art Spells | 16px 弹道帧条：Fireball、Light Bolt、Arcane Bolt、Bolt of Purity、Magic Ray… + 48px Shield | CC0 | 小弹道底稿（狐火 / 熔岩弹 / 炮弹） |
| `particles/kenney_particle_pack` | Kenney · Particle Pack（Calinou 打包） | 80 张柔光 / 烟 / 火花粒子（非像素） | CC0 | 加法发光层的柔光、烟雾底 |
| `icons/pixelboy_ninja_adventure` | pixel-boy · Ninja Adventure | 16px：FX（Slash / Claw / Explosion / Flam / Aura / Circle / Shield / Spirit / Smoke / Projectile）、Items 技能图标、粒子 | CC0 | **HUD 技能小图标**、爪痕 / 斩击参考；已删掉两个 Godot 工程包 |

## ansimuz 爆炸与魔法合集（2026-09-26 加入，用户购买）

目录 `ansimuz_explosions_magic/`：18 个包、约 130 个特效，逐帧 PNG（部分另有 spritesheet），原始 zip 在 `_zips/`，每包三帧预览在 `_preview/<包>.png`，帧数 / 尺寸清单在 `_catalog.json`；`_music_mystery_track/` 是附赠的一首音乐（wav / ogg / mp3）。
**许可（包内 readme）**：可用于个人及商业项目、可修改；**不得再分发**（无论改动多少）→ 不入库，只在游戏里用处理后的帧条；致谢页已加署名。
**画风**：统一的高对比像素风，帧宽多为 32–96px，按游戏 2 倍显示正合适（不必像 Ninja Adventure 那样放大 4–6 倍）。

| 包 | 内容（帧数 · 尺寸） | 建议用途 |
|---|---|---|
| 01 Magic N1 | 绿色旋风 air（17f 128×143）、冰晶升起 ice（17f 111）、落雷 thunder（15f 111×159） | 冰：敌对骑士 / 冰霜；雷：备用 |
| 02 Magic N2 Fire | 火团爆开 fire（14f 95）、**火焰光环 fire_aura**（13f 95，地面火圈张开）、**火苗 flame / flame-loop**（31f / 16f 47×75） | 推进之王跃空锤落地火圈；艾雅法拉点燃；铃兰狐火（调金） |
| 03 Magic N3 | 大落雷 big-bolt（23f 96×144）、蓝色能量球 small-spark 1–3、电弧 spark、雷柱 thunderrays | 雷系备用；small-spark-3 可作法术弹命中 |
| 04 Magic 4 | **治疗光柱 Cure**（29f 48×64，青色）、金色放射爆 Radial Explosion（10f 48）、电球 Sparks、水柱 Water（26f 48×88）、**紫红鬼火 wisp**（24f / 14f 48×55） | Cure → 凯尔希 / 塞雷娅 / 流明治疗；wisp → 逻各斯；Radial → 推进之王技力 / 金色冲击 |
| 05 Magic 5 | **火球弹 fire-missile**（5f 57×33）、火球爆 fireball、闪光 flash、**落地尘 impact-dust**（10f 45×27，白）、烟团 puff / vertical-puff / Smoke（17f 70×64）、**蓝色水花 water splash**（17f 64） | fire-missile → 艾雅法拉熔岩弹体；water splash → 斯卡蒂 / 乌尔比安（替换现在的米白水花）；flash → 炮口 / 手炮 |
| 06 Magic 6 | 白蓝斩击 slash / slash_b / slash-horizontal、绿边斩击 slash-e、**火焰斩 FireSlash**（11f 95）、紫电斩 electric slash | 斩击底稿（比 Ninja 的更细、密度对）：斯卡蒂、艾丽妮 S2、幽灵鲨 |
| 07 / 08 Warped Explosion 3 / 4 | 小型爆炸 20 种（16–48px，橙 / 白 / 烟） | **艾丽妮 S3 手炮 12 连击的落点小爆**；维什戴尔余震；通用命中 |
| 09 Warped Explosion 5 | 大爆炸 A（11f 80）、**蘑菇云 B**（9f 144×145，红黑）、烟尘爆 C（15f 192×160） | 维什戴尔巨炮 / 凋零处刑；艾雅法拉火山喷发 |
| 10 Magic 7 | 蓝水球 vfx-a、**暗红裂纹法球 vfx-b**、浪花球 vfx-c、紫→金爆 vfx-d（17f 80）、蓝能量爆 vfx-e | vfx-b / vfx-d → 逻各斯；vfx-c → 深海猎人 |
| 11 Warped Explosions 6 | 12 种：**火柱 explosion-e**（10f 64×82）、火苗柱 h / i / l、**冲击环 k**、黑烟爆 j（90）、碎片 c / d | 火柱 → 艾雅法拉火山；冲击环 → 通用落地；黑烟 → 维什戴尔 |
| 12 Warped VFX 1 | 血液 4 种（红）、**命中闪光 Hit-a…L 12 种**（蓝白：星芒、光环、定向刺光 Hit-H、弧光 Hit-k） | 通用命中特效（可替换现有 fx_hit_*）；Hit-H → 艾丽妮刺击；Hit-G → 剑尖星闪；血 → 幽灵鲨 S3 |
| 13 Magic 8 | 青色爪痕 Beam-slash（6f 64）、火爆 burst、青色能量盾 Spark、**水柱 water**（18f 64×192） | Beam-slash → Mon3tr 爪击（调绿）；水柱 → 斯卡蒂潮汐 / 涌潮悲歌 |
| 14 Magic 10 | 雷爆 Blast、落雷 Lightning-Bolt、电射线 Ray、Raybolt、电弧 Sparks | 雷系备用 |
| 15 Magic 11 | 冰刺 Ice_A / 冰柱 Ice_b / 冰晶 Ice_c（16–23f） | 冰系：骑士 Boss、减速地面 |
| 16 / 17 Warped Explosions 7 / 8 | 黑烟红火星爆炸、蓝色能量爆、白色冰爆、小爆 | 维什戴尔（黑红烟）、法术命中（蓝）、通用 |
| 18 Magic 12 | 金色十字闪 AirSlash、**龙息 DragonBreath**（8f 256×176）、**火焰 Flames**（7f 48×64）、绿色新月斩 GroundSlash、**毒云 Venom Cloud**（8f 128×80） | Flames → 推进之王落地火（替换程序火苗）、艾雅法拉；毒云调紫 → 溟痕 / 侵蚀；GroundSlash 调钢蓝 → 乌尔比安 |

**没有的**：地裂（仍用程序生成）、水母触手、锯盘、钩锚、光束 / 光柱（圣光仍用 Pimen）。

## 下一步（接入方式）

1. 圣光：Pimen VFX 02 光柱 → `fx_holy_pillar.png`（48px × 16 帧），铃兰暖光 / 迷雾展开时在光域中心与边缘播放；塞雷娅钙质化用同一条改琥珀色。
2. 火 / 岩浆：CodeManu `11_fire` / `16_sunburn` 缩到 64px、按 docs/25 的橙红色板重调 → `fx_lava_burst.png`；BDragon 16px 火舌替换程序画的点燃火舌。
3. 爆炸：a_klingon `explosionbig` 缩到 64px 调成暗红黑 → 维什戴尔炮击落点。
4. 图标：Ninja Adventure / CraftPix 的 16–32px 图标改成我们 8 人 × 3 技能的 HUD 小图标。
5. 全部经 `V6_FRAMES` 登记；致谢页加一行第三方素材来源（CC-BY 的 CodeManu 必须署名）。

## CreativeKind 31 合 1（2026-09-26 加入，用户购买）

目录 `creativekind/`：30 个子包（编号 01–31，没有 13）、**400 张精灵表 PNG**（12.4 MB），从仓库根目录的 `4313_CreativeKind 31 in one pack.zip`（32 MB，嵌套 zip + 1 个 rar）解出；只留 PNG，gif / zip / rar 没留。
**许可：CreativeKind（网上购买）。用户 2026-09-26 确认：网购，无单独许可文件，用户决定直接使用（可以进发布包）。** 和其他第三方素材一样**素材本体不入库、不推 GitHub**，只在游戏里用处理后的帧条；致谢页是否加 CreativeKind 由「文案」处理。

- `_catalog.json`：每张图的路径、尺寸、**推断的**帧尺寸 / 帧数 / 朝向（`orient`：h 横条 / v 竖条）、类别关键词（`tags`）、主色（`color`）。帧数是按「宽 / 高成整数倍」自动推断的，多行网格表会推错，用前对照 `_preview` 与原图核对。
- `_preview/<包>.png`：每包前 12 张各取中间一帧，缩到 64px 横排，挑素材先看这里。
- 画风：高对比像素、帧多为 32–128px（少数整张 300–1900px 的大表），按游戏 2 倍显示时多数要缩到 1 倍或重采样。
- 类别计数（一张可多类）：魔法 166、雷 56、火 47、冰 37、毒 37、暗 33、圣 29、空间 11、弹道 10、水 8、地 3、斩击 3、风 1、护盾 1
- 主色计数：青 95、蓝 77、橙 53、黄 43、红 40、绿 38、紫 16、白 14、粉 14、透明 6、灰 3、黑 1

| 子包 | 张数 | 类别 | 主色 | 常见帧边长 | 代表名 |
|---|---|---|---|---|---|
| 01_Ice_spell_effects | 8 | 冰 | 蓝 / 青 / 白 | 128 / 64 px | ice crystal、ice_prison、ice_spear_from_sky_few、ice_spear_from_sky_singl |
| 02_Lightning_spell_effects | 5 | 雷 / 弹道 | 白 / 绿 | 256 / 224 px | CLOUD LIGHTNING ATTACK、God_Spear、Lightning_ball_attack、Raijin_lightnin |
| 03_Magic_spell_effects | 9 | 魔法 / 冰 / 暗 | 青 / 蓝 / 红 | 128 / 160 px | Dark hand attack、Dragon head attack_blue、Dragon head attack_red、Energy |
| 04_Magic_spell_effects_2 | 8 | 魔法 / 火 / 空间 | 橙 / 蓝 / 青 | 128 / 300 px | Meteorite、SKY LASER_many、SKY LASER_single、comet_fire、comet_green |
| 05_Magic_Spell_Effects_3 | 9 | 魔法 / 雷 / 火 | 青 / 黄 / 蓝 | 256 / 240 px | Arrow、Fire bow attack、Hand attack、Lightning v1、Lightning v2 |
| 06_Magic_Spell_Effects_4 | 12 | 暗 / 火 / 弹道 | 红 / 蓝 / 黄 | 64 / 208 px | Starfall_blue、Starfall_yellow、explosion_simple、lightning_1、lightning_2 |
| 07_Fire_Spells_Effects | 16 | 火 / 空间 / 斩击 | 青 / 橙 / 紫 | 144 / 128 px | Fire vortex_blue、Fire vortex_green、Fire vortex_red、FireHammerBlueV1、Fi |
| 08_Dark_Spell_Effects | 10 | 暗 / 斩击 / 雷 | 红 / 紫 | 2112 / 1920 px | Dark Lord Anger、Dark Lord Anger_no_lord、Dark Lord Wrath、Dark Lord Wrat |
| 09_Magic_Spell_Effects_5 | 7 | 火 / 魔法 / 雷 | 黄 / 蓝 / 红 | 336 / 468 px | Ancient_Dragon_blue、Ancient_Dragon_red、demon_fire、fire_breath、fire_lig |
| 10_Dark_Electricity_Spell_Effects | 6 | 雷 / 暗 / 弹道 | 蓝 / 紫 / 灰 | 2016 / 576 px | Dark_eyes、Dark_octopus、Dark_tentacle_sphere、Electric_tentacle、two_elec |
| 11_Magic_Spell_Effects_6 | 10 | 雷 / 火 / 魔法 | 青 / 蓝 / 紫 | 1600 / 832 px | 4_magic_balls_explosion、Dark_spirit、Electric_explosion、Energy_beam、Kin |
| 12_Water_Spell_Effects | 7 | 水 | 蓝 | 112 / 96 px | Water_Spell_1、Water_Spell_2、Water_Spell_3、Water_Spell_4、Water_Spell_5 |
| 14_Magic_Spell_Effects_7 | 9 | 火 / 魔法 / 暗 | 红 | 128 / 192 px | Spell1_DarkBeam_black、Spell2_ExplosionSphere、Spell3_Smoke、Spell4_Small |
| 15_Space_Spell_Effects | 6 | 暗 / 空间 | 蓝 | 224 / 240 px | DarkSpell1、DarkSpell2、DarkSpell3、DarkSpell4、DarkSpell5 |
| 16_Fire_Spell_Effects_2 | 11 | 火 | 橙 / 青 / 黄 | 1728 / 448 px | Fire Spell 1、Fire Spell 2、Fire Spell 2 blue、Fire Spell 3、Fire Spell 3  |
| 17_Lightning_Spell_Effects_2 | 12 | 雷 | 青 / 黄 / 蓝 | 1056 / 1968 px | Lightning Spell 1、Lightning Spell 2、Lightning Spell 3、Lightning Spell  |
| 18_Ice_Spell_Effects_2 | 7 | 冰 | 青 / 蓝 | 160 / 576 px | Ice Spell、Ice Spell 2、Ice Spell 3、Ice Spell 4、Ice Spell 5 |
| 19_Magic_Spell_Effects_8 | 10 | 魔法 | 青 / 橙 / 蓝 | 448 / 100 px | Spell 1、Spell 2、Spell 3、Spell 3(2)、Spell 4 |
| 20_Magic_Spell_Effects_8 | 11 | 魔法 | 橙 / 蓝 / 青 | 352 / 96 px | Spell 1、Spell 1_blue、Spell 2、Spell 2_blue、Spell 3 |
| 21_Color_Spell_Effects | 6 | 魔法 | 蓝 / 红 / 橙 | 240 / 160 px | Spell 1、Spell 2、Spell 3、Spell 4、Spell 5 |
| 22_Magic_Spell_Effects_10 | 27 | 魔法 | 绿 / 蓝 / 红 | 1728 / 1184 px | Spell 1_blue、Spell 1_green、Spell 1_red、Spell 2_blue、Spell 2_green |
| 23_Holy_Spell_Effects | 26 | 圣 | 黄 / 青 / 透明 | 912 / 160 px | Spell 1、Spell 10、Spell 10_blue、Spell 11、Spell 12 |
| 24_Poison_Spell_Effects | 37 | 毒 / 水 | 绿 / 蓝 / 橙 | 288 / 320 px | Spell 1、Spell 1_blue、Spell 1_magenta、Spell 1_red、Spell 2 |
| 25_Magic_Spell_Effects_11 | 17 | 魔法 / 暗 / 圣 | 蓝 / 绿 / 红 | 1936 / 832 px | Spell 1_blue、Spell 1_dark_red、Spell 1_green、Spell 1_red、Spell 2_blue |
| 26_Magic_Spell_Effects_12 | 18 | 魔法 | 绿 / 橙 / 黄 | 512 / 320 px | Spell 1_blue、Spell 1_green、Spell 1_magenta、Spell 1_red、Spell 2_blue |
| 27_Lightning_Spell_Effects_3 | 21 | 雷 | 青 / 黄 / 绿 | 384 / 288 px | Spell 1_blue、Spell 1_green、Spell 1_red、Spell 2_blue、Spell 2_grey |
| 28_Magic_Spell_Effects_13 | 17 | 魔法 | 橙 / 蓝 / 青 | 1568 / 128 px | Spell 1、Spell 2.1、Spell 2.2、Spell 3、Spell 3_blue |
| 29_Magic_Spell_Effects_14 | 12 | 魔法 | 青 / 橙 / 黄 | 480 / 1936 px | Spell 1_blue、Spell 1_orange、Spell 2_blue、Spell 2_orange、Spell 3_blue |
| 30_Magic_Spell_Effects_15 | 26 | 魔法 | 青 / 黄 / 橙 | 432 / 576 px | Spell 1_blue、Spell 1_yellow、Spell 2_blue、Spell 2_yellow、Spell 3.1_blue |
| 31_Ice_Spell_Effects_3 | 20 | 冰 | 青 / 蓝 | 440 / 1760 px | Spell 1、Spell 1_emerald、Spell 2、Spell 2_emerald、Spell 3 |

**按用途找**（括号里是该包里这一类的张数）：
- **魔法**：03（6）、04（5）、05（5）、09（2）、11（3）、14（3）、19（10）、20（11）、21（6）、22（27）、25（15）、26（18）、28（17）、29（12）、30（26）
- **雷**：02（5）、05（2）、06（3）、08（2）、09（1）、10（6）、11（4）、17（12）、27（21）
- **火**：04（2）、05（1）、06（5）、07（16）、09（5）、11（3）、14（4）、16（11）
- **冰**：01（8）、03（2）、18（7）、31（20）
- **毒**：24（37）
- **暗**：03（1）、06（6）、08（10）、10（6）、11（1）、14（2）、15（6）、25（1）
- **圣**：06（2）、23（26）、25（1）
- **空间**：04（1）、06（2）、07（2）、15（6）
- **弹道**：02（1）、06（4）、08（2）、10（2）、11（1）
- **水**：12（7）、24（1）
- **地**：04（1）、06（2）
- **斩击**：07（1）、08（2）
- **风**：05（1）
- **护盾**：11（1）

**当前需求的推荐**：蓝色 / 靛蓝能量（逻各斯二技能）先看 03（Dragon head blue、Energy comet）、11、21、22 / 25 / 26 的 `_blue` 变体；冰 / 寒气（Boss）看 01、18、31（31 另有 `_emerald` 变体）；声波 / 冲击环看 23（圣光环）与 27（雷环），需要再调色。
