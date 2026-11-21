# 22 · 移动端适配（网页版）

> 2026-09-25。先做网页版（HTML5）验证触控；Android 包留待之后。

## 触屏操作（scripts/touch.gd）

- 启用条件：设备有触屏（`DisplayServer.is_touchscreen_available()`）、网页版在 Android / iOS 上、或命令行 `--touch`。
- 左半屏（x < 55%）按下即摇杆中心，拖动为移动方向；行程超出 64 px 时中心跟着手指走，避免越拖越远。松手复位。
- 右侧中部两个按钮：Ⅱ 暂停、≡ 属性（Tab）。属性面板点任意处关闭。
- ~~技能全自动，所以移动是唯一操作~~（已过时：现在还有冲刺键，队长有手动技能 / 手动普攻时另有按键，见下「触屏按键布局」与 docs/26 v2.3–2.5）。升级 / 藏品 / 商店 / 结算 / 指南全部靠点：Godot 的"触摸模拟鼠标"把点击送给现有按钮。
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
- 本地用假 `window.toy` + `window.__syToyBoot()` 验证过；需在 B站 App 真机验证。云存档已做（docs/89，10-13）；排行榜 / 分享未做。
- 10-22 起 Toy 包的接入细节（环境透传、胶囊、回退、导出 / 打包、验证）见下节「Toy 接入」。
- **11-13 改版（以本条为准，下文「缩进安全区」「四边按 0」的说法作废）**：iPhone 17 B站 App 横屏实测顶部露白边、左侧灵动岛压住「维什戴尔 晋升至精英二」、经验条悬在顶栏下。改成**画布铺满整个窗口、只让界面内缩**：
  - `container.js`：不再改写 `innerWidth / innerHeight`、不再定位画布；所有包都声明 `viewport-fit=cover` + `theme-color` 深色；`html / body` 底色 `#04070a`（loader.css）。`__sySafe` 四边 = B站容器 `safeArea` 与 `env(safe-area-inset-*)` 逐边取大（CSS px，相对整个窗口）；横屏回来的 safeArea 只有 top 时按竖屏值转 90°（`source: toy-rot`）；iPhone 横屏比例 ≥ 2 却两边都是 0 时估 59 / 0 / 59 / 21（`source: guess`）。resize / 转屏 / visualViewport / 容器变化都重算（转屏 300 ms 后再算一次）。手机回调仍非沉浸横屏时最多再请求 2 次 `setContainerMode`。
  - 诊断浮层：网址带 `sydiag` 或**四指同时点屏**，左上显示窗口 / visualViewport / 画布 / env / 容器状态 / 最终安全边距；再四指点一次关掉。真机还有白边时让用户截这块。
  - Godot：`Cfg.safe_insets()` = 系统边距（胶囊下沿并进「上」，整块界面 / 触屏按键用）；新增 `Cfg.hud_ins()`（只有系统边距）与 `Cfg.capsule_ui()`。局内 HUD 按 `hud_ins` 内缩：经验条贴屏幕顶边、左右让开、右端停在胶囊左边；左侧通知、连携提示、声呐、屏外指示框、左上读数、终结技切入条的立绘与名字让开左右；右上小牌（属性 / 暂停 / 倍速）与源石锭 / 藏品让开右侧，胶囊压住这一行时整排落到胶囊下面；指挥台按底部横条上抬 0.6 倍。桌面四边恒为 0，电脑版画面不变。
  - 测试：`--touch --winsize=WxH --safe=l,t,r,b`（窗口像素）`[--capsule=w,h]` 模拟；`python tools/safe_area_shots.py` 截 iPhone 17（双侧 / 只左 / 只右）、Pro Max、刘海、安卓 20:9 / 19.5:9、16:9、平板 4:3，另存叠了岛 / 圆角 / 胶囊 / 横条示意的 `_dev.png`。
  - **11-13 第二轮（局外 / 弹出界面，用户 iPhone 看过 HUD 后「去做掉」）**：真机数据 `safeArea` 左 62（岛侧）、右 0、上 54（B站胶囊那一行），`env` 两侧 62 / 下 20；横屏一律不让「上」，胶囊单独避让（Cfg.capsule_ui）。公共函数（settings.gd）：
    - `fit_design(vs, dsz, avoid_cap)`：设计稿等比缩放放进安全区；胶囊压右上时先左挪，挪不开在「停在胶囊左边」与「落到胶囊下面」里取大的缩法。选人、图鉴用它；寻访传 `avoid_cap = false`，改由 `HS.topbar(…, il, ir)` 让顶栏页码 / 返回避开胶囊（整版不缩）。
    - `safe_frame(vs)`：整屏流动版式的内容框（去刘海 / 岛 / 圆角 / 横条，顶部让胶囊）。作战记录、对局记录背景铺满，内容 `draw_set_transform` 进框，命中区和鼠标同换坐标（`_fo`）。
    - `edge_l()` / `edge_r(vs, y0, y1)`：贴边元素要让的宽度（右侧纵向碰到胶囊时让到胶囊左边）。认知塑造顶栏 / 详情卡、属性页手机版、载入页、致谢、操作说明用它。
    - 本来就按安全区排的：标题页、难度、设置、商店、三选一 / 招募 / 藏品、事件、暂停、结算、支持作者、意见反馈、精英化演出、终结技瞄准。
    - 截图：`python tools/ui_matrix.py <目录> --sizes ip17L,ip17R,touch16x9,ipad`（ip17L / ip17R 只给岛那一侧边距，分别看两侧；截图上叠圆角 / 岛 / 胶囊 / 横条示意）；没有现成钩子的事件 / 精英化 / 终结技瞄准 / 对局记录走 `tests/safe_screens_shots.tscn --which=`。

