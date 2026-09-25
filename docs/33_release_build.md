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
  game/ShuiyueSurvivors.exe + ShuiyueSurvivors.pck
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
