# 博士跑步测试版接入 · 2026-10-18

用户批准：“就先这样吧，放到游戏里去，剩下的后面再说”。

来源：codex-art/art/incoming/ck_doctor_rework_1018/pixel_revision_07/doctor_run@2x.png。
交付的 @2x 与批准版本逐字节相同；SHA256：ea8905162db1ed0e43c3ffa374683ecbc44f38e7ed8195c8caf632b0ee922ed0。

- doctor_run@2x.png：1024×128，8 帧，10 fps，循环 0.8 秒；脚底 (64,120)，逻辑锚点 (32,60)。
- doctor_run.png：从 @2x 最近邻导出 512×64，仅作旧加载兼容。
- 原待机、受伤、倒下资源保留。运行时通过 run_foot 区分新旧画布。
- 已知待返修：头部起伏 0.696px（标准 1–2.5）、前倾 26.46°（WARN）、新旧待机比例和朝向差异、非统一硬黑描边。用户批准当前版先测试，不等于这些问题通过美术验收。
- art_lint 的 doctor outline/frontal/run 临时豁免关联本次批准；更换相关资源时重新审查并移除。保留实际 FAIL* 与 WARN，不改通用阈值。
- 仅替换博士跑步，不改变跟随移动速度、伤害或随机数。

验收：tools/check.py --auto --jobs 3；doctor_run_test 场景检查混合画布、锚点、两轮 10 fps 循环、返回待机及倒下末帧。实际测试结果见接入提交说明。

实测结果：77 项检查、0 失败（build/check/quick_1018_111901），另博士专项清理后的复测 0 失败（quick_1018_111826）；TRACE seed=1 / saria / 45 秒与 main 6b697796 的 46 行完全一致。首轮遇 NumPy 并发导入异常，重跑用预加载 numpy 后执行同一 check.py --auto --jobs 3。原生核心未编译、14 个旧金样过期的对照项由既有检查程序跳过，不声明这些对照通过。
