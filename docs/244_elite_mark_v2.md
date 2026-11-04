# 精英标识去红描边（审阅开关）

基于 `origin/claude/integ-1105` 的 `e80a39eb2`，任务单 `Claude outputs/codex_tasks_1105.md` 单子3。

`render/elite_mark_v2` 默认0。开启后：

- 普通精英头顶白色阶梯▼，每一阶厚4屏幕像素（2美术像素），黑色细底分离背景；原橙红短血条改中性灰白。
- 用户纠正双杠并反馈太鲜红后，精英小队使用与普通精英一致的▼轮廓，颜色为沉珊瑚红 #b96b70、alpha=1，保留暗底。普通精英仍为浅色▼。红色只占小标记，不恢复整身红描边。双杠版413c10cdd已撤出当前候选。
- 非祝福精英和小队取消常驻轮廓，小队也不再周期闪白；小队不画短血条。伊莎尔祝福是明确例外，保留其特殊红色描边，优先于 v2。
- 现有原生 `_emit` / 帧条亮点提供物种颜色，末一个光点明暗呼吸；光学关闭时仍画这一处小点，不加扩散圈。
- 普通怪和Boss画法、体型、血量、伤害、敌人状态机不变。0时回原有分支。

## 画法缓存

开启时，非Boss的精英或小队成员由 `_dc_ok` 排除，走 `_draw_enemy_full`，保持完整绘制与物种光点路径。普通怪仍可缓存。截图探针带 `--dccheck`，验证实际普通怪缓存路径，并断言目标精英/小队确实被排除。

## 复现

本地只做短sanity和必须看图的离屏采样：

```
python tools/elite_mark_v2_review.py import
python tools/elite_mark_v2_review.py sanity
python tools/elite_mark_v2_review.py shots
```

截图探针通过正式 `spawner.spawn_enemy` 创建普通怪、精英与精英小队，在正常地图同屏排布。冻结模拟，在同一时刻切换实际 Bal 开关；不是两局不同时刻的拼接。`off.png` / `on.png` 为4.5秒，`no_flash.png` 为6.05秒，验证旧闪边时刻也无白边。此场景是标记审阅，不伪称自然后期局。

当前输出 `build/elite_mark_v2/revision_4/`，前三版证据保留，不覆盖；不提交build文件。完整 `check.py --auto --jobs 3` 与同种子TRACE交由云端统一跑，不能用短sanity代称全部通过。

本地已验证：5秒sanity与同屏截图运行均无SCRIPT ERROR/Parse Error；截图运行输出 `ELITE_MARK_REVIEW` 的 `dc_checked` > 0，证明实际执行过普通怪缓存比对。存在退出时ObjectDB / resources泄漏提示，未宣称所有引擎日志无报错。首次新工作树导入不完整（缺字体及UI缓存）造成加载失败，复制集成树已有导入缓存后重新执行通过；未修改资产或检查器掩盖错误。


## revision_4 审核修正

按 CLAUDE_REVIEW 和用户确认，保留普通精英白三角+血条、小队沉珊瑚红三角和暗底；去掉小队血条与周期白闪。祝福的特殊红描边优先，属于保留的机制提示例外。

`verify_marks` 调用正式 HUD 的 `_elite_mark_batch` 验证小队只有6个标记矩形（24顶点），精英还有2个血条矩形（32顶点），并验证颜色。遍历旧闪边前后7个时刻、两档开关、精英/小队组合检查祝福描边与颜色优先，默认关闭仍保留小队旧描边。批次提取只将原来的提交点移到调用者，未改变关闭路径几何。

`python tools/elite_mark_v2_review.py late` 从 seed=11 的自然模拟运行到480秒起，每秒取一张、共16张原尺寸截图，无敌人排布、增删或位置调整。测试文案修复来自协调分支 f0002aea8，单独 cherry-pick 为 2ffe93bba。

本轮短程结果：`sanity` 与 `shots` 均无 SCRIPT ERROR / Parse Error；`ELITE_MARK_RULES PASS`，`dc_checked=11`。已目视 `compare.png` 与 `mark_3x.png`，小队不再有血条或旧周期白边，白色精英血条与沉珊瑚红三角保持。用户视觉验收及当前 SHA 云端完整检查仍另行进行。
