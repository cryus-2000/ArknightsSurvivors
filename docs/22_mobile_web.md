# 22 · 移动端适配（网页版）

> 2026-09-25。先做网页版（HTML5）验证触控；Android 包留待之后。

## 触屏操作（scripts/touch.gd）

- 启用条件：设备有触屏（`DisplayServer.is_touchscreen_available()`）、网页版在 Android / iOS 上、或命令行 `--touch`。
- 左半屏（x < 55%）按下即摇杆中心，拖动为移动方向；行程超出 64 px 时中心跟着手指走，避免越拖越远。松手复位。
- 右侧中部两个按钮：Ⅱ 暂停、≡ 属性（Tab）。属性面板点任意处关闭。
- 技能全自动，所以移动是唯一操作。升级 / 藏品 / 商店 / 结算 / 指南全部靠点：Godot 的"触摸模拟鼠标"把点击送给现有按钮。
- 商店新增「刷新一次 / 离开」按钮（鼠标也可用，之前只有 F / Esc）。
- 触屏时底部提示改为"按住左半屏拖动移动"。

## 触屏按键布局（10-13 用户：冲刺键等可在设置里改大小和位置）

- 入口：设置 → 游戏 →「触屏按键布局」→「调整」（只在触屏设备列出）。编辑页 `screens/touch_editor.gd`：半透明网格 + 安全区框，摆出移动摇杆、冲刺、技能、攻击（手动普攻时）、暂停、属性、倍速；按住拖动改位置，选中后在中间面板用 − / 滑块 / + 调大小（70%–150%，步长 5%），「恢复默认」「取消」「完成」。
- 规则全在 `scripts/touch_layout.gd`（touch.gd 与编辑页共用）：缺省位置与改版前一致；技能 / 攻击键缺省跟着冲刺键走（拖冲刺键时先把它们定在原处）；拖动时整个按键（含标签）夹在安全区里；松手时和别的键中心距 < 两者半径和 × 0.75 就沿连线推开，推不开退回原位。
- 存档：`settings.cfg` 的 `[touch] layout = {键: {ax, ay, x, y, s}}`，横 / 纵各记离近的那条边多远（UI 逻辑像素），换比例（手机 ↔ 平板）时按钮仍贴原来那条边，读出后再夹进安全区。网页版同样经 user://（IndexedDB）保存，已实测刷新后保留。
- 摇杆改过位置后：按在摇杆圈内（行程 × 1.25）以摇杆圈为中心（固定摇杆手感），圈外仍是按下处为中心；摇杆挪到右半边时起摇杆区域换成右侧 55%。
- 倍速键在触屏上改由 touch.gd 处理点击（位置可调），hud_relics 只负责画。
- 回归：`tests/touch_layout_test`（快检 touch_layout）。

## 界面大小与战斗画面缩放（10-13 用户：手机横屏太拥挤、战斗画面放大一点）

- 手机横屏判定改为 `Cfg.phone_ui()`：触屏且画面比例 ≥ 1.9（19.5:9 是 2.17），不再只看界面逻辑高度 < 520（标题页、touch.gd、touch_layout 用它 OR 原条件）。
- 手机横屏界面放大缺省 `UI_K_PHONE` 1.3 → 1.15（界面整体收到约 88%，逻辑约 1181×544）：顶栏、灯火行、SONAR、编队栏、三选一卡片、暂停 / 设置面板、触屏按键一起收；卡片高仍 382，不再顶满画面高。平板 / 16:9 触屏仍按宽度 1.0–1.3，电脑 1.0 不变。
- 设置 → 画面「界面大小」80%–120%（步长 5），在设备缺省倍数上再乘，所有设备可用、实时生效（`Cfg.view_changed`），存 `[video] ui_size`；界面逻辑高不低于 470（`UI_MIN_H`）。触屏按键布局的单键大小在此之上再乘。
- 设置 → 画面「战斗画面缩放」100%–140%（步长 5），`Camera2D.zoom`；缺省手机横屏 120%、其余 100%（存 -1 = 按设备缺省，`[video] cam_zoom`）。玩法不读视口（刷怪、索敌、机器人、拾取都不依赖屏幕尺寸；pickups 用项目设置里的固定尺寸），同种子 TRACE 对照一致。
- 拉近后：SONAR 视野框按 `视口 / zoom` 画；新增屏外近处敌人的边缘红边（`hud_banners.draw_offscreen_edges`，四边各 8 段，画面外 240 界面像素内的敌人，精英 / Boss 记 3，越多越亮；zoom = 100% 时不画）。Boss / 商人 / 祭坛 / 灯标 / 围猎的边缘指示本来就按画布变换算，拉近后照常。
- 截图 / 对照参数：`--uisize=80`、`--camzoom=140`。

