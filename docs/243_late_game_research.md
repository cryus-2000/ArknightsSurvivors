# 243 同类游戏的后期画面可读性调研（11-04）

> **结论摘要**
> 1. 同类游戏里，没有一款靠「把我方特效画得更花」来解决后期看不清。常见的三种做法是：**威胁独占一种样式**、**非威胁的东西退后**（设置里的不透明度滑条、自动降级、改美术对比度）、**掉落物合并或自动回收**。
> 2. 我们的特殊问题是**红色被滥用**：黑潮整屏偏红、预警、溟痕、精英描边都偏红。其次是**暖金撞色**，经验结晶和我方攻击都是暖金。这两条都能用全局参数改，不用动美术。
> 3. 推荐 8 个方案（§3）。第一批先做三件低成本的：**红色只留给威胁**、**结晶换掉暖金并合并**、**地面区域只画边、靠照地显形**。然后用 late-game-diag 的色彩预算量一遍，再决定要不要做第二批的**明度分层**和**队员光源**。
> 4. 想让「攻击看得见」，比较对口的是 Noita 自己的办法：**每次出手带一个短命光源去照地**，再加上有重量的碎屑。不用逐个干员重画帧条，pixelfx 那条路不再推荐。
> 5. 资料的局限：这次会话的网络不放行 Steam、SteamDB 和各家维基，所有出处只能从搜索摘要里核对，**没有逐字读过原页**。下文对每条来源都标了可信度。

分支 `claude/late-game-research`，基于 `origin/claude/integ-1105` db27f6745。**本稿没有改任何游戏文件。**

---

## 0 范围与方法

- 题目：后期满屏怪时，同类游戏怎么让我方攻击和角色不被淹没。
- 调研对象：
  - 指定的 11 款：Vampire Survivors、Brotato、Halls of Torment、20 Minutes Till Dawn、HoloCure、Soulstone Survivors、Deep Rock Galactic: Survivor、Spirit Hunters: Infinite Horde、Noita、Risk of Rain 2、Hades；
  - 补充：Riot（英雄联盟）的可读性文章，GDC 上关于 VFX 可读性的演讲，Diablo IV 和 ESO 的「他人特效」处理。
- 方法：网页搜索，交叉核对补丁说明、官方或社区维基、Steam 讨论和访谈。
- **可信度标记**：
  - **[补丁]**：补丁说明或官方公告，经搜索摘要核对；
  - **[维基]**：社区维基，经搜索摘要核对；
  - **[二手]**：媒体转述；
  - **[玩家]**：玩家帖或玩家记忆；
  - **[未证实]**：只见于单个弱来源，或者摘要里看不出属于哪款游戏。
- **局限**：本会话的出站网络访问不到 steamdb.info、steamcommunity.com、各 wiki.gg 和 fandom 等站点（curl / WebFetch 都是 DNS 失败），所以每条结论**只核对到搜索摘要**一级。写进约束性文档之前，应当打开原页核一次措辞。
- 查不到的一律写「查不到」。

---

## 1 逐款记录

问题编号对应任务里的 6 问：
- ① 角色怎么保持可见；
- ② 敌我怎么分色、分亮度；
- ③ 特效设置或自动降级；
- ④ 掉落物怎么不抢眼；
- ⑤ 成长时攻击怎么加码；
- ⑥ 开发者谈可读性的出处。

### 1.1 Vampire Survivors（poncle）

- ① 查不到。没找到描边、光圈或角色置顶绘制的说明。
- ② 查不到。
- ③ 设置：
  - 选项里有 **Flashing VFX** 开关，五芒星闪光后来也改成受它控制 [维基] https://vampire.survivors.wiki/w/Options
  - 有伤害数字开关 [维基]，出处同上。
  - 0.11.209 加了「关闭移动背景」选项 [二手] https://primagames.com/tips/vampire-survivors-patch-notes-0-11-209
  - 武器不透明度：
    - 2024-11 有玩家回忆 poncle 说过不打算做武器不透明度滑条 [玩家] https://steamcommunity.com/app/1794680/discussions/0/4631482569784862180
    - SteamDB 有一条标题为 "Weapon opacity option" 的补丁说明，理由是「画面会被自己的攻击完全占满」 https://steamdb.info/patchnotes/12324890 。但摘要里看不出是哪款游戏，记为 **[未证实]**。
- ④ 掉落物：
  - 经验宝石分蓝、绿、红三档，档越高价值越高 [维基] https://vampire-survivors.fandom.com/wiki/Experience_Gem
  - 地上超过约 **400 颗**时不再掉新宝石，多出的经验并进一颗红宝石。离屏太远的经验也并进红宝石 [玩家，转引维基] https://steamcommunity.com/app/1794680/discussions/0/3829793451738405084
  - Vacuum（吸尘器）一次吸走全场宝石 [维基] https://vampire.survivors.wiki/w/Vacuum
