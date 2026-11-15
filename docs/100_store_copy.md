# 100 · 商店页文案与改名候选（2026-10-14，文案；§2 itch 三语 11-15 重写，同日加韩语成四语）

> 用途：B 站 Toy 与 itch 的商店页文案；游戏改名候选。写法按 docs/76（简短、克制、信息密，不用「您」「体验」「全新」「旅程」这类宣传词）。
> 合规按 docs/99：B 站版不放站外链接、收款码、第三方登录；标题、封面不用他人商标；主标题不写「明日方舟」，原作只在声明里提。
> 下文暂用现名「方舟幸存者」，定了新名后整体替换 `《方舟幸存者》` 即可。

---

## 1. B 站 Toy 版（口语一点，无外链）

**标题**：方舟幸存者 · 深海割草
**一句话简介**（≤ 30 字）：带一支小队下潜，在海嗣潮里撑过 10 分钟。

**短介绍**（≤ 150 字）：
同人割草小游戏。你是罗德岛的博士，带着开局干员潜入海嗣盘踞的深海。技能会自动释放，你负责走位和冲刺：升级、招募干员、收集藏品，守住灯火，撑过 10 分钟，打倒最终 Boss。不同的抉择会走向四个结局。

**特色**
- 18 名干员，每人三个技能，精英化解锁新技能并改变普攻
- 上百件藏品，能凑出不同的流派
- 8 只 Boss，每只都有自己的破解方法：打碎核心、打断装填、点亮灯柱……
- 灯火、溟痕、黑潮缩圈：站在灯火照亮的范围里打，敌人更脆
- 三档难度，四个结局
- 键鼠、手柄、手机触屏都能玩；普攻可以改成手动

**操作**
- 电脑：WASD 移动，空格冲刺，Q / E 手动技能，Esc 暂停
- 手机：按住左半屏拖动移动，右下角冲刺键
- 手柄：左摇杆移动，Ⓑ / RB 冲刺，Ⓐ / Ⓨ 手动技能
- 设置里可以把普攻改成手动：左键 / J 攻击（手柄 Ⓧ / RT）

**同人声明**
本作是《明日方舟》的非官方同人作品，免费、非商业。角色、世界观、名称与集成战略「水月与深蓝之树」的设定均属于鹰角网络（Hypergryph），本作与鹰角网络无关。如有侵权请联系作者，将立即处理。

> 反馈与联系只写「私信 UP 主」，不写站外账号（docs/99：可以引导到自己的 B 站主页）。

---

## 2. itch 版（英 / 中 / 日 / 韩四语，可放链接；11-15 按当前版本重写）

> 内容以 11-15 的代码和数据为准（main 90ee887c7）：干员 20 名（`game/data/characters/`）、编队 3 人（`squad.gd REGULAR_MAX`，藏品可 +1）、三个技能全自动、Q 终结技（`core/play_keys.gd`）、连携随队长技能自动触发（11-05 起没有 E 键）、中期 Boss 6 只（`waves.json mid_pool`）、最终 Boss 4 只对应 4 个结局、一局 10 分钟、藏品 265 件、三档难度。数字变了要同步这里。
> 英文、日文、韩文为 AI 翻译（docs/276 §12 / §13 / §14），页面上写明。itch 包有中 / 英 / 日 / 韩四种界面语言；B 站 Toy 版只有中文。

**Title**：方舟幸存者 / Arknights Survivors（itch 页现用名；改名后整体替换）

### English

**Tagline**: Lead a squad of operators into the deep and hold out for ten minutes against the Seaborn tide.

**About**
A free, fan-made survivor-like set in the Integrated Strategies theme *Mizuki & Caerula Arbor*. You are the Doctor of Rhodes Island. Pick a leader, dive into a sea held by the Seaborn and keep your Light burning. All three skills of every operator fire on their own; you move, dash, and choose when the leader's Ultimate lands. Level up, recruit operators, collect relics, and defeat the final boss at 10:00. The tokens you gather along the way decide which of four endings you reach.

