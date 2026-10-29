# -*- coding: utf-8 -*-
"""普通怪一下伤害曲线 改前 / 改后同口径折线图（docs/194）：python tools/dmg_curve_plot.py [输出 png]
口径 = 标准档「当时刷怪池平均」一下伤害 = 池平均基础伤害 × 时间倍率 × 密度 1.58 × 受伤 0.9 − 平均护甲 1.9。
改前 = integ-1029 的多段叠加（dmg_div / knee、dmg_early、late_cap、dmg_gain、trim_early_dmg）；改后 = dmg_curve 关键点 + 单调三次插值（与 run/dmg_curve.gd 同算法）。"""
import json, os, sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
B = json.load(open(os.path.join(ROOT, "game/data/balance.json"), encoding="utf-8"))
W = json.load(open(os.path.join(ROOT, "game/data/waves.json"), encoding="utf-8"))["threat"]
E = json.load(open(os.path.join(ROOT, "game/data/enemies.json"), encoding="utf-8"))
E = E.get("enemies", E)
en = B["enemy"]
K = 1.0 / en.get("density", 1.0) ** en.get("density_dmg_exp", 1.0)
TAKEN, ARMOR = 0.9, 1.9


def pool(t):
    k = 0
    for i, x in enumerate(W):
        if t >= x["t"]:
            k = i
    return W[k]


def avg_base(t):
    p = pool(t)["pool"]
    return sum(E[i]["dmg"] for i in p) / len(p)


def old_mult(t):
    m = 1 + min(t, en["dmg_knee"]) / en["dmg_div"]
    m *= en["dmg_early"] + (1 - en["dmg_early"]) * min(t / en["dmg_early_until"], 1)
    m *= en["dmg_gain_early"] if t < en["dmg_gain_from"] else en["dmg_gain_late"]
    m += min(max(t - en["dmg_late_start"], 0) / en["dmg_late_div"], en["dmg_late_cap"])
    k = 1 - min(max((t - en["trim_early_until"]) / en["trim_early_fade"], 0), 1)
    m *= 1 + (en["trim_early_dmg"] - 1) * k
    return m


def pchip(knots, t):
    n = len(knots)
    if t <= knots[0][0]:
        return knots[0][1]
    if t >= knots[-1][0]:
        return knots[-1][1]
    h = [knots[i + 1][0] - knots[i][0] for i in range(n - 1)]
    d = [(knots[i + 1][1] - knots[i][1]) / h[i] for i in range(n - 1)]
    m = [0.0] * n
    for i in range(1, n - 1):
        if d[i - 1] * d[i] <= 0:
            m[i] = 0.0
        else:
            w1 = 2 * h[i] + h[i - 1]
            w2 = h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])

    def end(h0, h1, d0, d1):
        s = ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1)
        if (s > 0) != (d0 > 0):
            return 0.0
        if (d0 > 0) != (d1 > 0) and abs(s) > 3 * abs(d0):
            return 3 * d0
        return s
    m[0] = end(h[0], h[1], d[0], d[1])
    m[-1] = end(h[-1], h[-2], d[-1], d[-2])
    j = 0
    while j < n - 2 and t >= knots[j + 1][0]:
        j += 1
    x = (t - knots[j][0]) / h[j]
    return ((2 * x**3 - 3 * x**2 + 1) * knots[j][1] + (x**3 - 2 * x**2 + x) * h[j] * m[j]
            + (-2 * x**3 + 3 * x**2) * knots[j + 1][1] + (x**3 - x**2) * h[j] * m[j + 1])


knots = B["dmg_curve"]["knots"]
ts = [i for i in range(0, 721)]
before = [avg_base(t) * old_mult(t) * K * TAKEN - ARMOR for t in ts]
after = [pchip(knots, t) for t in ts]
plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei"]
plt.rcParams["axes.unicode_minus"] = False
fig, ax = plt.subplots(figsize=(10, 5.2))
ax.plot([t / 60 for t in ts], before, color="#d62728", lw=2, label="改前（integ-1029，多段叠加）")
ax.plot([t / 60 for t in ts], after, color="#1f77b4", lw=2.4, label="改后（一条曲线，单调三次插值）")
ax.scatter([k[0] / 60 for k in knots], [k[1] for k in knots], color="#1f77b4", zorder=5, s=36)
for k in knots:
    ax.annotate("%.0f" % k[1], (k[0] / 60, k[1]), textcoords="offset points", xytext=(4, -14), fontsize=9, color="#1f77b4")
for x, name in [(75, "暗流"), (170, "深潜"), (280, "裂隙"), (400, "深渊"), (520, "深蓝之树")]:
    ax.axvline(x / 60, color="#bbb", lw=0.8, ls=":")
    ax.text(x / 60 + 0.03, 1.2, name, fontsize=8, color="#888")
ax.set_xlabel("分钟")
ax.set_ylabel("「当时刷怪池平均」的一下伤害")
ax.set_title("普通怪一下伤害曲线（标准档；基础 × 时间倍率 × 密度 1.58 × 受伤 0.9 − 平均护甲 1.9）")
ax.set_xlim(0, 12); ax.set_ylim(0, 42); ax.grid(alpha=.3); ax.legend(loc="upper left")
fig.tight_layout()
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "enemy_dmg_curve_1029_after.png")
os.makedirs(os.path.dirname(out), exist_ok=True)
fig.savefig(out, dpi=110)
print("saved", out)
for t in (0, 60, 120, 180, 240, 299, 300, 360, 420, 480, 540, 599, 600, 720):
    print("%5ds before %5.1f after %5.1f" % (t, before[t], after[t]))