## Toy 接入（10-22，分支 claude/toy-sdk；SDK 能力见 .claude/skills/bilibili-toy-sdk，官方 FAQ 见 docs/99 §0）

**同一份网页壳**：itch 包与 Toy 包用同一个 `index.html` 模板（Godot Web 预设的 `head_include` + `export_web.py` 内联的 gl_state / fps_meter / loader / container / cloud），加载进度页（「声呐测绘」：声呐进度环 + 终端日志 + 提示）与说明页脚两边一样。差异只有 `python tools/export_web.py --toy` 做的两件事：

1. `container.js` 之前写 `window.__SY_TOY = 1` → 一律加载 Toy JS SDK（`//s1.hdslb.com/bfs/seed/toy/app/sdk/toy-sdk.js`）；itch / 本地包仍只在域名含 bilibili / hdslb 或 UA 含 Bili 时加载。
2. 分片文件名不带 `.gz`：`index.00.pck` / `index.00.wasm`（内容仍是 gzip，`loader.js` 按魔数识别，不改加载器）。原因：Toy 只发布白名单后缀的文件（docs/99 一-16），`.pck` / `.wasm` 是 Godot 网页包必有的后缀，`.gz` 是否在白名单里没有官方清单可查。
   输出 `build/toy/web/`（目录）+ `build/toy/方舟幸存者_toy_<提交>.zip`（`index.html` 在 zip 根目录、无外层文件夹，gzip 内容的分片按存储放，> 50 MB 中止）。不上传：发布 / 预览由用户用 `/toy` 技能（`toy create <zip>`，先预览再 `--yes` 提交审核）。

**JS 侧（`tools/web/container.js`）**：

| 对象 | 内容 |
|---|---|
| `window.__syToyEnv` | `{rev, sdk, container, deviceType, orientation, immersive, viewport{w,h}, safeArea{l,t,r,b}, capsule, source}`；`rev` 每次变化 +1，`sdk` = `window.toy` 是否存在，`container` = 是否拿到过容器状态（只在 B站 App 内），`source` = `toy`（SDK 回调）/ `env`（CSS `env()` 回退）/ `none` |
| `window.__sySafe` | 当前生效的安全边距 `{left, top, right, bottom, source, capsule}`（CSS px；`capsule` 为画布坐标系里的 `{x, y, w, h}` 或 null） |
| `window.__syToy` | 给 Godot 的桥：`env()` 回 `__syToyEnv` 的 JSON 串；`onchange(cb)` 注册回调，环境每次变化 `cb(JSON)`，注册时已有状态就立刻回一次 |
| `window.__syToyWait()` | Promise，SDK 加载结束（成功 / 失败 / 8 秒超时 / 非 B站环境）后给出 `window.toy` 或 null；云存档 `cloud.js` 用它 |

流程：SDK 加载 → `isSupport('onContainerChange')` 为真（B站 App 内）→ 先 `onContainerChange` 监听，再 `setContainerMode({orientation:'landscape', immersive:true})`（手机横屏必须同时沉浸；Promise 不算成功，以回调状态为准）→ 回调的 `viewport` / `safeArea` 把画布缩进安全区（改写 `innerWidth` / `innerHeight` + 画布 `fixed` 定位 + 派 `resize`），`changedFields` 含 viewport / safeArea / orientation / immersive / deviceType 时重排。

**顶栏胶囊**：SDK 文档（技能清单）没有单独的胶囊接口，FAQ 三-14 说「由 SDK 提供」；`container.js` 兼容性地从容器状态里找 `capsule` / `capsuleRect` / `menuButton` / `menuButtonRect` / `menuButtonBoundingClientRect` / `topBar` / `navBar` / `navigationBar` 这类矩形字段（`{x|left, y|top, width, height}`，CSS px、相对 viewport），换到画布坐标系后写进 `__sySafe.capsule`。真机拿到真实字段名后若不在这串里，只需在 `findCapsule` 加一个名字。

**Godot 侧（`scripts/settings.gd`）**：

- `Cfg._toy_init()`（`_ready`，仅网页）：`JavaScriptBridge.get_interface("__syToy")`，`onchange` 注册回调 → `Cfg.toy_env`（Dictionary）更新、安全边距缓存清掉、`view_changed` 发出（标题页 / game.gd / 设置面板本来就按它重排）。
- `Cfg.toy_device()`：容器状态里的 `deviceType`（没拿到容器状态时为空串）。`Cfg.phone_ui()` 在「画面比例 ≥ 1.9」之外也认 `deviceType == phone`（16:9 的旧手机在 Toy 里也走手机版式）。
- `Cfg.safe_insets()`：画布已被 `container.js` 缩进安全区，所以四边仍按 0；只有 `__sySafe.capsule` 存在、且在画布上半部时，把它的下沿（`y + h`，CSS px → UI 逻辑像素）当成额外的顶部边距。触屏按键布局（`touch_layout.safe_rect`）、选卡面板、设置面板顶部本来就按 `safe_insets()[1]` 让位，所以 HUD 按键自动避开胶囊；顶部中央计时器等非交互元素不动（FAQ 的要求是交互元素避开）。
- 局内玩法代码不碰：以上全在界面层，同种子 TRACE 不变。