- ⑤ 攻击加码：武器进化会换外观和行为，例如鞭子进化成血泪，刀光更大；魔杖进化成圣杖，主要是变快 [二手] https://www.pcgamer.com/vampire-survivors-evolve-weapons-evolutions-guide
- ⑥ 查不到谈可读性的访谈。找到的 poncle 访谈谈的是商业和设计历程 [二手] https://www.pockettactics.com/vampire-survivors/interview

### 1.2 Brotato（Blobfish；后由 Evil Empire 开发）

- ① 查不到。
- ② 0.6.0.7 加了「**高亮敌方投射物**」选项，同时加了隐藏 Boss 血条的选项 [补丁/维基] https://brotato.wiki.spellsandguns.com/Patch_0.6.0.7
- ③ 设置与降级：
  - **1.0.1.3（2023-12-05）**加了「**我方投射物不透明度**」和「**爆炸不透明度**」选项，明确写着是「改善无尽模式的可见度」[补丁/维基] https://brotato.wiki.spellsandguns.com/Patch_1.0.1.3
  - 更早没有加选项，而是直接改美术：0.5.10 **降低爆炸亮度**，0.6.1.6 改了爆炸透明度 [维基] https://brotato.wiki.spellsandguns.com/Patch_0.5.10 、 https://brotato.wiki.spellsandguns.com/Patch_0.6.1.6
- ④ 材料同时是经验和货币。Harvesting（收获）属性在波次结束时直接结算，不用捡 [维基] https://brotato.wiki.spellsandguns.com/Harvesting
- ⑤ 查不到成长视觉的说明。
- ⑥ 查不到。网上有一条开发者谈「每秒 100 个敌人、20 发子弹，仍是可读的谜题」的引述，但来源不明 [未证实]，不采用。

### 1.3 Halls of Torment（Chasing Carrots）

- ① 查不到。Steam 上有玩家要求加特效和怪群不透明度滑条 [玩家] https://steamcommunity.com/app/2218750/discussions/0/3801652929323026410
- ② 2023-09-21 补丁有「Visibility」一节，改法是**改美术对比度**，不是加选项 [二手转述补丁] https://primagames.com/tips/halls-of-torment-update-2023-09-21-patch-notes
  - 亮紫色敌弹在亮背景上提高对比；
  - 红、蓝燃烧骷髅怪提高精灵对比。
- ③ 设置：
  - Update 01 加了「显示拾取范围」选项，并重排了选项菜单 [二手] https://consolepcgaming.com/exciting-changes-coming-to-halls-of-torments-experimental-branch
  - 特效透明度选项：查不到。
- ④ 掉落物：
  - 同一处经验宝石多了会合并 [玩家] https://steamcommunity.com/app/2218750/discussions/0/3807283698658520360
  - 有「贪婪之手」类道具，一次回收此前掉落的全部经验（出处同上）。
- ⑤ 查不到。
- ⑥ FullCleared 有一篇访谈，摘要里没有谈可读性 https://fullcleared.com/features/inside-halls-of-torment-an-interview-with-chasing-carrots/

### 1.4 20 Minutes Till Dawn（flanne）

- ① 查不到「玩家」的处理，但有反方向的做法：**给敌人和 Boss 加轮廓**。
  - 0.8.2「Visual Update」加了「显示敌人描边」选项 [维基] https://20minutestilldawn.wiki.gg/wiki/Versions
  - 手机版 2.1.220 加了可开关的 **Boss 轮廓线**，「让 Boss 更清楚」[二手] https://toucharcade.com/2022/11/14/20-minutes-till-dawn-yuki-character-unlock-update-boss-contour-option-ios-android-steam-iphone-ipad
- ② 同上，敌人描边是**可选**的。
- ③ 闪光、透明度、震屏选项：查不到。
- ④ 宝石兼作经验和局外货币；拾取范围靠升级。合并和上限：查不到 [维基]，出处同 ①。
- ⑤ 1.0 加了武器进化，Lv20 解锁；手机版每把武器 3 条进化路线 [维基/二手]，出处同 ①。进化后的外观：查不到。
- ⑥ 查不到。

### 1.5 HoloCure（Kay Yu）

- ① 查不到。
- ② 预警：
  - 冲锋怪在撞之前先冒两个大红感叹号，同时有音效 [维基] https://holocure.wiki.gg/wiki/Enemy
  - Boss 喷火前有锥形预警 [维基] https://holocure.wiki.gg/wiki/Area_15_(Bosses)
- ③ 图形设置里有「伤害数字」和「视觉特效」两个勾选项。早期 FAQ 建议关掉以提高帧率 [二手] https://samurai-gamers.com/holocure/frequently-asked-questions-faqs-4/
- ④ 掉落物（**很值得参考**）[维基] https://holocure.wiki.gg/wiki/EXP
  - 经验三角按价值**分 6 种颜色**：蓝 1–10、绿 11–19、黄 20–49、橙 50–99、紫 100–199、红 200 以上；
  - 小范围内同类掉落**合并成一个**，维基写明是「为了性能」；
  - 稀有的彩虹磁铁一次吸走全场经验。
