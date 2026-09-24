# 22 · 移动端适配（网页版）

> 2026-09-25。先做网页版（HTML5）验证触控；Android 包留待之后。

## 触屏操作（scripts/touch.gd）

- 启用条件：设备有触屏（`DisplayServer.is_touchscreen_available()`）、网页版在 Android / iOS 上、或命令行 `--touch`。
- 左半屏（x < 55%）按下即摇杆中心，拖动为移动方向；行程超出 64 px 时中心跟着手指走，避免越拖越远。松手复位。
- 右侧中部两个按钮：Ⅱ 暂停、≡ 属性（Tab）。属性面板点任意处关闭。
- 技能全自动，所以移动是唯一操作。升级 / 藏品 / 商店 / 结算 / 指南全部靠点：Godot 的"触摸模拟鼠标"把点击送给现有按钮。
- 商店新增「刷新一次 / 离开」按钮（鼠标也可用，之前只有 F / Esc）。
- 触屏时底部提示改为"按住左半屏拖动移动"。

## 网页版

- `export_presets.cfg` 新增 `Web` 预设：无线程版（不需要 COOP/COEP 头，任何静态托管都能放），`canvas_resize_policy=2` 自适应，横屏。
- 美术：网页没有本地文件系统，`art.gd` 在 `web` 特性下改从 `res://art/incoming` 读；导出前把 `../art/incoming/*.png` 复制到 `game/art/incoming/`（不入库；Windows 预设已排除该目录）。
- 性能：`settings.gd` 在网页版默认关闭辉光 / 水下滤镜 / 法线光照（触屏设备再关景深），玩家可在设置里打开。
- 宽屏手机（19.5:9）走 `stretch/aspect=expand`：逻辑高度 720，宽度按屏幕扩展，HUD 贴边元素自动到两侧。

## 构建

```
copy ..\art\incoming\*.png game\art\incoming\
godot --headless --path game --export-release "Web" ../build/web/index.html
```
云端已跑通：Chromium 手机模拟（844×390，触屏）从标题 → 选难度 → 指南 → 对局 → 摇杆移动全流程正常。产物在 `build/web/`，本地试玩说明见 `build/web/本地试玩.md`。

## 测试开关

`--touch`（桌面强制触屏 UI）、`--touchtest`（自动化：模拟按下-拖动-松开并截图）。

## 待做

- Android APK（需要 Android SDK + JDK 17 + 导出模板；预设可复用本文的触控层）。
- iOS Safari 的全屏 / 音频解锁细节，真机验证。
- 手机上的字号与热区再评估（现在按 1280×720 等比缩放，小屏可能偏小）。