**回退**（非 Toy 环境 / 旧客户端，全部静默）：

| 情况 | 行为 |
|---|---|
| itch / 本地 / 桌面（没有 SDK） | 不加载 SDK，`__syToyEnv.sdk=false`，`__syCloud.probe` 回 unsupported，浏览器自己的布局 |
| Toy 包但 SDK 加载失败 / 8 秒超时 | 同上 |
| B站网页端（SDK 在、容器接口 `unsupported`） | 不改布局；云存档照常 |
| B站 App 旧客户端（接口在、1.5 秒不回调） | 先试一次 `getContainerState`，再不行按 CSS `env(safe-area-inset-*)` 留边（`source=env`）；横竖屏交给预设 `head_include` 里原有的「请将手机横过来」提示 + 首次触摸尝试全屏 / `screen.orientation.lock('landscape')`（旋转自适应） |
| 容器状态里没有胶囊字段 | 11-08 起：沉浸且非桌面时 `container.js guessCapsule` 按 iPhone 实测估安全区右上 108 × 46 CSS px 的禁区（docs/318），顶部边距 = 46；非沉浸 / 桌面仍为 `capsule=null`、顶部边距 0 |

**验证**（内置浏览器，桌面 Chrome 模拟手机：宽 < 768、派 TouchEvent，docs 的 `web-mobile-emulation-testing`）：

```
python tools/export_web.py --toy
python tools/web_cloud_mock.py --dir build/toy/web --ports 8811,8812
```

`web_cloud_mock.py` 注入的假 `window.toy`（`tools/web/toy_mock.js`）在网址带 `?toyc=phone | tablet | desktop` 时同时模拟容器接口（手机横屏 safeArea 左右 44 / 下 21、沉浸后右上角 88×32 的胶囊；`setContainerMode` 后异步回调；窗口 resize 回调 viewport），`?toyc=old` 模拟旧客户端（接口在、永不回调）。真机（B站 App ≥ 9.9.0）与 Toy 平台预览仍需用户走 `/toy`（`toy create` 会在账号下建一个 Toy，10-22 本会话没有代做）。

**10-22 实测记录**（Toy 包 `--toy` 导出 + mock，内置浏览器模拟手机 740×360、合成 TouchEvent；面板隐藏时引擎不出帧，测试页注入 setTimeout 版 rAF）：

| 步骤 | 结果 |
|---|---|
| `?toyc=phone` 打开 | 加载进度页（同 itch）→ 标题页；mock 回调后 `__syToyEnv` = phone / landscape / immersive，safeArea 44 / 0 / 44 / 21，胶囊 `{x:556, y:8, w:88, h:32}`（画布坐标）；画布 651×338、`getBoundingClientRect` 左 44、上 0，右侧与底部留黑边 |
| 真 SDK 在非 B站域名 | 10-22 顺手实测：`s1.hdslb.com` 的 SDK 在 127.0.0.1 也能加载，`isSupport` 容器三项 false、云存储两项 true；真 SDK 会覆盖页面里已有的 `window.toy`，所以 `container.js` 遇到已有 `window.toy`（mock）不再加载 SDK。SDK 原型上另有本技能清单没列的 `getSharedStorage` / `setSharedStorage` / `onPlayerChange` / `getPlayerState` / `onPageClose` / `reportAction` / `sharePicture`，以后做排行榜 / 分享时再查官方文档 |
| 画布定位 | 引擎每次 resize 把 canvas 行内样式重写成 `position:absolute; left:0; top:0`，旧写法（改行内样式）在引擎起来后失效；改为 `<style id="sy-frame">` 里带 `!important` 的规则后稳定 |
| `Cfg.safe_insets` 的 JS 段 | 页面里直接跑同一段：`'0,40,0,0,652'`（胶囊下沿 40 CSS px 当顶部边距） |
| 设备 A（8811）首次进入 | 1 读 1 写（云端为空 → 上传），`sy_h` + `sy_d0` |
| 标题 → 选人 → 难度 → 一局（标准，原地不动，自动选第三张卡）→ 倒下 → 结算 → 寻访页 | 结算时 1 读 1 写，云端 813 字节、`n:1`；`__syCloud.staged()` 清空 |
| 设备 B（8812，空 IndexedDB = 清缓存）进入 | 1 读、不写（合并结果与云端一致），标题页正常 |
| 快检 `--auto` | 111 项，只剩「积木等价金样过期」（按规则忽略） |

没做到的：B站 App 真机（容器状态字段名、胶囊字段是否存在、`setContainerMode` 行为）与 Toy 平台预览（`toy create` 建 Toy 后才有 preview_url）。

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

## 手机布局整理 + 分辨率矩阵（10-26 用户 iPhone 实机「挤得太满」）

