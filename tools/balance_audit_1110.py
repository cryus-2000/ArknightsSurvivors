# -*- coding: utf-8 -*-
"""全局数值体检（docs/331，11-10，只读不改数）。

两部分：
  static  按 balance.json / enemies.json / waves.json 复算公式（同 run/spawner.gd、combat.gd、dmg_curve.gd）：
          普通怪 / 精英 / Boss 单只生命、池平均一下伤害、刷怪 + 大群「每秒涌入的血量」
  tel     读 balance_run 的整局记录（bot.curve 每 30 秒一格）：全队秒伤、承伤、最大生命、回复、等级、在场敌人、Boss 用时
用法（仓库根目录）：
  python tools/balance_audit_1110.py --m0 <m0.json> --m0nd <m0nd.json> --m18 <m18.json> --m18nd <m18nd.json> --out "Claude outputs/balance_audit_1110"
输出：PNG 曲线图 + audit.json（文档表格用的数字）。
"""
import argparse, glob, json, math, os, statistics, sys
from collections import defaultdict
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "DejaVu Sans"]
plt.rcParams["axes.unicode_minus"] = False


def J(p):
    return json.load(open(os.path.join(ROOT, p), encoding="utf-8"))


B = J("game/data/balance.json")
E = J("game/data/enemies.json")
E = E.get("enemies", E)
W = J("game/data/waves.json")
TH = W["threat"]
EN = B["enemy"]
DIFF_HP = B["difficulty"]["standard"].get("enemy_hp", 1.0)
DEN = EN["density"]
INV = 1.0 / DEN
SL = B["shape_lv"]
TIMES = [60, 180, 300, 420, 540, 600]
MINS = [t // 60 for t in TIMES]


def threat_at(t):
    k = 0
    for i, x in enumerate(TH):
        if t >= x["t"]:
            k = i
    return k


def hp_time(t):
    hk = EN["hp_knee"]
    return 1 + min(t, hk) / EN["hp_div"] + max(t - hk, 0) / EN["hp_late_div"]


def clamp(x, a, b):
    return max(a, min(b, x))


def lerp(a, b, x):
    return a + (b - a) * x


def trim_hp(t):
    u = EN.get("trim_early_until", 180.0)
    k = 1 - clamp((t - u) / max(1, EN.get("trim_early_fade", 60.0)), 0, 1)
    f = EN.get("trim_all_hp", 1.0) * lerp(1, EN.get("trim_early_hp", 1.08), k)
    t0, t1 = EN.get("trim_late_t0", 420.0), EN.get("trim_late_t1", 480.0)
    return f * lerp(1, EN.get("trim_late_hp", 0.92), clamp((t - t0) / max(1, t1 - t0), 0, 1))


def late_hp(t, mult):
    t0, t1 = EN.get("hp_late_t0", 240.0), EN.get("hp_late_t1", 360.0)
    return lerp(1, mult, clamp((t - t0) / max(1, t1 - t0), 0, 1))


def normal_hp(tp, t):
    d = E[tp]
    hp = d["hp"] * hp_time(t) * DIFF_HP
    hp *= INV ** EN.get("density_hp_exp", 0.75)
    if "hp_late" in d:
        hp *= late_hp(t, d["hp_late"])
    hp *= trim_hp(t)
    if d.get("tier_cap"):
        hp *= TH[threat_at(t)].get("tier_hp", 1.0)
    return hp


def elite_hp(tp, t):
    d = E[tp]
    hp = d["hp"] * hp_time(t) * DIFF_HP
    if d.get("tier_cap"):
        hp *= TH[threat_at(t)].get("tier_hp", 1.0)
    return hp * EN["elite_hp_mult"]


# ---- 伤害曲线（同 dmg_curve.gd）
def pchip(t):
    k = B["dmg_curve"]["knots"]
    n = len(k)
    if t <= k[0][0]:
        return k[0][1]
    if t >= k[-1][0]:
        return k[-1][1]
    h = [k[i + 1][0] - k[i][0] for i in range(n - 1)]
    dl = [(k[i + 1][1] - k[i][1]) / h[i] for i in range(n - 1)]
    m = [0.0] * n
    for i in range(1, n - 1):
        if dl[i - 1] * dl[i] <= 0:
            m[i] = 0
        else:
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / dl[i - 1] + w2 / dl[i])

    def es(h0, h1, d0, d1):
        s = ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1)
        if math.copysign(1, s) != math.copysign(1, d0):
            return 0
        if math.copysign(1, d0) != math.copysign(1, d1) and abs(s) > 3 * abs(d0):
            return 3 * d0
        return s
    m[0] = es(h[0], h[1], dl[0], dl[1])
    m[-1] = es(h[-1], h[-2], dl[-1], dl[-2])
    j = 0
    while j < n - 2 and t >= k[j + 1][0]:
        j += 1
    x = (t - k[j][0]) / h[j]
    x2, x3 = x * x, x * x * x
    return (2 * x3 - 3 * x2 + 1) * k[j][1] + (x3 - 2 * x2 + x) * h[j] * m[j] + (-2 * x3 + 3 * x2) * k[j + 1][1] + (x3 - x2) * h[j] * m[j + 1]


