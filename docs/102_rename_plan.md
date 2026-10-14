# 101 · 改名预案：界面影响清单与 tools/rename_game.py（界面与美术，2026-10-15，协调人派）

> 游戏可能改名（候选：灯火深潜 / 沉潮录 / 潮下行，用户未定）。本页列出现名「方舟幸存者 / Arknights Survivors」在界面、打包、宣传上出现的每一处、改法，以及哪些**不能改**。
> 脚本 `tools/rename_game.py <中文名> <英文名>` 缺省只打印计划，`--apply` 才改；**现在还没执行**。

## 1. 影响清单

「组」= 脚本里的分组（`--groups` 可只做其中几组）。行号以 main af293dcf 为准，脚本按文本匹配、不靠行号，并核对每条的命中次数。

| 位置（玩家看到的） | 文件 | 改法 | 组 |
|---|---|---|---|
| Windows 窗口标题、网页 `<title>`、任务栏名 | `game/project.godot` `config/name` | 换中文名（Godot 窗口标题与网页导出的 `<title>` 都取它） | game |
| Windows exe 属性里的产品名 | `game/export_presets.cfg` `application/product_name` | 换英文名（`modify_resources=false` 时不写进 exe，但保持一致） | game |
| 标题页英文名（Logo 下一行） | `game/scripts/title.gd` `"ARKNIGHTS  SURVIVORS"` | 换成全大写、词间两个空格的新英文名 | game |
| 标题页 Logo（T5a 版式左上） | `art/incoming/logo.png`（520×130 像素字，画的就是「方舟 幸存者」），`title.gd` `tex_logo = A.tex("logo")` | 旧 Logo 画着旧名，**停用**（`tex_logo = null`），自动退回 `title.gd` 已有的文字版标题：前 N 字 96 号白、其余 40 号青（`--split N`，缺省 2）。新像素 Logo 到货后恢复 `A.tex("logo")`（§3.1） | game |
| 标题页文字版标题（Logo 缺失时的兜底） | `title.gd` `"方舟"` 96 号 / `"幸存者"` 40 号 | 换成新名拆分的两段；小号段的 x 偏移按大号段字数 × 105 | game |
| 致谢「同人声明」 | `game/data/credits.json` 「《方舟幸存者》是《明日方舟》的非官方同人作品……」 | 书名号里换新名 | game |
| 源码注释（不显示） | `title.gd` 文件头、`game.gd` 文件头 | 顺手换 | game |
| Windows 包文件夹名、zip 前缀、包内「说明.txt」首行 | `tools/export_build.py` `NAME`、`README` | 换中文名 | packaging |
| 发版暂存路径 / 文档串 | `tools/release_all.py` `STAGED_PKG`（`build/_export/<名>`）与文件头 | **必须与 export_build `NAME` 同改**，否则验包找不到暂存目录 | packaging |
| itch 上传找包 | `tools/deploy_itch.py` `NAME`（找 `<名>_Public_Encrypted_*.zip` / `<名>_itch_html5_*.zip`） | 同上一起改；改名后只认新名打出的包（旧包不再被选中，预期） | packaging |
| 对局记录读取的缺省名 | `tools/runs_report.py` `kv.get("config/name", …)` | 换中文名 | packaging |
| 宣传图标题常量 | `tools/promo_cover.py` `TITLE` / `TITLE_EN`（封面 F、半身版、小红书都引用）、`tools/promo_xhs.py` 角标与片尾 | 换名后**重出**：`promo_cover_pal.py`（itch 封面 / 横幅）、`promo_xhs.py`（小红书首图 / 图文 / 视频） | promo |
| 对外文案 | `art/promo/itch_page.md`、`art/promo/toy_page.md`、`art/promo/xhs/post.md`、`docs/100_store_copy.md` | 全文替换中英文名；标题 / 话题标签里的名字要人工再读一遍（字数限制） | copy |

**查过、不涉及游戏名、不用改**：