- **改了什么**：
  - 选卡 / 商店卡在手机上只写一句，全文点「详情」看。
  - 干员卡在所有平台都只写一句。
  - 选卡 / 商店时收起四周 HUD；藏品栏只留一行。
  - 手机局内字号下限 13；结算页、翻卡字号放大。
  - 准则见 docs/37「最小字号与点击区」。
- **iPhone Safari 横屏可视区**：
  - 用户截图 2868×1320 里，画布 2467×1130，约 2.18:1。扣掉了左右刘海边和底部地址栏，itch iframe 里安全边距读到 0，所以画布本身就在安全区内。
  - 本地按 `--touch` + 1170×537 截图验收。
- **分辨率矩阵** `python tools/ui_matrix.py <输出目录> [--screens …] [--sizes …] [-j 3]`：
  - 15 屏 × 10 尺寸逐张截图，拼成缩略总表 `matrix.jpg`，另有每屏一张大图 `matrix_<界面>.jpg`。
  - 15 屏：标题、选人、难度、寻访、图鉴、认知塑造、蚀刻章、设置、局内、升级、商人、翻卡、事件、暂停、结算。
  - 10 尺寸：720p、900p、1080p、1440p、2560×1080、1024×768、1680×1050；iPhone 2178×1002、安卓 2400×1080、iPad 2048×1536（这三个是触屏）。
  - 窗口用 `--winsize=WxH`（settings.gd，无边框，可以比本机屏幕大）。
- **自动检查**：
  - touch_layout：手机选卡卡片在面板内、只写一句、字号 ≥ 18、四周 HUD 收起。
  - ea_ui：精英化卡一句话；四种画面比例下三选一卡片不出面板。

## 性能报告（10-27 用户：真机采集，重点手机网页）

- **采集**（`core/perf_report.gd`）：
  - 每局自动记录，只做计数和分桶，不逐帧存数组。
  - 只算对局进行中的帧：面板、暂停、开局前 3 秒、超过 1 秒的间隔都不算。
- **记录内容**：
  - 帧时 P50 / P95 / P99：0.5 毫秒一格的直方图。
  - 最低 1 秒帧率：按真实时间算。
  - 7 分钟后（对局时间）单独一组。
  - 内存峰值：每 5 秒取一次。网页取显存加音频样本估算，同 `_mem_guard` / `--memlog` 口径；桌面取引擎内存加显存。
  - 同屏敌人峰值、是否触发内存护栏、局长、画质与帧率上限、版本和提交号（`data/build.json`）。
  - 设备：网页取 UA、屏幕、devicePixelRatio、deviceMemory、CPU 核数；桌面取系统、处理器、显卡、内存。
- **存储**：`user://perf_reports.json` 只留最近 5 局，不上传。中途退出且不到 30 秒的局不记。图鉴演示和 Boss 演练不算。
- **查看与复制**：
  - 入口在设置 → 画面 →「性能报告」→「查看」（`screens/perf_view.gd`），显示最近一局摘要和更早几局各一行。
  - 「复制报告」复制精简纯文本：网页走 `navigator.clipboard`，1 秒内没成功就盖一个可全选的网页文本框；桌面失败时显示引擎文本框。
- **测试开关**：
  - 测试运行只有加 `--perfreport` 才记（打印 `PERFREPORT finish …`）。
  - `--perfout=<文件>` 指定读写文件（godot_runner 每次给临时用户目录）。
  - `--settingsshot --perfview` 截报告页。

## 网页版

- `export_presets.cfg` 新增 `Web` 预设：无线程版（不需要 COOP/COEP 头，任何静态托管都能放），`canvas_resize_policy=2` 自适应，横屏。
- 美术：网页没有本地文件系统，`art.gd` 在 `web` 特性下改从 `res://art/incoming` 读；导出前把 `../art/incoming/*.png` 复制到 `game/art/incoming/`（不入库；Windows 预设已排除该目录）。
- 性能：`settings.gd` 在网页版默认关闭辉光 / 水下滤镜 / 法线光照（触屏设备再关景深），玩家可在设置里打开。
- 宽屏手机（19.5:9）走 `stretch/aspect=expand`：逻辑高度 720，宽度按屏幕扩展，HUD 贴边元素自动到两侧。

## 网页版两个坑（已修）

- **静音**：网页版默认"采样播放"模式下，运行时 `AudioServer.add_bus()` 建的 Music / SFX 总线接不上输出，整局没声音。修法：`game/default_bus_layout.tres` 预定义 Music（送 Master，挂 LowPassFilter）和 SFX 两条总线，`project.godot` 指定为默认布局；`sfx.gd` 的 `_ensure_bus` 发现已存在就直接复用，Windows 行为不变。已用无头 Chromium 的 AnalyserNode 测到输出电平。
- **单文件 25 MB 上限**（EdgeOne / Cloudflare Pages；单个 `.wasm.gz` 的做法已被下文「分片」取代）：`index.wasm` 43.7 MB → 导出后 `gzip -9` 成 `index.wasm.gz`（9.4 MB）并删掉原文件；Web 预设的 `html/head_include` 注入一段 fetch 拦截脚本，把 `.wasm` 请求改取 `.wasm.gz`，按 1f8b 魔数判断后用 DecompressionStream 解压（服务器自动解压时也兼容）。