def dmg_target(t, comp=True):
    dc = B["dmg_curve"]
    cut, a, b, sc = dc.get("mid_cut", 0), dc.get("mid_from", 180), dc.get("mid_to", 420), dc.get("scale", 1)

    def cv(tt):
        x = clamp((tt - a) / max(1, b - a), 0, 1)
        return pchip(tt) * sc * (1 - cut * x * x * (3 - 2 * x))
    if t <= a or cut <= 0:
        v = pchip(t) * sc
    else:
        mx = max(cv(min(a + i, b)) for i in range(0, int(min(t, b) - a) + 1))
        v = max(cv(t), mx)
    if comp and B["growth"].get("late_shape", 0) > 0:
        x = clamp((t - SL["comp_from"]) / max(1, SL["comp_to"] - SL["comp_from"]), 0, 1)
        v *= 1 + (SL["comp_dmg"] - 1) * x * x * (3 - 2 * x)
    return v


def pool_avg_dmg(th):
    p = TH[th]["pool"]
    return sum(E[i]["dmg"] for i in p) / len(p)


def dens_k():
    return INV ** EN["density_dmg_exp"]


def mob_hit(tp, t):
    """该类普通怪一下打在队长身上（受伤 0.9、护甲 1.9 之后）"""
    th = threat_at(t)
    m = max(0.05, (dmg_target(t) + B["dmg_curve"]["ref_armor"]) / (pool_avg_dmg(th) * dens_k() * B["dmg_curve"]["ref_taken"]))
    d = E[tp]["dmg"] * m * dens_k() * EN.get("dmg_x_" + tp, 1.0)
    if E[tp].get("tier_cap"):
        d *= TH[th].get("tier_dmg", 1.0)
    return max(0.0, d * B["dmg_curve"]["ref_taken"] - B["dmg_curve"]["ref_armor"])


def pool_avg(f, t):
    p = TH[threat_at(t)]["pool"]
    return sum(f(i, t) for i in p) / len(p)


def spawn_rate(t):
    knee = EN.get("spawn_knee", 520)
    r = EN["spawn_base"] + min(t, knee) / EN["spawn_div"] + max(t - knee, 0) / EN.get("spawn_late_div", EN["spawn_div"])
    return r * DEN * TH[threat_at(t)].get("rate_mult", 1.0)


def horde_n(t):
    return (EN["horde_base"] + int(min(t, EN["horde_grow_until"]) / EN["horde_div"])) * DEN * TH[threat_at(t)].get("horde_mult", 1.0)


def horde_avg_hp(t):
    body = TH[threat_at(t)]["horde"]
    return sum(normal_hp(i, t) for i in body) / len(body)