- ⑤ 两把满级武器可以合成 Collab。可合成时，武器图标上会出现**闪光提示** [维基] https://holocure.wiki.gg/wiki/Collabs 。Super Collab 是再融合一件满级道具 https://holocure.wiki.gg/wiki/Super_Collab
- ⑥ MoguraVR 有开发者访谈，摘要里没有谈可读性 https://www.moguravr.com/holocure-developer-interviews/

### 1.6 Soulstone Survivors（Game Smithing）

同类里对可读性**做得最系统**的一款。
- ① 查不到角色描边；但 Visibility Mode 会把光标放大一倍，见 ②。
- ② 敌我区分：
  - 补丁说明：设置里开 **Visibility Mode** 后，**敌方投射物加黄色描边**，光标放大一倍。理由是后期玩家找不到光标和弹幕 [补丁，摘要] https://steamdb.info/patchnotes/10121256
  - 0.9.5.3：「几乎所有敌方投射物和敌方范围效果改用新配色，投射物有明确的形状和边框」[补丁，摘要]（搜索摘要提到，没核到具体页面）。
  - 评测：敌方范围攻击有「非常显眼的红圈和箭头」，能看出时机和大小 [二手] https://playday.one/2025/06/25/soulstone-survivors-review/
  - 反面教训：玩家抱怨某个后期模式里「全是红的」，看不清敌方攻击区，要求把敌方指示**画在最上层**，而不是压在下面 [玩家] https://steamcommunity.com/app/2066020/discussions/0/689741058328026888/
- ③ 设置与降级：
  - 图形设置里有 **Special Effects Visibility** 滑条，调的是**自己技能特效**的不透明度 [玩家/二手] https://steamcommunity.com/app/2066020/discussions/0/3591086730691827584
  - 滑条拉到最低时，「部分特效完全不画」，兼作自动降级（v0.9.028c，2022-11-15）[补丁，摘要] https://steamdb.info/patchnotes/9944985/
  - **敌方特效不受滑条影响**。被误伤时开发者当 bug 修，例如：
    - Gammuth 火球「又被滑条影响了」https://steamdb.info/patchnotes/12990006/
    - 1.3（2025-09-26）修了奥术爆炸、骷髅法师的攻击没有被滑条正确隐藏 https://steamdb.info/patchnotes/20144862/
    - 低特效档下，军团兵投石车蓝图看不见 [补丁，摘要]
  - 叠在一起的特效即使拉到 25%，看起来也接近不透明 [玩家]，出处同滑条那条。
  - 任务里提到的「自己 / 队友两条滑条」：**查不到出处**，不采用。
- ④ 查不到。
- ⑤ 查不到。
- ⑥ 查不到访谈，主要的一手资料是补丁说明。

### 1.7 Deep Rock Galactic: Survivor（Funday Games）

- ① 查不到。Update 01 承认敌人会被岩石挡住，说以后会修 [补丁，摘要] https://steamdb.info/patchnotes/13796277/
- ② 查不到。
- ③ 设置：
  - Update 03（2024-06）加了**镜头震动滑条**和**受伤红色暗角开关** [补丁转载] https://patchtracker.gg/deep-rock-galactic-survivor/update-03-masteries
  - 2025-12 的补丁优化了弹道拖尾的渲染 [补丁，摘要] https://steamdb.info/patchnotes/21189700/
- ④ 掉落物：
  - 红糖满血时捡不起来；
  - 「公司配发磁铁」在关底回收剩下 50% 的经验 [二手] https://www.treyexgaming.com/deep-rock-galactic-survivor-1-0-artifact-guide/
- ⑤ 武器在 6、12、18 级各选一个超频，可以改变行为和伤害类型 [二手] https://primagames.com/gaming/how-to-get-and-use-overclock-weapons-in-deep-rock-galactic-survivor
- ⑥ 查不到。

### 1.8 Spirit Hunters: Infinite Horde（Creature Cauldron）

- ① Patch 1（2022-05-28）**降低了龙卷风技能的不透明度**，因为它挡住了玩家和敌人 [补丁，摘要] https://steamdb.info/patchnotes/8828185/
- ② 查不到。
- ③ 伤害数字：玩家抱怨后期很乱，开发者回复说以后会改；后来改没改，查不到 [玩家/开发者回复] https://steamcommunity.com/app/1914580/discussions/0/3394038377484521334
- ④ 灵魂就是经验，有磁铁类升级 [二手] https://gamepretty.com/spirit-hunters-infinite-horde-basic-guide-to-new-hunter/
- ⑤ 14 个基础能力，每个 2 个变体 [商店页] https://www.xbox.com/mt-MT/games/store/spirit-hunters-infinite-horde/9N4KR2J8BKPZ
- ⑥ 查不到。

### 1.9 Noita（Nolla Games）

