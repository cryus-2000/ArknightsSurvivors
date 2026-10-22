# 89 B站 Toy 云存档

2026-10-13 用户：「先只做云存档」。排行榜、每日挑战、分享先不做。SDK 说明见主仓库 `.claude/skills/bilibili-toy-sdk/SKILL.md`（未入 git），容器适配见 docs/22 与 `tools/web/container.js`。

## 1. 生效范围

只在同时满足下面几条时启用，否则完全照旧只存本地（itch、普通浏览器、桌面版零影响）：

1. 网页版（`OS.has_feature("web")`），页面里有 `window.__syCloud`（`tools/export_web.py` 内联的 `tools/web/cloud.js`）；
2. Toy SDK 加载成功（`container.js` 只在域名含 bilibili / hdslb 或 UA 含 Bili 时异步加载），且 `toy.isSupport('getCloudStorage')`、`toy.isSupport('setCloudStorage')` 都为真；
3. 启动时第一次 `getCloudStorage` 成功（= 已登录）。云存储只要求登录，不触发数据确认弹窗；本功能不调 `getUserProfile`、不读 `toyOpenId`；
4. 不是自动测试（任何 `--xxx` 启动参数）、不是对内包「全部解锁」（`Cfg.unlock_all`）。

## 2. 本地持久化盘点

全部存档只有一个文件：`user://settings.cfg`（网页版在浏览器 IndexedDB，按网站源隔离），由 `settings.gd` 的 `save()` 整份重写。另外两处 `user://` 写入都不进云：

| 文件 | 内容 | 进云 |
|---|---|---|
| `user://settings.cfg` | 设置 + 进度（下表） | 部分（见下表） |
| `user://runs/runs.jsonl` | 对局记录（docs/40，对内包 / 调试版才写） | 否：对内遥测 |
| `user://normal_cache/*.png` | 法线贴图缓存（art.gd） | 否：可重建的缓存 |

`settings.cfg` 各项：

| 节 / 键 | 含义 | 类别 | 合并 | 写入时机（`Cfg.save()` 的调用点） |
|---|---|---|---|---|
| audio/master music sfx voice | 音量 | 设置 | 较新 | 设置面板关闭 |
| game/dmg_numbers hitstop boss_intro reduce_motion outline | 开关 | 设置 | 较新 | 同上 |
| video/brightness | 亮度 | 设置 | 较新 | 同上 |
| video/ui_size、video/cam_zoom | 界面大小、战斗画面缩放 | 设置 | 较新 | 同上 |
| input/pad_rumble、input/manual_attack | 手柄震动、普攻手动 | 设置 | 较新 | 同上 |
| touch/layout | 触屏按键布局（相对锚点，换比例不跑出屏幕） | 设置 | 较新 | 触屏按键布局编辑页「完成」 |
| game/play_speed | 倍速 | 设置 | 较新 | 局内切倍速（play_clock.gd） |
| display/cover_character | 标题页封面干员 | 设置 | 较新 | 选封面干员 |
| progress/difficulty | 上次选的难度档 | 设置 | 较新（夹到已解锁） | 难度页出发 |
| progress/diff_unlocked | 已解锁最高难度档 | 进度 | 较大值 | 通关（victory_flow.gd） |
| progress/gallery_seen | 图鉴已见敌人 / 物件 | 进度 | 并集 | 局内遭遇（gallery_progress.gd） |
| progress/seen_relics | 获得过的藏品 | 进度 | 并集 | 拿到新藏品（progression.gd） |
| progress/endings_cleared | 已达成结局 | 进度 | 并集 | 通关（endings.gd） |
| progress/seen_shows | 已看演出（目前未使用，恒空） | 进度 | 并集 | — |
| progress/seen_intro、opening_seen | 看过开局指南 / 完整开场 | 进度 | 或 | 关指南 / 播完开场 |
| video/quality fullscreen res_index dof bloom water_filter normal_maps | 画质与窗口 | 设备相关 | **不上云** | 设置面板关闭 |
| progress/diff_ver、video/look_ver | 存档迁移版本 | 内部 | 不上云 | 每次保存 |
| cloud/set_t、cloud/sig、cloud/set_sig | 云存档元数据（下节） | 内部 | 不上云 | 每次保存 |

