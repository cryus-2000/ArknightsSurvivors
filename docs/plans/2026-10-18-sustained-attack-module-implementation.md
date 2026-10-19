# 持续攻击阶段模块实施计划

用户已确认设计边界；使用 writing-plans 和 subagent-driven-development 执行。

目标：保持 ac090f8b 行为，移除维什戴尔 S2 专用调度，让普通攻击形状能够复用。
架构：独立阶段状态与队列 + data_operator 生命周期 + 角色攻击执行适配。
技术：Godot GDScript、既有 JSON 编译/校验、Godot runner。

- [x] 1. 保留 ac090f8b 可执行源码基线，记录同 seed 攻击时间/炮弹目标/伤害/效果；新增独立测试夹具并观察旧版失败。
- [x] 2. 新建 attack_phases.gd：配置校验、start/begin_round/release/tick/active_left/locked/cancel；阶段快照与队列不保存角色专用状态。
- [x] 3. 接入 data_operator 技能生效、每帧、攻击起手与出手、占用查询和离场；character 提供序列切换入口。未启用配置保持旧分支。
- [x] 4. 迁移 wisadel.json 和 seg_wisadel、ob_hw、ob_check。炮击适配保留原效果，移除 s2_queue/s2_over/固定下标控制。
- [x] 5. 独立夹具检验不同槽、不同阶段比例、三连发、普通形状；非法配置、大 dt、取消、无目标、攻速、互斥、计数、到期收势。保留维什戴尔现有专项覆盖。
- [x] 6. 审查模块边界与行为，比较重构前后同 seed 事件；运行 python tools/check.py --auto --jobs 3，失败先修复。
- [ ] 7. 更新 docs/61、索引、交付记录；只提交本次文件，导出独立本地测试版、校验启动和素材。不得合 main 或公网发布。

## 已验证记录

- 新模块独立夹具：66 项通过；S1、30% 切换、3 连发、圆形/扇形、手动方向、无目标、取消/撤退及非法配置。
- 维什戴尔原专项：534 项通过；三人时序：179 项通过。
- 首轮完整快检 quick_1018_164019：80 项中 1 项失败。原因是 attack_timing_test 逐技能用例仅清画面、不清上一持续技能；显式取消隔离后全部原断言保留，新增占用断言通过。生产代码没有为测试放宽互斥。
- 以 ac090f8b 为基线，wisadel_phase_trace.tscn 在 1/2/4 倍攻速各 11 秒的 21/38/76 发事件逐字段一致（发射 tick、目标、伤害、炮口、半径、余震、普攻计数、最终生命及随机状态）。
- tools/trace_base.py 1 wisadel 30 --ref ac090f8b --here：缓存基线 31 行 TRACE 逐行一致。
- 210 帧实机重录完成：没有持续阶段普通 attack 闪帧，完整经过 start/idle/attack/over_start/over_attack/over_end。预览 build/wisadel_s2_capture/review.html。
- 仍有既有 Godot 退出资源清理告警；无 SCRIPT ERROR / Parse Error。C++ 原生对照未编译、14 个旧金样过期，仍按原检查标记跳过。不执行本地平衡 A/B。
- 最终完整快检 quick_1018_164801：80 项通过、0 失败，328 秒，无缓存命中。提交后导出独立本地包并记录包内 verification.json。