- 网页加载页（`tools/web/loader.js`）：只写「加载中」和「明日方舟同人作品 · 非商业」。
- 作战记录抬头（`run_stats_screen.gd`）：写的是「作战记录 · <结局 / 结果名>」。
- 标题页顶行「ARKNIGHTS FAN GAME · ROGUELIKE SURVIVORS」：是类型标签，不是作品名；改名后如果新名不含「幸存者」，可以考虑留着。
- 页脚「明日方舟同人作品 · 非商业 · 与鹰角网络无关」。
- 设置页没有「关于」页：作品名只出现在致谢。

## 2. 不改的标识符（改了会出事）

| 标识符 | 在哪 | 为什么不改 |
|---|---|---|
| 存档目录 `ArknightsSurvivors` / `ArknightsSurvivors_Internal` | `project.godot` `custom_user_dir_name`、`settings.gd` 迁移常量、`export_build.py`、`verify_encrypted_game.py`、`godot_runner.py` | 玩家的存档、设置、图鉴进度都在这里；改了等于清档（网页版的 IndexedDB 路径也跟着变） |
| exe / pck 文件名 `ArknightsSurvivors.exe` | `export_build.py`、`encrypted_release.py`、`verify_encrypted_game.py`、`启动对内测试版.bat` | 加密包校验、启动脚本都按这个名找；玩家看到的是包文件夹名（已随 `NAME` 改） |
| itch 目标 slug、Toy slug | `.deploy.env` 的 `ITCH_TARGET`、Toy 发布记录 | 改了旧链接失效、评论 / 收藏不跟过去；页面标题另改（§3.2、§3.3） |
| 贴图名 `logo`、私钥目录 `~/.codex/private/ArknightsSurvivors` | `art/incoming/`、`encrypted_release.py` | 资源名 / 本机路径，与玩家无关 |
| 历史文档、提交记录 | `docs/33`、`docs/41`、`docs/archive/` 等 | 是记录，不追改 |

## 3. 脚本做不了、要人工做的

1. **新像素 Logo**（Codex 单）：沿用 `art/incoming/logo.png` 的规格——520×130、透明底、像素硬边，主名大字 + 副段小字（与现 Logo 同版式，标题页按 520×130 缩放、手机缩到 360×90）。到货后把 `title.gd` 的 `tex_logo = null` 改回 `A.tex("logo")`，标题页截桌面 + 手机各一张。过渡期用文字版（预览：`build/shots/rename/title_preview_灯火深潜.png`，桌面 1280×720 与手机 1170×540 都排得下）。
2. **itch 页面**：后台改 Title，页面文案按改过的 `itch_page.md` 粘；slug 不动。
3. **B站 Toy**：`toy update` 改标题与简介（`.claude/skills` 的 toy 技能），slug 不动；封面见下一条。
4. **有字封面**：itch 封面 / 横幅、小红书图由我们的工具压字，`promo` 组改完重出即可。Toy 封面是 Codex 交的有字版 + 无字版（`art/promo/toy/*_notext.png`）：在无字版上重新压新标题（Codex 单只要一张新标题字稿，规格同 `handoff_title_ruins_1014.md`：透明底、像素字、与原无字版逐像素对齐），人物与构图不重画。
5. **对外文案复读**：小红书标题 ≤ 20 字、话题标签、商店文案的字数限制，替换后人工读一遍。
6. **语言风格**：新名与副标题按 docs/76 核对（不要与原作专有名词冲突）。

## 4. 执行顺序（用户定名后）

1. `python tools/rename_game.py <中文名> "<English Name>" --split <N>`：读计划，每条应为 `OK`；出现 `!!` 说明代码变了，先核对再更新脚本规则。
2. 加 `--apply` 执行 → `python tools/check.py --auto`（10-15 演练：`--only ea_ui`、`--only title_menu` 均 rc=0，致谢 JSON 可解析）→ 标题页桌面 + 手机截图。
3. 重出宣传图（`promo_cover_pal.py`、`promo_xhs.py`），派 Codex 新 Logo 与 Toy 标题字稿。
4. 合入后由协调人 `ship.py` 发版；itch / Toy 页面标题人工改（§3.2–3.3）。

演练记录（10-15，未提交）：`灯火深潜 "Lamplight Dive"` 计划 25 条全部命中；`--apply` 后上面两项测试通过，标题页文字版正常；随后逐个文件恢复原样。