画质、全屏、分辨率和四项后期跟设备性能走（手机与电脑不同），不上云。

没有其他局外数据：当前版本没有局外货币、局外成长或累计统计（「计数类取较大值」目前只有已解锁难度一项；以后加累计计数时同样取较大值）。

新增的本地字段（`settings.cfg` 的 `[cloud]`）：

- `set_t`：设置最后一次修改的 Unix 秒。`save()` 时把上云设置项的签名和上次比较，变了才更新；旧存档 / 首次启动为 0（没改过设置的新设备会采用云端的设置）。
- `sig`：上次与云端一致时存档正文的签名（md5）。当前正文签名 ≠ `sig` 即「待上传」，重启后也记得。
- `set_sig`：设置部分的签名，供上面的比较。

## 3. 云端格式

逻辑正文（`game/scripts/core/cloud_pack.gd`）：

```json
{"set":  {"t": 1760331000, "d": {"master": 0.8, "music": 0.8, …, "difficulty": 1, "touch_layout": {"dash": {"ax":1,"ay":1,"x":120,"y":200,"s":1.1}}}},
 "prog": {"diff": 1, "gal": ["enemy:bone", …], "rel": ["59", …], "end": ["standard"], "shows": [], "intro": true, "open": true}}
```

上云：正文按排序键转 JSON，非 ASCII 字符转 `\uXXXX`（字符数 = 字节数），每 1000 字节切一片：

| key | value |
|---|---|
| `sy_h` | 头：`{"v":格式版本,"minv":能读它的最低版本,"t":上传时刻 Unix 秒,"n":片数,"len":总长,"md5":全文 md5}` |
| `sy_d0` … `sy_d{n-1}` | 正文分片，每片 ≤ 1000 字节 |

头和全部分片在同一次 `setCloudStorage` 里写；读时一次 `getCloudStorage()`（不带 key = 全部），只认 `sy_` 开头的 key，别的 key 不影响。没有压缩（当前最大不到 3 KB，不值得）；以后需要时在头里加 `"z"` 字段并升 `v`。

平台限制与预算：每 Toy 每用户 ≤ 128 个 key；key `[A-Za-z0-9_-]` ≤ 128 字节、不以 `__` 开头；value ≤ 1024 字节。`cloud_pack.gd` 的 `items_ok` 自检，mock 服务端也按这几条拒绝。

| 项 | 大小 |
|---|---|
| 正文上限 `MAX_CHUNKS` | 48 片 = 48 000 字节，共 49 个 key；超过时不上传（状态「上传失败」，日志写明） |
| 当前全收集实测（264 件藏品、42 条图鉴、全部结局、七个触屏键都自定义） | 2 948 字节 = 3 片 + 头 = 4 个 key |
| 余量 | 正文可再长到约 16 倍；其余 79 个 key 留给以后的功能 |

头 / 分片 / 长度 / md5 / 正文结构不对 → 判为无法读取，不覆盖本地、不自动上传，日志 `[Cloud]` 写明原因。

### 3.1 版本升级不丢档（用户 10-13：「以后 Toy 上发新版本、加新干员，不会覆盖原本的存档吧」）

保证：发新版本、加干员 / 藏品 / 结局 / 设置项，不会清掉或覆盖已有存档。规则写在 `cloud_pack.gd`，单测覆盖：

1. **前向兼容（只加字段）**：新版本新增字段时不升 `minv`。
   - 新版本读旧云档：旧档里没有的字段按缺省补齐（`normalize`：列表空、布尔假、难度 0），合并只按存在的字段算，不清空其他字段；`Cfg.cloud_apply` 遇到缺字段保持本地值。
   - 旧版本读新版本写的云档（多出未知的顶层键 / `set` 键 / `set.d` 设置项 / `prog` 键）：原样保留。合并时未知字段透传（同名时设置跟较新的一份，其余以云端为准）；`Cfg.cloud_apply` 把未知字段记进本地 `[cloud] extra`，之后 `cloud_body()` 原样带回，所以写回本地、读写合并、页面隐藏时直接上传、手动「以本地覆盖云端」都不会丢它们。