## 加载链路（11-16，B站 Toy「加载很久、根本加载不出来」）

**现象**：11-15 玩家截图（B站 App 安卓横屏，四指诊断浮层）：除浮层外全黑，连加载页都没有；`canvas 300x150`（引擎根本没启动）、`screen 800x360`（安卓，720p 低端机）。

**原因**（桌面 Chromium 复现不出来，按截图逐项排除后定位到安卓旧 WebView）：
1. 引擎脚本 `index.js`（emscripten 4.0.20）用了 `??=` / `||=` / `?.` / `??`、`BigInt64Array` 和 WASM BigInt，**最低要 Chrome 85 / Safari 15**（11-17 更正：引擎 wasm 还用了 SIMD 和 wasm 异常处理，实际门槛 Chrome 95 / iOS 16.4，见下文「最低内核」）。没装谷歌服务的国产安卓机，系统 WebView 常年不更新，内核低于 85 时 `index.js` 直接语法错误 → `Engine` 不存在 → 页面末尾的启动脚本报错 → 画布停在默认 300×150。原来没有任何提示。
2. 同时加载页看不见：`loader.css` 里 `#sy-load` 只写了 `inset: 0`（要 Chrome 87）。旧内核不认 → 固定定位的加载页没有宽高、`overflow:hidden` 把内容全裁掉 → 只剩 `body` 的深色底，正是截图里的「全黑」。内核 85–86 时引擎能跑，但整个加载过程（几十秒）也是黑的。
3. 方向 4 加载页整页靠 `requestAnimationFrame` 在画布上逐帧画，WebView 不给帧（页面在后台、跨域 iframe 被节流）时同样一片黑；wasm 的 LZMA 解码在主线程（桌面约 2 秒，手机估 10–20 秒），且 6 个分片一起抢带宽，wasm 要到下载快结束才齐，解码 + 编译全压在下载之后。

**修法**（`tools/web/` 下，`export_web.py` 拼进 `index.html`）：
- **首帧壳** `boot_shell.html`：纯 HTML / CSS 插在 `<body>` 最前（只用旧内核也认的写法：`top/right/bottom/left`，不用 `inset` / `min()`），页面解析到就有深色底、罗德岛标志、进度条（一直在走的光是 CSS 动画）、阶段文字（`正在下载资源 12.3 / 29.6 MB · 1.2 MB/s` → 解压 → 启动引擎 n 秒 → 准备主菜单 n%）。方向 4 加载页画出第一帧（`.p4on`）后盖在它上面；rAF 400 ms 不来就用定时器补画。
- **错误捕获** `boot_err.js`：`<head>` 里第一个自有 `<script>`、单独内联（后面那一大块有语法错时它照样在），本页 / `index.js` 的脚本错误立刻弹卡片；卡片里「重新加载」是内联 `onclick`，所有脚本都挂了也能点。
- **内核检查**（`loader.js` 开头）：测 `??=` / `?.` 语法、`BigInt64Array`、`WebAssembly`；不满足就不下那 30 MB，直接显示「当前浏览器内核版本过旧」+ 检测到的内核版本 + 更新 Android System WebView / Chrome、iOS 15 的说明。`index.js` 没跑起来（`typeof Engine === 'undefined'`）也报。网址 `?oldcore=1` 可模拟。
- **失败与超时**：每片 15 秒收不到字节就中止重下，最多 4 次（1 / 2 / 4 秒退避），用尽 → 红色失败卡片（哪个文件、HTTP 状态）+「重新加载」；Godot 自己的 `#status-notice` 报错也换成这张卡片。进度（字节 / 阶段 / 游戏回传）60 秒没动 → 黄色「加载比平时慢」提醒（不打断加载，进度恢复自动收起）。
- **关键路径**：页面一开始就下（不等 `index.js` 下完、引擎来要）；wasm 两片先下，字节收齐再开 pck 四片（引擎先要完整 wasm 才能编译，解码 / 编译和 pck 下载重叠）；引擎提前来要还在排队的 pck 时等它开始，不放行到网络。LZMA 在 Worker 里解：wasm 整块缓冲区转移给 Worker、解完转回，不另分配（内存峰值不变），主线程不卡；Worker 起不来（先 ping）就退回主线程切片解。网址 `?nolzw=1` 强制主线程。
- **诊断卡**（11-16 用户：让玩家自己截图反馈）：超过 20 秒没进标题、进度 60 秒没动、本页脚本报错、加载失败时自动弹出，不用四指。内容：当前阶段与已停秒数、各分片已下 / 总字节（`01.pck 3.2/8.3（重试 1）`）、第一条报错（脚本错误或下载失败的文件名 + HTTP 状态 / 断流）、系统与 WebView 内核版本、是否在 B站 App 内、包版本（导出时写进 `boot_err.js`，同 `build.txt`）、内存（`deviceMemory` / JS 堆可读时）。三个按钮「重试」「复制诊断信息」「继续等待」，下写「截图这张卡私信 UP 主」（Toy 不许放站外链接 / 联系方式）。「继续等待」后只有新的报错 / 进度停住才再弹；失败卡片没有「继续等待」；读完出「开始游戏」时提醒卡自动收起（别盖住按钮），之后看四指浮层。复制先用 Clipboard API，不行退 `execCommand`，再不行选中文字让玩家长按复制。**不往任何服务器发数据**。文字生成在 `boot_err.js` 的 `window.__syDiagText()`，诊断卡、复制、四指浮层共用。
- **多语言**（11-16 协调人追加，itch 包中 / 英 / 日 / 韩）：`tools/web/boot_l10n.js` 是 head 里第一个自有 `<script>`，首帧前选语言 → `window.__syL`、`<html data-sylang>`。顺序：Toy 包（`--toy` 导出写 `LOCK = 1`）一律中文 → 游戏存的界面语言 `localStorage.sy_lang`（`settings.gd apply_lang` 在网页且未锁中文时写生效语言）→ `navigator.language`（zh* / ja* / ko* / 其余英语）；网址 `?sylang=en|ja|ko|zh` 临时指定。首帧壳的固定文字四种语言都写在 HTML 里（`.l-zh / .l-en / .l-ja / .l-ko`），CSS 按 `data-sylang` 只显示一种，那段脚本没跑就显示中文；日 / 韩只写系统字体回退（Hiragino / Yu Gothic / Meiryo / Noto Sans JP，Apple SD Gothic Neo / Malgun Gothic / Noto Sans KR），不下载字体。脚本里的文字一律 `__syT('中文原文')` 查字典，内部状态（日志 key、阶段、Godot 回传的 `读取 · 美术素材`）保持中文、画到页面时才翻（`TP` 按「 · 」逐段译）。字典由 `tools/web_loader_l10n.py` 在导出时生成：`tools/web/loader_l10n.json` 的 `ui` 段按 key 从 `game/l10n/ui.csv` 取（启动页 boot_views / boot_screen、启动顺序分类、加载提示等游戏里已有的术语），`hand` 段是 ui.csv 里没有的（阶段、诊断卡、内核提示等，AI 翻译）；找不到 key 导出直接报错。PRTS / ARCHIVE INDEX / DOWNLOAD 等装饰英文不动。诊断卡底下的反馈提示按渠道由导出填：Toy「截图这张卡私信 UP 主」（只中文），itch「截图这张卡，发到 itch 页面的评论区」（四种语言）。Toy 包不带外语字典。方向 0–3（不再发布）的 DOM 页面文字没有翻译。
- **诊断浮层**（四指 / `?sydiag`）新增 4 行，并在末尾附上诊断卡同一份文字（进游戏后也能看）：`ua`（内核版本、OLD 标记、`typeof Engine`）、`load`（当前阶段 / 字节 / 重试 / 最近错误）、`t`（各阶段耗时 ms：`wasm_bytes` / `index.wasm` / `index.pck` / `unpacked` / `title` / `fail`）、`err`（捕获到的脚本错误）。下次玩家截图就能看出卡在哪。