**Features**
- 20 operators. Three skills each, all automatic; promotion to Elite 1 and Elite 2 changes how they fight.
- Each leader has an Ultimate on Q. Teammates follow up with Link attacks whenever the leader casts a skill; bonded pairs get a combined attack.
- Squads of three (a relic can open a fourth slot), 265 relics and route events to build around.
- 6 mid-bosses and 4 final bosses, each with its own counterplay.
- Light, Nethersea Brand and Guiding Beacons: fight inside the lit area.
- 4 endings, 3 difficulty settings, Cognitive Shaping, headhunting and medals between runs.
- Keyboard & mouse, gamepad or touch. Runs in the browser.

**Controls**
- Keyboard: WASD move · Space dash · Q Ultimate (hold to aim, release to fire) · F command wheel · Esc pause (P in the browser) · hold left mouse to steer basic attacks
- Gamepad: left stick move · Ⓑ / RT dash · Ⓐ / RB Ultimate · right stick aim · LB command wheel · START pause
- Touch: drag on the left half to move · Dash, Ultimate and Command buttons on the right

**Languages**: Chinese (original), English, Japanese, Korean. The English, Japanese and Korean text is AI-translated from the Chinese.

**Disclaimer**
An unofficial, free, non-commercial fan work based on *Arknights*. Characters, world, names and the setting of the Integrated Strategies theme *Mizuki & Caerula Arbor* belong to Hypergryph. This project is not affiliated with Hypergryph. Contact the author for any rights concern and it will be handled immediately.

### 中文

**一句话**：带一支干员小队下潜，在海嗣潮里撑过 10 分钟。

**简介**
同人割草小游戏，背景是集成战略「水月与深蓝之树」。你是罗德岛的博士：选一名队长，潜入海嗣盘踞的深海，守住灯火。每名干员的三个技能都自动释放，你负责走位、冲刺，以及决定队长的终结技落在哪里。升级、招募干员、收集藏品，在 10:00 击败最终 Boss；路上拿到的信物决定走向四个结局中的哪一个。

**特色**
- 20 名干员，每人三个技能，全部自动释放；精英一、精英二改变战斗方式
- 每名队长有自己的终结技（Q）；队长放技能时队友自动连携，羁绊搭档另有合击
- 编队三人（藏品可再开一格），265 件藏品与路线事件，凑出不同流派
- 6 只中期 Boss、4 只最终 Boss，各有破解方法
- 灯火、溟痕、引航灯标：站在照亮的范围里打
- 4 个结局、3 档难度；局外有认知塑造、寻访、蚀刻章
- 键鼠、手柄、触屏都能玩，浏览器直接开

**操作**
- 键盘：WASD 移动 · 空格 冲刺 · Q 终结技（按住瞄准、松开释放）· F 指挥圆盘 · Esc 暂停（网页版也可按 P）· 按住左键引导普攻方向
- 手柄：左摇杆移动 · Ⓑ / RT 冲刺 · Ⓐ / RB 终结技 · 右摇杆瞄准 · LB 指挥圆盘 · START 暂停
- 触屏：左半屏拖动移动 · 右侧冲刺、终结技、指挥键

**语言**：中文（原文）、English、日本語、한국어。英文、日文与韩文为 AI 翻译。

**同人声明**
本作是《明日方舟》的非官方同人作品，免费、非商业。角色、世界观、名称与集成战略「水月与深蓝之树」的设定均属于鹰角网络（Hypergryph），本作与鹰角网络无关。如有侵权请联系作者，将立即处理。

### 日本語

**ひとこと**：オペレーター小隊を率いて深海へ。シーボーンの潮の中で10分間持ちこたえる。

**紹介**
統合戦略「ミヅキと紺碧の樹」を舞台にした、無料の二次創作サバイバーライクです。プレイヤーはロドスのドクター。リーダーを選び、シーボーンが巣くう深海へ潜り、灯火を守り抜きます。オペレーターのスキル3つはすべて自動発動。プレイヤーは移動とダッシュ、そしてリーダーの必殺技をどこへ撃つかを担当します。レベルアップ、オペレーターの招集、秘宝の収集を重ね、10:00に現れる最終ボスを倒してください。道中で集めた証によって、4つのエンディングのどれに辿り着くかが決まります。