## B站 Toy 容器（10-13 用户确认接入）

- `tools/web/container.js`（export_web.py 内联到加载器后面）：只在 B站环境（域名含 bilibili / hdslb，或 UA 含 Bili）异步加载 Toy JS SDK；`isSupport('onContainerChange')` 为真（只在 B站 App 内）时先监听再 `setContainerMode({orientation:'landscape', immersive:true})`，按回调的 `viewport` / `safeArea` 把画布缩进安全区（改写 innerWidth / innerHeight + 画布定位，派 resize）；1.5 秒收不到回调回退 `env(safe-area-inset-*)`。itch / 普通浏览器 / 桌面版不加载。
- 本地用假 `window.toy` + `window.__syToyBoot()` 验证过；需在 B站 App 真机验证。云存档 / 排行榜 / 分享未做。

## 超宽横屏（10-13 用户反馈：iPhone 横屏在 itch App 里显示不全、比例失调）

itch App 里扣掉标题栏 / 底栏后画面在 2.2:1 到 2.6:1 以上。根因与改法：
- 标题背景 `title_bg.gd` 按「覆盖」缩放后上下平均裁切：越宽裁得越多，人物脚出了画面底边、页脚压在人物身上。改为多裁天空、少裁沙滩，人物脚底停在页脚上方 `FOOT_ROOM`（34 UI 像素）处。16:9 及更窄不受影响。
- 选卡（升级 / 藏品 / 招募）在触屏上标题压在顶栏位置，顶栏中央计时器从标题背后透出、灯火状态行被卡片截断：触屏选卡 / 商店 / 事件时不画顶部中央计时器、灯火状态行、Boss 血条（`hud.panel_over_top`）；标题整体下移 4，英文小标不再贴上沿被切。
- 界面层放大倍数 `Cfg.ui_k` 只在进场景时算一次：竖屏打开网页再转横屏会一直用 1.11、手机版式判定跟着错。现在视口变化时重算（title.gd / game.gd `_ui_fit` / 设置面板）。
- 手机「属性」键标签压到编队区「源石锭」小字：右侧暂停 / 属性键上移 12（172 → 160）。
- 安全区：`Cfg.safe_insets()` 读原生 `DisplayServer.get_display_safe_area()` 或网页 CSS `env(safe-area-inset-*)`，触屏按键夹在其内。网页没声明 `viewport-fit=cover`，浏览器自己给刘海留黑边，读到 0；嵌在 itch 的 iframe 里也读不到父页面的安全区。

## 图鉴在 iPhone 上只剩舞台（10-14 用户：「手机端 itch 点进图鉴是这样的」）

