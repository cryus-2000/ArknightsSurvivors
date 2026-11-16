# 350 自由更改键位（11-16）

状态：已实现，分支 `claude/festive-khayyam-3460f3`，待协调人合入（V2.1 同批）。用户 11-16 要求「加自由更改键位」，全平台（Windows 桌面、itch 网页、B站 Toy）。

## 1. 入口与界面

- 设置 → 操作 →「键位设置」→「调整」，打开 `screens/keybind_view.gd`（盖在设置面板上，同性能报告页 / 触屏布局编辑页）。所有设备都列出；B站 App 里多半是触屏，点开不报错，点格子只进等待、点别处取消。触屏按键布局仍在「触屏按键布局」改，不动。
- 两页：**键鼠** / **手柄**（Q / E、LB / RB 或点页签切换）。每个动作两格：主键 + 备用。
- 改键：点格子（或选中按 Enter / Ⓐ）→ 格子变金色「按下新按键…」→ 下一次按键 / 鼠标键（手柄页：按钮 / LT / RT）即新绑定。等待中 Esc 取消、Delete / Backspace 清空这一格；6 秒没按自动取消。
- 冲突：新键已被别的动作占用 → 弹框「已被『X』占用，交换？」：交换 = 对方拿到这一格原来的键（原来是空就变空）；取消 = 不改。
- 每页「恢复默认」只恢复本页（键鼠页不动手柄页）。
- 底部说明：网页版加一句「网页版不能绑定浏览器保留键（F5、F11、F12、Ctrl、Alt 等）」。

截图（11-16，键位已改过演示）：`build/kb/shots/`（keybind_kb / keybind_pad / keybind_conflict / guide_controls_rebound，各 zh / en）。

## 2. 可改的动作（12 个；手柄页 7 个 + 2 个固定项）

| 动作 id | 名称 | 键鼠缺省 | 手柄缺省 | 说明 |
|---|---|---|---|---|
| up / down / left / right | 向上 / 下 / 左 / 右移动 | W / ↑、S / ↓、A / ←、D / → | 左摇杆（固定） | 轮询（`PlayKeys.held`） |
| dash | 冲刺 | 空格 / Shift | Ⓑ / RT | 原 K 键去掉（两格） |
| ult | 终结技 | Q | Ⓐ / RB | 按住瞄准、松开释放；ult/on = 0 时为旧手动技能 |
| aim | 按住瞄准 | 鼠标左键 | 右摇杆（固定） | 绑到键盘键时朝光标打 |
| command | 指挥圆盘 | F | LB / LT | 按住选、松开确认 |
| speed | 倍速 | V | — | |
| stats | 属性面板 | Tab / C | SELECT | 面板里 Tab / Esc 也能关 |
| pause | 暂停 | **Esc（固定）** / P | **START（固定）** | 备用格可改；P 原只在网页版有，现在全平台缺省 |
| music | 音乐开关 | M | — | |

不开放（界面导航，保持缺省）：确认 Enter / Ⓐ、返回 Esc / Ⓑ、方向键 / 十字键导航、暂停菜单里的 O / G / H / T / R、商店 1–5 / F / E、选卡 1–9、F8（调试）。

不许绑：Esc（暂停 / 返回，防止锁死）、Win / Meta、PrintScreen、滚轮；网页版另禁 F1 / F3 / F5 / F6 / F7 / F11 / F12、Ctrl、Alt（Ctrl+W 之类关页）、鼠标侧键（浏览器前进后退）；手柄 START、十字键（对局里是移动）。

## 3. 实现

- `core/play_keys.gd`：唯一的动作表（`ACTIONS`）+ 当前绑定（静态表）。键码编码：键鼠 0 = 空、> 0 键码、< 0 = -鼠标键；手柄 -1 = 空（JOY_BUTTON_A = 0）、扳机 `PAD_LT / PAD_RT` = 100 / 101。接口：`act(event)`（键 / 鼠标键 / 虚拟键 → 动作）、`held(id)`、`pad_action(b)`、`bind / owner_of / forbidden / reset_page`、`overrides / apply`（存档）、`primary / both / cur / fill / move_text`（键名）。
- `game.gd`：`_unhandled_input` 先 `PlayKeys.act` 翻成动作，`_action_press` 分派（冲刺 / 终结技 / 倍速 / 圆盘 / 属性 / 暂停 / 音乐）；鼠标键绑的动作同一入口；移动四向读 `held`。
- `pad.gd`：对局（context = play）里按钮 / 扳机按绑定翻成该动作的**虚拟键**（`VK_BASE = KEY_F25` + 动作序号）注入；按住型（终结技 / 圆盘）按住期间保持虚拟键按下，离开对局补松开。菜单上下文照旧（Ⓐ = Enter …）。
- `doctor.gd`（按住瞄准、旧手动技能蓄力）、`command_wheel.gd`（按住圆盘、取消键、提示）读 `PlayKeys`。
- 键名提示：HUD（冲刺 / 瞄准牌、开局提示、属性提醒、指挥标签、藏品栏提示、属性面板返回）、终结技瞄准提示、指南（`data/guide.json` 用 `{move2} {dash} {ult} {aim} {cmd} {stats2} {music} {speed} {p_dash} {p_ult} {p_cmd} {p_stats}` 占位，`intro.fill_numbers` 填）、新手引导（`data/onboard.json` 同上，`onboard.text_of` 先查表再填）、终结技说明（`data/ult_text.json` `{ult}`）、开局聚光引导、技能说明里的「队长按 %s 释放」。英文 / 日文 / 韩文的整句先查表再填键名（填完的句子查不到表）。
- 存档：`settings.cfg [input] keybinds`（只写改过的动作）+ `keybinds_set`；`Cfg.load_keybinds / save_keybinds`；云存档见 docs/89 §3。

## 4. 测试

快检 `keybind`（`tests/keybind_test.tscn`，53 项）：绑定表改绑 / 冲突 / 交换 / 锁定 / 网页保留键 / 坏存档清洗、ConfigFile 往返、旧存档缺省、云存档写出与读回、局内改键生效（L 冲刺、空格不冲；手柄 Ⓧ 冲刺、Ⓑ 不冲；I 向上、W 不动；鼠标侧键倍速；Y 暂停 / 继续、Esc 仍暂停；J 属性面板）、键名提示与指南「操作」页、键位页等新键 / 冲突框交换 / Esc 只取消 / 恢复默认 / 切页。
截图：`python tools/keybind_shots.py zh en`（窗口模式屏外，`--kbshot=<目录>`）。
