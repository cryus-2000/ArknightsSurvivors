# 222 灯火三档（11-02）

状态：实现中（claude/lamp-tiers-1102，从 claude/integ-1101 c73d2ff86 开）。
来源：协调人 11-02 提出灯火分档方案，用户批准，并把通明档从「光幕减速」改为「加伤」。

## 1. 目标

灯火原来只有「暗淡 < 30」一个负面档和隐性的「通明 ≥ 70 技力 ×1.3」。玩家看不出灯火高有什么好处、低有什么坏处。
本轮把三档做成一眼看得出的状态：**通明是奖励（加伤 + 金色火花），暗淡是气氛（看不清怪），寂灭是警报（掉血 + 压迫）**。

## 2. 三档

| 档 | 灯火 | 数值 | 画面 / 声音 |
|---|---|---|---|
| 通明 | ≥ 70 | 光中敌人受伤 +25% → **+40%**（新旋钮 `lamp/lit_bonus_hi` 0.40；< 70 仍 `lamp/lit_bonus` 0.25）；技力 ×1.3、溟痕退散保留 | 打中光中敌人冒金色小火花（每只敌人 0.12 秒冷却、全场每秒上限 `fx/lit_spark_rate`，走 vfx 粒子总上限，低画质减半）；灯圈暖亮一档（灯色偏暖，0.6 秒过渡；能量不动，开场动画在调能量）；HUD 灯火条亮金 |
| 摇曳 | 30–70 | 不变（+25%） | 不变 |
| 暗淡 | < 30 | **不加新数值**（原有 dark_taken 1.05 / dark_enemy 1.1 / 拾取 −30% 保留） | 灯圈外的普通海嗣本体压暗成暗轮廓，只剩光学层的发光眼点（精英、Boss、敌弹、预警、精英标记不压）；灯圈边缘轻微抖动（±2.5%，纯画面）；低沉心跳（录音，见 §4）；HUD 灯火条暗红慢闪 |
| 寂灭 | 0 | 保留每秒 −3 生命 | 全屏边缘暗红压迫（慢呼吸）；屏幕中下提示「灯火寂灭——寻找灯油或灯标」 |

## 3. 实现点

- `run/combat.gd` `_damage`：光中加伤倍率按档取 `lamp/lit_bonus_hi` / `lamp/lit_bonus`；通明档调 `vfx.lit_spark(e)`（纯画面、只用 vrng）。
- `render/vfx.gd`：`lit_spark()`；`watch_lamp` 记 `lit_k`（通明过渡 0..1）与 `dark_k`（暗淡过渡 0..1），world / hud 读。
- `render/world.gd`：灯光颜色按 `lit_k`；暗淡档半径抖动；`draw_enemy` 里圈外普通怪 `_act_mod` 按 `dark_k` 压暗（每帧算，不进敌人画法缓存签名）；暗淡档心跳（与低血心跳共用节拍，不叠两套）。
- `screens/hud_bars.gd`：灯火条三档颜色（30 / 70 刻度已有）；状态条文字写明加伤 %。
- `screens/hud.gd`：寂灭边缘暗红 + 提示。
- `gallery.gd`：图鉴「灯油」说明改写成三档。
- 同种子：只有加伤倍率改变模拟，火花 / 压暗 / 抖动 / 心跳都是画面，不碰 `g.rng`。

## 4. 心跳录音

Sonniss GDC 2026 包里没有现成心跳。用库里已有的真实录音 344 Audio - Cinematic Fight Vol. 1「FGHTImpt_4 x Punch, Body 02」（身体闷击），取两下拼「咚—咚」，降调 + 150 Hz 低通 + 300–900 Hz 高频层（外放可闻），生成 `game/audio/sfx/lamp_heart.wav`。授权同 docs/113 §20（免版税、可商用、不需署名；不得再分发原文件、不得用于 AI 训练），登记见 docs/205「附：灯火暗淡心跳」。
生成脚本：`game/tools/gen_sfx_lamp_heart.py`。

## 5. 验证

- 同种子对照 1 局（docs/36 §3.2）：预期 TRACE 只在通明档伤害处出现差异。
- 云端配对两档（无成长 45–55%、18 细胞 65–75%，≥ 3 份均值）；超窗口调灯油掉率（`lamp/oil_kill_chance` 等），不削加伤。
- 录像：通明 / 暗淡 / 寂灭三段对照 `Claude outputs/lamp_tiers_1102.mp4`（--realtime 30 帧原色原速，≤ 20 MiB）。

