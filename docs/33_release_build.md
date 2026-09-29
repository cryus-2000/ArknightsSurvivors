# 33 · 打包发布版本

> 2026-09-26。给朋友 / 测试者发可直接运行的 Windows 版本。

## 一条命令

发布（对外 + 对内 + 网页，同一提交，逐个验证）：

```bash
python tools/release_all.py --ref <冻结提交>
```

`tools/release_all.py`（2026-09-30）串行做：出对外包 → `verify_encrypted_game.py` 验证 → 出对内包（`--ea`）→ 验证 → 出网页版（`export_web.py`），
任一步失败就中止；最后写 `build/release/release_<提交>.json`（两个 zip 的路径 / 大小 / sha256、验证报告、存档目录、网页最大单文件）。
两个 Windows 包必须串行：导出与验证共用 `build/_export/`，验证读的是刚导出的那份打包源码。验证报告与日志按 audience 分开命名
（`build/encrypted_game_verification_<public|internal>_<提交>.json`），同一提交的两份不会互相覆盖。

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

“未解锁”指首次启动的默认进度，不是每次启动清空玩家已有存档。对内版不要求自动全解锁正常游戏；测试所需配置由演练界面提供。

EA 是开发阶段标记，不等于内测权限。不能仅凭 EA 标记向对外包开放 Boss 演练。构建信息应显式区分 Public / Internal；导出器、主页可见性和演练入口校验统一使用该标记。

交付前分别检查：两个包对应同一提交；全新存档启动；对外版无 Boss 演练入口且不能绕过进入；对内版能进入和退出演练；内测进度不会影响对外存档。未完成这些检查时，不得把已有单一 EA 包称为已符合双版本约定。

当前章节记录发布要求；现有 --ea 参数本身不能证明已经生成上述两个版本。落实构建区分后，应在交接中列出两个包的路径与验证结果。

**落实情况（2026-09-30，架构 / 部署）**：
- 演练入口按 `build.json` 的 `audience == "internal"` 放开（`settings.gd` `Cfg.can_boss_trial()`；主页入口、演练设置窗、`run/boss_trial.gd` 开局都走它）。原来按 `channel == "EA"` 判断，与本节「EA 标记不等于内测权限」不符。调试版（编辑器 / 源码运行）仍一律开放。
- 对内包存档目录改为 `%APPDATA%\ArknightsSurvivors_Internal`（`export_build.py` 只改打包副本的 `project.godot`），对外包仍是 `%APPDATA%\ArknightsSurvivors`。同一台机器两个包都装时，对内包的正常游玩不会解锁对外包的图鉴 / 难度；对内包说明.txt 写明。
- `verify_encrypted_game.py` 在加密包里实测：全新存档（图鉴 / 藏品 / 结局为空、难度 0）、发布版屏蔽开发参数、`can_boss_trial()` 与 audience 一致、存档目录与 audience 一致、对外包图鉴只有干员页开放、普通模板读不了加密 PCK、zip 与验证过的目录逐文件一致。


### 对外版范围澄清（2026-09-27）

对外版始终使用最新游戏内容，不是回退版本或删减玩法版本。区别只在图鉴初始解锁状态、关闭 Boss 演练，以及一结局以外路线按正常条件解锁。所有干员、怪物、Boss 行为、动画、美术、属性特效、弹幕、数值、商店、成长、倍速及其他已完成修复均与同提交的最新版保持一致。不删除其他结局的内容，只保持其初始未解锁状态。

9b2161a 的 EA 与 Public 包由同一提交构建；文件列表相同，外置美术资源完全一致。Public 不启用 EA 演练权限，初始进度已经用全新存档验证。

### 图鉴最终标准

对外新存档：干员图鉴全部开放（包括动作与技能演示）；敌人、精英、Boss、道具、藏品、结局图鉴全部初始未解锁。敌人和场景 / 掉落物在正式冒险中发现后收录，藏品获得、结局达成后收录。演练与图鉴演示不写入遭遇进度。其他游戏内容与最新提交一致；Boss 演练关闭，非一结局路线遵循正常解锁条件。


## 发布待办（非阻塞，2026-09-30 预演记录）

1. 网页版 `export_web.py` 不写 `build.json` 的 commit / audience（局内记录的版本号是 dev）；网页版按对外版处理（无 audience → 演练关闭）。以后要出对内网页版需补。
2. Web 预设 `exclude_filter` 没排除 `tests/*`（加密 Windows 预设已排除）：测试脚本会打进网页包。发布版读不到命令行参数，测试入口不可达，只是多占体积。
3. 打包游戏退出时有引擎自带的「2 resources still in use / ObjectDB leaked」提示，验证脚本已按已知项放行；不影响运行。
4. 加密导出只能在存有密钥与自编译模板的机器上做（`~/.codex/private/ArknightsSurvivors`）：换机器按「一次性准备」重来。
