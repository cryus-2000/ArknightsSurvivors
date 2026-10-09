# 33 · 打包发布版本

> 2026-09-26。给朋友 / 测试者发可直接运行的 Windows 版本。

## 一条命令

发布（对外 + 对内 + 网页，同一提交，逐个验证）：

```bash
python tools/release_all.py --ref <冻结提交>
```

`tools/release_all.py`（2026-09-30）串行做：出对外包 → `verify_encrypted_game.py` 验证 → 出对内包（`--ea`）→ 验证 →
出对外网页版 → `verify_web_build.py` 验证 → 出对内网页版（`export_web.py --ea`）→ 验证，
任一步失败就中止。产物统一收进 `build/release/final_<提交>/`：两个 zip、`web/`、`web_internal/`、汇总 `release_<提交>.json`（zip 的路径 / 大小 / sha256、
验证报告、存档目录、是否全部解锁、网页最大单文件）、各份验证报告与各次启动日志，以及对内包验证过的解压目录 `internal/`。
两个 Windows 包必须串行：导出与验证共用 `build/_export/`，验证读的是刚导出的那份打包源码。验证报告与日志按 audience 分开命名
（`encrypted_game_verification_<public|internal>_<提交>.json`、`web_verification_<public|internal>_<提交>.json`），同一提交的各份不会互相覆盖。
`--only public|internal|web|web_internal` 只出其中一份（其余不动，汇总并进同一个 `release_<提交>.json`）；`--no-web` 两个网页版都不出。

**网页版的 audience**（2026-10-01）：`export_web.py` 和 Windows 包一样往打包副本的 `data/build.json` 写 `commit / built / audience / encrypted=false / platform=web`；
`--ea` 出对内网页版（`audience = internal`、`channel = EA`）：Boss 演练开、启动即全部解锁（只在内存），与对内 Windows 包同一套 `settings.gd` 判断；不带 `--ea` 为对外网页版。
网页存档在浏览器 IndexedDB，按网站源（协议 + 域名 + 端口）隔离——**对内网页版必须放在与对外版不同的域名 / 端口下**，否则两版共用一份存档。
`tools/verify_web_build.py` 把分片拼回 `index.pck`，用 4.7.2 release 诊断模板（`encrypted_release.diagnostic_verifier`；普通 release 模板关了 `--main-pack`）在临时用户目录里加载跑探针：
`build.json` 的 audience / commit / platform、发布版开发参数屏蔽、全部解锁与演练入口和 audience 一致；对外包新存档进度为空，对内包写一次存档后文件里进度仍为空；单文件 ≤ 25 MB。

**一键启动对内测试版**（1.1.1）：仓库根目录 `启动对内测试版.bat`（进 git），双击即运行 `build/release/final_*/internal/` 里最新的一份
（按目录修改时间）；找不到就提示先跑 `python tools/release_all.py --ref main --only internal`。解压目录在 `build/` 下，不进 git。

只出一个包：

```bash
python tools/export_build.py
```

输出 `build/release/方舟幸存者_Public_Encrypted_<日期>_<提交>.zip`，解压后双击「开始游戏.bat」即可。

- 只打包**已提交**的内容（`git archive HEAD`）：其他会话在工作区里没提交的改动不会混进去。要打包新改动，先提交。
- `--ref <提交或分支>` 打指定版本；`--no-zip` 只生成目录（`build/_export/方舟幸存者/`）。

## 包的结构

默认对外包使用正式 PCK 资源与目录加密，脚本、配置、音频、美术全部封装；玩家不需要密码。默认导出缺少专用模板或密钥就中止，不回退成明文包。

```
方舟幸存者/
  开始游戏.bat
  说明.txt
  release_manifest.json
  game/ArknightsSurvivors.exe
  game/ArknightsSurvivors.pck
```

`--ea` 生成 `Internal_EA_Encrypted` 内测包；`--unencrypted` 只生成本地 `Diagnostic` 诊断包，不可作为对外发布包。构建信息显式记录 audience 和 encrypted。

## 一次性准备：加密导出模板

使用与编辑器一致的 Godot 4.7.2 源码和私有 AES 密钥编译 Windows release 模板。执行 `python tools/prepare_encrypted_template.py`，完成后执行 `python tools/verify_encrypted_template.py` 验证正确模板能启动、普通模板不能读取加密 PCK。操作细节见 [加密交接](encrypted_release_20260928.md)。