## 6. 结果

实现提交 f5aa99181（分支 claude/lamp-tiers-1102，已推）。

- 快检 `check.py --auto`：164 过 / 0 失败。
- 同种子：seed1 mizuki 240 秒，钉 `--bal=lamp/lit_bonus_hi=0.25` 时 241 行 TRACE 与 c73d2ff86 逐行相同；不钉时 t=6.01 起只有敌人血量和分叉，符合预期。
- 录像：`Claude outputs/lamp_tiers_1102.mp4`（本机 E:\ArknightsSurvivors\Claude outputs，7.15 MB，通明 100 / 暗淡 20 / 寂灭 0 各 6 秒，seed3 mizuki 70 秒起，`tools/lamp_tiers_rec.py` 可重录）。
- 云端配对（11-02 17:10 本机关机前状态，待收）：
  - `lt1102-m0`（无成长，`--tier=0 --tide=0`，expert，4 seed × 7 编队 × 安慰剂 3 份，新 f5aa99181 对 基线 c73d2ff86）：虚拟机 batch-lt1102-m0 在跑，new 已写出，base 在跑。结果传 GCS，收法：本机 `python tools/gcp/batch.py collect lt1102-m0`，再看 `build/cloud/lt1102-m0/{new,base}/*.md`。
  - `lt1102-m18`（`--tide=0 --meta=18`）：**未开跑**——12 vCPU 配额被别的批跑占着，本机等待循环随关机中断。开法：`python tools/gcp/batch.py run lt1102-m18 --commit f5aa99181 --cmd-file <同 m0 的命令文件，加 --meta=18> --machine e2-standard-8`。
  - 判定：无成长 45–55%、18 细胞 65–75%（≥3 份均值）；超窗口只调灯油掉率（`lamp/oil_kill_chance` 等），不削加伤。
  - 胜率（11-03 收，GCS gs://…-batch/lt1102-m0 / lt1102-m18；两档都跑完，m18 后来由别的会话用 e2-standard-8 补开）：

    | 档 | 基线 c73d2ff86 | 灯火分档 f5aa99181 | 差 | 安慰剂 0 / 1 / 2（新） | 安慰剂 0 / 1 / 2（基线） | 窗口 |
    |---|---|---|---|---|---|---|
    | 无成长 m0（`--tier=0 --tide=0`） | 53.6% | **61.9%** | +8.3 | 78.6 / 60.7 / 46.4 | 64.3 / 42.9 / 53.6 | 45–55 |
    | 18 细胞 m18（`--tide=0 --meta=18`） | 63.1% | **76.2%** | +13.1 | 78.6 / 82.1 / 67.9 | 50.0 / 71.4 / 67.9 | 65–75 |

    各 84 局（4 seed × 7 编队 × 3 份），expert。两档都比窗口上沿高约 7 / 1 点；m0 的安慰剂份间差 32 点、m18 差 14 点，噪声大，但两档同方向。偏执泡影用时中位 127 → 102 秒（m0）、阶段护盾秒 6.3 → 15.2（加伤快过阶段，打到护盾的次数变多）。**只报不调**（协调人 11-03）：要压回窗口按上面判定调灯油掉率，不削加伤。

m18 命令文件（`--cmd-file`；m0 同此，去掉 `--meta=18`）：

```sh
python3 tools/balance_run.py --preset starts --bot expert --seeds 4 --seed0 1 --placebos 0,1,2 --nocache --jobs $GODOT_MAX_PROCS --extra="--tide=0 --meta=18" --tag $TAG-new --out $OUT/new
git fetch -q --depth 1 origin c73d2ff86bfb50529def537a7288974a7feae819
git worktree add -q --detach /tmp/lt_base c73d2ff86bfb50529def537a7288974a7feae819
python3 tools/balance_run.py --preset starts --bot expert --seeds 4 --seed0 1 --placebos 0,1,2 --nocache --jobs $GODOT_MAX_PROCS --extra="--tide=0 --meta=18" --game /tmp/lt_base/game --tag $TAG-base --out $OUT/base
```
