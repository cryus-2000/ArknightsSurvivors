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

## 下一步（接入方式）

1. 圣光：Pimen VFX 02 光柱 → `fx_holy_pillar.png`（48px × 16 帧），铃兰暖光 / 迷雾展开时在光域中心与边缘播放；塞雷娅钙质化用同一条改琥珀色。
2. 火 / 岩浆：CodeManu `11_fire` / `16_sunburn` 缩到 64px、按 docs/25 的橙红色板重调 → `fx_lava_burst.png`；BDragon 16px 火舌替换程序画的点燃火舌。
3. 爆炸：a_klingon `explosionbig` 缩到 64px 调成暗红黑 → 维什戴尔炮击落点。
4. 图标：Ninja Adventure / CraftPix 的 16–32px 图标改成我们 8 人 × 3 技能的 HUD 小图标。
5. 全部经 `V6_FRAMES` 登记；致谢页加一行第三方素材来源（CC-BY 的 CodeManu 必须署名）。
