# 317 Toy 首发前两项修复（11-07）

用户在 Toy 预览（main ed28cd083）上实测发现两个问题，协调人派活。两项都修完 Toy 才提交审核。

## 1. 引导卡和提示卡叠在一起

**现象**：新手引导演示局第 7/7 张「指挥 · 集火」教程卡打开时，正式局的提示卡「TIP · ELITE 精英海嗣」叠在它上面，两张互相挡字。

**原因**：两张卡来自两套系统：
- 引导卡：`screens/onboard.gd`；
- 到点小提示：`screens/tour.gd`。

两套都画在左上角同一个位置（桌面 (16, 112)，触屏 (16, 72)），互相不知道对方。集火这一步会在队长身边放一只精英，正好触发「第一次遇到精英」提示。

**修法**：
- `onboard.card_busy()`：这些情况下都算引导占着左上角——演示局进行中、有引导卡在显示或收起、问题框打开、演示图鉴打开。
- `tour._held()` 为真时：
  - 正在显示的提示放回队首，新触发的只排队，计时不走；
  - 等引导空了，按顺序从头再弹。
- 提示不会丢：「每样只弹一次」的记录照常写进存档。
- 回归：`tests/tour_test` 的 2b 段，用 `hold_test` 模拟引导占着 / 让开。

## 2. 点出网页之后不好操作

**现象**：网页失焦后操作变得不顺，包括点到页面外、切标签、B站 App 里切出再回来。

**原因**（按代码查；没有在网页上实机复现）：
- 失焦以后，浏览器不再给画布发按键和触点的「抬起」。
- 本作有好几处自己记着的「按住」状态，会因此卡住：
  - 触屏摇杆手指 `touch.stick_id`：继续推着走；
  - 技能 / 普攻 / 终结技键的触点：一直算按着；
  - 按住 F 打开的指挥圆盘：回来后 F 被当成松开，**把当时悬停的指令确认了**；
  - 选点阶段；
  - 移动键：`Pad.key_down` 轮询 `Input.is_key_pressed`。
- 回到页面时，焦点常停在页面别处，要先点一下画布按键才有反应。

**修法**：`scripts/web_focus.gd`，由 `game.gd` 接线。

1. **检测失焦**：
   - 网页：JS 监听 `window blur`、`visibilitychange`（hidden）、`pagehide`，记一个计数，Godot 每 0.2 秒轮询一次；
   - 所有平台：`NOTIFICATION_APPLICATION_FOCUS_OUT`、`WM_WINDOW_FOCUS_OUT`、`APPLICATION_PAUSED` 由 `game._notification` 转进来。
2. **网页版对局中失焦就自动暂停**。在选卡、商店这类非对局状态下失焦，回到对局时补一次暂停。暂停放在清状态之前，补发的「松开」事件不会落进对局（比如松开 Q 放出终结技）。
3. **清掉按住状态**，只取消、不确认：
   - 取消圆盘和选点；
   - 触屏 `touch.release_all()`：清掉摇杆、技能、普攻、滚动的触点和槽位表；终结技瞄准按松手处理，和原来切后台的保险一致；
   - 给仍按着的局内键（WASD、方向键、Shift、空格、F、Q、E 等）和鼠标键补「松开」事件。
4. **回到前台**（`focus` / `visibilitychange` visible）时，`canvas.focus()` 把焦点还给画布。

桌面版只做第 3 条，不自动暂停。带调试参数运行（测试、录像、批跑）时，桌面上整段跳过：这类窗口常在后台、焦点来回切，免得把计划里打开的圆盘或合成的按键清掉。测试用 `--focustest` / `--focuspause` 打开。

**回归**：`check.py --only web_focus`（`tests/web_focus_test`），覆盖：
- 摇杆手指、D 键按着时失焦：都松开，对局自动暂停；
- 按住 F 打开圆盘时失焦：圆盘取消，阵型不变（没有当成确认）；
- 选点中失焦：选点取消；
- 选卡中失焦：状态不变，回到对局时补一次暂停。

**还没验证**：没有出网页包在浏览器里实机点出页面再回来。上 Toy 预览后要实测一次：点到页面外、切标签、在 App 里切出再回来，三种情况都要看。

## 3. 从别的 App 切回来没声音（用户 iPhone B站 App 实测）

**原因**：iOS / WebKit 会把网页音频的 AudioContext 挂起（suspended）或中断（interrupted，来电、切 App），回到前台不会自己恢复；不在用户手势里调用的 `resume()` 也常常不生效。原来 `tools/web/power.js` 的手势监听在第一次全部 running 后就撤掉了，回来后再也没有手势去唤醒。

**修法**（`tools/web/power.js`）：

1. 回到前台（`visibilitychange` 变可见、`pageshow`、`focus`）时，对每个上下文先调一次 `resume()`，同时重新挂上手势监听。
2. 手势监听覆盖 `touchstart`、`pointerdown`、`pointerup`、`touchend`、`click`、`mousedown`、`keydown`。下一下手势里唤醒全部上下文；全部 running 后再撤掉监听。
3. 每个上下文监听 `statechange`：页面在前台时状态掉回非 running（包括 interrupted），就重新挂上手势监听。
4. `resume()` 不改各总线音量。Godot 的总线增益在音频图里，挂起只是停了时钟，所以不会爆音。

**暂停菜单**：失焦自动暂停时，暂停菜单多一句金色提示：「离开过页面，已自动暂停 · 点击「继续」回到作战」，桌面版加「或按 Esc」。点「继续」这一下同时唤醒声音。

**测试**：`node tools/web/power_selftest.js` 用假的 AudioContext 模拟 iOS 行为：手势外调 `resume()` 无效，系统可以把它打成 interrupted。依次覆盖：
- 第一次点按解锁；
- 切到后台挂起；
- 回到前台时非手势 resume 无效，重新挂上监听；
- 第一下 touchstart 恢复；
- 前台被中断（interrupted）后，下一下 pointerdown 恢复；
- 恢复后监听撤掉。

**还没验证**：iPhone 真机要由用户实测。