我们的观感底子，重点看它的**光和爆炸**是怎么做的。
- ① 查不到角色剪影、描边或置顶的说明。
- ② 查不到。
- ③ 有关震屏选项 [无障碍数据库] https://www.familygamingdatabase.com/accessibility/Noita 。粒子数量和闪光选项：查不到。
- ④ 不适用。
- ⑤ 光和爆炸（模组文档，属于一手资料）：
  - 爆炸配置有 `explosion_sprite_emissive`，爆炸精灵作为自发光画 [维基/官方模组文档] https://noita.wiki.gg/wiki/Documentation:_ConfigExplosion
  - 爆炸可以带一个**光源**：颜色可配，半径等于爆炸半径 × `light_radius_coeff`，有淡出时间（出处同上）。
  - 「Light」修饰让投射物飞行中照亮直径约 267 px 的圆 https://noita.wiki.gg/wiki/Light
  - Epilogue 更新日志：火焰偶尔会喷出装饰火星，`GameCreateSpriteForXFrames()` 新增 emissive 参数 https://nollagames.itch.io/noita/devlog/240051/noita-epilogue-update
  - 80.lv 访谈：爆炸之后，引擎检查被打到的像素，把「合适的」转成会塌落的沙，于是有了塌方 https://80.lv/articles/noita-a-game-based-on-falling-sand-simulation
  - **由此推断**（不是出处原话）：Noita 的「亮」不是全局泛光，而是**逐个精灵的自发光标记 + 逐次爆炸、有寿命的光源**。所以攻击是靠「这一下把地面照亮了，然后熄灭」被看见的。
- ⑥ GDC 2019 Petri Purho「Exploring the Tech and Design of Noita」https://gdcvault.com/play/1025695/Exploring-the-Tech-and-Design 。内容是落沙世界、刚体和涌现玩法，**没有专门谈可读性**。

### 1.10 Risk of Rain 2（Hopoo；后由 Gearbox 运营）

- ① 查不到。相关的一点：转 3D 的理由之一是**道具直接显示在角色模型上**，「即使所有道具同时显示也成立」，让玩家看到构筑在长大 [二手访谈] https://www.gamedeveloper.com/design/how-moving-from-2d-to-3d-shaped-the-design-of-i-risk-of-rain-2-i-
- ② 查不到开发者的说法。
- ③ 设置与改动：
  - 周年更新（2021-03）：
    - 加了「关闭屏幕扭曲」选项 [二手] https://www.gamerevolution.com/guides/677329-risk-of-rain-2-anniversary-update-patch-notes
    - 岩浆虫的震屏和后期亮度调低 [维基] https://riskofrain2.fandom.com/wiki/Anniversary_Update
    - 部分投射物「不那么不透明」[维基，未在官方说明里核到]
  - 2025-12-09（1.4.1）：更新了 bubble 的视觉，以「减少杂乱」[补丁，摘要] https://support.2k.com/hc/en-us/articles/47210814399123-Risk-of-Rain-2-Patch-Notes-December-9-2025
  - 2026-10-08：调低了多处震屏 [补丁，摘要] https://support.2k.com/hc/en-us/articles/56193476123795-Risk-of-Rain-2-Patch-Notes-October-8-2026
  - 某次早期更新去掉了「随层数变大的触发特效」[二手摘要，未证实] https://www.gamespot.com/articles/risk-of-rain-2-pc-patch-notes-artifacts-system-deb/1100-6475446/
  - 「减少闪光」「触发特效透明度」类选项：查不到。
- ④ 查不到。
- ⑤ 道具无限叠加，画面随之变密，有评论说「看不清是设计使然」。出处见上文 Wikipedia 与评测摘要，没有官方表态。
- ⑥ 查不到专谈可读性的。

### 1.11 Hades / Hades II（Supergiant）

- ① 查不到官方说明。美术分析提到：暗部用**色相偏移**而不是压暗，高光「很亮、有时近乎酸性」；3D 角色叠了一层黑色线稿 [二手] https://www.pointnthink.fr/en/the-art-of-hades-en/ 、 https://www.gamedeveloper.com/art/learn-how-supergiant-brought-i-hades-i-hand-painted-characters-to-life
- ② 敌人出招前**定住姿势并整体叠白**，魔法爆炸有「清楚的边界」标出范围 [学术论文图注] https://www.researchgate.net/figure/left-In-Hades-the-enemy-holds-a-pose-and-is-colored-with-a-white-overlay-to-signal_fig5_364535949 。「红橙预警对恩赐色是刻意分工」：**查不到出处**。
- ③ Hades II 有震屏开关和「亮光标」选项；开发者说震屏开关是因无障碍反馈而加的 [二手] https://kotaku.com/hades-2-early-access-god-mode-autofire-timer-1851461987
- ④、⑤ 查不到。
- ⑥ 有美术总监 Jen Zee 的访谈视频（Game Informer），没有专谈战斗可读性的演讲 https://gameinformer.com/exclusive-video/2024/07/05/supergiant-games-art-director-jen-zee-on-the-making-of-hades-ii 。有评测把可读性列为 Hades 的主要缺点 https://opencritic.com/kyotofu/review/10181/hades

