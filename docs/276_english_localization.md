# 276 英文版本地化方案（第一步：摸底 + 方案 + 术语表，待用户定）

2026-11-05 用户：「英语的版本也得准备了」。本文是第一步交付：文本摸底、框架选型、术语表、英文口吻、工作量与拆分。**未改任何代码**。第二步（搭框架、抽取）和第三步（翻译、界面适配、逐屏截图验收）等用户点头后再做。

原作数据只作参照：本次对照用的 ArknightsGameData（zh_CN / en_US 两份 excel 表）下载在 `build/l10n_ref/`（不进 git、不进包），术语表里的「来源」写的是表名与路径，可以直接复查。

---

## 1. 摸底：玩家可见文本有多少、在哪里

统计口径：含中文字符的字符串字面量。`.gd` 去掉注释和 print / push_warning / push_error（报错不翻）；`.json` 去掉 `_` 开头的字段、`_doc`、`src`、`relics.json` 的 `original`（原作原文），以及 boot_order / fx_pxplane / fx_recipes / pxp_* / build / ult_audio 这些只给工具或日志用的文件。数字是**估算上限**：脚本里仍有少量调试字符串、对内包专用文字。

### 1.1 总量

| 来源 | 字符串（出现次数） | 去重后 | 中文字数 |
|---|---|---|---|
| `game/scripts/**/*.gd` | 5 075 | 约 2 930 | 约 2.5 万 |
| `game/data/**/*.json` | 3 981 | 约 2 490 | 约 7.9 万（含标点） |
| **合计** | 约 9 000 | **约 5 000 条** | **约 10 万字** |

扣掉 `screens/ak_mock.gd`（审稿样张，449 条，不翻）和 `core/perf_report.gd`（对内帧率报告，54 条），脚本侧实际要翻约 2 400 条。中文 10 万字折成英文约 6–7 万词。

另有 763 条脚本字符串带 `%` 或 `{}` 格式化，是插值改写的重点（§3.4）。

### 1.2 脚本侧（按目录）

| 目录 | 字符串 | 文件数 | 主要文件（条数） |
|---|---|---|---|
| screens/ | 1 769 | 53 | stats_panel 148、choice_panel 88、run_stats_screen 82、title_op_pick 76、headhunt 74、hud_bars 52、settlement_screen 46、meta_tree_ui 44、shop_screen 43、initial_stats 43、command_wheel 35、hud_banners 34、difficulty_screen 32、hud 32 |
| 顶层 | 867 | 16 | gallery 242（图鉴机制行）、endings 143、data 109（难度、职业等常量）、relic_fx 80、title 73、settings_panel 72、game 57、ui 36 |
| run/ | 768 | 34 | run_stats 135、progression 65、skill_link 79、affects 52、combat 51、build_affinity 32、ult 30 |
| characters/ | 750 | 37 | ob_summon 86、ob_check 69、ob_vortex 54、ob_hw 51、character 47、doctor 40、seg_* 各 20–40（多是伤害来源名，作战记录里会显示） |
| enemies/ | 651 | 18 | izumik 95、knight_boss 95、paranoia_combos 89、ishar_combos 76、saint 66、bishop 40、path 37、final_attacks 41（招式名 / 横幅） |
| core/ | 162 | 7 | stat_defs 65（属性面板名）、perf_report 54（不翻） |
| render/ | 99 | 9 | vfx 39（飘字） |

### 1.3 数据侧（按文件）

