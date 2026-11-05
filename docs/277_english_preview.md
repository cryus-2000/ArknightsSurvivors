# 277 英文版对照样张（干员 + 怪物，20 条）

2026-11-05 第一批英文初稿的代表条目。全部条目在 `game/l10n/ops.csv`、`game/l10n/enemies.csv`（列：key / zh / en / 来源 / 备注）。方案与术语见 docs/276。

来源：**官方** = 国际服 en_US 原文；**暂定** = docs/276 §3.6 推荐词，用户可改；**模型** = Vertex Gemini 初稿，过了自动检查；**人改** = 复核时改过。

| 模块 | 官方 | 暂定 | 模型 | 人改 | 合计 |
|---|---|---|---|---|---|
| ops | 238 | 54 | 1498 | 147 | 1937 |
| enemies | 35 | 0 | 417 | 5 | 457 |

| # | 类别 | 中文 | English | 来源 | 备注 |
|---|---|---|---|---|---|
| 1 | 官方名：技能（改正了旧的 WAVEBREAKER） | 跃浪击 | Wave Strike | 官方 | skill_table.skchr_skadi_2 |
| 2 | 暂定名：拉普兰德「噤声」 | 噤声 | Hush | 暂定 | 暂定（docs/276 §3.6） |
| 3 | 技能说明（带变量） | {$s2_dur} 秒高速状态：挥伞间隔 ×{$s2_interval}，触手追击目标 +1 并附带 {$s2_bind} 秒束缚 | High-speed state for {$s2_dur}s: Umbrella Strike interval ×{$s2_interval}. Tentacle pursuit targets +1 and inflicts Bind for {$s2_bind}s. | 模型 |  |
| 4 | 天赋说明 | 附近有半血敌人时自身伤害 +{$talent_mult*100-100}%；每击杀一名普通敌人为队长回复 {$kill_heal*$k_kill*100}% 最大生命（精英 / Boss {$kill_heal*100}%；每秒有上限） | When there are enemies with less than half HP nearby, own damage +{$talent_mult*100-100}%. Defeating a normal enemy recovers {$kill_heal*$k_kill*100}% Max HP for the Leader (Elite / Boss {$kill_heal*100}%; capped per second). | 模型 |  |
| 5 | 普攻说明 | 每 {$cd} 秒向射程 {$range} 内敌群最密处射一枚重力弹：落点半径 {$aoe} 法术伤害，并把半径 {$pull_r} 内的敌人向落点拉拢 {$pull}（精英减半、重型 ×0.3，Boss 除外；「受到的击退」加成同样作用于拉拢距离） | Every {$cd}s, fires a Gravity Shot at the densest enemy cluster within {$range} range: deals Arts damage in a {$aoe} radius at the impact point, and pulls enemies within a {$pull_r} radius toward the impact point by {$pull} (halved on Elites, ×0.3 on heavy enemies, Bosses excepted; 'knockback taken' bonuses also apply to pull distance). | 模型 |  |
| 6 | 成长节点名 | 强迫性重复 | Repetition Compulsion | 模型 |  |
| 7 | 成长节点说明 | 触手追击同一名敌人，{$rep_window} 秒内第二次命中时，触手缠绕它：束缚 {$rep_bind} 秒（精英减半，Boss 除外），并再受一次 {$rep_mult*100}% 触手伤害 | When tentacles pursue the same enemy and hit a second time within {$rep_window}s, they entangle the target: inflicts Bind for {$rep_bind}s (halved on Elites, Bosses excepted) and deals another instance of {$rep_mult*100}% tentacle damage. | 模型 |  |
| 8 | 终结技说明 | 冲进落点一圈内接连斩出刀痕，同时斩开，隔半拍换个角度再斩一次，收刀回到原位 | Dashes into the target area and releases consecutive slashes, slashing outward simultaneously, then slashes again from a different angle after a short pause, before returning to her original position. | 模型 |  |
| 9 | 干员档案（首句换成官方招聘合同原文） | 「审判庭信使艾丽妮，为守护伊比利亚的海岸线而战。」<br>前伊比利亚审判官，大审判官达里奥的学生。幼时一场自然灾害席卷了她居住的小镇，她失去了所有家人，是达里奥把她从废墟下救了出来。「愚人号」事件后她辞去审判官一职，由凯尔希推荐，以审判庭信使的身份与罗德岛合作，为应对海洋的威胁做准备。她擅长迅捷的剑术，随身带着审判庭制式的提灯（一种法杖）与手炮。 | 'Inquisition Messenger Irene, fighting to protect Iberia's coastline.'<br>Former Iberian Inquisitor and student of High Inquisitor Dario. When a natural disaster swept through her town in her childhood, she lost all her family, and Dario saved her from the ruins. After the 'Stultifera Navis' incident, she resigned as an Inquisitor. Recommended by Kal'tsit, she collaborated with Rhodes Island as an Inquisition Messenger to prepare for the threat of the ocean. She excelled in swift swordsmanship and carried a standard Inquisition lantern (a type of staff) and a hand cannon. | 模型 | 首句招聘合同已换官方原文 character_table.char_4009_irene.itemUsage |
| 10 | 招募卡简介（梗，待定） | 这片大地的代言人（划掉） | The voice of this land (crossed out) | 人改 | 难翻，待用户定：梗在「（划掉）」，英文可用删除线或括号。候选2：Spokesperson for all of Terra ~~(not really)~~ |
| 11 | 招募卡简介（官方原句 + 玩家梗） | 罗德岛干员铃兰，九倍的温柔与坚强。她是罗德岛的光 | Suzuran, Rhodes Island Operator, has nine times the strength, and the fluffiness. She is the light of Rhodes Island. | 人改 | 难翻，待用户定：前句是官方 char_358_lisa.itemUsage 原文（官方把「温柔」译成 fluffiness，呼应九尾）；「她是罗德岛的光」是玩家梗，直译。候选2：... She is Rhodes Island's little sun. |
| 12 | 招募卡简介（梗，待定） | 我的天哪维什戴尔大人 | Oh my god, Lady Wiš'adel | 人改 | 难翻，待用户定：国服玩家梗，英文没有对应的固定说法。候选2：OMG it's Wiš'adel-sama |
| 13 | 招募卡简介（双声部排版） | 名为斯卡蒂的深海猎人//名为伊莎玛拉的海嗣<br>正停留此处<br>等待你的部署//渴盼你的呼唤 | The Abyssal Hunter named Skadi // The Seaborn named Ishar'mla<br>waits here<br>for your deployment // for your call | 人改 | 伊莎玛拉官方拼写 Ishar'mla（初稿写成 Ishar-mla）；保留 // 双声部排版。候选2：An Abyssal Hunter called Skadi // A Seaborn called Ishar'mla<br>lingers here<br>awaiting your orders // longing for your call |
| 14 | 敌人名（官方） | 骨海漂流体 | Bone Sea Drifter | 官方 | enemy_handbook_table.enemy_2021_syfish |
| 15 | 敌人档案 | 最常见的海嗣个体。它们成群地漂过海床，像被潮水推着的白骨，任何靠近的温热之物都会引来它们的撕咬。 | The most common Seaborn specimen. They drift across the seabed in swarms like white bones pushed by the tide; any warm object that approaches draws their bite. | 模型 |  |
| 16 | Boss 档案 | 「偏执泡影」。她曾是一名阿戈尔少女，吞下了海嗣的细胞。大群的祈望堵住了她的喉咙，她说不出话，只能被那股力量拖着，一点点变成自己最痛恨的模样。 | 'Paranoia Illusion'. She was once an Ægir girl who swallowed Seaborn cells. The wishes of We Many blocked her throat; unable to speak, she could only be dragged by that power, slowly turning into the very thing she hated most. | 模型 |  |
| 17 | Boss 图鉴机制行（含官方结局名） | 结局四「如星空般深蓝」的最终 Boss。学习阶段无敌，子代从场边缓慢靠近本体；吸收子代后发动分享。阐释阶段按幕成组连续出招，每组结束露出破绽：「潮汐坠落」「解读旋涡」「分享」「震撼」「护群触腕」「迁徙潮」「深渊涌流」，以及摆动的水流弹、子代共鸣、螺旋弹臂、停顿后转向的习得弹、卷回的回流弹。水流在子代来向留出通道；走在路上的子代会跟着放弹，吸收层数越多习得弹越多。迁徙潮横穿场地并留有通道，涌流形成向内收拢的环带。震撼与三幕的分享·全场可通过冲刺或站进点亮的灯柱光圈躲避，灯柱不挡别的弹。 | Final Boss of Ending 4 'Stella Caerula'. Invincible during the Learning phase; offspring slowly approach the main body from the edge of the field. Triggers Share after absorbing offspring. During the Elucidation phase, uses attacks in successive groups by act, revealing a Flaw at the end of each group: 'Tidal Fall', 'Deciphering Vortex', 'Share', 'Shock', 'Protective Tentacle', 'Migration Tide', and 'Abyssal Surge', as well as swaying water current projectiles, Offspring Resonance, Spiral Arm, Learned Shots that Halt before turning, and Backflow Shots that roll back. Water currents leave a path in the direction the offspring come from; offspring walking on the path will also fire projectiles. The more stacks absorbed, the more Learned Shots fired. Migration Tide crosses the field and leaves a path. Abyssal Surge forms an inward-converging ring. Shock and Act 3's 'Share · Global' can be dodged by dashing or standing inside the Beacon Ring of a lit Lamp Pillar. Lamp Pillars do not block other projectiles. | 模型 |  |
| 18 | Boss 出场副标题 | 最终 · 堂吉诃德 | Final · Don Quixote | 模型 |  |
| 19 | Boss 战横幅 | 伊祖米克进入「阐释」阶段！ | Izumik enters the 'Elucidation' phase! | 人改 | 横幅保留感叹号（原文有） |
| 20 | 精英图鉴机制行 | 精英。伪装成补给箱，受到攻击后现形。现形后尖叫 2.5 秒：周围 150 内累积神经损伤并吞噬灯火，期间照常追击、不啃咬；尖叫结束前击倒，源石锭 ×1.5。啃咬两连，第二口伤害 ×0.6。免疫眩晕、寒冷和封印；击败后掉落源石锭。 | Elite. Disguised as a supply box, revealing itself when attacked. Screams for 2.5s after revealing itself: accumulates Nervous Impairment within a 150 radius and consumes Light. Pursues normally but does not bite during this period; defeating it before the Scream ends yields Originium Ingot ×1.5. Bites twice, with the second bite dealing ×0.6 damage. Immune to Stun, Cold, and Silence; drops Originium Ingots upon defeat. | 模型 |  |