源码、编译工具链、模板和密钥存放在当前用户 `.codex/private/ArknightsSurvivors`，不进入 Git 或发布包。加密增加直接提取资源的难度，不代表无法逆向。换机器时必须安全保管或重新生成密钥并重编模板，不能只复制普通导出模板。

通过环境变量 `GODOT` 指定本机匹配的 Godot 编辑器路径。导出前运行项目检查，导出后检查加密标志、包内容、首次启动与实际资源读取。

## 版权与授权

包里的特效帧条是从第三方素材加工后的游戏资源（按各自许可可用于游戏发布），原始素材包（`art/third_party/`）不随包分发。致谢在游戏内「致谢」页。本作为非商业同人。

## 发布检查清单（每次发给玩家前逐条过，2026-09-26 起）

1. **名字**：`project.godot` 的 `config/name` =「方舟幸存者」（窗口标题、网页 `<title>`）；Windows 预设 `application/product_name` = Arknights Survivors；压缩包 / 文件夹 / 说明.txt 首行 =「方舟幸存者」（`export_build.py` 的 `NAME` / `README`）。
2. **存档目录固定**：`project.godot` 开 `config/use_custom_user_dir=true`、`config/custom_user_dir_name="ArknightsSurvivors"`，与显示名解耦，以后改名不再换目录。Windows 存档在 `%APPDATA%\ArknightsSurvivors`（实测 `OS.get_user_data_dir()`）；网页版存 IndexedDB（按网站域名隔离，与目录名无关）。发布说明写一句：此前版本的设置 / 存档在旧目录，更新后会恢复默认一次。
3. **初始状态**：发布版必须是图鉴未解锁、难度重置。用 release 模板导出；`tools/check_release.py`（玩法系统；`export_build.py` / `export_web.py` 导出前自动对打包源码跑，不过就中止）；用全新的浏览器配置 / 全新的 Windows 用户目录实测首次打开是未解锁状态。
4. **无数据上传 / 导出入口**（EA 小范围试玩阶段，用户 2026-09-26 定）：发布版里不得有任何网络上报，也不得有数据导出按钮。
5. **包体**：Windows 包不带审稿拼图（`SKIP_WORDS`）；网页包由 `tools/export_web.py` 分片，脚本检查单文件 ≤25 MB（docs/22）。
6. **不擅自发布**：上传 / 发链接前由用户确认。


## 双版本发布约定（2026-09-27，用户确认）

以后同一提交的 release 分为两个独立的包，包名与说明.txt 必须标明用途：

| 项目 | 对外版（Public） | 对内测试版（Internal） |
| --- | --- | --- |
| 初始进度 | 新存档保持正常未解锁状态，按游戏规则解锁 | 保留测试功能，不把测试解锁状态带到对外包 |
| Boss 演练 | 不显示入口，运行入口也必须拒绝进入 | 保留 Boss、形态、主控和成长选择，便于检查 |
| 常规玩法 | 正常成长、图鉴及难度解锁流程 | 与对外版使用同一套战斗、美术与数值 |
| 包名 | 包含 Public / 对外版 | 包含 Internal / 内测版 |
| 存档 | 正常玩家存档 | 与对外版隔离，演练不得污染正式进度 |

“未解锁”指首次启动的默认进度，不是每次启动清空玩家已有存档。对内版启动即「全部解锁」（1.1.1，用户 09-30 改）：难度三档、图鉴、结局线全开，与调试版同一套 `Cfg._apply_unlock_all`，只在内存、不写入存档（存档里仍是真实进度），标题右上角显示「测试版 · 已全部解锁（不写入存档）」；对外版恒不解锁。`check_release.py` 静态断言对外分支、`verify_encrypted_game.py` 在打包后实测（对内：`unlock_all` 为真、图鉴全开、写一次存档后文件里进度仍为空；对外：`unlock_all` 为假、图鉴只开干员页）。

EA 是开发阶段标记，不等于内测权限。不能仅凭 EA 标记向对外包开放 Boss 演练。构建信息应显式区分 Public / Internal；导出器、主页可见性和演练入口校验统一使用该标记。