| 文件 | 字符串 | 去重 | 内容 |
|---|---|---|---|
| characters/*.json（20 人） | 1 369 | 793 | 名字、职业、普攻 / 技能 / 天赋 / 成长节点 / 精英化 desc、图鉴 tags / desc / **intro（招募卡简介，用户亲写）**、banner、hint |
| relic_effects.json | 669 | 288 | 藏品效果 desc、稀有度、职业要求 |
| relics.json | 769 | 513 | 藏品名、adapt（改编效果）、稀有度、流派名 |
| lore.json | 137 | 88 | 干员 / 敌人档案 |
| ult_text.json | 167 | 130 | 终结技 / 连携名与说明 |
| waves.json + events_v2.json | 317 | 293 | 事件正文、选项、横幅 |
| guide.json + onboard.json | 102 | 101 | 指南、新手引导（含触屏版） |
| enemies.json | 126 | 106 | 敌人名、招式名、图鉴行 |
| meta_tree.json + meta_roots.json | 137 | 94 | 认知塑造节点 |
| credits.json | 23 | 23 | 制作名单 |
| cards.json / medals.json / synergy.json / practice_squads.json / balance.json 的 txt | 162 | 122 | 升级卡、勋章、连携、练习编队、少量提示 |

### 1.4 现有的有利条件

- **英文名已经有一半**：20 人的 `en`（大写英文名）、全部原作技能的 `en`（大写原作英文名，10-14 已按 en_US 填）、`data.gd` 的 `CLASS_EN`、选人 / 图鉴的英文装饰字，都已存在。
- **插值已经统一**：干员 / 藏品说明用 `{$键}` 占位（docs/61 §1.4、relic_db.fill_desc），翻译时占位原样保留，数字照常由代码填。
- **排版助手集中在 ui.gd**：`UI.text / ctext / fit / fit_line / text_fit / wrap_lines` 几乎是全部文字的出口，已有「先缩字号、再截断加…」的逻辑，英文变长时可以复用。
- 难翻的不是量，而是三处：脚本里拼句子的地方（`"对 " + name + " 造成"` 这类）、中文按字折行的假设（`UI.soft()` 插零宽空格）、字体子集。

---

## 2. 方案选型

### 2.1 推荐：Godot TranslationServer + CSV（单表，按模块分键）

| 选项 | 结论 |
|---|---|
| **CSV（推荐）** | Godot 4.4 原生导入 `.csv` → `.translation`。一行一键，列 `keys,zh_CN,en`，表格软件能直接开，适合逐条审稿、给用户标注。按模块拆成多份 CSV（`l10n/ui.csv`、`l10n/ops.csv`、`l10n/relics.csv` …），减少多会话合并冲突 |
| PO / gettext | 支持复数和上下文，但工具链更重；本作英文复数只在少数计数句（「1 kill / 3 kills」）里出现，用两条键解决即可。不选 |
| 自写 JSON 字典 | 不用引擎的 tr()，也拿不到 Label/Button 自动翻译。不选 |

**中文作为键还是用模块键？** 用**模块键**（`ui.settings.volume`、`op.mizuki.s2.desc`、`relic.1.name`）。中文原文一改，中文键就断；模块键稳定，中文列仍保留原文给审稿看。

### 2.2 键名规则

```
<模块>.<对象>.<字段>
ui.<屏>.<元素>            ui.settings.lang、ui.hud.lamp.dim、ui.settle.btn_retry
op.<id>.name / .s1.name / .s1.desc / .talent.name / .growth.<节点id>.desc / .intro / .gallery.desc
relic.<编号>.name / .desc / .adapt
enemy.<id>.name / .move.<招式> / .lore
boss.<id>.banner.<n>
event.<id>.text / .opt<n>.label / .opt<n>.desc
meta.<节点id>.name / .desc
guide.<页>.<n>、onboard.<步>、credits.<段>、card.<id>、medal.<id>
term.<词>                 共用术语（灯火、技力、队长……），用于拼接和自查
```

数据文件里的字段**不改结构**：抽取脚本按「文件 + 路径」生成键，运行时 `Data` 读 JSON 时按同一规则查表替换（`L.data("op.mizuki.s2.desc", 原文)`，查不到退回中文）。这样 json 继续是中文的单一事实来源，设计会话照常改中文。

### 2.3 抽取怎么做（第二步）

1. `tools/l10n_extract.py`：
   - json：按 §2.2 规则遍历玩家可见字段（白名单字段：name / desc / adapt / lore / text / label / hint / banner / intro / tags / brief / line / lines / more / sections / txt / trigger / kind / range …），写进对应模块 CSV；已有的英文列不覆盖，中文变了把该行标「待更新」。
   - gd：扫描含中文的字面量，生成「待改清单」（文件:行号 + 建议键）。脚本**手改**成 `tr("ui.xxx")`，不做全自动替换（拼接句、条件分支要人判断）。
2. 新增 `tools/l10n_check.py` 进快检：①CSV 键在代码 / 数据里都有引用；②英文列缺项数；③占位符一致（`{$键}`、`%d`、`{name}` 中英两列一一对应）；④脚本里新出现的未包 tr 的中文字面量（白名单：注释、报错、对内工具）。
3. 之后新写中文文字的流程：写代码时直接用键 + 中文缺省，英文列留空，`l10n_check` 报缺，由本地化会话补。

### 2.4 运行时切换语言

- 新增 autoload `L`（`scripts/core/l10n.gd`）：`L.t(key, fallback_zh)`、`L.data(...)`、`L.lang`、信号 `lang_changed`。内部就是 `TranslationServer.set_locale()` + `tr()`。
- **缺省按系统语言**：首次启动读 `OS.get_locale_language()`（网页版就是浏览器 `navigator.language`）：`zh` → 中文，其余 → 英文。B站 Toy 版固定缺省中文。
- **设置里加「语言 / Language」一行**（settings_panel.gd，放「显示」组第一行）：中文 / English。选项名永远用本语言写，不翻。存进现有 ConfigFile。
- 切换后：清 `UI._wrap_cache`、各屏 `queue_redraw()`；局内切换允许，但已生成的横幅 / 飘字不回改。文字是即时绘制（87 处 draw_string、141 处 get_string_size），下一帧就是新语言，不用重建节点。
- 语音照旧用原有中文语音，不做英文配音。

### 2.5 数字与变量插值

| 场景 | 写法 |
|---|---|
| 干员 / 藏品说明 | 保留现有 `{$键}` 占位，英文句子里照样写：`"Deals {$s1_mult}× damage for {$s2_dur}s"`。先翻译、后填数（fill_desc 不变） |
| 脚本里的简单数值 | 用 Godot 的 `tr("ui.settle.kills") % [n]`，CSV 里写 `%d kills` |
| 多个变量 | 用具名占位 `tr("ui.x").format({"name": n, "t": s})`，CSV 写 `{name} joined the squad`。英文语序和中文不同，**禁止**用 `a + "的" + b` 拼句子，一律改成整句模板 |
| 单复数 | 两条键：`.one` / `.other`，`L.plural(key, n)` 选 |
| 时间、百分比、乘号 | 两种语言同一套：`10:00`、`+25%`、`×1.5`、`3s` / `3 秒`（单位进模板，不进代码） |
| 中文全角标点 | 英文列一律半角；模板里的「」改成英文引号 `'…'`（原作 en_US 用单引号，如 `'Paranoia Illusion'`） |

### 2.6 英文变长后的防溢出

英文通常比中文宽 1.5–2.5 倍（同一说明，中文 20 字 ≈ 英文 40–55 个字母）。按优先级处理：

1. **换行规则分语言**：`UI.soft()` 的零宽空格只对中文做；英文走 TextParagraph 的单词断行（`BRK` 加 `BREAK_WORD_BOUND`），防孤字逻辑改成按「末行 ≤ 1 个词」判断。
2. **所有可能变长的文字都过 `fit / fit_line / text_fit`**：现在已经有「先缩字号再截断」，英文下把最小字号放宽 1 档（13 → 12）；截断时另给悬停 / 长按看全文。
3. **固定宽度的小标签**（按钮、chip、tab、HUD 状态）：英文写短名，CSV 单独一列 `en_short`（≤ 中文宽度的 1.6 倍），例如「技力回复」→ `SP Regen`。
4. **版式按语言微调**：少数版式（招募卡、结算标题、图鉴机制行）英文下让文本区多 1 行高度；用 `L.is_en()` 分支，只在截图验收发现问题的屏上做，不预先改。
5. **装饰英文**（选人 / 图鉴的 ghost_name、strip 的英文小字）：英文版下与正文重复，改为只显示一次（例：strip「VANGUARD 先锋」→ 英文版只写 `VANGUARD`）。
6. 验收：第三步每屏桌面 1280×720 + 手机 740×360 两种比例各截一张，加一个「最长文本」压力测试（把所有键临时填成英文最长版本 × 1.2）。

### 2.7 字体

现状：本作界面**不是像素字体**——正文 `ui.ttf` = Noto Sans CJK SC Bold 子集（4 096 字形），手机 `ui_phone.ttf` = Noto Sans SC Medium + Montserrat SemiBold，英文小标签和大数字用 Montserrat Bold / SemiBold（只含 ASCII 子集），叙事用 Noto Serif SC。全部 SIL OFL 1.1。

| 方案 | 字体 | 授权（可查证） | 结论 |
|---|---|---|---|
| **A（推荐）沿用现有字体族** | 英文正文用 **Noto Sans**（拉丁全集，与 ui.ttf 同族同字重，Google Fonts / github.com/notofonts/latin-greek-cyrillic），标题与短标签继续 Montserrat（github.com/JulietaUla/Montserrat） | 均 SIL OFL 1.1，可商用、可嵌入、可子集 | 画面风格不变，中英混排同一套度量。工作量只是重做子集：英文包把 Latin-1 + 常用标点（’ “ ” – — … é 等）补进子集，体积约 +60–120 KiB |
| B 换像素字体 | Fusion Pixel / Ark Pixel（github.com/TakWolf，OFL 1.1，含中英） 或 Silkscreen（Google Fonts，OFL 1.1，仅拉丁、只适合短标签） | OFL 1.1 | 会改动全游戏观感（docs/37 已定的水月风格界面用的是无衬线），需要用户另定；不建议为英文版单独换 |

英文 Noto Sans 比 CJK 字体的拉丁部分略窄，同字号英文能多放约 5% 字。字体子集脚本在第二步按「CSV 英文列实际用到的字符」生成，避免漏字（`ArknightsGameData` 里的 `Æ`（Ægir）、`š`（Wiš'adel）、`γ` 这几个要单独确认进子集）。

---

## 3. 术语表

规则：**原作有官方英文的，一律用国际服 en_US 原文**；来源列写 ArknightsGameData_YoStar（`en_US/gamedata/excel/`）的表名和键，`build/l10n_ref/` 有本地副本，`tools/l10n_glossary.py`（第二步加）会把全表重新对一遍。本作自创的词给 2–3 个候选，**加粗的是我的推荐**，需要用户定。

### 3.1 干员名（20 人，全部官方）

来源：`character_table.<id>.name`。

| 中文 | 英文 | id |
|---|---|---|
| 安洁莉娜 | Angelina | char_291_aglina |
| 能天使 | Exusiai | char_103_angel |
| 艾雅法拉 | Eyjafjalla | char_180_amgoat |
| 歌蕾蒂娅 | Gladiia | char_474_glady |
| 星熊 | Hoshiguma | char_136_hsguma |
| 艾丽妮 | Irene | char_4009_irene |
| 凯尔希 | Kal'tsit | char_003_kalts |
| 拉普兰德 | Lappland | char_140_whitew |
| 逻各斯 | Logos | char_4133_logos |
| 流明 | Lumen | char_4042_lumen |
| 水月 | Mizuki | char_437_mizuki |
| 塞雷娅 | Saria | char_202_demkni |
| 推进之王 | Siege | char_112_siege |
| 斯卡蒂 | Skadi | char_263_skadi |
| 浊心斯卡蒂 | Skadi the Corrupting Heart | char_1012_skadi2 |
| 归溟幽灵鲨 | Specter the Unchained | char_1023_ghost2 |
| 铃兰 | Suzuran | char_358_lisa |
| 德克萨斯 | Texas | char_102_texas |
| 乌尔比安 | Ulpianus | char_4145_ulpia |
| 维什戴尔 | Wiš'adel | char_1035_wisdel |

职业：先锋 Vanguard、近卫 Guard、重装 Defender、狙击 Sniper、术师 Caster、医疗 Medic、辅助 Supporter、特种 Specialist（`data.gd CLASS_EN` 已有，与官方一致）。

### 3.2 技能与天赋名

来源：技能 `skill_table.<skillId>.levels[0].name`，天赋 `character_table.<id>.talents[i].candidates[-1].name`。正文写首字母大写（官方原样），装饰大写字维持现有 `en`。

| 干员 | 技能 1 / 2 / 3（官方） | 天赋（官方） |
|---|---|---|
| 安洁莉娜 | Arcane Staff - Quick Charge Mode / Arcane Staff - Particle Mode / Arcane Staff - Anti-Gravity Mode | Accelerator Field |
| 能天使 | Charging Mode / Shooting Mode / Overloading Mode | Fast Cartridge |
| 艾雅法拉 | Duetto / Ignition / Volcano | Pyrobreath |
| 歌蕾蒂娅 | Waterless Parting of the Great Ocean / Waterless Grasp of the Raging Seas / Waterless Dance of the Shattered Maelstrom | Waves of Ægir |
| 星熊 | Warpath / Thorns / Saw of Strength | Tactical Armor |
| 艾丽妮 | Gust / Shattertide / Judgment | Flames of Castigation |
| 凯尔希 | Command: Structural Fortification / Command: Tactical Coordination / Command: Meltdown | 本作「指挥」非原作名 → 见 §3.6 |
| 拉普兰德 | Sundial / Wolf Spirit / 「噤声」 | Spiritual Destruction |
| 逻各斯 | Synecdoche / Perish / Extended Acuity | Lexical Evolution |
| 流明 | In Drizzle, Privation / In Downpour, Grace / This Lantern Undying | An Everyman's Wish |
| 水月 | Awaken / Prisoner's Dilemma / Moon in the Water | Countertransference |
| 塞雷娅 | First Aid / Medicine Dispensing / Calcification | 本作「坚守」 → §3.6 |
| 推进之王 | Charge γ / Aerial Hammer / Skull Breaker | 本作「鼓舞」 → §3.6；成长节点「万兽之王」= King of Beasts（原作天赋） |
| 斯卡蒂 | Swift Strike γ / **Wave Strike** / Tidal Elegy | Abyssal Predator |
| 浊心斯卡蒂 | Chant of Returning by Varied Paths / Wish of Burial Beyond the Light / The Tide Surges, The Tide Recedes | Predatory Habits |
| 归溟幽灵鲨 | The Skill to Survive / The Thirst to Survive / The Pressure to Survive | Embraced Self |
| 铃兰 | I'll Do My Best / Childhood Frolic / Foxfire Haze | 本作「祈愿」 → §3.6；成长节点「画地为牢」= Binding Circle（原作天赋） |
| 德克萨斯 | Sword Rain / Charge γ / Torrential Sword Rain（`skchr_texas2_3`，缄默德克萨斯的三技能） | Tactical Delivery |
| 乌尔比安 | Contact Must Be Made / Boundaries Must Be Kept / Paths Must Be Opened | Nourish the Blood |
| 维什戴尔 | Localized Liquidation / Saturated Vengeance / Explosive Dawn | Souvenir |

**和现有 `en` 字段对不上、要改的 3 处**（第二步顺手改）：
1. 斯卡蒂二技能「跃浪击」：现写 `WAVEBREAKER`，官方是 **Wave Strike**（`skchr_skadi_2`）。
2. 德克萨斯二技能：现写 `CHARGE ORDER γ`，官方是 **Charge γ**（`skcom_charge_cost[3]`，与推进之王同一条通用技能）。
3. 拉普兰德三技能「噤声」：拉普兰德原作只有两个技能，「噤声」不是她的技能名；en_US 里同名的只有集成战略 #1 藏品 `rogue_1_relic_n15`「“噤声”」= **'Silence'**。现有 `SILENCE` 英文可以保留，但要在 docs/91 附录 B 记一笔「本作自拟、与原作藏品同名」，**请用户确认**。

普攻名、成长节点名、精英化形态名是本作自拟（docs/76 §5），英文意译，第三步随文本一起翻，不进本表（例外：上面两条原作天赋名）。

### 3.3 敌人与 Boss（官方）

来源：`enemy_handbook_table.enemyData.<id>.name`。

| 中文 | 英文 | 中文 | 英文 |
|---|---|---|---|
| 骨海漂流体 | Bone Sea Drifter | 底海滑动者 | Deep Sea Slider |
| 固海凿石者 | Ocean Stonecutter | 伊祖米克的子代 | Izumik's Offspring |
| 注亡拟嗣 | Baleful Broodling | 脊海喷吐者 | Ridge Sea Spitter |
| 壳海狂奔者 | Shell Sea Runner | 浮海飘航者 | Floating Sea Drifter |
| 钵海收割者 | Basin Sea Reaper | 深溟奠基者 | Nethersea Founder |
| 深溟引痕者 | Nethersea Brandguider | 深溟巢涌者 | Nethersea Swarmcaller |
| 塑路者分形 | Pathshaper Fractal | 伊莎玛拉之泪 | Ishar'mla's Tears |
| 囊海爬行者 | Pocket Sea Crawler | 掠海漂移体 | Skimming Sea Drifter |
| 投嗣育母 | Retching Broodmother | 箱形恐鱼 | Chest Seaborn |
| 塑路者 | Pathshaper | 伊祖米克，生态泉源 | Izumik, Source of Ecology |
| 圣徒伊比利亚 | Saint Iberia | 圣徒卡门 | Saint Carmen |
| 接潮主教 | Tidelinked Bishop | 接潮蔑死体 | Tidelinked Archon |
| 接潮斥亡体 | Tidelinked Immortal | “偏执泡影” | 'Paranoia Illusion'（`enemy_2037_sygirl`；集成战略结局档案里另写过 'Ghastly Paranoia'，以图鉴名为准） |
| 伊莎玛拉，腐化之心 | Ishar'mla, Heart of Corruption | 最后的骑士 | The Last Knight |
| 鸭爵 | Duck Lord | | |

敌人招式名（骨刺扫击、酸蚀脉冲、交错潮环……共 32 个）是本作自拟，第三步意译。

### 3.4 藏品（集成战略 #2 原作名）

来源：`roguelike_topic_table.details.rogue_2.items.<id>.name`。265 件里 **262 件自动对上官方英文**（全部是 `rogue_2_*`，例：精选兽肉罐头 Featured Canned Meat、凉拌海草 Seaweed Salad、源石鸢尾花 Originium Iris）。对不上的 3 件是本作自加：**263 血魔的银杯、264 猎人的口粮、265 穿甲弹**，候选：

| 中文 | 候选 |
|---|---|
| 血魔的银杯 | **Vampire's Silver Chalice** / Vampire's Silver Cup（「血魔」官方英文是 Vampire：rogue_1_relic_r04「血魔的寝床」= Vampire's Bed；Sanguinarch 只指「血魔大君」） |
| 猎人的口粮 | **Hunter's Rations** / Hunter's Provisions |
| 穿甲弹 | **Armor-Piercing Rounds** / AP Rounds |

藏品的效果说明（adapt / desc）是本作改编，不能直接用原作 usage，第三步翻译。

### 3.5 机制词、地名、系统词（官方）

| 中文 | 英文 | 来源 |
|---|---|---|
| 水月与深蓝之树（集成战略 #2） | Mizuki & Caerula Arbor | roguelike_topic_table.topics.rogue_2.name |
| 深蓝之树 | Caerula Arbor | rogue_2_relic_curse_10 |
| 藏品 | Collectible | rogue_2 choices（「获得收藏品」Obtain Collectible） |
| 遭诅古物 | Cursed Curio | rogue_2 choice_ro2_11_1 |
| 源石锭 | Originium Ingot(s) | rogue_2_gold |
| 希望 | Hope | rogue_2_population |
| 灯火 | Light | rogue_2_san |
| 生命上限 | Max Life Points（属性面板 Max HP） | rogue_2_hpmax |
| 可携带干员数 / 编队上限 | Squad Size Limit | rogue_2_squad_capacity |
| 护盾 | Shield | gamedata_const ba.shield |
| 不期而遇 | Encounter | rogue_2 nodeTypeData.INCIDENT |
| 紧急作战 | Emergency Ops | BATTLE_ELITE |
| 险路恶敌 | Dreadful Foe | BATTLE_BOSS |
| 安全的角落 | Safe House | REST |
| 诡意行商 | Rogue Trader | BATTLE_SHOP |
| 得偿所愿 | Wish Fulfilled | WISH |
| 地区委托 / 郁金香的委托 | Regional Commissions / Tulip's Commission | MISSION、scene_ro2_task_enter |
| 认知塑造 | Cognitive Shaping | rogue_2 band unlockCondDesc |
| 认知塑造 11 节点 | Aggression / Survival Instincts / Appreciation of Life / Self-Preservation / Leadership Drive / Curiosity / Multi-Pass Information Processing / Hoarder / Negotiation / Danger Awareness / Precautionary Measures | customizeData.rogue_2.developments（官方带 I/II/III 后缀，本作按需要保留或去掉） |
| 招募券（按职业） | Recruitment Voucher（官方缩写 Vanguard Rec. Voucher 等） | rogue_1_recruit_ticket_* |
| 人事调度函 | HR Dispatch Letter | rogue_1_recruit_ticket_5star |
| 寻访 | Headhunting | character_table itemObtainApproach |
| 抗干扰指数 | Anti-Interference Index | rogue_3_vision（若用到） |
| 溟痕 | Nethersea Brand | character_table trap_061_creep |
| 罗德岛 | Rhodes Island | — |
| 伊比利亚 / 阿戈尔 | Iberia / Ægir | 多处（Saint Iberia、Waves of Ægir） |
| 审判庭 | Inquisition | char_4009_irene itemUsage |
| 深海猎人 | Abyssal Hunter | gamedata_const cc.g.abyssal |
| 海嗣 | Seaborn | token_10017_skadi2_dedant 等 |
| 博士 | Doctor | — |
| 精英化 / 精英一 / 精英二 | Promotion / Elite 1 / Elite 2（徽标 E1 / E2） | 官方通用写法 |
| 天赋 / 技能 / 技力 / 技力回复 | Talent / Skill / SP / SP Recovery | character_table 天赋 / 技能 / 「初始技力」= starting SP |
| 攻击力 / 防御力 / 法术抗性 / 攻击速度 / 生命 | ATK / DEF / RES / ASPD / HP | character_table potentialRanks、talents |
| 物理 / 法术 / 真实伤害 | Physical / Arts / True damage | enemy_handbook abilityList |
| 部署 / 再部署 / 阻挡 | Deploy / Redeployment / Block | skill_table、character_table |
| 眩晕 / 束缚 / 冻结 / 寒冷 / 沉睡 / 减速 / 脆弱 | Stun / Bind / Freeze / Cold / Sleep / Slow / Fragile | gamedata_const termDescriptionDict |
| 神经损伤 / 侵蚀损伤 / 元素损伤 / 凋亡损伤 / 灼燃损伤 | Nervous Impairment / Corrosion Damage / Elemental Injury / Necrosis Damage / Burn Damage | 同上 |
| 鼓舞 / 浮空 / 迷彩 / 隐匿 / 屏障 | Inspiration / Levitate / Camouflage / Invisible / Barrier | 同上 |

### 3.6 本作自创词（需用户定）

| 中文 | 说明 | 候选（加粗为推荐） |
|---|---|---|
| 队长 | 玩家操控的干员（docs/76 §5） | **Leader** / Captain / Squad Lead（官方集成战略有「Leader Squad」，Leader 最贴） |
| 灯油 | 掉落物，补灯火 | **Lamp Oil** / Oil |
| 通明 / 摇曳 / 暗淡 / 寂灭 | 灯火四档 | **Bright / Flickering / Dim / Out** · Radiant / Wavering / Faint / Extinguished |
| 照亮范围 | 灯火照到的半径 | **Light Radius** / Illumination |
| 照亮（状态） | 流明光弹 | **Illuminated** / Lit |
| 引航灯标（灯标） | 地图上的点灯目标 | **Guiding Beacon (Beacon)** / Pilot Lamp / Waymark |
| 光圈 | 灯标前的圈 | **Beacon Ring** / Light Circle |
| 光域 | 铃兰减速场 | **Foxfire Field** / Light Domain |
| 灯塔光圈 | 流明三技能区域 | **Lighthouse Zone** / Lantern Circle |
| 灯柱 | 伊祖米克战 | **Lamp Pillar** / Light Pillar |
| 黑潮 / 安全区 | 圈外 / 圈内 | **Black Tide / Safe Zone** · Dark Tide / Haven |
| 海嗣祭坛 / 抉择 | 祭坛事件 | **Seaborn Altar / Decision** · Seaborn Shrine / Choice |
| 终结技 | 队长 Q | **Ultimate** / Finisher / Final Order |
| 连携 | 自动连携 | **Link** / Combo / Chain |
| 随行 / 突击 / 部署 / 集火 | 指挥 v2 四指令 | **Follow / Assault / Deploy / Focus Fire** · Escort / Charge / Deploy / Focus |
| 生机细胞 | 局外成长货币 | **Vital Cells** / Life Cells / Bio Cells |
| 作战记录 | 局终统计（原作「作战记录」是经验道具 Battle Record，避开） | **Mission Report** / Combat Log / Op Record |
| 寻访凭证 | 本作抽卡券（原作寻访凭证无 en 对照项） | **Headhunting Permit**（国际服通用写法）/ Headhunting Ticket |
| 潮位 X · 昏灯 等难度 | 难度档 | 「潮位」**Tide Level** / Tide；「昏灯」**Dim Lamp**（现有 en 已是 DIM LAMP） |
| 藏品稀有度 基础 / 核心 / 稀有 / 升华 / 结局 | 本作分档 | **Basic / Core / Rare / Ascended / Ending** · Common / Core / Rare / Sublime |
| 7 个流派（近战扩域 / 多弹火力 / 召唤驻场 / 控场引爆 / 弱点收割 / 护盾反击 / 治疗转伤） | relics.json lane_names | **Melee Reach / Barrage / Summons / Control & Detonate / Weakpoint Harvest / Shield Counter / Heal to Harm** · 各给一个更短的 chip 版第三步定 |
| 升级卡三类 生存 / 机动 / 协同 | cards.json | **Survival / Mobility / Synergy** · Endure / Move / Teamwork |
| 凯尔希 / 塞雷娅 / 推进之王 / 铃兰的天赋（指挥 / 坚守 / 鼓舞 / 祈愿） | 本作天赋名，原作无同名天赋 | **Command / Steadfast / Rally / Prayer**（「鼓舞」不用官方状态词 Inspiration，免得和状态混） |
| 勋章名（深蓝之下、泡影散尽等 19 个） | 本作自拟 | 第三步逐条给候选 |

---

## 4. 英文口吻（docs/76 的英文版，第二步并入 docs/76 §9）

目标：读起来像国际服的终端与档案——**短、冷静、信息密**，和中文版同一套约束，只是换成英文的写法。

| 类别 | 英文写法 | 例 |
|---|---|---|
| 界面、横幅、提示 | 终端口吻，祈使句或短陈述，不用感叹号。横幅「事件 —— 指示」保留为 `Event — Instruction` | `Seaborn Altar 'Decision I' has appeared — approach it to decide` |
| 技能 / 天赋 / 藏品效果 | 官方技能描述的句法：主语可省，现在时，数值在前，条件在后，例外用 `(Bosses excepted)` 或 `(not on Bosses)` 二选一，全篇统一 | `When the Leader takes more than 10% Max HP in one hit, nearby enemies are Stunned for 3s (not on Bosses)` |
| 状态词 | 官方关键词首字母大写：Stun、Bind、Freeze、Fragile、Nervous Impairment、Corrosion Damage | — |
| 档案（lore） | 人事档案腔，第三人称、过去时；**引言用 en_US `character_table.itemUsage`**（招聘合同，即 docs/76 §4.1 用的那句的官方英文），一字不改；正文只转述官方英文档案（`handbook_info_table` en_US）里有的事 | Irene：`Inquisition Messenger Irene, fighting to protect Iberia's coastline.` |
| 敌人档案 | 现场观察记录，短句，停在一个画面上；敌人名与官方图鉴一致 | — |
| 结局、事件 | 行动记录，一两句；集成战略原作事件 / 结局有官方英文的，标题与选项用官方（`choiceScenes` / `endbook`） | `Tulip's Commission` |
| 商人台词 | 口语、简短，可以有角色味 | — |
| 第二人称 | `you` 指博士 / 玩家；不用 `Your Excellency`、`Commander` | — |

英文禁用写法（对应 docs/76 §3）：
- 宣传腔：`epic`、`ultimate power`、`unleash`、`embark on a journey`、`adventure`（一局 = `run`；正文叫 `operation` 或 `run` 二选一，**推荐 run**，界面短标签可用 `this run`）。
- 空洞程度词：`massive`、`powerful`、`a bit`、`greatly` → 写数字。
- 段尾感悟、口号、排比、反问铺垫（`It's not X, it's Y`）。
- 叙事里堆破折号（em dash 只用于横幅格式）。
- 性别中立：泛指干员用 `the Operator` / `they`；具体某人用官方代词。
- 美式拼写（Armor、Color、Defense），与国际服一致；数字用阿拉伯数字，时间 `10s`、`10:00`，乘号 `×`。

---

## 5. 招募卡简介（用户亲写，20 条）

`characters/*.json` 的 `gallery.intro`，含梗，按记忆「不按 docs/76 改」。翻译时保留原意和梗，**每条给直译 + 意译两版，难翻的标出来让用户定**，不自己替换笑点。第三步单独出一张对照表（docs/276 附录），不和其他文字混在一起审。

---

## 6. 工作量与拆分

按「第二步 / 第三步」排，单位是一个会话的工作日（含自查，不含等用户审）。

| 包 | 内容 | 估时 | 依赖 | 可并行 |
|---|---|---|---|---|
| F 框架 | autoload `L`、TranslationServer 接入、设置语言行、系统语言缺省、UI 折行分语言、fit 系列英文参数、字体子集脚本、`l10n_check` 进快检 | 1–1.5 天 | — | 先做，其余都依赖它的键规则 |
| X1 数据抽取 | `l10n_extract.py` 处理全部 json → CSV；Data 读取接 `L.data` | 0.5–1 天 | F 的键规则 | 与 X2 并行 |
| X2 脚本改写 | 2 400 条 gd 字面量改 tr()，拼句改模板；按目录分 3 份：screens / 顶层+core+render / run+characters+enemies | 2–3 天（3 个会话并行约 1 天） | F | 三份互不碰文件，可并行；**但会和正在改这些文件的特效 / Boss / HUD 会话冲突**，建议每份小步合入 |
| G 术语定稿 | 用户定 §3.6；`l10n_glossary.py` 全表比对生成 `l10n/terms.csv` | 0.5 天 | 用户定 | 与 F 并行 |
| T 翻译 | 约 5 000 条 / 6–7 万词。分包：①界面 + HUD + 设置 + 引导 ②干员 20 人 ③藏品 265 件 ④事件 + 结局 + 档案 ⑤敌人 / Boss / 招式 / 勋章 / 制作名单 | 每包 0.5–1 天，共 3–4 天 | G、X1/X2 生成 CSV | 5 包可并行（各自一份 CSV） |
| U 界面适配 | 英文下逐屏截图（GCP，本机最多 1 个 Godot），修溢出、短名、版式分支 | 1.5–2 天 | T 至少完成①② | 截图批跑走 GCP，修版式串行（同改 ui.gd） |
| V 验收 | 全屏双比例截图表、最长文本压力测试、占位符 / 缺键检查、网页包体复核（字体子集） | 0.5 天 | U | — |

合计约 8–11 个会话日；并行后墙钟约 4–5 天。

**风险**
1. 脚本改写和其他会话并行改同一批文件（screens/*、bosses/*），冲突概率高 → X2 按目录小步合入；新代码从第二步起直接写键。
2. 中文文案还在频繁改（数值调整会改 desc）→ CSV 带中文原文列 + `l10n_check` 报「中文已变、英文待更新」，不要求冻结中文。
3. 字体子集漏字 → 子集由 CSV 实际字符生成，快检里比对。
4. 网页包体：英文 CSV 约 0.5 MiB（.translation 二进制更小），字体 +0.1 MiB，在预算内（docs 记忆：现 43.96 MiB）。

---

## 7. 待用户定

1. 方案：TranslationServer + CSV + 模块键（§2.1–2.2）。
2. 缺省语言按系统语言，B站 Toy 固定中文（§2.4）。
3. 字体：沿用 Noto Sans + Montserrat（方案 A），不换像素字体（§2.7）。
4. §3.6 自创词候选（尤其：队长 = Leader、终结技 = Ultimate、连携 = Link、一局 = run、灯火四档名）。
5. §3.2 拉普兰德「噤声」与原作藏品同名，是否保留 `Silence`。
6. 拆分与并行（§6）：第二步开 1 个框架会话，框架合入后再开 3 个脚本改写 + 5 个翻译会话。
