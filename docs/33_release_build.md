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
3. **初始状态**：发布版必须是图鉴未解锁、难度重置。用 release 模板导出；跑玩法系统提供的发布检查（待交付）；用全新的浏览器配置 / 全新的 Windows 用户目录实测首次打开是未解锁状态。
4. **无数据上传 / 导出入口**（EA 小范围试玩阶段，用户 2026-09-26 定）：发布版里不得有任何网络上报，也不得有数据导出按钮。
5. **包体**：Windows 包不带审稿拼图（`SKIP_WORDS`）；网页包由 `tools/export_web.py` 分片，脚本检查单文件 ≤25 MB（docs/22）。
6. **不擅自发布**：上传 / 发链接前由用户确认。