### 1.12 补充：通用原则的出处

- **Riot《英雄联盟》VFX 风格指南（2017）**：特效四个目标里，第一个是玩法清晰度 https://nexus.leagueoflegends.com/en-us/2017/10/dev-leagues-vfx-style-guide/
- **Riot「VFX 更新幕后」**：可读性「永远优先于主题契合」；视觉和判定不一致的指示框要先修 https://www.leagueoflegends.com/en-us/news/dev/dev-behind-the-scenes-of-vfx-updates/
- **Riot「Clarity in League」（2021）**：从判定框、调色板、剪影三方面谈清晰度 https://riotgames.com/en/news/dev-clarity-in-league
- **GDC 2024「Attention Overload: Creating Readable VFX」**（Rocksteady，Hanno Hinkelbein）：动作、武器、天赋都要反馈时的视觉过载；核心观点是 VFX 要从设计早期就参与 https://gdcvault.com/play/1034360/Attention-Overload-Creating-Readable-VFX
- **GDC 2026「Controlled Chaos: 12 Principles of Design for VFX」**（Beyond-FX，Rachel Quitevis）https://schedule.gdconf.com/session/controlled-chaos-12-principles-of-design-for-vfx/914747
- **GDC VFX Bootcamp「Artistic Principles of VFX」** https://www.gdcvault.com/play/1024439/Visual-Effects-Bootcamp-Artistic-Principles
- **压低「别人的」特效有先例**：
  - Diablo IV 把其他玩家的死灵召唤物和部分陷阱对别人几乎画成透明 https://www.icy-veins.com/d4/news/has-disabling-other-players-effects-become-needed-for-diablo-4/
  - ESO 有分「玩家 / NPC」压低特效的滑条 https://forums.elderscrollsonline.com/en/discussion/697188
- GDC Vault 正文需要登录，以上只核到场次简介；明确写出「不透明度预算」规则的演讲：查不到。

---

## 2 对比表

「—」表示查不到。

| 游戏 | ① 角色可见 | ② 敌我分色 / 敌弹 | ③ 设置 / 降级 | ④ 掉落物 | ⑤ 成长加码 | ⑥ 出处 |
|---|---|---|---|---|---|---|
| Vampire Survivors | — | — | Flashing VFX、伤害数字开关；武器不透明度 [未证实] | 三色分档；约 400 颗上限转红宝石；吸尘器 | 进化换形、变大 | — |
| Brotato | — | **高亮敌弹**选项 | **我方投射物 / 爆炸不透明度**；先前直接降爆炸亮度 | 波末自动收获 | — | — |
| Halls of Torment | — | **改美术**提高敌弹 / 怪对比 | 显示拾取范围 | 宝石合并；全场回收 | — | 访谈（不涉可读性） |
| 20 Minutes Till Dawn | 反向：**敌人 / Boss 轮廓**可选 | 同左 | — | 拾取范围升级 | Lv20 进化 | — |
| HoloCure | — | 冲锋双感叹号、锥形预警 | 特效、伤害数字开关 | **6 色分档**、**合并**、彩虹磁铁 | Collab 合成，可合成时闪光提示 | — |
| Soulstone Survivors | 光标 ×2 | **敌弹黄描边（可选）**；敌方统一新配色 + 边框；红圈箭头预警 | **自己特效不透明度滑条**；最低档直接不画；**敌方特效豁免**，误伤当 bug 修 | — | — | 补丁说明 |
| DRG: Survivor | — | — | 震屏滑条、受伤暗角开关 | 关底磁铁回收 50% | 超频改行为 | — |
| Spirit Hunters | **降龙卷风不透明度**，不挡玩家 | — | — | 磁铁 | 能力变体 | 补丁说明 |
| Noita | — | — | 震屏 | — | — | **爆炸 = 自发光精灵 + 限时光源**；GDC 2019 |
| Risk of Rain 2 | 道具显示在模型上 | — | 屏幕扭曲开关、震屏；降岩浆虫亮度；bubble 减杂乱 | — | 道具叠加 | 转 3D 访谈 |
| Hades | 黑线稿；暗部色相偏移 | 出招**定姿叠白**；爆炸有清楚边界 | 震屏、亮光标 | — | — | Jen Zee 访谈 |
| Riot / GDC | — | 判定框与视觉一致；调色板；剪影 | — | — | — | VFX 指南；GDC 2024 / 2026 |

---

## 3 适用于我们的方案（8 个）

先对齐现状（integ-1105）。
- 已经做了的：
  - 敌弹和预警在顶层：`render/foe_top`（docs/226 §1）；
  - 队长被盖住时画剪影：`render/lead_sil`（226 §2）；
  - 拥挤降噪：`render/declutter` 3；
  - 粒子上限：`render/pfx_cap` 30；
  - 结晶两档亮度、远处合并：`gem_rest`，`gem_merge_n` 50；
  - 敌弹改青：`optical_col_ebullet_*`；
  - 队长特效提亮：`lead_emph` 1。
