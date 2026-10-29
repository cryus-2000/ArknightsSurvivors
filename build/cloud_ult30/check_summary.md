# ult30-check 全量快检结果（docs/199 §9.3）

- 基线提交：d302cc331（Merge origin/claude/integ-1029 into claude/ult-proto）
- 命令：`python3 tools/check.py --nocache`（Linux 云端，4 Godot 并行，未用缓存，耗时 675 秒）
- 结果：共 169 项，**通过 168 项，失败 1 项**
- 真实玩法 / 逻辑失败：**0 项**

## 金样（golden）过期类失败（单独列出）

> 角色分支不重录金样，合入后统一重录。

1. **积木等价（数据版 vs 金样）** — 金样过期需要重录 14 份，与金样相同 0 份
   - 关键报错行：`⚠ 金样过期需要重录 14（eqtest seed1、kaltsit seed1、skadi seed1、eyjafjalla seed1、logos seed1、ulpianus seed1……）：别处玩法代码变了，无法比对；……请跑 python tools/check.py --only blocks_eq --eq-all --update-golden 重录；与金样相同 0`
   - 涉及：eqtest、kaltsit、skadi、eyjafjalla、logos、ulpianus、specter_unchained、mizuki、irene、lumen、siege、suzuran、wisadel、saria（均 seed1）
   - 各局本身正常跑完（有完整 BALANCE / SPAWNQ 输出），stderr 只有 Godot 退出时的常规资源泄漏 ERROR，无脚本崩溃

## 其他失败项

无。

完整日志：build/cloud_ult30/check.log