交付前分别检查：两个包对应同一提交；全新存档启动；对外版无 Boss 演练入口且不能绕过进入；对内版能进入和退出演练；内测进度不会影响对外存档。未完成这些检查时，不得把已有单一 EA 包称为已符合双版本约定。

当前章节记录发布要求；现有 --ea 参数本身不能证明已经生成上述两个版本。落实构建区分后，应在交接中列出两个包的路径与验证结果。

**落实情况（2026-09-30，架构 / 部署）**：
- 演练入口按 `build.json` 的 `audience == "internal"` 放开（`settings.gd` `Cfg.can_boss_trial()`；主页入口、演练设置窗、`run/boss_trial.gd` 开局都走它）。原来按 `channel == "EA"` 判断，与本节「EA 标记不等于内测权限」不符。调试版（编辑器 / 源码运行）仍一律开放。
- 对内包存档目录改为 `%APPDATA%\ArknightsSurvivors_Internal`（`export_build.py` 只改打包副本的 `project.godot`），对外包仍是 `%APPDATA%\ArknightsSurvivors`。同一台机器两个包都装时，对内包的正常游玩不会解锁对外包的图鉴 / 难度；对内包说明.txt 写明。
- 对内包一次性迁移（`settings.gd` `_migrate_internal_save`）：对内包启动时，`_Internal` 目录还没有 `settings.cfg`、旧目录 `ArknightsSurvivors` 有，就复制过来（不移动、不删旧的，`_Internal` 已有存档不覆盖），标准输出记一行「[Cfg] 对内包存档迁移」。已经在玩 1.0 内测包的人换新包后进度不丢。对外包 / 调试版不迁移。
- `verify_encrypted_game.py` 另起隔离的 APPDATA 放一份旧目录存档启动打包游戏：对内包必须复制成功、旧存档原样、日志有那一行，`_Internal` 已有存档时不被覆盖；对外包不得建 `_Internal` 目录。
- 本地对局记录（docs/40，2026-10-10）：对内包写 `%APPDATA%\ArknightsSurvivors_Internal\runs\runs.jsonl`（`Cfg.runs_log_enabled()`），标题页脚与设置页有「测试版：本地记录对局摘要（不上传）」提示和「打开记录文件夹」按钮，`说明.txt` 写明；对外包恒不写。`check_release.py` 第 6 项静态断言，`verify_encrypted_game.py` 实测 `runs_log_audience`。
- `verify_encrypted_game.py` 在加密包里实测：全新存档（图鉴 / 藏品 / 结局为空、难度 0）、发布版屏蔽开发参数、`can_boss_trial()` 与 audience 一致、存档目录与 audience 一致、对外包图鉴只有干员页开放、普通模板读不了加密 PCK、zip 与验证过的目录逐文件一致。


### 对外版范围澄清（2026-09-27）

对外版始终使用最新游戏内容，不是回退版本或删减玩法版本。区别只在图鉴初始解锁状态、关闭 Boss 演练，以及一结局以外路线按正常条件解锁。所有干员、怪物、Boss 行为、动画、美术、属性特效、弹幕、数值、商店、成长、倍速及其他已完成修复均与同提交的最新版保持一致。不删除其他结局的内容，只保持其初始未解锁状态。

9b2161a 的 EA 与 Public 包由同一提交构建；文件列表相同，外置美术资源完全一致。Public 不启用 EA 演练权限，初始进度已经用全新存档验证。

### 图鉴最终标准

对外新存档：干员图鉴全部开放（包括动作与技能演示）；敌人、精英、Boss、道具、藏品、结局图鉴全部初始未解锁。敌人和场景 / 掉落物在正式冒险中发现后收录，藏品获得、结局达成后收录。演练与图鉴演示不写入遭遇进度。其他游戏内容与最新提交一致；Boss 演练关闭，非一结局路线遵循正常解锁条件。


## 网页部署：阿里云 OSS + CDN（2026-10-01 骨架，未接通）

`tools/deploy_web.py`：把 `build/release/final_<提交>/web/`（对外）和 `web_internal/`（对内）传到阿里云 OSS，再刷新 CDN。
**缺省只做 dry-run**（列出对象、响应头、要刷新的地址，不连阿里云）；地域、域名由用户定了之后再接通，真上传要用户确认发布。

```bash
python tools/deploy_web.py --ref <提交>                               # dry-run
python tools/deploy_web.py --ref <提交> --apply --confirm <提交>        # 真上传（用户确认后）
```