2. **版本号只升不降**：回写时头里 `v` / `minv` 取「本版」与「见过的云端版本」（本地 `[cloud] v / minv`）的较大值。
3. **只读保护**：只有不兼容的格式改动才升 `minv`。读到 `minv` 高于本版的云档 → 不读、不合并、不自动上传、清掉网页暂存（页面隐藏时也不写），本地照常玩；设置状态行显示「云存档版本较新，请更新游戏」，「以本地覆盖云端」不可用（提示「请更新游戏」），「从云端恢复」也不改本地。
4. **迁移**：要改格式时写 `v → v+1` 的迁移函数登记在 `MIGRATIONS`，`unpack` 读旧版本存档时逐级执行；单测用两级假迁移验证顺序与触发。
5. **本地存档**：`settings.gd` 读 `settings.cfg` 时每个键单独 `get_value(…, 缺省)`，缺的键用缺省，不会重置整个文件；`save()` 先读回原文件再逐项覆盖，本版不认识的键（更新版本写的）原样保留。

## 4. 同步规则（`game/scripts/cloud_save.gd`，自动加载 `Cloud`）

- **启动**：探测 SDK → 读一次云端 → 校验 → 与本地合并 → 合并结果和本地不同就写回本地（`Cfg.save()` + `Cfg.apply()`）→ 和云端不同（含云端为空）就上传。
- **合并**（`cloud_pack.gd merge`）：图鉴 / 藏品 / 结局 / 演出取并集（本地顺序在前）；已解锁难度取较大值；看过指南 / 开场取「或」；设置整组取 `set.t` 较新的一份，一样新用本地。采用云端设置时 `set_t` 取云端的值，不算本机新修改。
- **本地保存**：`Cfg.save()` 末尾调 `Cloud.local_saved()`：只标「待上传」，并把打包好的内容交给网页（`__syCloud.stage`）。不联网，所以拾取 / 遭遇触发的保存不会变成请求。
- **上传时机**：一局结算（胜 / 负，game.gd）、回到标题（title.gd `_ready`）、设置面板关闭（settings_panel.gd）、页面隐藏（`visibilitychange` 变 hidden / `pagehide`，由 cloud.js 直接把 stage 的内容写上去，那时引擎可能已停帧）。前三个调 `Cloud.flush()`：只有待上传时才排队；去抖 1 秒（同时到的触发合成一次）；两次联网至少隔 10 秒。
- **每次上传前先读云端再合并**（读 → 合并 → 写，两次请求）：另一台设备期间写过的进度不会被覆盖。页面隐藏时的直接写入没有先读，另一台设备同时在玩时可能盖掉对方刚写的内容；对方下次同步时会按并集重新写回进度，设置按时间取新。
- **失败**：
  - 读写 reject 时本地照旧，保留「待上传」，不阻塞游戏；
  - `307044` 限流：指数退避，5 秒起翻倍，封顶 300 秒，到点自动重试；
  - 其他错误：60 秒起翻倍，封顶 600 秒，到点自动重试，状态「上传失败，稍后重试」；
  - 启动时第一次读就失败（非限流）按「未登录（仅本地保存）」处理，本次运行不再请求：云存储和排行榜的频率额度全 Toy 共享，未登录的玩家不消耗。
- **手动入口**（设置 → 存档页，只在 B站环境出现）：
  - 「云存档」状态行：已同步 / 同步中 / 待上传 / 上传失败，稍后重试 / 未登录（仅本地保存）/ 云端存档无法读取（仅本地保存）/ 云存档版本较新，请更新游戏。点一下 = 立即同步（有待上传时）。
  - **10-22 用户定去掉这两个手动入口**：设置「存档」页只留云存档状态一行（点一下立即同步）；下面两条的代码（`Cloud.pull` / `Cloud.push`）与单测保留，不再在设置里列出。
  - 「从云端恢复」：云端存档整份替换本机进度与设置（不合并）。云端为空 / 无法读取 / 版本更新时不动本地。
  - 「以本地覆盖云端」：本机存档整份写到云端（不合并），云端无法读取时也可以用；云档版本较新时不可用（只读保护）。
  - 两个按钮都要在 4 秒内点第二次确认（按钮变金色「确认恢复」/「确认覆盖」）；未登录时显示「登录后可用」。