- 用户定过的约束：
  - 队友特效不降（docs/139 §10）；
  - 敌弹不加描边，嫌丑（139 §11.1）；
  - 不要逐个干员手绘帧条（本任务）。
- 红色的来源，代码里能看到：
  - 危险色洋红偏深红，即 #ff2667；
  - 黑潮开始缩圈后，危险色**偏移到正红**（`optical_col` 的 `horde_h`，1.0 = 正红）；
  - 精英有暖橙标识；
  - 溟痕已改成青调（139 §6.4），但黑潮圈外的压暗和圈边带仍跟着走。

下面每个方案都写清楚：参考了谁、怎么做、实现方式、工作量和风险。

### S1 红色只留给「马上要躲」（色彩分工）

- **参考**：
  - Soulstone 玩家抱怨「全是红的，看不清攻击区」；
  - Riot「可读性优先于主题」；
  - Halls of Torment 用改对比度修可见性。
- **做法**：
  - 全屏红只允许出现在**预警轮廓**和**即将命中的敌弹拖尾**上。
  - 黑潮改用「环境更暗、更冷、去饱和」表达压迫感，不再整屏偏红：
    - `horde_h` 不再偏到正红；
    - 黑潮圈外压暗只降明度。
  - 精英标识从红、橙改成**白色闪烁或体型 + 发光点**，不用红描边（光学层已有「精英多一处发光点、大一号」）。
  - 溟痕保持青调。
- **预期**：红色像素占屏大幅下降，红色重新等于「要躲」；我方暖色在暗冷背景上自然浮出。
- **实现**：全局参数，改 balance.json 的 render 段，必要处加一两个旋钮。**不动美术。**
- **工作量**：小（约半天），外加一轮对照录像。
- **风险**：
  - 黑潮「来了」的情绪会变弱，需要靠音乐、镜头一瞥和横幅补；
  - 精英改标识要重验精英辨识度。
- **量化**：用 late-game-diag 的「红像素占比」做前后对照（该分支 10c20cd8 已有这个量法）。

### S2 结晶退出暖金，并分档、合并、回收（掉落物让位）

- **参考**：
  - HoloCure 按价值分 6 色 + 合并 + 磁铁；
  - Vampire Survivors 三色分档 + 约 400 颗上限转大宝石；
  - Halls of Torment 合并；
  - Brotato 波末结算；
  - DRG: Survivor 关底磁铁。
- **做法**：
  1. **改色相**：低价值结晶不用暖金（`gem_style` 已有 2 淡青绿 / 3 宝蓝 / 5 翠绿 等候选）。
     - 青、蓝和敌弹 #33ceff 会撞色，紫和危险色会撞色，所以优先试 **5 翠绿**。
     - 暖金留给高价值档：少而亮，见到就是好东西。
  2. **静止时更暗**：`gem_rest` 的静止亮度再降一档，靠近或被吸起时才亮（机制已有，只调数）。
  3. **合并上限**：`gem_merge_n` 50 → 30 左右；超过约 200 颗时，新经验直接并进最近的大结晶（照 VS）。
  4. **事件回收**：黑潮开始、Boss 登场时自动吸回全场结晶（照 Brotato 和 DRG），把后期地面清空。
- **预期**：解决「暖金结晶撞我方金橙攻击」，后期地面的颗粒噪点明显减少。
- **实现**：①② 是全局参数；③④ 是少量逻辑（拾取和掉落）。
- **工作量**：①② 小；③④ 中，因为涉及经验节奏，要跑一次曲线验证。
- **风险**：
  - docs/242 §12.6 写的「经验结晶暖金」禁撞色要同步改；
  - 用户 10-29 嫌过白色结晶「不明显」，新色要在暗地面上实拍确认；
  - ④ 会稍微改变拾取节奏（属于数值）。

### S3 地面区域「只画边，靠照地显形」

- **参考**：
  - Hades 爆炸有清楚的边界；
  - Riot「视觉要和判定一致」；
  - Spirit Hunters 降低大范围技能的不透明度；
  - Noita 的光源照地。
- **做法**：
  - 地上大块半透明几何填充（我方技能场、光环、Boss 预警填充）把填充 alpha 压到接近 0。
  - 范围改由两样东西表达：
    - **边**：1–2 美术像素，我方用本人主色，敌方用危险色；
    - **区域内照地**：光学层地面光，只提亮，不铺色。
  - 我方区域要被注意时（生成那一下、到时前 0.5 秒），边才亮起来，其余时间低调。
- **预期**：去掉「满地半透明色块」；地面重新露出 Noita 式的材质和光；范围信息不丢。
- **实现**：全局。改通用区域绘制函数和预警填充的参数（`declutter` 的「填充减淡」已有雏形），各干员不用逐个改。
- **工作量**：中（1–2 天）。要清点哪些区域走通用画法、哪些是各人自画。
- **风险**：
  - 部分干员的技能存在感就是那块色场，例如凯尔希、流明的场，变淡后会觉得「没放」，需要配合 S5 的照地光；
  - 治疗场与伤害场要靠边的颜色区分。