- **工具选型：官方 Python SDK**（`alibabacloud-oss-v2` + `alibabacloud-cdn20180510`，`--apply` 时才导入）。不选 ossutil：要逐个对象设 `Content-Type` / `Cache-Control`、上传后逐个 HEAD 核对大小，SDK 一个脚本就能做完，也不用另装 exe；OSS 走 V4 签名。
- **两个源隔离存档**：网页存档在浏览器 IndexedDB，按网站源（协议 + 域名 + 端口）隔离。所以对外、对内必须是**两个不同的 CDN 域名**（可以是同一主域名下的两个子域名）；Bucket 可以共用，前缀要不同，也可以分两个 Bucket。脚本检查两边域名相同就拒绝。
- **对内包不会传错地方**：每个目标只接受 `release_all.py` 出的、`web_verification_<audience>_<提交>.json` 验证通过且 audience 与目标一致的那份。`--apply` 时缺报告或对不上直接拒绝，dry-run 只警告。
- **缓存与布局**（网页包文件名不带内容哈希，所以按提交号分目录）：

  | 对象 | Cache-Control | 说明 |
  | --- | --- | --- |
  | `<前缀>/index.html` | `no-cache` | 部署时在 `<head>` 后插入 `<base href="v/<提交>/">`，页面里的相对地址（index.js、引擎取的 index.pck / index.wasm、加载器的分片）都落到版本目录 |
  | `<前缀>/version.json` | `no-cache` | 提交号、audience、部署时间 |
  | `<前缀>/v/<提交>/*` | `public, max-age=31536000, immutable` | 其余文件；新版本是新路径，旧版本留着可以回滚（只要把 index.html 换回去） |

- **压缩**：分片 `index.pck.NN.gz` / `index.wasm.NN.gz` 本身已经是 gzip，按 `application/octet-stream` 原样存，不设 `Content-Encoding`；加载器按 1f8b 魔数自己解压，CDN 若再压缩或解压也兼容。html / js / json / txt 在 CDN 控制台开「智能压缩」（gzip + brotli），按类型生效。
- **CDN 刷新**：上传后刷新 `<域名>/<前缀>/`（目录）、`index.html`、`version.json`；版本目录是新路径，不用刷新。
- **配置**：全部走环境变量，或者写进仓库根目录的 `.deploy.env`（已在 `.gitignore`，模板是 `.deploy.env.example`）。包括 `OSS_ACCESS_KEY_ID / OSS_ACCESS_KEY_SECRET`、`DEPLOY_REGION`，以及 `DEPLOY_PUBLIC_*` / `DEPLOY_INTERNAL_*` 各自的 `BUCKET / PREFIX / DOMAIN`。AccessKey 用 RAM 子账号，只给这两个 Bucket 写权限和 CDN 刷新权限；脚本不打印、不写日志。
- **待用户决定**：地域；两个域名（是否备案、HTTPS 证书）；对内网页版要不要加访问限制（CDN URL 鉴权或 Referer 白名单，否则拿到地址就能玩全解锁版）；旧版本目录保留多久（以后可以加 OSS 生命周期规则自动清理）。
- **本地布局实测（2026-10-01，5844334）**：`--stage build/deploy_stage` 按 OSS 布局落到本地，用静态服务在内置浏览器打开 `/public/index.html` 与 `/internal/index.html`：所有请求（index.js、wasm / pck 分片、图片）都落到 `v/5844334/` 下，两版都进到标题画面；对外版菜单没有「Boss 演练」，对内版有，右上角显示「测试版 · 已全部解锁（不写入存档）」。
- **还没实测**：`--apply` 这条路径（SDK 调用写好了，没连过阿里云）；接通后先对一个测试 Bucket 跑一遍，再确认 304 / 缓存头是否符合预期。加载器取分片时带 `cache: 'no-cache'`，版本目录长缓存后每片仍会发一次条件请求，CDN 回 304，开销很小，后续可以去掉。

## itch.io（2026-10-01 预备，未上传）

**只发对外版**：Windows 加密包推到 `<ITCH_TARGET>:windows`，网页版推到 `<ITCH_TARGET>:html5`。对内版（全部解锁、演练开）不上 itch，脚本只认 audience = public 且验证通过的产物。