**特徴**
- オペレーター20名。スキルは各3つ、すべて自動発動。昇進1・昇進2で戦い方が変わる
- リーダーごとに専用の必殺技（Q）。リーダーがスキルを使うと仲間が自動で連携、絆のある組み合わせには合体攻撃も
- 3人編成（秘宝で4枠目も）、秘宝265種とルートイベントでビルドを組む
- 中ボス6体・最終ボス4体、それぞれに攻略法あり
- 灯火・溟痕・導きの灯標：照らされた範囲で戦う
- エンディング4種、難易度3段階。探索の合間に認知形成・人材発掘・勲章
- キーボード＆マウス、ゲームパッド、タッチ操作に対応。ブラウザでそのまま遊べる

**操作**
- キーボード：WASD 移動 ・ Space ダッシュ ・ Q 必殺技（長押しで照準、離して発動）・ F 指揮サークル ・ Esc ポーズ（ブラウザ版は P も可）・ 左クリック長押しで通常攻撃の向きを指定
- ゲームパッド：左スティック 移動 ・ Ⓑ / RT ダッシュ ・ Ⓐ / RB 必殺技 ・ 右スティック 照準 ・ LB 指揮サークル ・ START ポーズ
- タッチ：画面左半分をドラッグで移動 ・ 右側にダッシュ／必殺技／指揮ボタン

**対応言語**：中国語（原文）、英語、日本語、韓国語。英語・日本語・韓国語のテキストは中国語からのAI翻訳です。

**二次創作に関する表記**
本作は『アークナイツ（明日方舟）』の非公式二次創作であり、無料・非営利で公開しています。キャラクター、世界観、名称、および統合戦略「ミヅキと紺碧の樹」の設定の権利はHypergryph（鷹角網絡）に帰属します。本作はHypergryphとは一切関係ありません。権利上の問題がございましたら作者までご連絡ください。速やかに対応いたします。

### 한국어

**한 줄 소개**: 오퍼레이터 소대를 이끌고 심해로. 시본의 물결 속에서 10분을 버텨라.

**소개**
통합 전략 '미즈키 & 카이룰라 아버'를 배경으로 한 무료 2차 창작 서바이버라이크 게임입니다. 당신은 로도스 아일랜드의 박사. 리더를 고르고, 시본이 도사린 심해로 잠수해 등불을 지켜 내세요. 오퍼레이터의 스킬 3개는 모두 자동으로 발동하며, 당신은 이동과 대시, 그리고 리더의 필살기를 어디에 떨어뜨릴지를 맡습니다. 레벨 업, 오퍼레이터 모집, 소장품 수집을 거듭해 10:00에 나타나는 최종 보스를 쓰러뜨리세요. 도중에 모은 증표에 따라 네 가지 엔딩 중 어디에 도달할지가 정해집니다.

**특징**
- 오퍼레이터 20명. 각자 스킬 3개, 모두 자동 발동. 정예화 1·정예화 2에서 싸우는 방식이 바뀝니다
- 리더마다 전용 필살기(Q). 리더가 스킬을 쓰면 동료가 자동으로 연계하고, 인연이 있는 조합은 합동 공격도 가능
- 3인 편성(소장품으로 4번째 칸 개방), 소장품 265종과 루트 이벤트로 빌드 구성
- 중간 보스 6종, 최종 보스 4종, 각각 공략법이 있습니다
- 등불·명흔·길잡이 등표: 빛이 닿는 범위 안에서 싸우세요
- 엔딩 4종, 난이도 3단계. 탐험 사이에는 인지 형성·헤드헌팅·훈장
- 키보드와 마우스, 게임패드, 터치 지원. 브라우저에서 바로 플레이

**조작**
- 키보드: WASD 이동 · Space 대시 · Q 필살기(누르고 있으면 조준, 떼면 발동) · F 지휘 원판 · Esc 일시정지(브라우저판은 P도 가능) · 왼쪽 클릭을 누르고 있으면 일반 공격 방향 지정
- 게임패드: 왼쪽 스틱 이동 · Ⓑ / RT 대시 · Ⓐ / RB 필살기 · 오른쪽 스틱 조준 · LB 지휘 원판 · START 일시정지
- 터치: 화면 왼쪽 절반을 드래그해 이동 · 오른쪽에 대시 / 필살기 / 지휘 버튼

**지원 언어**: 중국어(원문), 영어, 일본어, 한국어. 영어·일본어·한국어 텍스트는 중국어 원문을 AI로 번역한 것입니다.