现象：iPhone 横屏、itch 全屏模式（可用区约 2.9:1），图鉴干员页只看到左侧暗舞台（英文大名、立绘、斜带，斜带一直画到右边缘），右侧终端面板、名册、顶栏、返回全不见。
- **不是排版问题**：桌面 `--touch` 在 1170×400（2.93:1）/ 1170×540 / 1200×540 / 1280×720 / 960×720 下七个分页都完整；用户截图里舞台元素的位置和 2.93:1 截图逐项对得上（MIZUKI 横向 30%–59%），说明版式算对了，只是舞台之后画的东西没了。桌面 Chromium 手机模拟（750×258）也正常。
- **根因**：图鉴是全游戏唯一在一帧中途读屏的界面：舞台（背后层）→ `BackBufferCopy` 整屏拷贝 → 磨砂玻璃（`ui_glass.gdshader` 读拷贝）→ 面板正文，标题页的后期层（`post_fx`，亮度 ×1.05 恒开）再读一次屏盖满全屏。用户截图恰好等于「拷屏那一刻」的画面，推断（无 iOS 真机可验）是 iOS WebKit（WebGL2 经 Metal）上中途拷屏之后的绘制 / 第二次拷屏没生效，后期层把拷屏时的舞台原样铺满全屏。
- **改法**：`Cfg.screen_copy_ok()`——网页版的触屏设备与苹果 WebKit（iOS 所有浏览器、macOS Safari）返回 false：图鉴不加 `BackBufferCopy`（隐藏）、磨砂退回平涂 `UI.C_L_GLASS`，图鉴开着时后期层整层隐藏（不读屏，亮度不乘）。桌面版与桌面 Chrome 网页版不变。磨砂关掉时 `BackBufferCopy` 也一并隐藏，不再每帧白拷。桌面上用 `--noscreencopy` 强制走这条路截图验收。
- 局内选卡的灰阶压暗带（`ui_band.gdshader`）同样读屏，但它在后期层之后、两次都是带 mipmap 的同类拷贝，iPhone 上未见报告；如再出现「选卡时 HUD 某块消失」类问题，先查这里。

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
python tools/export_web.py        # 导出 HEAD 到 build/web/（改了 Web 预设还没提交时加 --worktree-presets）
```

一步完成：`git archive` 干净副本 → 把 `art/incoming/*.png` 复制进 `game/art/incoming/`（审稿拼图由 Web 预设 `exclude_filter` 排除）→ Godot 导出 `Web` → **分片** → 内联加载器。需要 Godot 4.7.2 的 `web_nothreads_*.zip` 导出模板（官方 tpz，按 SHA512-SUMS 核对后解压到 `%APPDATA%\Godot\export_templates\4.7.2.stable\`）。

- **分片**（2026-09-26，绕开 25 MB 单文件上限）：`index.pck` / `index.wasm` 按原始字节每 10 MiB 切一片（`--part-mib`），每片 `gzip -9` 成 `index.pck.00.gz` …，删掉原文件；脚本最后逐个检查，有文件超 25 MB 就报错。
- **加载器** `tools/web/loader.js` + `loader.css`：导出时内联到 Web 预设 `html/head_include` 里的 `<!--SHUIYUE_LOADER-->` 处，分片清单（每片字节数、原文件大小）写进脚本。它拦截引擎对 `index.pck` / `index.wasm` 的 fetch，并行下载全部分片、逐片 DecompressionStream 解压、拼回并核对大小后交给引擎；每片失败自动重试 2 次。游戏代码不动。取代了原来 head_include 里只管 `.wasm.gz` 的拦截脚本。
- **加载画面**：「加载中，请耐心等待」+ 进度条，博士（`doctor_run@2x.png` 复制为 `loader_doctor.png`，6 帧 CSS 动画）跟着进度跑。进度 = 已下载字节 / 分片总字节，真实平滑；下载完显示「正在启动…」，引擎移除自带 `#status` 后淡出；引擎报错（`#status-notice`）时也撤掉让报错露出来。视觉按 docs/37，由「界面与美术」定。
- 本地试玩要走 HTTP（不能双击 index.html）：`python -m http.server -d build/web 8000`。

云端已跑通：Chromium 手机模拟（844×390，触屏）从标题 → 选难度 → 指南 → 对局 → 摇杆移动全流程正常。产物在 `build/web/`，本地试玩说明见 `build/web/本地试玩.md`。

## 测试开关

`--touch`（桌面强制触屏 UI）、`--touchtest`（自动化：模拟按下-拖动-松开并截图）。

## 待做

- Android APK（需要 Android SDK + JDK 17 + 导出模板；预设可复用本文的触控层）。
- iOS Safari 的全屏 / 音频解锁细节，真机验证。
- 手机上的字号与热区再评估（现在按 1280×720 等比缩放，小屏可能偏小）。