```bash
python tools/release_all.py --ref <提交> --only public          # 对外 Windows 包（加密）
python tools/release_all.py --ref <提交> --only web             # 对外网页版（含 verify_web_build）
python tools/deploy_itch.py --ref <提交>                        # dry-run：生成 itch 网页 zip，打印 butler 命令（不上传）
python tools/deploy_itch.py --ref <提交> --apply --confirm <提交>  # 真推（用户确认发布后）
```

- **itch 网页 zip**：`final_<提交>/方舟幸存者_itch_html5_<提交>.zip`，把 `web/` 的内容直接放在 zip 根目录（`index.html` 在根、没有外层文件夹）。脚本会检查 itch 的限制：最多 1000 个文件、单文件 ≤ 200 MB。gz 分片按「存储」放进 zip，不再二次压缩。
- **不需要 SharedArrayBuffer**：Web 导出预设是单线程模板（`variant/thread_support=false`、`ensure_cross_origin_isolation_headers=false`），不依赖 SharedArrayBuffer，也不需要 COOP / COEP 头。所以 itch 页面的「SharedArrayBuffer support」**不用勾**；勾了也能运行。2026-10-01 用 48ce675c 实测：把 itch zip 解压后，用 `tools/serve_web.py` 在内置浏览器里打开，普通托管和 `--coi`（带 COOP / COEP，`crossOriginIsolated = true`）两种都能进到主菜单（对外版：没有 Boss 演练，没有测试版角标），控制台无错误。
- **itch 页面设置**：见下面「itch 页面设置清单」（2026-10-01 用户定：itch 版必须支持移动端，「Mobile friendly」要勾）。
- **配置**：`BUTLER_API_KEY`（itch → Settings → API keys）和 `ITCH_TARGET`（`<用户名>/<游戏名>`）只放环境变量或仓库根目录的 `.deploy.env`（不进 git，模板见 `.deploy.env.example`）。密钥只传给 butler 进程，不打印。缺 butler / 密钥 / 目标时只能 dry-run；`--apply` 必须带 `--confirm <提交>`，并且要先经用户确认发布。
- **本地验证网页包**：`python tools/serve_web.py --dir <网页包目录> [--port 8794] [--coi]`，只监听 127.0.0.1。

### itch 页面设置清单（上传前逐项勾）

| 设置 | 选什么 | 说明 |
|---|---|---|
| Kind of project | HTML | 网页 zip 标「This file will be played in the browser」；Windows 包另作为可下载文件（`:windows` 频道） |
| Embed options → Viewport dimensions | 1280 × 720 | 桌面页面里嵌入的大小；游戏是 `canvas_items` + `expand`，别的尺寸也能铺满，不会出滚动条 |
| Mobile friendly | **勾** | 用户要求；itch 在手机上会改成全屏启动 |
| Orientation（Mobile friendly 下面） | Landscape | 游戏只按横屏设计；竖屏时页面自己会盖「请将手机横过来」提示 |
| Fullscreen button | 勾 | 桌面嵌入时给玩家一个全屏按钮 |
| Automatically start on page load | **不勾** | 保持「点一下再开始」：这一下同时算用户手势，浏览器才放出声音；自动开始时有的浏览器会静音（itch 文档也这么提醒），而且会让只是路过页面的人白下 35 MB |
| Enable scrollbars | 不勾 | 画面按窗口缩放，不需要滚动 |
| SharedArrayBuffer support | 不勾 | 单线程导出，不需要（见上） |
| 嵌入方式 | 「Embed in page」 | 也可以选「Click to launch in fullscreen」；手机上勾了 Mobile friendly 都是全屏启动 |

itch 的上传限制：zip 内最多 1000 个文件、单文件 ≤ 200 MB、解压后总共 ≤ 500 MB。48ce675c 的网页 zip 远低于这些（`deploy_itch.py` 会检查前两项）。

### 移动端（2026-10-01 用 final_48ce675c 的 itch 网页 zip 实测）

**怎么测的**：把 itch zip 解压后用 `tools/serve_web.py` 托管，在内置浏览器里用移动端模拟（Android Chrome UA + 触摸点）。模拟只在宽度 < 768 时生效，所以横屏用 740×360（812×375 不算手机）。内置浏览器面板被挡住时没有动画帧，测试时给页面注入了一个 `requestAnimationFrame` 替身；测试页面只放在本地，不进包。

