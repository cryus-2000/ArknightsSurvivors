# tx-diag 云端批跑结果（2026-10-24）

## 结论：探针本身有 bug，三个配置的数据均不可用

`game/tests/melee_diag.gd`（取自诊断探针提交 `8181e8387`）第 37 行：

```gdscript
while g.state == g.S.PLAY or g.state == g.S.CHOICE or g.state == g.S.LEVELUP:
```

`game.gd` 的 `enum S` 从未有过 `LEVELUP` 这个成员：

```gdscript
enum S { PLAY, CHOICE, PAUSE, DEAD, WIN, SHOP, SHOW, STATS, INTRO, OPENING }
```

核对过 `8181e8387`（探针自己所在提交）、`04607ca76`（v1）、`2a6cf7029`（tri）、`origin/main` 四处的
`game/scripts/game.gd`，这一行完全一致——这不是 main 后续改的，是探针提交当时就写错了，对三个配置都会
100% 原样重现。

## 实测现象

对 main 配置跑了 texas / lappland / mizuki 三个 op（各 8 seed，`--jobs 4`），三个 op 全部 `n:0`（8 个
seed 全部超时返回 None），每个 op 跑满 2 轮 × 900s 超时 ≈ 30 分钟。单独复现一个 job（texas seed=1）：

```
TIMED_OUT= True
...
SCRIPT ERROR: Invalid access to property or key 'LEVELUP' on a base object of type 'Dictionary'.
          at: _ready (res://tests/melee_diag.gd:42)
          GDScript backtrace (most recent call first):
              [0] _ready (res://tests/melee_diag.gd:42)

real	15m50.183s
```

`g.S.LEVELUP` 访问无效会在 while 循环每一帧都报一次 SCRIPT ERROR + 完整 backtrace（diag-t=300 大约
对应上万帧），把原本几秒钟能跑完的一局拖到超过 900s 硬超时。

本地做了一次仅用于核实、未提交的对照实验：把该行的 `or g.state == g.S.LEVELUP` 去掉后，同一局
(seed=1, --diag-t=300) 只用 7.5s 就跑完，但游戏在 `t=51.7s`（非 `dead`/`win`）就提前退出了循环——说明
探针对状态机的覆盖本来就和当前 `game.gd` 的 `S` 枚举（例如升级选择之后是否会进入 `SHOP` 等循环未覆盖
的状态）不匹配，去掉这一行引用并不能让探针本身变得可信，只是证实了"每帧报错"确实是超时的直接原因。

## 为什么 v1 / tri 没有真的跑

三个配置检出的探针三个文件（`melee_diag.gd` / `.tscn` / `melee_diag.py`）都是原样从同一个 `8181e8387`
复制过去的，未做任何改动；而 v1 (`04607ca76`) / tri (`2a6cf7029`) 的 `game.gd` 在这一处的 `enum S` 与
main 完全相同（见上）。换句话说这个 bug 与"跑哪个配置"无关，只取决于探针代码本身，三个配置会给出完全
相同的失败模式（8 seed 全部超时、`n:0`）。按照"任何一步失败就把错误原文写进最终回复，不要重试超过一次"
的要求，在 main 配置上已经验证过一次失败（texas/lappland/mizuki 三个 op、合计 24 个 seed 全部超时）后，
没有再对 v1 / tri 重复烧 ~30–60 分钟的云端算力去确认同一个已证实必然重现的 bug；`v1.log` / `tri.log`
里记录的是跳过的原因，不是真实跑出来的汇总行。

## 需要协调人 / 探针作者处理

建议修 `game/tests/melee_diag.gd:37`（去掉或改成真实存在的状态名），并确认升级选择相关的状态覆盖
（`SHOP` 等）是否也要纳入循环条件，再重新跑一次这批 tx-diag。

## 本次云端环境

见 `env.txt`（三个提交号 / Godot 版本 / nproc / UTC 时间）。setup_linux.sh 跑过一次（见
`setup_main.log`），后续两次 checkout 复用同一份 Godot 安装、未重新下载。
