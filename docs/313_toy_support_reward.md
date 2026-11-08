# 313 B站 Toy「支持作者」奖励（11-07）

用户 11-07 定，协调人派活。

## 1. 规则

两项奖励，各只能领一次：

| 奖励项 | 条件 | 奖励 | 配置 |
|---|---|---|---|
| 关注作者 | 已关注当前 Toy 的作者 | 寻访凭证 ×5 + 专属结算分享卡边框 | `toy/support_follow`：1 = 显示（首发后的版本再打开就改成 0 / 1） |
| 三连视频 | 对指定视频点赞 + 投币 + 收藏 | 寻访凭证 ×5 + 专属结算分享卡边框 | `toy/support_bvid`：视频 BV 号，留空时照样列出、置灰写「PV 发布后开放」（11-08） |

- **边框**：两项都送，**领了任意一项就解锁**（11-08 用户，`toy_support.frame_unlocked`）。凭证照旧各 5 张。
- **不做称号**。不解锁干员、数值、难度。
- **不设任何门槛**（docs/99：至少有免交互可玩内容，主线不强制关注）。不领也不影响正常游玩。
- **只在 Toy 版出现**。判断方法同意见反馈：页面里有 `window.toy.navigate`。itch、桌面版完全不出现。
- **领取记录**：`Cfg.toy_support`（`"follow"` / `"triple"`），存本地 `settings.cfg [toy] support`。
  - 云存档正文带 `prog.tsup`，合并取并集（`cloud_pack` 的 `LIST_KEYS` / `OPTIONAL_KEYS`）。没领过的存档不写这个字段，往返与旧版本逐字相同。
  - 边框按合并后的列表判断：两台设备只要有一台领过任意一项，合并后就算解锁。
  - 凭证直接加进 `roster_tickets.hunt`，随现有云存档同步。
- **前端校验可以被破解**，无所谓：奖励本来就是附加的。

## 2. 入口与界面

- **入口只有两处**（11-08 用户；结算页的入口已去掉）：
  - **标题页**：左侧档案组「支持作者」（心形图标），还有没领的就带角标「领 N 张」，两项都算，最多 10 张；
  - **寻访页**：凭证不够寻访一次、且还有没领的奖励时，兑换框下面一枚按钮「支持作者：关注 +5 · 三连 +5 张寻访凭证 ›」（领过的那项不写）。
  - 点了都打开同一个浮层。
- **浮层** `screens/support_view.gd`，版式跟意见反馈浮层一致：
  - 标题「支持作者」SUPPORT；
  - 一句说明：「在 B站 App 里关注作者、三连视频，可以领取下面的奖励。每项只能领取一次，不影响正常游玩。」
  - 关注作者、三连视频两张卡并排，都写「寻访凭证 ×5」和「专属结算分享卡边框」，各一枚「领取」按钮（已领取 / PV 发布后开放时置灰），没满足时在按钮上方写原因；
  - Enter 把能领的都查一遍，Esc 关闭。
- **查询结果的提示**：

  | 结果 | 提示 |
  |---|---|
  | 满足 | 「已领取：寻访凭证 ×5和专属分享卡边框」；边框已经解锁过的，只写「已领取：寻访凭证 ×5」 |
  | 没关注 | 「还没有关注作者」 |
  | 三连缺项 | 「三连还差：投币、收藏」 |
  | 外部浏览器 / 不支持（`unsupported`） | 「请在 B站 App 中打开」 |
  | 没登录 | 「请先登录 B站账号」 |
  | 其他错误 | 「暂时无法查询，请稍后再试」 |

  遇到环境问题（unsupported / 没登录 / 出错）只提示一次，不再查下一项。
- **专属分享卡边框**：关注、三连领过任意一项以后，结算「分享战绩」卡面加一圈金色细框、四角加粗折角，底边正中一块「SUPPORTER」小牌（`share_card._polaroid` 的 supporter 款，11-08 改成黑底金边拍立得）。导出图也带。

## 3. SDK 接法

网页端薄封装是 `tools/web/support.js`，由 `export_web.py` 接在 share.js 后面内联。Godot 侧通过 `JavaScriptBridge.get_interface("__sySupport").check(kind, bvid, cb)` 调用。

- `follow`：`toy.getAuthorRelation()`。
- `triple`：`toy.getVideoUserActions({ videos: [{ bvid }] })`，`liked`、`coinCount > 0`、`favorited` 三项都满足才算。
- 两个调用之前都先 `toy.isSupport`。外部浏览器里不支持或抛 `unsupported`，统一回 `"unsupported"`。
- 关注状态的字段名，SDK 文档里没给，按几种常见写法兼容着读：`isFollow` / `is_follow` / `following` / `follow` / `attention` / `relation.*`。都读不出时按「出错」处理，既不误发奖励，也不误报「没关注」。
  - **首次上 Toy 时，用真实账号核对一次返回结构**，读不出就补字段名。
- 只读互动状态：不读 `toyOpenId`，不上传，不打日志。

## 4. 测试

- **Godot 回归**：`check.py --only toy_support`（`tests/toy_support_test`，参数 `--fbtoy --toybv=…`）。覆盖：
  - 关注 yes / no、三连 yes / 缺项、unsupported、没登录、出错；
  - 每项只发一次，领任一项解锁边框（只领三连也算），云存档合并后任一项在就解锁；
  - 统一入口文案、角标两项合计、三连未开放领不了；
  - 云存档正文带 tsup，两台设备取并集；没领过的不多出字段；
  - 浮层遇到 unsupported 停止查询。
- **JS 自测**：`node tools/web/support_selftest.js`。用假 `window.toy` 覆盖 10 种返回，含不包 data、`result.items`、`item.ref`、isSupport 为假、抛错、没有 SDK 几种情况。
- **本地网页**：`tools/web_cloud_mock.py` 的假 SDK 支持 `?toysup=follow,triple`（已关注 / 已三连）。不带这个参数时等于外部浏览器。
- **截图调试参数**（只在调试版读）：
  - `--fbtoy`：按 Toy 环境走；
  - `--toybv=<BV>`：覆盖三连视频；
  - `--supopen`：标题页截图时盖上浮层；
  - `--supcheck`：顺手点一次「检查并领取」；
  - `--toysim=follow:yes,triple:no:coin`：桌面上模拟 SDK 返回；
  - `--supframe`：分享卡强制带边框；
  - `--shareopen`：结算入场演完就打开分享卡。