def incoming_hps(t):
    """每秒涌入的普通怪血量（刷怪 + 大群摊平 + 精英摊平），不含 Boss"""
    th = TH[threat_at(t)]
    s = spawn_rate(t) * pool_avg(normal_hp, t)
    h = horde_n(t) * horde_avg_hp(t) / th["horde_every"]
    el = pool_avg(elite_hp, t) / th["elite"]
    return s, h, el


BOSS_SLOT = {"path": 210, "carmen": 210, "iberia": 420, "bishop": 420, "archon": 420, "immortal": 420,
             "paranoia": 600, "knight_boss": 600, "ishar": 600, "izumik": 600}
FINAL = {"paranoia", "knight_boss", "ishar", "izumik"}


def boss_hp(tp, t=None):
    t = BOSS_SLOT[tp] if t is None else t
    bb = B["boss"]
    hp = E[tp]["hp"] * (1 + t / EN["boss_hp_time_div"])
    hp *= bb["hp_final"] if tp in FINAL else bb["hp_mid"]
    hp *= bb.get("hp_x_" + tp, 1.0)
    hp *= SL.get("comp_boss_hp", 1.0)
    if tp == "iberia":
        hp *= bb["iberia_hp_k"]
    if tp == "carmen":
        hp *= bb["carmen_hp_k"]
    if tp == "izumik":
        pass   # 伊祖米克另有 35% 起始、吸收机制，按满血池算
    return hp


def boss_dmg(tp):
    bb = B["boss"]
    d = E[tp]["dmg"] * bb.get("dmg_x_" + tp, 1.0) * SL.get("comp_boss_dmg", 1.0)
    if tp == "iberia":
        d *= bb["saint_dmg_mult"]
    if tp == "carmen":
        d *= bb["carmen_dmg_mult"]
    return d


def static_part():
    out = {"t": TIMES, "rows": []}
    for t in TIMES:
        s, h, el = incoming_hps(t)
        out["rows"].append({
            "t": t, "threat": TH[threat_at(t)]["name"], "hp_time": round(hp_time(t), 2),
            "bone": round(normal_hp("bone", t), 1), "slider": round(normal_hp("slider", t), 1),
            "tracer": round(normal_hp("tracer", t), 1), "founder": round(normal_hp("founder", t), 1),
            "pool_hp": round(pool_avg(normal_hp, t), 1), "elite_hp": round(pool_avg(elite_hp, t), 1),
            "spawn_rate": round(spawn_rate(t), 2), "horde_n": round(horde_n(t), 1),
            "in_spawn": round(s, 1), "in_horde": round(h, 1), "in_elite": round(el, 1), "in_total": round(s + h + el, 1),
            "dmg_target_raw": round(dmg_target(t, comp=False), 1), "dmg_target": round(dmg_target(t), 1),
            "hit_pool": round(pool_avg(mob_hit, t), 1), "hit_bone": round(mob_hit("bone", t), 1),
            "hit_runner": round(mob_hit("runner", t), 1), "hit_tracer": round(mob_hit("tracer", t), 1),
            "hit_reaper": round(mob_hit("reaper", t), 1), "hit_elite_pool": round(pool_avg(mob_hit, t) * EN["elite_dmg_mult"], 1),
        })
    out["bosses"] = {k: {"t": BOSS_SLOT[k], "hp": round(boss_hp(k)), "dmg": round(boss_dmg(k), 1)} for k in BOSS_SLOT}
    return out


# ---------------- 遥测
def load(p):
    if not p:
        return []
    fs = [p] if p.endswith(".json") else glob.glob(os.path.join(p, "**", "*.json"), recursive=True)
    recs = []
    for f in fs:
        d = json.load(open(f, encoding="utf-8"))
        if isinstance(d, dict):
            for w in d.get("records", []):
                r = dict(w.get("data") or {})
                if not r:
                    continue
                r["_start"] = (w.get("squad") or ["?"])[0]
                r["_seed"] = w.get("seed")
                recs.append(r)
    return recs