**实测**（11-16，本地伺服：旧 = 线上 8185f341f 的 Toy 包；新 = 同一包重新注入新加载器，以及正式导出的 d7a080fd4。Playwright 手机横屏 800×360 dpr 2 + toy_mock，带 GPU、窗口在屏幕外；4G = 9 Mbps / 60 ms，CPU 4× 只节流主线程）：

| 节点（秒） | 旧（两轮） | 新（三轮） |
|---|---|---|
| 首次绘制 | 0.4 / 0.6 | 0.5 / 0.6 / 0.6 |
| wasm 解码 + 编译完 | 23.9 / 25.2 | 8.2 / 8.3 / 8.4 |
| 全部下完（pck 到齐） | ≈ 24–25 | 26.3 |
| 引擎起来（`__syBootUp`） | 35.8 / 36.0 | 36.7 / 38.4 / 43.2 |
| 出「开始游戏」 | 75.8 / 100.4 | 82.3 / 87.7 / 95 |

- 这个档位下总耗时由**下载（约 26 秒 / 29 MB）+ 游戏侧启动（引擎起来到读完 40–60 秒，boot_screen 逐个编译脚本 + 渲染预热）**决定，两段这次都没动；「出开始游戏」的差别在噪声里（同一包两轮差 25 秒）。新链路把 wasm 就绪从下载末尾提到第 8 秒（解码 / 编译不再压在下载之后），对 CPU 更慢、网络更快的机器收益更大；不节流时出「开始游戏」27.2 → 21.0 秒。
- 本次真正修的是「看不到任何东西 / 静默卡死」：旧内核上从黑屏变成说明原因的失败卡，加载慢、断网、报错都有诊断卡和「重试」。
- 失败路径：屏蔽 `index.01.pck`（404）→ 重试 3 次（约 7 秒）后红色失败卡，分片行标「01.pck 0.0/8.3（失败）」、报错 `index.01.pck HTTP 404`（`build/toy_load_fail404_1116.mp4`）；在加载器脚本开头插 `throw` → 黄色「页面脚本出错」卡，阶段「加载器没有运行」、报错带 `@index.html:行号`；`?oldcore=1` → 红色「内核版本过旧，无法运行」，不下载资源。
- 录像：`build/toy_load_compare_1116.mp4`（上旧下新，4G + CPU 4×，原速 30 帧）。
- 下一步要再快，得动：① 游戏侧启动（`boot_screen.gd` 逐个 `load()` + 渲染预热，CPU 4× 下 40–60 秒，是最大一块）；② 下载量（pck 23 MB gzip）。

