#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""萨米 vs 水月 敌人纸面对照（docs/392 §10）：只读数据，不跑游戏。

用法（仓库根目录）：python tools/sami_paper.py [--md 输出.md]

按 spawner.new_enemy / dmg_curve.gd 的公式在若干时间点算单只敌人：
  生命 = hp × 时间曲线 × 常规档 enemy_hp × （普通怪）密度 (1/k)^density_hp_exp × hp_late × 前后期微调 × （高阶）tier_hp ；精英 × elite_hp_mult
  一下伤害 = dmg × dmg_x × dmg_curve 时间倍率 m(t)（norm_full：按当档刷怪池归一）× （普通怪）密度伤害系数 × （高阶）tier_dmg ；精英 × elite_dmg_mult
  经验 = xp × （普通怪）1/k ；精英 × elite_xp_mult
  每秒伤害上限 = 近战：一下 ÷ 队长受击无敌 0.45 秒；远程：一下 × bullet_dmg_mult ÷ cd
  击杀时间 = 生命 ÷ 木桩秒伤（docs/331 §2 木桩表，队长、无藏品、不升级；按时间取精零 / 精一 / 精二）
  每分钟刷怪总血量 = 普通刷怪（只数 / 秒 × 池平均生命）+ 大群（每次总血量 ÷ horde_every）+ 精英（单只 ÷ 精英间隔），不含 Boss