def rec_start(r):
    if "_start" in r:
        return r["_start"]
    for k in ("squad0", "start", "op"):
        if k in r:
            return r[k]
    sq = r.get("squad_in") or r.get("cfg", {}).get("squad")
    if isinstance(sq, list) and sq:
        return sq[0]
    if isinstance(sq, str):
        return sq.split(",")[0]
    return (r.get("squad") or ["?"])[0]


def curve_stats(recs):
    """按 30 秒格汇总：秒伤（相邻格 outc 差 / 30）、承伤 / 秒、最大生命、回复、等级、在场敌人、击杀 / 秒"""
    by = defaultdict(lambda: defaultdict(list))
    for r in recs:
        cv = (r.get("bot") or {}).get("curve") or []
        prev = None
        for c in cv:
            t = c["t"]
            if prev is not None and "outc" in c:
                by[t]["dps"].append((c["outc"] - prev["outc"]) / max(1, t - prev["t"]))
                by[t]["kps"].append((c["kills"] - prev["kills"]) / max(1, t - prev["t"]))
            by[t]["taken"].append(c["taken"] / 30.0)
            by[t]["press"].append(c["taken"] * 2.0 / max(1, c["mhp"]) * 100)   # 每分钟承伤占最大生命 %
            by[t]["hpmin"].append(c.get("hpmin", 100))
            by[t]["mhp"].append(c["mhp"])
            by[t]["rg"].append(c.get("rg", 0))
            by[t]["lv"].append(c["lv"])
            by[t]["en"].append(c["enemies"])
            by[t]["hpm"].append(c.get("hpm", 0))
            by[t]["squad"].append(c["squad"])
            by[t]["heal"].append(sum((c.get("hsrc") or {}).values()) / 30.0)
            by[t]["boss"].append(c.get("boss", 0))
            by[t]["elites"].append(c.get("elites", 0))
            prev = c
    out = {}
    for t in sorted(by):
        out[t] = {k: (statistics.median(v) if v else 0) for k, v in by[t].items()}
        out[t]["n"] = len(by[t]["mhp"])
        out[t]["dps_mean"] = statistics.mean(by[t]["dps"]) if by[t]["dps"] else 0
        pr = sorted(by[t]["press"]); hm = sorted(by[t]["hpmin"])
        out[t]["press_mean"] = statistics.mean(pr) if pr else 0
        out[t]["press_p90"] = pr[int(0.9 * (len(pr) - 1))] if pr else 0
        out[t]["hpmin_p10"] = hm[int(0.1 * (len(hm) - 1))] if hm else 100
    return out


def win_rate(recs):
    if not recs:
        return None
    return sum(1 for r in recs if r.get("win")) / len(recs)


def boss_times(recs):
    d = defaultdict(list)
    for r in recs:
        for b in (r.get("bot") or {}).get("bosses", []):
            if b.get("t1", -1) >= 0:
                d[b["type"]].append(b["t1"] - b["t0"])
            elif b["type"] in FINAL and r.get("win"):
                d[b["type"]].append(r.get("t", 0) - b["t0"])   # 最终 Boss 倒下即结算，t1 不写
    return {k: (statistics.median(v), len(v), min(v), max(v)) for k, v in d.items()}


def boss_seen(recs):
    d = defaultdict(int)
    for r in recs:
        for b in (r.get("bot") or {}).get("bosses", []):
            d[b["type"]] += 1
    return d


def near(cs, t):
    ks = sorted(cs)
    k = min(ks, key=lambda x: abs(x - t))
    return cs[k]