## 最低内核（11-17，玩家诊断卡：Android 11 · Chrome 83 WebView · B站 App 9190400）

协调人问能不能把门槛从 Chrome 85 降到 80 左右。**结论：不能靠转译 JS 降，门槛在引擎 wasm，实际是 Chrome 95 / iOS 16.4**（原来按 JS 语法写的 85 偏低）。

逐条解码 c1e0c6c65 Toy 包的 `index.wasm`（39.5 MB，官方 Godot 4.7.2 网页模板 + Emscripten 4.0.20）：

| wasm 特性 | 用量 | Chrome / Safari 起始 |
|---|---|---|
| SIMD（`0xFD` 前缀） | 161,779 条指令 | 91 / 16.4 |
| 旧式异常处理（try / catch / throw / rethrow / delegate，tag 段 1 个） | 41 条 | 95 / 15.2 |
| i64 导入（WASM BigInt 互通，index.js 直接收发 BigInt） | 6 个导入 | 85 / 14.1 |
| 批量内存 / 非陷阱浮点转换 / 符号扩展 | 8663 / 3596 / 1371 条 | 75 / 75 / 74 |

- 交叉验证：node（V8）关掉旧式异常处理（`--no-experimental-wasm-legacy-eh`）后，游戏 wasm 的 `WebAssembly.validate` 直接为 false；默认开时为 true。SIMD 在 node 里关不掉，按解码计数。
- JS 侧：`index.js` 要 ES2021（`??=` / `||=` / `?.`、可选 catch 绑定、`BigInt64Array`），Chrome 85 起都有，被 wasm 门槛盖住。转译 index.js 到 ES2019 没有意义：Chrome 83 过了语法这关也编译不了 wasm。
- 降到 80 左右的唯一办法：用 Godot 4.7.2 源码 + Emscripten 自编网页导出模板，去掉 `-msimd128`、异常改回 JS 实现（不用 `-fwasm-exceptions`）、关 `WASM_BIGINT`（i64 导入拆成两个 i32）。代价：
  - 要搭 Emscripten + SCons 编 Godot 模板（每次升级引擎都要重编，与官方模板行为可能不一致，要全量回归）；
  - JS 异常比 wasm 异常慢、代码大（经验上 wasm 体积 +10–20%、带 try 的调用路径变慢），去 SIMD 后数学 / 渲染批处理变慢——**所有玩家**都吃这份性能；
  - 另出一份兼容 wasm 按需加载：LZMA 后约 6.7 MB，Toy 包现在 49.72 MB、只剩约 0.3 MB 余量，**放不下**；itch 包可以放，但只有 itch 受益。
  - 受影响人群：没装谷歌服务、系统 WebView 停在 2020 年前后的安卓机（截图这台 Android 11 + Chrome 83）。手机自带浏览器 / Chrome 通常更新得上，诊断卡已提示更新「Android System WebView」。
  - 建议：先不做；等诊断卡 / 反馈里「内核过旧」的人数有数了再评估。
- **本次改动**：`loader.js` 内核检查改为直接测引擎要的 wasm 特性——三段几十字节的小 wasm（SIMD：`i8x16.splat` + `popcnt`；异常：`try` + `catch_all`；BigInt：同步实例化一个 i64 恒等导出并用 `BigInt(3)` 调用，字节同 wasm-feature-detect 的检测模块），缺任一项就不下载资源、给「内核版本过旧」失败卡，文案改为「需要 Chrome 95 / iOS 16.4 以上」，诊断卡「报错」行写缺哪项（`WASM SIMD` / `WASM 异常处理` / `WASM BigInt`）。原来 Chrome 85–94、iOS 15–16.3 会过检查、下完 30 MB 才在编译时失败。
- 验证：当前 Chromium 正常进到「开始游戏」；注入脚本让 SIMD 检测模块校验失败（模拟 Chrome 90）→ 2 秒内出失败卡，分片一个都没下。**没有在真正的旧内核（Chrome 83–94）上跑过**（本机没有旧版浏览器，下载旧版 Chromium 需用户同意）。

## 部署（EdgeOne Pages）

> 2026-10-14：本节已作废，留作记录。现行发布走 itch（docs/33「itch.io」「一键发版」）；阿里云 OSS + CDN 骨架见 docs/33，未接通。

- 匿名试部署（无需登录，1 小时内须认领）：`npx -y edgeone makers deploy build/web --anonymous --site china --json`
- 正式部署：`npx -y edgeone makers deploy build/web -n shuiyue-survivors -t <Pages API Token>`（token 放 `.edgeone_token`，已在 .gitignore）
- 2026-09-25 第一次匿名部署成功（项目 makers-rz3tfzqiuxr1）。

## 构建

```
python tools/export_web.py        # 导出 HEAD 到 build/web/（改了 Web 预设还没提交时加 --worktree-presets）
```