| 检查项 | 结果 |
|---|---|
| 竖屏 375×812 | 盖住全屏的「请将手机横过来」提示，没有滚动条 |
| 横屏 740×360 进主菜单 | 能进，控制台无错误；画布铺满，没有滚动条 |
| 开场可以跳过 | 点一下屏幕就跳过 |
| 触屏操作 | 左半屏浮动摇杆能走、冲刺按钮能用（能看到冷却）、暂停 / 属性按钮在；升级卡片点了能选；底部提示换成了触屏版 |
| 技能按钮 | 只有带手动技能的干员才出现（测的是水月，没有手动技能，所以没有这个按钮，符合设计） |
| 首次触摸解锁声音 | **内置浏览器不拦自动播放，测不出来，要真机验证**（Android Chrome 与 iPhone Safari 各一台）。Godot 在第一次用户输入时恢复 AudioContext；itch 那边保持「点一下再开始」就多一道保险 |

**画质默认值（任务第 4 项）**：已经满足，不用改。`settings.gd` 的 `_guess_quality()` 在触摸屏、`web_android`、`web_ios` 时返回 low；网页版默认关掉泛光、水面滤镜、法线贴图，触屏再关景深；触屏设备界面整体放大 1.15。只是默认值，玩家仍可在设置里改。

**导出预设（Web）检查**：`html/canvas_resize_policy=2`（画布跟着窗口走，手机旋转、itch 全屏都对）；`html/focus_canvas_on_start=true`（键盘玩家不用先点一下画布）；`variant/thread_support=false`（单线程，不需要 SharedArrayBuffer，iOS 也能跑）；`html/experimental_virtual_keyboard=false`（游戏里没有文字输入）；`progressive_web_app/enabled=false`；`vram_texture_compression/for_mobile=false` 不影响：项目里 82 张导入贴图都是无损（`compress/mode=0`），没有用到 VRAM 压缩格式。`head_include` 里的手机脚本：竖屏盖提示；首次触摸时尝试全屏 + 锁定横屏（Android Chrome 能成，iPhone 没有元素全屏，失败会被吞掉，只靠提示）。

**内存与加载（估算，没上真机量）**：
- 下载量约 35 MiB：pck 的 gz 分片 25.7 MiB（解开 27.5 MiB）+ wasm 的 gz 分片 9.6 MiB（解开 37.7 MiB）。
- 加载器（`tools/web/loader.js`）逐片下载、逐片解 gzip，再拼成一整块交给引擎。拼接时解开的分片和整块同时在内存里，所以 JS 这一侧短时间要 2–3 倍原始大小，pck + wasm 合计**峰值约 170 MiB**；交给引擎后这些缓冲由垃圾回收释放。
- 引擎这一侧：wasm 编译后的机器码；pck 在引擎的虚拟文件系统里再存一份（27.5 MiB）；711 张 PNG 全部解码成 RGBA 约 109 MiB（再上传到 GPU）。桌面浏览器里看到稳定后的 JS 堆约 107 MB。
- 合起来，标签页峰值大约在几百 MB 量级。新款手机的浏览器标签页一般能用到 1 GB 以上，问题不大；2–3 GB 内存的老 iPhone / 低端安卓可能在加载时被系统杀掉标签页（表现是页面自己刷新或白屏），要真机看。
- **结论：现在不开渐进加载，也不改压缩方式**。分片已经 gzip 过，itch 静态托管就能用（解压在加载器里做，不依赖服务器的 Content-Encoding）。Godot 网页版不支持一边下载 pck 一边进游戏；真要渐进，得把资源拆成多个资源包、进游戏后再按需下载并 `load_resource_pack`，改动大，35 MB 不值得。如果真机上加载时内存不够，先做两件小事：加载器把分片直接写进预先分配好的整块（省掉一份拷贝，JS 峰值降到约 1.5 倍）；贴图按需加载而不是开局全解码。