近似：大群按混编 body 均值 + extra pct 估组成；大群固定时刻（225 / 300 / 375）不单列；Boss 在场减刷、灯火、难度以外的旋钮都不算。两个主题用同一套近似，只看相对差。
"""
import argparse, json, os, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
B = json.load(open(os.path.join(ROOT, "game/data/balance.json"), encoding="utf-8"))
EN, BOSS, DC, SH = B["enemy"], B["boss"], B["dmg_curve"], B["shape_lv"]
STD_HP = B["difficulty"]["standard"].get("enemy_hp", 1.0)
DEN = EN.get("density", 0.4)
IFRAME = 0.45   # combat.gd 队长受击后的无敌秒数


def load(theme, waves="waves.json"):
    d = os.path.join(ROOT, "game/themes", theme, "data")
    E = json.load(open(os.path.join(d, "enemies.json"), encoding="utf-8"))["enemies"]
    W = json.load(open(os.path.join(d, waves), encoding="utf-8"))
    return E, W


def bal(sec, key, dflt):
    return B.get(sec, {}).get(key, dflt)


# ---------- dmg_curve（同 run/dmg_curve.gd）----------
def pchip(k, t):
    n = len(k)
    if t <= k[0][0]:
        return k[0][1]
    if t >= k[-1][0]:
        return k[-1][1]
    h = [k[i + 1][0] - k[i][0] for i in range(n - 1)]
    dl = [(k[i + 1][1] - k[i][1]) / h[i] for i in range(n - 1)]
    m = [0.0] * n

    def end(h0, h1, d0, d1):
        s = ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1)
        if (s > 0) != (d0 > 0):
            return 0.0
        if (d0 > 0) != (d1 > 0) and abs(s) > 3 * abs(d0):
            return 3 * d0
        return s
    for i in range(1, n - 1):
        if dl[i - 1] * dl[i] <= 0:
            m[i] = 0.0
        else:
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / dl[i - 1] + w2 / dl[i])
    m[0] = end(h[0], h[1] if n > 2 else h[0], dl[0], dl[1] if n > 2 else dl[0])
    m[-1] = end(h[-1], h[-2] if n > 2 else h[-1], dl[-1], dl[-2] if n > 2 else dl[-1])
    j = 0
    while j < n - 2 and t >= k[j + 1][0]:
        j += 1
    x = (t - k[j][0]) / h[j]
    x2, x3 = x * x, x * x * x
    return (2 * x3 - 3 * x2 + 1) * k[j][1] + (x3 - 2 * x2 + x) * h[j] * m[j] + (-2 * x3 + 3 * x2) * k[j + 1][1] + (x3 - x2) * h[j] * m[j + 1]


def smooth(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def target0(t, _mono={}):
    cut, sc = DC.get("mid_cut", 0.0), DC.get("scale", 1.0)
    raw = lambda u: pchip(DC["knots"], u) * sc
    if cut <= 0 or t <= DC.get("mid_from", 180):
        return raw(t)
    a, b = DC.get("mid_from", 180), max(DC.get("mid_from", 180) + 1, DC.get("mid_to", 420))
    cv = lambda u: raw(u) * (1 - cut * smooth((u - a) / max(1, b - a)))
    if not _mono:
        m = -1e9
        for i in range(int(b - a) + 1):
            m = max(m, cv(min(a + i, b)))
            _mono[i] = m
    if t >= b:
        return max(cv(t), _mono[max(_mono)])
    i0 = min(int(t - a), max(_mono) - 1)
    return _mono[i0] + (_mono[i0 + 1] - _mono[i0]) * min(max(t - a - i0, 0), 1)


def target(t):
    if B["growth"].get("late_shape", 0) > 0:
        x = smooth((t - SH.get("comp_from", 240)) / max(1, SH.get("comp_to", 420) - SH.get("comp_from", 240)))
        return target0(t) * (1 + (SH.get("comp_dmg", 1.0) - 1) * x)
    return target0(t)


def relief(t):
    k = DC.get("relief", [])
    if not k:
        return 1.0
    if t <= k[0][0]:
        return k[0][1]
    for i in range(1, len(k)):
        if t <= k[i][0]:
            a = k[i - 1][0]
            return k[i - 1][1] + (k[i][1] - k[i - 1][1]) * min(max((t - a) / max(1e-6, k[i][0] - a), 0), 1)
    return k[-1][1]


_EFF = []


def target_eff(t):
    if not _EFF:
        m = -1e9
        for i in range(901):
            m = max(m, target(i) * relief(i))
            _EFF.append(m)
    u = max(0.0, t)
    i0 = min(int(u), 899)
    return _EFF[i0] + (_EFF[i0 + 1] - _EFF[i0]) * min(max(u - i0, 0), 1)


# ---------- 主题相关 ----------
class Theme:
    def __init__(self, tid, waves="waves.json"):
        self.id = tid
        self.E, self.W = load(tid, waves)
        self.T = self.W["threat"]

    def threat(self, t):
        k = 0
        for i, x in enumerate(self.T):
            if t >= x["t"]:
                k = i
        return k

    def tier_k(self, key, t, th):
        cur = self.T[th].get(key, 1.0)
        ramp = EN.get("tier_ramp", 0.0)
        if th == 0 or ramp <= 0:
            return cur
        prev = self.T[th - 1].get(key, 1.0)
        return prev + (cur - prev) * min(max((t - self.T[th]["t"]) / ramp, 0), 1)

    def pool_eff(self, th, t):
        p = self.T[th]["pool"]
        tk = self.tier_k("tier_dmg", t, th)
        return sum(self.E[i]["dmg"] * EN.get("dmg_x_" + i, 1.0) * (tk if self.E[i].get("tier_cap") else 1.0) for i in p) / len(p)

    def mult(self, t):
        th = self.threat(t)
        dk = (1 / DEN) ** EN.get("density_dmg_exp", 0.5)
        return max(0.05, (target_eff(t) + DC.get("ref_armor", 1.9)) / max(0.01, self.pool_eff(th, t) * dk * DC.get("ref_taken", 0.9)))

    def unit(self, eid, t, horde=False):
        """→ 生命 / 一下 / 经验 / 每秒伤害上限（单只，常规档）"""
        d = self.E[eid]
        role = d.get("role", "")
        th = self.threat(t)
        hk = EN.get("hp_knee", 480)
        tm = 1 + min(t, hk) / EN.get("hp_div", 110) + max(t - hk, 0) / EN.get("hp_late_div", 120)
        hp = d["hp"] * tm * STD_HP
        dmg = d["dmg"] * self.mult(t) * EN.get("dmg_x_" + eid, 1.0)
        xp = d["xp"]
        if role == "":
            inv = 1 / DEN
            hp *= inv ** EN.get("density_hp_exp", 0.75)
            xp *= inv
            dmg *= inv ** EN.get("density_dmg_exp", 0.5)
            if "hp_late" in d:
                t0, t1 = EN.get("hp_late_t0", 240), EN.get("hp_late_t1", 360)
                hp *= 1 + (d["hp_late"] - 1) * min(max((t - t0) / max(1, t1 - t0), 0), 1)
            f = EN.get("trim_all_hp", 1.0)
            u = EN.get("trim_early_until", 180)
            k = 1 - min(max((t - u) / max(1, EN.get("trim_early_fade", 60)), 0), 1)
            f *= 1 + (EN.get("trim_early_hp", 1.08) - 1) * k
            t0, t1 = EN.get("trim_late_t0", 420), EN.get("trim_late_t1", 480)
            f *= 1 + (EN.get("trim_late_hp", 0.92) - 1) * min(max((t - t0) / max(1, t1 - t0), 0), 1)
            hp *= f
        if d.get("tier_cap"):
            hp *= self.tier_k("tier_hp", t, th) * EN.get("tier_hp_scale", 1.0)
            dmg *= self.tier_k("tier_dmg", t, th) * EN.get("tier_dmg_scale", 1.0)
        if role == "elite":
            hp *= EN.get("elite_hp_mult", 7.0)
            xp *= EN.get("elite_xp_mult", 10.0)
            dmg *= EN.get("elite_dmg_mult", 1.3)
        if horde:
            hp *= EN.get("horde_hp_mult", 2.0)
            dmg *= EN.get("horde_dmg", 1.4)
        if d.get("ai") == "ranged":
            dps = dmg * EN.get("bullet_dmg_mult", 0.75) / max(0.1, d.get("cd", 2.0))
        elif d.get("no_contact") and d.get("pattern") == "blast":
            dps = None   # 自爆：一次性
        else:
            dps = dmg / IFRAME
        return {"hp": hp, "dmg": dmg, "xp": xp, "dps": dps}

    def pool_hp(self, t):
        p = self.T[self.threat(t)]["pool"]
        return sum(self.unit(i, t)["hp"] for i in p) / len(p)

    def horde_avg_hp(self, t):
        mixes = self.T[self.threat(t)].get("horde_mix") or [{"body": self.T[self.threat(t)]["horde"], "extra": []}]
        tot = 0.0
        for mx in mixes:
            ex = sum(x["pct"] for x in mx.get("extra", []))
            body = sum(self.unit(i, t, True)["hp"] for i in mx["body"]) / len(mx["body"])
            v = body * (1 - ex) + sum(x["pct"] * self.unit(x["id"], t, True)["hp"] for x in mx.get("extra", []))
            tot += v
        return tot / len(mixes)

    def elite_hp(self, t):
        es = [k for k, v in self.E.items() if v.get("role") == "elite" and "elite_after" in v and v["elite_after"] <= t and k != "knight"]
        return sum(self.unit(k, t)["hp"] for k in es) / len(es) if es else 0.0

    def hp_per_min(self, t):
        th = self.T[self.threat(t)]
        sk = EN.get("spawn_knee", 520)
        rate = EN.get("spawn_base", 2.3) + min(t, sk) / EN.get("spawn_div", 40) + max(t - sk, 0) / EN.get("spawn_late_div", 40)
        rate *= DEN * th.get("rate_mult", 1.0)
        trickle = rate * 60 * self.pool_hp(t)
        n = (EN.get("horde_base", 20) + int(min(t, EN.get("horde_grow_until", 570)) / EN.get("horde_div", 12)))
        n = n * EN.get("horde_count_mult", 1.5) * th.get("horde_mult", 1.0) * DEN
        horde = n * self.horde_avg_hp(t) * 60 / th.get("horde_every", 90)
        elite = self.elite_hp(t) * 60 / th.get("elite", 50) if t >= EN.get("first_elite", 60) else 0.0
        return trickle, horde, elite


STAKE = {   # docs/331 §2 木桩表（队长、无藏品、不升级），精零 / 精一 / 精二
    "20 人中位": (59, 98, 180),
    "单体·斯卡蒂": (92, 153, 297),
    "群伤·艾雅法拉": (38, 89, 357),
}


def elite_lv(t):
    return 0 if t < 120 else (1 if t < 210 else 2)   # docs/331：精二集中在 3:00–3:56 到手


PAIRS = [   # 萨米, 水月对位, 首次出现（萨米池）
    ("husk", ["bone", "slider"]),
    ("drone", ["runner"]),
    ("caster", ["stone", "floater"]),
    ("icebug", ["runner"]),
    ("breaker", ["tracer", "founder"]),
    ("warrior", ["pocket"]),
]
PAIRS_FULL = PAIRS + [
    ("snsbr", ["slider", "bone"]),
    ("uterer", ["slider"]),
    ("mhshep", ["stone"]),
    ("snmage", ["spitter"]),
    ("rockback", ["founder"]),
    ("hound", ["reaper"]),
    ("uamord", ["skimmer"]),
    ("frostd", ["mother"]),
]
TIMES = [45, 120, 220, 340, 460, 570]


def present(th, eid, t):
    if th.E[eid].get("role") == "elite":
        return th.E[eid].get("elite_after", 0) <= t
    return eid in th.T[th.threat(t)]["pool"]


def fmt(x, nd=0):
    return "—" if x is None else (f"{x:.{nd}f}")


def flag(a, b):
    if a is None or b is None or b == 0:
        return ""
    r = a / b - 1
    return f"{r:+.0%}" + (" ⚠" if abs(r) > 0.20 else "")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--md")
    ap.add_argument("--full", action="store_true", help="萨米用全量刷怪表 waves_full.json（docs/392 §11）")
    a = ap.parse_args()
    S, D = Theme("sami", "waves_full.json" if a.full else "waves.json"), Theme("deep_sea")
    pairs = PAIRS_FULL if a.full else PAIRS
    out = []
    w = out.append
    w("### 10.1 单只对照（常规档；括号是萨米 ÷ 水月对位均值 − 1，⚠ = 偏离超过 ±20%）\n")
    w("木桩秒伤按时间取：2:00 前精零、2:00–3:30 精一、之后精二（docs/331 §2）。击杀时间列「中位 / 斯卡蒂 / 艾雅法拉」。\n")
    for sid, dids in pairs:
        w(f"**{S.E[sid]['name']} `{sid}`** ↔ " + " / ".join(f"{D.E[x]['name']} `{x}`" for x in dids) + "\n")
        w("| 时间 | 萨米 生命 | 水月 生命 | 萨米 一下 | 水月 一下 | 萨米 每秒上限 | 水月 每秒上限 | 萨米 经验 | 水月 经验 | 萨米 击杀秒（中位 / 斯卡蒂 / 艾雅） | 水月 击杀秒 |")
        w("|---|---|---|---|---|---|---|---|---|---|---|")
        for t in TIMES:
            if not present(S, sid, t):
                continue
            su = S.unit(sid, t)
            here = [x for x in dids if present(D, x, t)] or dids   # 水月对位只取当时在池里的（都不在就全取）
            du = [D.unit(x, t) for x in here]
            avg = lambda k: (sum(u[k] for u in du if u[k] is not None) / max(1, sum(1 for u in du if u[k] is not None))) if any(u[k] is not None for u in du) else None
            dh, dd, dp, dx = avg("hp"), avg("dmg"), avg("dps"), avg("xp")
            lv = elite_lv(t)
            kt_s = " / ".join(fmt(su["hp"] / v[lv], 1) for v in STAKE.values())
            kt_d = " / ".join(fmt(dh / v[lv], 1) for v in STAKE.values())
            w(f"| {t // 60}:{t % 60:02d} | {fmt(su['hp'])} ({flag(su['hp'], dh)}) | {fmt(dh)} | {fmt(su['dmg'], 1)} ({flag(su['dmg'], dd)}) | {fmt(dd, 1)} | "
              f"{fmt(su['dps'], 1)} ({flag(su['dps'], dp)}) | {fmt(dp, 1)} | {fmt(su['xp'], 1)} ({flag(su['xp'], dx)}) | {fmt(dx, 1)} | {kt_s} | {kt_d} |")
        w("")
    # 刷怪池
    w("### 10.2 刷怪池平均（普通刷怪，单只）\n")
    w("| 时间 | 萨米阶段 | 萨米 池平均生命 | 水月 池平均生命 | 差 | 萨米 池平均一下 | 水月 池平均一下 |")
    w("|---|---|---|---|---|---|---|")
    for t in TIMES:
        sp, dp_ = S.pool_hp(t), D.pool_hp(t)
        sd = sum(S.unit(i, t)["dmg"] for i in S.T[S.threat(t)]["pool"]) / len(S.T[S.threat(t)]["pool"])
        dd = sum(D.unit(i, t)["dmg"] for i in D.T[D.threat(t)]["pool"]) / len(D.T[D.threat(t)]["pool"])
        w(f"| {t // 60}:{t % 60:02d} | {S.T[S.threat(t)]['name']} | {sp:.0f} | {dp_:.0f} | {flag(sp, dp_)} | {sd:.1f} | {dd:.1f} |")
    w("")
    w("### 10.3 每分钟刷怪总血量（不含 Boss；千）\n")
    w("| 时间 | 萨米 普通 | 萨米 大群 | 萨米 精英 | **萨米 合计** | 水月 普通 | 水月 大群 | 水月 精英 | **水月 合计** | 差 |")
    w("|---|---|---|---|---|---|---|---|---|---|")
    for t in range(30, 600, 30):
        s3, d3 = S.hp_per_min(t), D.hp_per_min(t)
        w(f"| {t // 60}:{t % 60:02d} | " + " | ".join(f"{x / 1000:.1f}" for x in s3) + f" | **{sum(s3) / 1000:.1f}** | "
          + " | ".join(f"{x / 1000:.1f}" for x in d3) + f" | **{sum(d3) / 1000:.1f}** | {flag(sum(s3), sum(d3))} |")
    w("")
    # Boss
    w("### 10.4 Boss 出场生命（常规档）\n")
    w("| Boss | 出场 | 生命 | 对位 | 对位生命 | 差 |")
    w("|---|---|---|---|---|---|")

    def boss_hp(th, eid, t, final):
        d = th.E[eid]
        hp = d["hp"] * (1 + t / EN.get("boss_hp_time_div", 600)) * BOSS.get("hp_final" if final else "hp_mid", 1.0) * BOSS.get("hp_x_" + eid, 1.0)
        if eid == "carmen":
            hp *= BOSS.get("carmen_hp_k", 2.4)
        if eid == "iberia":
            hp *= BOSS.get("iberia_hp_k", 2.9)
        return hp
    for sid, t, did, fin in [("blade", 210, "carmen", False), ("wanderer", 420, "iberia", False), ("will", 600, "paranoia", True), ("will", 600, "knight_boss", True)]:
        sh, dh = boss_hp(S, sid, t, fin), boss_hp(D, did, t, fin)
        w(f"| {S.E[sid]['name']} | {t // 60}:{t % 60:02d} | {sh / 1000:.1f} 千 | {D.E[did]['name']} | {dh / 1000:.1f} 千 | {flag(sh, dh)} |")
    w("")
    txt = "\n".join(out)
    if a.md:
        open(a.md, "w", encoding="utf-8", newline="\n").write(txt + "\n")
    sys.stdout.reconfigure(encoding="utf-8")
    print(txt)


if __name__ == "__main__":
    main()