一步完成：`git archive` 干净副本 → 把 `art/incoming/*.png` 复制进 `game/art/incoming/`（审稿拼图由 Web 预设 `exclude_filter` 排除）→ Godot 导出 `Web` → **分片** → 内联加载器。需要 Godot 4.7.2 的 `web_nothreads_*.zip` 导出模板（官方 tpz，按 SHA512-SUMS 核对后解压到 `%APPDATA%\Godot\export_templates\4.7.2.stable\`）。

- **分片**（2026-09-26，绕开 25 MB 单文件上限）：`index.pck` / `index.wasm` 按原始字节每 10 MiB 切一片（`--part-mib`），每片 `gzip -9` 成 `index.pck.00.gz` …，删掉原文件；脚本最后逐个检查，有文件超 25 MB 就报错。
- **加载器** `tools/web/loader.js` + `loader.css`：导出时内联到 Web 预设 `html/head_include` 里的 `<!--SHUIYUE_LOADER-->` 处，分片清单（每片字节数、原文件大小）写进脚本。它拦截引擎对 `index.pck` / `index.wasm` 的 fetch，并行下载全部分片、逐片 DecompressionStream 解压、拼回并核对大小后交给引擎（2026-10-11 起改为边下边解压、直接写进整块缓冲，见 docs/33 网页内存一节，9ee13e45）；每片失败自动重试（11-16 起断流 15 秒超时、最多 4 次，失败有提示和「重新加载」，见上文「加载链路」）。游戏代码不动。取代了原来 head_include 里只管 `.wasm.gz` 的拦截脚本。
- **加载画面**（10-25 用户定「声呐测绘」，对照图方向 C 第一张）：网格深底，左上标志（`game/art/ui/title_deep/logo_mark.png` 复制为 `loader_logo.png`，1 KB），中间声呐圈（三道同心圆 + 十字 + 扫描扇面 + 回波点，扇面是 CSS transform 动画，引擎占住主线程时也在转），外圈是进度环、圈心百分比；左下「TERMINAL LOG」逐行 `[ OK ]`：下载资源（x / y MB）→ 解压校验 → 启动引擎（显示已等秒数）；右下「TIPS」4 秒换一句（与 `screens/loading_tips.gd` 同一批）。进度环：下载字节占 0–60%（真实）；下载解压完以后是引擎启动，拿不到真实进度，按已等秒数向 80% 渐近（τ = 6 秒）；引擎起来后由游戏内启动页接着走 80–100%（见下）。引擎移除自带 `#status` 后淡出；引擎报错（`#status-notice`）时也撤掉让报错露出来。矮屏（高 ≤ 520，手机横屏）面板与标志缩小；系统「减少动态效果」时扇面不转。
- **游戏内启动页**（10-25 用户「启动中要加入百分比，然后说明在渲染什么」）：主场景改为 `boot.tscn`（`screens/boot_screen.gd`，只依赖字体、标志、提示表），同一「声呐测绘」版式。启动最慢的一段是读入标题页——`title.gd` 经 preload / extends 一路带出 `game.gd` 与几乎全部脚本（10-25 桌面调试版实测约 12 秒，本机负载高），以前全压在 Godot 静态启动图下。现在启动页按 `game/data/boot_order.json`（`tools/gen_boot_order.py` 生成，叶子在前；GDScript 的 `ResourceLoader.get_dependencies` 不列 preload、导出包里没有源码，所以离线生成）每帧 30 ms 逐个 `load()`，每个只编译它自己，百分比是真实的；圈下写「读取 · 干员积木 / 海嗣 / 战场渲染 …」和当前文件名、条数，左下日志「编译脚本 n / m → 打开标题页」。读完再读 `main.tscn`（都在缓存里）、淡到黑、切标题页。桌面 0–100%；网页接着 HTML 加载页的百分比走（`window.__syPct`），本页第一帧画完就调 `window.__syBootUp()` 让 HTML 加载页淡出（以前要等引擎自带 `#status` 撤掉，那时标题页都出来了，游戏内这一页根本看不到）。新增 / 删改 preload 后跑一次 `python tools/gen_boot_order.py`（`--check` 只比对）；表过期只会让进度粗一点，漏掉的在最后读 `main.tscn` 时一并编译。测试（带命令行参数或无界面）直接进标题页；`--bootshot` 读到一半截 `shot_boot.png` 退出。
- **桌面启动图**：引擎初始化与自动加载（Sfx / Cfg / Pad / Cloud）在启动页之前，拿不到进度，仍由静态启动图盖着：同一版式的静态帧 `game/art/ui/boot_splash.png`（20 KB，256 色，圈心「启动中」），`project.godot` 的 `application/boot_splash/*`，底色 `#070c11`。10-25 前是 Godot 默认启动图。
- 本地试玩要走 HTTP（不能双击 index.html）：`python -m http.server -d build/web 8000`。

云端已跑通：Chromium 手机模拟（844×390，触屏）从标题 → 选难度 → 指南 → 对局 → 摇杆移动全流程正常。产物在 `build/web/`，本地试玩说明见 `build/web/本地试玩.md`。

## 测试开关

`--touch`（桌面强制触屏 UI）、`--touchtest`（自动化：模拟按下-拖动-松开并截图）。

## 待做

- Android APK（需要 Android SDK + JDK 17 + 导出模板；预设可复用本文的触控层）。
- iOS Safari 的全屏 / 音频解锁细节，真机验证。
- 手机上的字号与热区再评估（现在按 1280×720 等比缩放，小屏可能偏小）。