**2차 창작 고지**
본 작품은 《명일방주(Arknights)》의 비공식 2차 창작물이며, 무료·비영리로 공개합니다. 캐릭터, 세계관, 명칭 및 통합 전략 '미즈키 & 카이룰라 아버'의 설정에 관한 권리는 Hypergryph(鹰角网络)에 있습니다. 본 작품은 Hypergryph와 아무런 관련이 없습니다. 권리 관련 문제가 있으시면 작자에게 연락해 주세요. 즉시 대응하겠습니다.

> itch 可以放小红书联系方式（菜月colafax（373145407））和致谢页里的第三方素材署名。
> 日文段落的用语与游戏内日文一致（必殺技 / 連携 / 秘宝 / 認知形成 / 導きの灯標，见 tools/l10n/translate_ja.py PROVISIONAL_JA）；「寻访」= 人材発掘（日服官方）、「蚀刻章」= 勲章，与 ui.csv 的 ja 列一致，改了要同步这里。
> 韩文段落的用语与游戏内韩文一致（필살기 / 연계 / 소장품 / 인지 형성 / 길잡이 등표 / 등불 / 명흔，见 tools/l10n/translate_ko.py PROVISIONAL_KO；后四条中 등불 / 명흔 / 인지 형성 / 소장품 是韩服官方）；「寻访」= 헤드헌팅（韩服官方）。

---

## 3. 改名候选

改名原因（协调人转用户）：「Survivors」撞品类，「方舟」擦边商标。下面按灯火 / 潮 / 深渊三条线给 10 个，撞名结果来自 2026-10-14 的网络搜索，只代表搜得到的范围。

| # | 中文名 | 英文名 | 理由 | 风险 |
|---|---|---|---|---|
| 1 | **灯火深潜** | LAMPLIGHT DESCENT | 两个词正好是本作的两个核心：灯火机制、深海下潜；字面直白，一眼知道在干什么 | 「深潜」是常见词，同类标题多；英文 Descent 类标题也多，但没搜到完全同名 |
| 2 | **沉潮录** | TIDEBOUND RECORDS | 「录」接近原作档案、作战记录的口吻；三个字好记 | 偏文学，搜索时不直观；和《沉渊归航》字面接近 |
| 3 | **潮下行** | BENEATH THE TIDE | 三个字，动作感强；「行」对应一次探索 | 和《Tides of Tomorrow》的中文名「潮行者」只差一个字 |
| 4 | 深蓝之下 | BELOW THE CAERULA | 直接呼应母题「深蓝之树」 | 借原作专有名词，擦边程度比「方舟」更高；和《深渊之下》（The Great Below）字形接近 |
| 5 | 守灯人 | LAMPKEEPER | 博士守着灯火、带队前进；角色感强 | Lamplighter / Lampkeeper 类英文名很常见，撞名概率高 |
| 6 | 残灯潜航 | LAST LIGHT DIVE | 「残灯」写出灯火会熄、要守住的压力 | 四个字略长；Last Light 英文名撞名多 |
| 7 | 灯下十分钟 | TEN MINUTES UNDER THE LAMP | 直接写出 10 分钟生存的玩法 | 容易被看成模仿《20 Minutes Till Dawn》 |
| 8 | 溟痕 | MIRE | 原作术语，独特、短 | 原作专有词，可能被视为借用 IP；单词 Mire 英文歧义（泥沼） |
| 9 | 潮灯 | TIDELAMP | 两个字，灯与潮两条线合一 | 太短，搜索时容易淹没；意义平 |
| 10 | 引航 | PILOT LIGHT | 呼应引航灯标、博士带队 | Pilot Light 是常用英文词（燃气长明火），搜索被淹没 |

**前三名**
1. **灯火深潜 / LAMPLIGHT DESCENT**：最直白，同时点出灯火和下潜两个核心，搜索时没有明显撞名，不碰原作专有词。
2. **沉潮录 / TIDEBOUND RECORDS**：最有原作「档案」的味道，适合同人身份；缺点是不直观，需要靠副标题补玩法（如「沉潮录 · 深海割草」）。
3. **潮下行 / BENEATH THE TIDE**：最短、最有动作感；要接受和「潮行者」相近的风险，正式用前建议再查一遍 B 站与 TapTap 同名。

> 不推荐 4、8：都借用了原作专有名词，正好违背这次改名「离商标远一点」的初衷。
