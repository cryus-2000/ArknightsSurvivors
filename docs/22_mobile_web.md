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

## 网页版两个坑（已修）

- **静音**：网页版默认"采样播放"模式下，运行时 `AudioServer.add_bus()` 建的 Music / SFX 总线接不上输出，整局没声音。修法：`game/default_bus_layout.tres` 预定义 Music（送 Master，挂 LowPassFilter）和 SFX 两条总线，`project.godot` 指定为默认布局；`sfx.gd` 的 `_ensure_bus` 发现已存在就直接复用，Windows 行为不变。已用无头 Chromium 的 AnalyserNode 测到输出电平。
- **单文件 25 MB 上限**（EdgeOne / Cloudflare Pages）：`index.wasm` 43.7 MB → 导出后 `gzip -9` 成 `index.wasm.gz`（9.4 MB）并删掉原文件；Web 预设的 `html/head_include` 注入一段 fetch 拦截脚本，把 `.wasm` 请求改取 `.wasm.gz`，按 1f8b 魔数判断后用 DecompressionStream 解压（服务器自动解压时也兼容）。

## 部署（EdgeOne Pages）

- 匿名试部署（无需登录，1 小时内须认领）：`npx -y edgeone makers deploy build/web --anonymous --site china --json`
- 正式部署：`npx -y edgeone makers deploy build/web -n shuiyue-survivors -t <Pages API Token>`（token 放 `.edgeone_token`，已在 .gitignore）
- 2026-09-25 第一次匿名部署成功（项目 makers-rz3tfzqiuxr1）。

## 构建

```
copy ..\art\incoming\*.png game\art\incoming\
godot --headless --path game --export-release "Web" ../build/web/index.html
cd ../build/web && gzip -9 index.wasm     # 得到 index.wasm.gz，删掉 index.wasm
```
云端已跑通：Chromium 手机模拟（844×390，触屏）从标题 → 选难度 → 指南 → 对局 → 摇杆移动全流程正常。产物在 `build/web/`，本地试玩说明见 `build/web/本地试玩.md`。

## 测试开关

`--touch`（桌面强制触屏 UI）、`--touchtest`（自动化：模拟按下-拖动-松开并截图）。

## 待做

- Android APK（需要 Android SDK + JDK 17 + 导出模板；预设可复用本文的触控层）。
- iOS Safari 的全屏 / 音频解锁细节，真机验证。
- 手机上的字号与热区再评估（现在按 1280×720 等比缩放，小屏可能偏小）。