**iOS Safari 的坑**（上线前用真机过一遍）：
- **声音**：AudioContext 必须在用户手势里启动；Godot 在第一次触摸时恢复，开场前那一下点击就够。手机侧边的**静音开关打开时网页声音全没**（Web Audio 走「铃声」通道），这是系统行为，不是 bug；客服口径要准备。切到后台再回来，声音偶尔不恢复，再点一下屏幕即可。
- **全屏**：iPhone 上的 Safari 不支持对页面元素全屏（只有视频能全屏），`requestFullscreen` 不存在；也不能锁定方向。所以 iPhone 只能靠 itch 的全屏启动 + 我们的「请横屏」提示；地址栏和底部工具栏会占一点高度，横屏时 Safari 一般会自动收起。iPad 支持元素全屏。「添加到主屏幕」能去掉浏览器边框，但不是必须。
- **内存**：iOS 对单个标签页的内存限制比安卓严，超了直接重载页面，没有报错。上面的估算在新机上够用，老机型（iPhone 8 / X 这一代，2–3 GB 内存）是风险点。
- **WebGL 2**：Godot 4 网页版（兼容渲染器）需要 WebGL 2，iOS 15 及以上才有；更老的系统进不去。
- **帧率**：低电量模式下 Safari 把动画帧限制在 30 帧；部分 iPhone 的高刷屏在 Safari 里也只给 60 帧。游戏逻辑按帧时间走，30 帧能玩，只是不流畅。
- **触摸手势**：网页模板给画布设了 `touch-action: none`，视口是 `user-scalable=no`，双击缩放、双指缩放、长按选字在画布上都不会触发（iOS 会无视 `user-scalable=no`，靠的是 `touch-action`）。从屏幕左边缘右滑「返回上一页」在 Safari 里拦不住，玩家贴着左边缘拖摇杆可能退出页面（itch 全屏启动时影响小一些）。

**真机还要补的**（技术侧在内置浏览器里做不到的）：首次触摸出声；iPhone Safari 能否加载完成、加载时的内存；Android Chrome 首次触摸后全屏 + 锁横屏；长时间（10 分钟以上）帧率与发热。

**真机怎么连（2026-10-01 协调人定）**：Godot 网页版启动前要求「安全上下文」（`index.js` 的 `getMissingFeatures`），只认 HTTPS 或 localhost。手机用 `http://<电脑局域网 IP>` 打开会直接报「Secure Context」缺失，进不了游戏；而且 `serve_web.py` 只监听 127.0.0.1，手机本来也连不上。所以：
- **Android**：手机开 USB 调试并连上电脑，电脑装好 Android platform-tools，先跑 `adb reverse tcp:8794 tcp:8794`，再跑 `python tools/serve_web.py --dir <网页包目录>`，然后手机 Chrome 打开 `http://localhost:8794`。走 localhost 算安全上下文，脚本不用改。
- **iPhone**：上传到 itch 的草稿页（Draft，只有自己能看），itch 自带 HTTPS，顺便把 itch 的 iframe / 全屏 / Mobile friendly 一起测了。上传要经用户确认。
- 不走的路：给 `serve_web.py` 加局域网监听加 Chrome 的「把不安全来源当安全」开关；自签证书（iPhone 要装根证书并完全信任）；内网穿透（等于临时公网发布）。

## 发布待办（非阻塞，2026-09-30 预演记录）

1. ~~网页版 `export_web.py` 不写 `build.json` 的 commit / audience~~：2026-10-01 已补，并有 `--ea` 对内网页版与 `verify_web_build.py`（见「一条命令」）。
2. Web 预设 `exclude_filter` 没排除 `tests/*`（加密 Windows 预设已排除）：测试脚本会打进网页包。发布版读不到命令行参数，测试入口不可达，只是多占体积。
3. 打包游戏退出时有引擎自带的「2 resources still in use / ObjectDB leaked」提示，验证脚本已按已知项放行；不影响运行。
4. 加密导出只能在存有密钥与自编译模板的机器上做（`~/.codex/private/ArknightsSurvivors`）：换机器按「一次性准备」重来。

## 一键发版（2026-10-10 起）

用户定方案 A：改动合入 main、快检与发布检查通过后，协调人直接 `python tools/ship.py`——推 origin/main → release_all 出 public / web / internal 三包 → deploy_itch --apply 推 itch，不再逐次申请。任一步失败即停。`--skip-check` 跳过快检、`--no-itch` 只推代码与出包、`--dry-run` 只打印。对内包永不上 itch（deploy_itch 把关）。日志在 build/ship/<提交>/。