### S4 明度分层：怪群与地面压低，干员和我方攻击保留全亮（拥挤时自动）

- **参考**：
  - Diablo IV、ESO 压低「不是你的」特效；
  - RoR2 降低岩浆虫的后期亮度；
  - Hades 暗部用色相偏移，不发灰。
  - 方向相反的参考：Soulstone 和 Brotato 降的是**自己的**特效。我们的用户要求我方不降，所以把这个思路**反过来用在怪和地面上**。
- **做法**：拥挤度高时，按拥挤度给以下几层乘一个明度 / 饱和系数（例如明度 ×0.75、饱和 ×0.8）：
  - 普通怪本体；
  - 地面纹理；
  - 溟痕；
  - 环境孢子。

  **以下不受影响**：
  - 敌弹和预警（已在顶层）；
  - 精英和 Boss；
  - 干员；
  - 我方特效。

  暗部按 Hades 的思路往冷色偏，不变灰（呼应 docs/139 用户嫌「显灰」）。
- **预期**：不碰我方一根线，攻击和小队的相对明度提高一档，等于「我方变亮」。这是唯一一个**不改我方任何东西**、却能直接回应「攻击不显眼」的方案。
- **实现**：全局，挂在 declutter 体系里，新增 `render/declutter_foe_dim` 一类的键。敌人绘制本来就过 look 调制（`op_unlit` 只管干员），加一个乘数即可。
- **工作量**：中（1 天 + 对照）。
- **风险**：
  - 怪暗了，近身的威胁也会变难认，所以**离队长一定半径内的怪不压**；
  - 和 `enemy_pop`（10-14 用户要求怪「祛雾」）方向相反，要用户确认可以接受「拥挤时才压」。

### S5 我方每次出手带一个「短命光源」照地（Noita 式加码）

- **参考**：
  - Noita 爆炸 = 自发光精灵 + 带半径、带淡出的光源；
  - 「Light」修饰让投射物飞行时照亮周围；
  - RoR2 让成长直接显示在角色身上；
  - VS 进化让攻击变大。
- **做法**：
  - 全局规则：我方攻击命中或爆点时，在光学层挂一个 **0.08–0.15 秒的点光**照亮地面；投射物飞行时带一个跟随的小光。
  - docs/242 §11.2 已经允许「首帧爆亮时挂一个 0.1 s 的 optical 点光，强度 ≤ 0.6」，这里把它推广成所有干员都走的公共层。
  - **成长加码不画新帧条**，只调三个参数：
    1. 光半径随范围属性走；
    2. 光强按精英化档位（E0 / E1 / E2）走；
    3. 碎屑或余烬的数量和重量随伤害档位走（`material_grains` 已有的有重量的颗粒）。
  - 光色用本人主色（`trail_col` 已有）。所以「哪束光是谁的」靠颜色就能分开，而且天然不是红色。
- **预期**：攻击被「它照亮了周围」看见，而不是靠细线。后期攻击越强，地面越亮、碎屑越多，加码是有物理感的，和 Noita 底子一致。
- **实现**：全局。在 vfx 的公共命中、出手入口加一次光源调用，各干员不用逐个改；只有少数自画命中的招式要补一个调用。
- **工作量**：中到大（2–3 天），主要花在光源预算和性能上。
- **风险**：
  - 光源一多，整屏亮度预算会被吃光，又回到「全屏发亮、什么都看不清」；
  - 必须配**全队光源上限**，例如同屏 24 个，按人数分额，超额丢最弱的，再加 `optical_glow_budget` 联动；
  - 要验证入门本 60 帧（docs/50）。

### S6 小队「脚下光池」常驻（队员可见性）

- **参考**：
  - Noita 的 Light 修饰（会照亮周围的东西）；
  - Soulstone 放大光标；
  - 20 Minutes Till Dawn 给关键单位加轮廓（我们用光代替描边）；
  - 我方已有的队长剪影（226 §2）。
- **做法**：每名干员脚下常驻一个小光池（光学层地面光，半径约 1.2 个身位），颜色用本人主色，队长更大更亮。
  - 干员本身仍然不吃灯（`op_unlit` 1 不变），只是**自己发光照地**。
  - 拥挤时光池不受 S4 压暗影响。
  - 可选：把 `lead_sil` 剪影扩到队员，只在队员被大面积覆盖时出现。
- **预期**：约 40 px 的灰暗小人，在暗冷的地面上各带一圈自己颜色的亮地，「我的队在哪」一眼可答。不加描边，也不放大精灵，保留像素密度。
- **实现**：全局。每个角色每帧一个光，挂在 character 的绘制或光学层。
- **工作量**：小到中（半天到 1 天）。
- **风险**：
  - 和 S5 共用光源预算；
  - 光池颜色不能落进危险色和结晶色（结晶色在 S2 里已经换掉，正好腾出位置）；
  - 和已有的跑动余烬（`mate_ember`）叠加，可能过热，需要一起调。