## 5. Godot ↔ JS

`tools/web/cloud.js`（导出时接在 `container.js` 后面内联进 index.html）提供 `window.__syCloud`，Godot 经 `JavaScriptBridge.get_interface("__syCloud")` 调用，Promise 转回调（参数都是字符串）：

| 方法 | 说明 |
|---|---|
| `probe(cb)` | 等 `container.js` 的 `window.__syToyWait()`（SDK 加载成功 / 失败 / 8 秒超时 / 非 B站环境时给出 `window.toy` 或 null），回 `"supported"` / `"unsupported"` |
| `read(cb)` | `toy.getCloudStorage()` → `cb("ok", JSON)` / `cb("err", {code,type,msg})` |
| `write(json, cb)` | `toy.setCloudStorage(items)` → `cb("ok", "")` / `cb("err", …)` |
| `stage(json)` | 存下最新打包内容（空串清掉），页面隐藏时自动上传一次 |

方法名不用 `get` / `set`：`JavaScriptObject` 上这两个名字会调到 Godot `Object.get / set`。

## 6. 测试

### 单元测试（快检场景回归 `cloud_save`）

`python tools/check.py --only cloud_save --jobs 3`（`game/tests/cloud_save_test.gd`，快检默认也跑）：

- 打包：小存档 1 片 + 头；大存档多片，每片 ≤ 1024 字节；非 ASCII（含超出基本平面的字）往返一致；平台限制自检（`__` 开头、非法字符、超长 value、129 个 key 都拒绝）；超过 48 片拒绝打包；打印当前全收集的实际大小；
- 校验：缺片、篡改、头坏、正文结构坏都判为无法读取；`minv` 高于本版判 newer；版本 0 判无法读取；没有头 = 空；云端有别的 key 不影响；
- 版本升级（§3.1）：旧格式云档缺字段按缺省补齐、与本地新增的干员字段合并后都在；`Cfg.cloud_apply` 遇到缺字段不清空本地列表；v2（minv 1）云档带未知的顶层 / set / set.d / prog 字段，本版读、合并、写回本地、再取正文、再打包都不丢，头里 v 不降；`minv` 高于本版只读、不给正文；迁移逐级按顺序执行、读旧档时触发；状态行「云存档版本较新，请更新游戏」且不许覆盖云端；
- 合并：并集、较大值、或、设置取较新、一样新用本地、云端为空 = 本地、幂等、int / float 不影响签名；
- Cfg：`cloud_body` ↔ `cloud_apply` 往返；越界项夹取（界面大小到 5 的倍数、缩放到上限、已解锁难度到最高档）、类型不对 / 不存在的干员 / 不合法倍速保持本地值；触屏布局清洗；采用云端设置后签名同步；
- 非网页平台：`Cloud` 为 OFF、不发请求、没有状态行。

### 网页 mock

```
python tools/export_web.py --out build/web_cloud
python tools/web_cloud_mock.py --dir build/web_cloud --ports 8811,8812
```

`web_cloud_mock.py` 把同一份包开在两个端口（网站源不同 = 两台设备，各自的 IndexedDB 本地存档），返回 index.html 时在 `<head>` 最前面注入 `tools/web/toy_mock.js`（假 `window.toy`，读写转发到进程内存里的一份云端；网址带 `?toyc=phone` 时同时模拟容器接口，见 docs/22「Toy 接入」）。Toy 包（`export_web.py --toy`）也能这样测：`container.js` 遇到页面里已有的 `window.toy` 不再加载真 SDK。`POST /__mock/ctl` 切换未登录 / reject N 次 / 307044 N 次 / 清空，`GET /__mock/state` 看云端内容与请求日志（时间戳）。发布包里没有 mock。

