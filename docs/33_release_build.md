# 33 · 打包发布版本

> 2026-09-26。给朋友 / 测试者发可直接运行的 Windows 版本。

## 一条命令

```bash
python tools/export_build.py
```

输出 `build/release/水月深海幸存者_<日期>_<提交>.zip`，解压后双击「开始游戏.bat」即可。

- 只打包**已提交**的内容（`git archive HEAD`）：其他会话在工作区里没提交的改动不会混进去。要打包新改动，先提交。
- `--ref <提交或分支>` 打指定版本；`--no-zip` 只生成目录（`build/_export/水月深海幸存者/`）。

## 包的结构

游戏 exe 从「exe 所在目录/../art/incoming」读美术（`game/scripts/art.gd incoming_dir()`，Windows 预设不把美术打进 pck），所以目录必须保持：

```
水月深海幸存者/
  开始游戏.bat
  说明.txt
  game/ArknightsSurvivors.exe + ArknightsSurvivors.pck
  art/incoming/*.png        （跳过交接文档、清单和 preview / overview 预览图）
```

## 一次性准备：Godot 4.7.2 导出模板

导出需要与编辑器同版本的官方模板。本机已装在 `%APPDATA%\Godot\export_templates\4.7.2.stable\`（只保留 Windows 发布 / 调试模板）。换电脑或升级 Godot 时：

1. 从 GitHub godotengine 发布页下载 `Godot_v<版本>-stable_export_templates.tpz`（约 1.2 GB，其实是 zip）；
2. 把里面 `templates/` 下的 `windows_release_x86_64.exe`、`windows_debug_x86_64.exe` 和 `version.txt` 放进 `%APPDATA%\Godot\export_templates\<version.txt 的内容>\`；
3. 或在 Godot 编辑器「编辑器 → 管理导出模板」里在线安装。

Godot 路径默认 `E:\Godot_v4.7.2-stable_win64.exe\...console.exe`，其他位置用环境变量 `GODOT` 指定。

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


### 对外版范围澄清（2026-09-27）

对外版始终使用最新游戏内容，不是回退版本或删减玩法版本。区别只在图鉴初始解锁状态、关闭 Boss 演练，以及一结局以外路线按正常条件解锁。所有干员、怪物、Boss 行为、动画、美术、属性特效、弹幕、数值、商店、成长、倍速及其他已完成修复均与同提交的最新版保持一致。不删除其他结局的内容，只保持其初始未解锁状态。

9b2161a 的 EA 与 Public 包由同一提交构建；文件列表相同，外置美术资源完全一致。Public 不启用 EA 演练权限，初始进度已经用全新存档验证。

### 图鉴最终标准

对外新存档：干员图鉴全部开放（包括动作与技能演示）；敌人、精英、Boss、道具、藏品、结局图鉴全部初始未解锁。敌人和场景 / 掉落物在正式冒险中发现后收录，藏品获得、结局达成后收录。演练与图鉴演示不写入遭遇进度。其他游戏内容与最新提交一致；Boss 演练关闭，非一结局路线遵循正常解锁条件。
