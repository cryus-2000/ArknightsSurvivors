# 材质粒子试稿交付给 Claude（2026-10-24）

分支：codex/particle-materials。用户要求交付当前工作，明确排除歌蕾蒂娅。本批未获全部视觉认可，不是发布完成。

## 范围与依赖

依赖 Claude 的 CPU 粒子模板提交 12a9dc6ac；本工作树原先以未提交 cherry-pick 引入，该依赖涉及 docs/136、docs/50、world/optical/vfx/autotest。接手时如主线已包含模板，保留主线新版并人工移植本批增量，不要覆盖新版。

交付：共享材质粒子池、艾雅火球/熔岩/点燃爆燃、拉普兰德剑气本体转碎片、固定演示脚本和轻量契约。
排除：歌蕾蒂娅所有新增水滴、滑行、牵引、龙卷模板与演示；gladiia_water.gd 未启用实验不提交。通用 fx_water_splash 是此前已认可水花，不是歌蕾蒂娅专用改动。

## 行为

- fx/material_grains 默认关闭，需 --bal=fx/material_grains=1；高/中共享900/450颗，低画质回原版。延迟粒子占预算，未出生不移动、不老化。
- 艾雅：普通火球保留紧凑火核，连续余烬；熔岩保留硬壳，重力碎屑与落地水平方向爆溅；点燃保留缩小爆心、取消额外长HDR射线，火焰冷却为灰烬。已获用户阶段性方向认可。
- 拉普兰德 fx_lappland_slash：0.16秒后交接最多72/40颗定向碎片，原贴图80ms内退出。预算不足完整保留原图。用户要求明显差异，本稿未获最终视觉批准，后半段偏暗。未重做剑气弹体、其他技能和封印叉。
- 不改变技能伤害、范围、攻击周期或出手时刻；视觉随机走 vrng，完整TRACE待验收。

## 查看与复现

本机动态：build/eyja_material_chain/review.html、build/eyja_ignite_material/review.html、build/lappland_break_movie/review.html。build产物不提交。
游戏测试入口 --materialmovie 配合 --eyjamovie / --ignitemovie / --lapplandmovie、--shotdir=绝对目录，必须通过 tools/godot_runner.py 单进程静音离屏录制。42帧拉普兰德固定演示是实际渲染，不是自然战斗录像。

轻量契约：python tools/material_grains_contract.py，覆盖延迟出生、预算回退、灰烬色、低画质、拉普兰德一次性交接和预算满不隐藏原图。

## 未完成项

整局性能未验证；录制退出时存在纹理/ObjectDB资源泄漏，需Claude定位，不能按性能验收通过处理。不能把美术试稿等同于正式接入。最终提交检查结果补在下方。

## 本次交付前检查状态

已执行 git diff --check，无空白错误。已执行 python tools/check.py --auto --jobs 3，全机 GODOT_MAX_PROCS=1；检查在共享启动锁处阻塞，无Godot测试日志生成，等待后已中断本次检查进程。因此本次清理后的完整检查未通过验收，不得描述为已通过。此前单项契约通过只针对清理前版本。2026-10-24 用户明确授权按“未验收草稿”提交给 Claude，豁免本次提交前检查完成要求；不豁免接手后的验收、合入或发布要求。


### 检查分项（不要将历史结果当成本提交通过）

- 通过：本次暂存内容 `git diff --cached --check`，无空白错误；核对暂存文件与代码增量，无歌蕾蒂娅专用实现或演示。
- 阻塞后中断：`python tools/check.py --auto --jobs 3`，日志目录 `build/check/quick_1024_151447`；未实际完成任何Godot检查，不是测试通过，也没有可据此判定的行为失败项。
- 历史通过：移除歌蕾蒂娅前的 `MATERIAL_CONTRACT_PASS`；动态录制没有 SCRIPT ERROR/Parse Error，42个不同绘制帧。本次清理后未重跑契约/录制。
- 未运行/未完成：最终树的完整回归、同seed TRACE对照、整局性能与网页端性能。
- 已观察到但未修复：录制退出的纹理、ObjectDB和资源泄漏错误；拉普兰德碎片后半段偏暗，尚无最终视觉认可。

Claude 接手顺序：确认主线模板依赖是否已合入 → 人工核对与当前主线的增量 → 重跑轻量契约及分级检查 → 同seed TRACE → 退出泄漏和整局性能 → 视觉复审。此提交只供接手，不建议直接合入发布。