验收步骤（2026-10-13 实测结果见 §7）：

1. 设备 A 首次进入：云端为空 → 上传（日志 1 读 1 写，云端出现 `sy_h` + 分片）；设置 → 存档页显示「已同步」；
2. 设备 A 改设置（如界面大小）后关设置面板 → 去抖后读 + 写；
3. 设备 B（另一端口，本地存档不同）进入：读到 A 的存档并合并，设置采用 A 的（B 的设置没改过，`set_t` = 0）；
4. 刷新 B：本地已保存合并结果，状态仍「已同步」，不再上传；
5. 限流：`{"ratelimit": 3}` 后触发同步，日志里重试间隔约 5 / 10 / 20 秒（受 10 秒最小间隔约束），最后成功；
6. 未登录：`{"login": false}` 后刷新 → 状态「未登录（仅本地保存）」，之后不再发请求；
7. 手动入口：「以本地覆盖云端」「从云端恢复」点两次生效。

### 真机

**需在 B站 App（iOS / Android）与 B站网页端真机验证**：登录 / 未登录、首次上传、换设备合并、页面切后台时上传、307044 提示。mock 只验证本地逻辑，平台真实的错误类型 / 错误码（未登录时 reject 的 `type` / `code`）和限频额度以真机为准；如果真机里未登录的错误能明确识别，可以把「首次读失败按未登录处理」收窄到只认这个错误。

## 7. 实测记录（2026-10-13，网页导出 04934f77 + mock，内置浏览器 1280×720）

| 步骤 | 结果（mock 请求日志） |
|---|---|
| 设备 A 首次进入 | 1 读 1 写，云端出现 `sy_h` + `sy_d0`（422 字节）；存档页「已同步」 |
| A 改主音量后关设置 | 去抖后 1 读 1 写 |
| 设备 B 首次进入 | 1 读，不写（合并结果与云端相同）；B 的主音量变成 A 的 90 |
| 模拟新版本写入（v2 / minv 1，多出顶层 `ops`、`set.d.new_setting`、`prog.ops_seen`，另加藏品 59 / 67） | B 改设置关面板后 1 读 1 写：上传结果仍是 v2，未知字段都在，藏品并集 |
| 刷新 B | 1 读，不写，设置保持 |
| 限流 `ratelimit: 3` 后 B 改设置 | 读失败 3 次（307044），间隔 5.4 / 10.4 / 20.5 秒，第 4 次读成功并写入 |
| B 换封面干员（只本地保存，不触发上传）后模拟页面隐藏 | cloud.js 直接 1 写（无读），云端封面变为新干员、v2 与未知字段保留 |
| 云档头改成 v3 / minv 3，刷新 B | 1 读，不写；状态行「云存档版本较新，请更新游戏」，「以本地覆盖云端」显示「请更新游戏」 |
| 云档分片截短（md5 不符），刷新 B | 1 读，不写；状态行「云端存档无法读取（仅本地保存）」 |
| 「以本地覆盖云端」点两次 | 第一次按钮变金色「确认覆盖」，第二次 1 写，状态「已覆盖云端存档」，云端恢复可读（v2、未知字段保留） |
| 云端主音量改 30 后「从云端恢复」点两次 | 1 读，本地主音量变 30，刷新后仍是 30 |
| `login: false` 刷新 B | 1 读失败（-101），状态「未登录（仅本地保存）」，之后改设置关面板不再请求 |
| 恢复登录后 `reject: 1`，B 改设置关面板 | 读失败（500），状态「上传失败，稍后重试」；60 秒后重试读写成功 |

注：内置浏览器面板隐藏时页面不出帧（requestAnimationFrame 暂停），Godot 里的退避计时到页面重新显示后才发出重试。真机上页面在后台时同样不出帧；离开页面时的上传由 cloud.js 的 `visibilitychange` / `pagehide` 负责，不依赖引擎出帧。

截图（不入库）：会话草稿目录 `cloud_shots/1_synced_deviceA.jpg` … `9_upload_failed_retry.jpg`。