## 待用户定：难翻的招募卡简介（6 条）

| 干员 | 中文 | 推荐 | 候选与说明 |
|---|---|---|---|
| kaltsit | 这片大地的代言人（划掉） | The voice of this land (crossed out) | 难翻，待用户定：梗在「（划掉）」，英文可用删除线或括号。候选2：Spokesperson for all of Terra ~~(not really)~~ |
| logos | 女妖河谷年轻的「女主人」，罗德岛圆凳滑行赛组织创始人 | The young 'Mistress' of the Banshee Valley, and founder of Rhodes Island's stool-sliding races. | 难翻，待用户定：「女主人」是梗（逻各斯是男性），英文保留引号；「圆凳滑行赛」出处我没查到原作，按字面译。候选2：Young 'Lady' of the Banshee Valley; founder of the Rhodes Island Office Chair Racing League. |
| siege | “举起大锤，领着大伙，毫不畏惧地冲锋”，对她来说，这些一直都是理所当然的事情。 | 'Raise the hammer, lead the crew, charge without fear.' For her, that has always gone without saying. | 难翻，待用户定：引号里那句如果出自原作语音 / 档案，应换成官方英文，我没在 character_table 里找到出处。候选2：'Hammer up, gang behind me, charge without fear.' To her, it has always been the obvious thing to do. |
| skadi | 前阿戈尔传奇电工，能够以一己之力维护一整座城市的海底灯光阵列 | Former legendary Ægir electrician, able to maintain an entire city's undersea lighting array single-handedly. | 难翻，待用户定：「电工」是国服玩家梗，英文社区不一定懂；候选2 换成国际服玩家熟悉的说法：Former legendary Ægir maintenance worker. Keeps a whole city's undersea lights on all by herself. |
| suzuran | 罗德岛干员铃兰，九倍的温柔与坚强。她是罗德岛的光 | Suzuran, Rhodes Island Operator, has nine times the strength, and the fluffiness. She is the light of Rhodes Island. | 难翻，待用户定：前句是官方 char_358_lisa.itemUsage 原文（官方把「温柔」译成 fluffiness，呼应九尾）；「她是罗德岛的光」是玩家梗，直译。候选2：... She is Rhodes Island's little sun. |
| wisadel | 我的天哪维什戴尔大人 | Oh my god, Lady Wiš'adel | 难翻，待用户定：国服玩家梗，英文没有对应的固定说法。候选2：OMG it's Wiš'adel-sama |