### S7 威胁独占一种「样式」（玩家可选的增强模式）

- **参考**：
  - Soulstone Visibility Mode（敌弹黄描边，可选）；
  - Brotato 高亮敌弹（可选）；
  - 20 Minutes Till Dawn 敌人和 Boss 轮廓（可选）；
  - Hades 出招叠白。
- **做法**：
  - 用户嫌描边丑，所以**缺省不开**，在设置里做成「威胁高亮」开关，开了以后：
    - 敌弹加一圈深色底 + 亮边；
    - 预警轮廓加粗；
    - 冲撞类敌人出招前整体叠白 2 帧。
  - 叠白那一条也可以考虑做成缺省：它不加描边、只在前摇时出现，属于「状态变化」，不是常驻装饰。
- **预期**：给后期看不清的玩家一条退路；不影响默认的观感。
- **实现**：全局开关。敌弹、预警的绘制已经集中在 foe_top 层，改一处即可。
- **工作量**：小（半天）。
- **风险**：几乎没有，只是多一个设置项；设置界面要跟 HUD 重设计（docs/222）对齐。

### S8 玩家可调的「我方特效强度」与闪光 / 震屏设置，带豁免名单

- **参考**：
  - Brotato 1.0.1.3 我方投射物和爆炸不透明度；
  - Soulstone 特效可见度滑条（最低档直接不画，敌方豁免，误伤当 bug 修）；
  - VS 的 Flashing VFX；
  - DRG: Survivor 震屏滑条；
  - RoR2 屏幕扭曲开关；
  - Hades II 震屏开关。
- **做法**：
  - 设置里加三项：
    - 「我方特效强度」：100% / 75% / 50% / 精简，只乘装饰层，核心层和判定形状不动；
    - 「闪光强度」：冲击帧、白闪封顶；
    - 「镜头震动」。
  - 写死一份**豁免名单**，任何档位都不降：
    - 敌弹；
    - 预警；
    - 治疗落点；
    - 召唤物出入场；
    - 队长剪影。
  - **缺省保持 100%**，符合用户「队友特效不降」的口径；这是给玩家自己选的。
- **预期**：极端后期或手机上，玩家可以自救；也是一个性能档位。
- **实现**：全局参数。`vfx.px_deco_k` 和 declutter 已有乘数接口，只需要接到设置。
- **工作量**：小到中（1 天，含设置界面）。
- **风险**：如果有人把它当成解决可读性的主手段，默认体验其实没改善。所以它只能和 S1–S6 配合，不能替代。

---

## 4 推荐组合与先后顺序

| 批 | 方案 | 理由 | 合计工作量 |
|---|---|---|---|
| **第一批** | S1 红色只留给威胁、S2 结晶退出暖金（先做 ①②）、S3 地面区域只画边 | 都是全局参数或通用绘制，不动美术、不动数值，直接对应用户点名的「红光太多」「结晶撞色」「几何色块」 | 约 2–3 天 |
| 量一次 | late-game-diag 的色彩与层级预算（红像素占比、各层色相 / 亮度排名）做前后对照，加上录像给用户看 | 先确认「我方攻击不显眼」有多少是被背景抢了 | 半天 |
| **第二批** | S4 拥挤时压低怪群和地面、S6 小队脚下光池 | 不改我方特效，却让小队和攻击相对浮出来；也是 S5 的前提（背景暗了，光才看得见） | 约 2 天 |
| **第三批** | S5 出手短命光源 + 成长参数化加码 | 收益最大、风险也最大（亮度预算和性能），放在背景已经清理干净之后 | 约 2–3 天 |
| 随时可插 | S7 威胁高亮开关、S8 特效强度、闪光和震屏设置 | 设置项，和 HUD 重设计一起排期 | 各约半天到 1 天 |

不推荐：
- 逐个干员重画特效帧条（pixelfx，用户已否决）；
- 缺省降低队友特效（用户 10-25 否决）；
- 缺省给敌弹加描边（用户 10-24 嫌丑，只做成 S7 的开关）；
- 放大干员精灵（会破坏 1 倍像素密度，docs/128）。

## 5 待用户定

1. S1：黑潮的压迫感改用「暗、冷、去饱和」表达，能不能接受不再整屏偏红？精英标识改白闪 + 发光点，还是保留暖橙但缩小面积？
2. S2：结晶新颜色从哪几个候选里试（推荐 5 翠绿）？黑潮或 Boss 时全场自动回收，算不算可以接受的数值改动？
3. S4：拥挤时压暗普通怪，和 10-14「怪物祛雾」方向相反，能不能接受「只在拥挤时、队长近身半径外」？
4. S8：设置里给不给「我方特效强度」？缺省 100%。

## 6 出处汇总

都已在 §1 各条后面列出。可信度标记见 §0。**写进约束文档之前，请在能访问 Steam / SteamDB / 维基的环境里逐条打开原页核一次措辞**，尤其是标了「摘要」和「未证实」的那些。