def main():
    ap = argparse.ArgumentParser()
    for k in ("m0", "m0nd", "m18", "m18nd"):
        ap.add_argument("--" + k)
    ap.add_argument("--dummy", help="op_dummy_table.py 的 table.json（木桩表）")
    ap.add_argument("--out", default="Claude outputs/balance_audit_1110")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    st = static_part()
    res = {"static": st}
    R = {k: load(getattr(a, k)) for k in ("m0", "m0nd", "m18", "m18nd")}
    res["n"] = {k: len(v) for k, v in R.items()}
    res["win"] = {k: win_rate(v) for k, v in R.items()}
    res["boss_t"] = {k: boss_times(v) for k, v in R.items()}
    res["boss_seen"] = {k: boss_seen(v) for k, v in R.items()}
    CS = {k: curve_stats(v) for k, v in R.items() if v}
    res["curve"] = {k: {str(t): v for t, v in cs.items()} for k, cs in CS.items()}
    # 按开局干员的秒伤（不死模式）
    per = {}
    for k in ("m0nd", "m18nd"):
        g = defaultdict(list)
        for r in R.get(k, []):
            g[rec_start(r)].append(r)
        per[k] = {op: {str(t): near(curve_stats(rs), t) for t in TIMES} for op, rs in g.items()}
    res["per_start"] = per
    # 死亡时刻 / 死因
    deaths = {}
    for k in ("m0", "m18"):
        segs = defaultdict(int)
        src = defaultdict(int)
        for r in R.get(k, []):
            if r.get("win"):
                continue
            t = r.get("t", 0)
            seg = "0-3:30" if t < 210 else "3:30-7" if t < 420 else "7-10" if t < 600 else "10+"
            segs[seg] += 1
            src[(r.get("bot") or {}).get("death_src", "?")] += 1
        deaths[k] = {"segs": dict(segs), "src": dict(sorted(src.items(), key=lambda x: -x[1])[:8])}
    res["deaths"] = deaths
    json.dump(res, open(os.path.join(a.out, "audit.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1, default=str)
    plots(st, CS, per, a.out)
    plot_boss(res, a.out)
    if a.dummy:
        plot_dummy(a.dummy, a.out)
    print(json.dumps({"n": res["n"], "win": res["win"]}, ensure_ascii=False))


def plots(st, CS, per, out):
    ts = list(range(0, 631, 10))
    # 1 敌人生命
    fig, ax = plt.subplots(1, 2, figsize=(12, 4.2))
    for tp, lab in (("bone", "骨海漂流体"), ("slider", "底海滑动者"), ("tracer", "深溟引痕者"), ("founder", "深溟奠基者")):
        ax[0].plot([t / 60 for t in ts], [normal_hp(tp, t) for t in ts], label=lab)
    ax[0].plot([t / 60 for t in ts], [pool_avg(normal_hp, t) for t in ts], "k--", label="刷怪池平均")
    ax[0].plot([t / 60 for t in ts], [pool_avg(elite_hp, t) for t in ts], "r:", label="精英（池平均）")
    ax[0].set_yscale("log"); ax[0].set_xlabel("分钟"); ax[0].set_ylabel("单只生命（对数）"); ax[0].set_title("普通怪 / 精英单只生命"); ax[0].legend(fontsize=8); ax[0].grid(alpha=.3)
    sp = [incoming_hps(t) for t in ts]
    ax[1].stackplot([t / 60 for t in ts], [x[0] for x in sp], [x[1] for x in sp], [x[2] for x in sp], labels=["持续刷怪", "大群（摊平）", "精英（摊平）"], alpha=.8)
    for k, c in (("m0nd", "C3"), ("m18nd", "C4")):
        if k in CS:
            tt = [t for t in sorted(CS[k]) if "dps" in CS[k][t]]
            ax[1].plot([t / 60 for t in tt], [CS[k][t]["dps"] for t in tt], color=c, lw=2, label="全队秒伤中位（%s）" % ("无认知" if k == "m0nd" else "18 细胞"))
    ax[1].set_xlabel("分钟"); ax[1].set_ylabel("每秒"); ax[1].set_title("每秒涌入血量 vs 全队秒伤"); ax[1].legend(fontsize=8); ax[1].grid(alpha=.3)
    fig.tight_layout(); fig.savefig(os.path.join(out, "01_enemy_hp.png"), dpi=110); plt.close(fig)
    # 2 我方输出
    fig, ax = plt.subplots(1, 2, figsize=(12, 4.2))
    for k, axx in (("m0nd", ax[0]), ("m18nd", ax[1])):
        for op, d in sorted(per.get(k, {}).items()):
            axx.plot(MINS, [d[str(t)]["dps"] for t in TIMES], marker="o", label=op)
        axx.set_title("全队秒伤（按开局干员，%s，不死模式中位）" % ("无认知" if k == "m0nd" else "18 细胞")); axx.set_xlabel("分钟"); axx.set_yscale("log"); axx.grid(alpha=.3); axx.legend(fontsize=7)
    fig.tight_layout(); fig.savefig(os.path.join(out, "02_squad_dps.png"), dpi=110); plt.close(fig)
    # 3 生存
    fig, ax = plt.subplots(1, 2, figsize=(12, 4.2))
    for k, c in (("m0", "C0"), ("m0nd", "C1"), ("m18nd", "C2")):
        if k in CS:
            tt = sorted(CS[k])
            ax[0].plot([t / 60 for t in tt], [CS[k][t]["mhp"] for t in tt], color=c, label="最大生命 " + k)
            ax[0].plot([t / 60 for t in tt], [CS[k][t]["taken"] * 10 for t in tt], color=c, ls="--", label="承伤/秒 ×10 " + k)
    ax[0].set_title("队长最大生命 vs 承伤（中位）"); ax[0].set_xlabel("分钟"); ax[0].legend(fontsize=7); ax[0].grid(alpha=.3)
    ax[1].plot([t / 60 for t in ts], [pool_avg(mob_hit, t) for t in ts], "k", label="池平均一下")
    for tp, lab in (("runner", "狂奔者"), ("tracer", "引痕者"), ("reaper", "收割者")):
        ax[1].plot([t / 60 for t in ts], [mob_hit(tp, t) for t in ts], label=lab)
    ax[1].plot([t / 60 for t in ts], [pool_avg(mob_hit, t) * EN["elite_dmg_mult"] for t in ts], "r:", label="精英池平均")
    ax[1].plot([t / 60 for t in ts], [dmg_target(t, comp=False) for t in ts], color="gray", ls="--", label="曲线目标（不含后期补偿 ×2）")
    ax[1].set_title("普通怪一下伤害（受伤 0.9、护甲 1.9 后）"); ax[1].set_xlabel("分钟"); ax[1].legend(fontsize=7); ax[1].grid(alpha=.3)
    fig.tight_layout(); fig.savefig(os.path.join(out, "03_survival.png"), dpi=110); plt.close(fig)
    # 5 比值 + 参考怪击杀用时
    fig, ax = plt.subplots(1, 2, figsize=(12, 4.2))
    for k, c in (("m0nd", "C3"), ("m18nd", "C4")):
        if k in CS:
            tt = [t for t in sorted(CS[k]) if t <= 600 and "dps" in CS[k][t]]
            lab = "无认知" if k == "m0nd" else "18 细胞"
            ax[0].plot([t / 60 for t in tt], [CS[k][t]["dps"] / max(1, sum(incoming_hps(t))) for t in tt], color=c, marker=".", label="秒伤 ÷ 公式涌入血量 " + lab)
            ax[1].plot([t / 60 for t in tt], [pool_avg(elite_hp, t) / max(1, CS[k][t]["dps"]) for t in tt], color=c, label="精英（池平均）" + lab)
            ax[1].plot([t / 60 for t in tt], [normal_hp("tracer", t) / max(1, CS[k][t]["dps"]) for t in tt], color=c, ls="--", label="引痕者 " + lab)
            ax[1].plot([t / 60 for t in tt], [normal_hp("bone", t) / max(1, CS[k][t]["dps"]) for t in tt], color=c, ls=":", label="骨海漂流体 " + lab)
    ax[0].axhline(1, color="k", lw=.8)
    ax[0].set_yscale("log"); ax[0].set_xlabel("分钟"); ax[0].set_title("我方秒伤 ÷ 敌方血量涌入（>1 能清得过来）"); ax[0].legend(fontsize=8); ax[0].grid(alpha=.3)
    ax[1].set_yscale("log"); ax[1].set_xlabel("分钟"); ax[1].set_ylabel("秒（全队集火一只的下限）"); ax[1].set_title("参考怪击杀用时 = 单只生命 ÷ 全队秒伤"); ax[1].legend(fontsize=7); ax[1].grid(alpha=.3)
    fig.tight_layout(); fig.savefig(os.path.join(out, "05_ratio.png"), dpi=110); plt.close(fig)


NAMES = {"path": "塑路者", "carmen": "卡门", "iberia": "伊比利亚", "bishop": "主教", "archon": "蔑死体", "immortal": "斥亡体",
         "paranoia": "偏执泡影", "knight_boss": "骑士", "ishar": "伊莎玛拉", "izumik": "伊祖米克"}


def plot_boss(res, out):
    ks = [k for k in NAMES if k in res["boss_t"].get("m0", {}) or k in res["boss_t"].get("m18", {})]
    fig, ax = plt.subplots(figsize=(10, 4.2))
    x = range(len(ks))
    for j, (k, c) in enumerate((("m0", "C3"), ("m18", "C4"))):
        v = [res["boss_t"].get(k, {}).get(b, (0,))[0] for b in ks]
        ax.bar([i + (j - 0.5) * 0.38 for i in x], v, 0.38, color=c, label="无认知" if k == "m0" else "18 细胞")
    ax.axhspan(60, 90, xmin=0, xmax=6 / len(ks), color="green", alpha=.12, label="中期目标 60–90 秒")
    ax.axhspan(90, 120, xmin=6 / len(ks), xmax=1, color="blue", alpha=.10, label="最终参考 90–120 秒")
    ax.set_xticks(list(x)); ax.set_xticklabels([NAMES[b] for b in ks])
    ax.set_ylabel("击杀用时中位（秒，正常局）"); ax.set_title("Boss 击杀用时（expert，56 局 / 档；伊祖米克 / 伊莎玛拉样本 ≤ 4）"); ax.legend(fontsize=8); ax.grid(alpha=.3, axis="y")
    fig.tight_layout(); fig.savefig(os.path.join(out, "04_boss_ttk.png"), dpi=110); plt.close(fig)


def plot_dummy(path, out):
    R = json.load(open(path, encoding="utf-8"))["results"]
    m = defaultdict(dict)
    for r in R:
        if r.get("ok") and r.get("data"):
            m[(r["scene"], r["role"], r["stage"])][r["op"]] = r["data"]["dps"]
    fig, ax = plt.subplots(1, 2, figsize=(12, 4.2))
    for axx, sc, tit in ((ax[0], "single", "木桩（单体）"), (ax[1], "horde", "怪群（30 只）")):
        med = [statistics.median(m[(sc, "leader", s)].values()) for s in (0, 1, 2)]
        lo = [min(m[(sc, "leader", s)].values()) for s in (0, 1, 2)]
        hi = [max(m[(sc, "leader", s)].values()) for s in (0, 1, 2)]
        axx.fill_between([0, 1, 2], lo, hi, color="gray", alpha=.15, label="20 人范围")
        axx.plot([0, 1, 2], med, "k--", label="20 人中位")
        for op, lab in (("skadi", "单体：斯卡蒂"), ("eyjafjalla", "群伤：艾雅法拉"), ("wisadel", "群伤：维什戴尔"), ("kaltsit", "召唤：凯尔希")):
            axx.plot([0, 1, 2], [m[(sc, "leader", s)].get(op, 0) for s in (0, 1, 2)], marker="o", label=lab)
        axx.set_xticks([0, 1, 2]); axx.set_xticklabels(["精零", "精一", "精二"]); axx.set_yscale("symlog", linthresh=10)
        axx.set_title("木桩表 队长秒伤 · " + tit + "（无藏品、不升级）"); axx.grid(alpha=.3); axx.legend(fontsize=7)
    fig.tight_layout(); fig.savefig(os.path.join(out, "02b_dummy_stage.png"), dpi=110); plt.close(fig)


if __name__ == "__main__":
    main()
