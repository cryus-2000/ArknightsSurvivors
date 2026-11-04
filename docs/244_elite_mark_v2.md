# 精英标识去红描边（审阅开关）

基于 `origin/claude/integ-1105` 的 `e80a39eb2`，任务单 `Claude outputs/codex_tasks_1105.md` 单子3。

`render/elite_mark_v2` 默认0。开启后：

- 精英和精英小队头顶白色阶梯▼，每一阶厚4屏幕像素（2美术像素），黑色细底分离背景；原橙红短血条改中性灰白。
- 精英取消常驻轮廓；精英小队每3秒同步闪白描边0.15秒，使用游戏时钟，不抽随机数。
- 现有原生 `_emit` / 帧条亮点提供物种颜色，末一个光点明暗呼吸；光学关闭时仍画这一处小点，不加扩散圈。
- 普通怪和Boss画法、体型、血量、伤害、敌人状态机不变。0时回原有分支。

## 画法缓存

开启时，非Boss的精英或小队成员由 `_dc_ok` 排除，走 `_draw_enemy_full`，避免同步闪边状态漏入缓存签名。普通怪仍可缓存。截图探针带 `--dccheck`，验证实际普通怪缓存路径，并断言目标精英/小队确实被排除。

## 复现

本地只做短sanity和必须看图的离屏采样：

```
python tools/elite_mark_v2_review.py import
python tools/elite_mark_v2_review.py sanity
python tools/elite_mark_v2_review.py shots
```

截图探针通过正式 `spawner.spawn_enemy` 创建普通怪、精英与精英小队，在正常地图同屏排布。冻结模拟，在同一时刻切换实际 Bal 开关；不是两局不同时刻的拼接。`off.png` / `on.png` 为4.5秒，`squad_flash.png` 为6.05秒闪边示意。此场景是标记审阅，不伪称自然后期局。

输出 `build/elite_mark_v2/`，不提交build文件。开启后的美术方向仍需用户看对照图认可。完整 `check.py --auto --jobs 3` 与同种子TRACE交由云端统一跑，不能用短sanity代称全部通过。

本地已验证：5秒sanity与同屏截图运行均无SCRIPT ERROR/Parse Error；截图运行输出 `ELITE_MARK_REVIEW` 的 `dc_checked` > 0，证明实际执行过普通怪缓存比对。存在退出时ObjectDB / resources泄漏提示，未宣称所有引擎日志无报错。首次新工作树导入不完整（缺字体及UI缓存）造成加载失败，复制集成树已有导入缓存后重新执行通过；未修改资产或检查器掩盖错误。
