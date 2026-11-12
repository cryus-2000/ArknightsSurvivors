"""普通怪单下伤害：换档渐入 + 显式折扣曲线（docs/335 §7）。静态复算，模型同 tools/balance_audit_1110.py。

旧口径（dmg_curve/norm_full 0）：时间倍率按池平均「基础伤害」归一，dmg_x_<类型>（引痕者 0.81）与 tier_dmg 在归一化之外，
  换池时池平均一下会跟着组成跳（4:40 −16%、1:15 −2.4%、8:40 −3.8%）。
新口径（norm_full 1）：归一化分母把 dmg_x 与（渐入后的）tier_dmg 都算进去，池平均一下 = 有效目标 T'(t)，与组成无关；
  原来靠 tier_dmg 隐式压下的平均降幅改成显式折扣 dmg_curve/relief（[秒, 系数] 线性插值），T'(t) = 按秒累计最高的 target(t) × relief(t)，处处单调。
tier_hp / tier_dmg 换档时在 enemy/tier_ramp 秒内从上一档线性过渡（个体之间的相对强弱用，平均伤害不受影响）。

  python tools/tier_ramp_solve.py                 # 旧口径曲线 + 回落点
  python tools/tier_ramp_solve.py --new           # 新口径（读 balance.json 的 relief / tier_ramp）
  python tools/tier_ramp_solve.py --fit           # 按旧口径每档平均比值标定 relief 节点（打印建议值）
  --plot out.png [--compare] 画图（--compare 同时画旧口径）
"""
import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import balance_audit_1110 as A

DC = A.B["dmg_curve"]
TH = A.TH
RAMP = float(A.EN.get("tier_ramp", 20.0))


def tier_val(key, t):
    k = A.threat_at(t)
    cur = float(TH[k].get(key, 1.0) or 1.0)
    if k == 0 or RAMP <= 0:
        return cur
    prev = float(TH[k - 1].get(key, 1.0) or 1.0)
    x = A.clamp((t - TH[k]["t"]) / RAMP, 0.0, 1.0)
    return prev + (cur - prev) * x


def type_k(tp, t, ramp=True):
    k = A.EN.get("dmg_x_" + tp, 1.0)
    if A.E[tp].get("tier_cap"):
        k *= tier_val("tier_dmg", t) if ramp else float(TH[A.threat_at(t)].get("tier_dmg", 1.0) or 1.0)
    return k


def relief(t, knots):
    if not knots:
        return 1.0
    if t <= knots[0][0]:
        return knots[0][1]
    for (a, va), (b, vb) in zip(knots, knots[1:]):
        if t <= b:
            return va + (vb - va) * (t - a) / max(1e-9, b - a)
    return knots[-1][1]


_tm = {}
def target_eff(t, knots):
    key = json.dumps(knots)
    if key not in _tm:
        arr, m = [], -1e9
        for s in range(0, 901):
            m = max(m, A.dmg_target(s) * relief(s, knots))
            arr.append(m)
        _tm[key] = arr
    arr = _tm[key]
    i = min(int(t), len(arr) - 2)
    return arr[i] + (arr[i + 1] - arr[i]) * (t - i)


def hit_old(tp, t):
    th = A.threat_at(t)
    m = max(0.05, (A.dmg_target(t) + DC["ref_armor"]) / (A.pool_avg_dmg(th) * A.dens_k() * DC["ref_taken"]))
    d = A.E[tp]["dmg"] * m * A.dens_k() * type_k(tp, t, ramp=False)
    return max(0.0, d * DC["ref_taken"] - DC["ref_armor"])


def hit_new(tp, t, knots):
    th = A.threat_at(t)
    pool = TH[th]["pool"]
    avg = sum(A.E[p]["dmg"] * type_k(p, t) for p in pool) / len(pool)
    m = max(0.05, (target_eff(t, knots) + DC["ref_armor"]) / (avg * A.dens_k() * DC["ref_taken"]))
    d = A.E[tp]["dmg"] * m * A.dens_k() * type_k(tp, t)
    return max(0.0, d * DC["ref_taken"] - DC["ref_armor"])


def curve(f, step=5):
    return [(t, A.pool_avg(f, t)) for t in range(0, 601, step)]


def problems(cv, jump=0.15):
    bad = []
    for (t0, a), (t1, b) in zip(cv, cv[1:]):
        if b < a - 1e-6:
            bad.append(("回落", t0, t1, round(a, 2), round(b, 2), round(b / a - 1, 4)))
        elif a > 0 and b / a - 1 > jump:
            bad.append(("跳变", t0, t1, round(a, 2), round(b, 2), round(b / a - 1, 4)))
    return bad


def fit():
    old = dict(curve(hit_old))
    out = []
    for k, th in enumerate(TH):
        t0 = int(th["t"])
        t1 = int(TH[k + 1]["t"]) if k + 1 < len(TH) else 600
        rs = [old[t] / A.dmg_target(t) for t in range(t0 + 10 - t0 % 5, t1, 5) if t in old]
        r = sum(rs) / len(rs)
        out.append((k, t0, round(r, 3)))
        print("第 %d 档 %3ds  旧口径 池平均一下 / 目标 平均 %.3f" % (k, t0, r))
    return out


if __name__ == "__main__":
    knots = json.loads(sys.argv[sys.argv.index("--knots") + 1]) if "--knots" in sys.argv else DC.get("relief", [])
    if "--fit" in sys.argv:
        fit()
    new = "--new" in sys.argv
    cv = curve((lambda tp, t: hit_new(tp, t, knots)) if new else hit_old)
    pb = problems(cv)
    print("%s；渐入 %.0f 秒；问题 %d 处" % ("新口径" if new else "旧口径", RAMP, len(pb)))
    for p in pb:
        print("  ", p)
    for t in (60, 70, 75, 120, 165, 170, 180, 240, 275, 280, 300, 330, 360, 400, 420, 480, 515, 520, 540, 600):
        print("  %3d  %.2f" % (t, dict(cv)[t]))
    if new:
        old = dict(curve(hit_old))
        for a, b in ((0, 210), (210, 420), (420, 600), (240, 330)):
            o = [old[t] for t in range(a, b, 5)]
            n = [dict(cv)[t] for t in range(a, b, 5)]
            print("  %d–%d 秒平均：旧 %.2f  新 %.2f（%+.1f%%）" % (a, b, sum(o) / len(o), sum(n) / len(n), 100 * (sum(n) / sum(o) - 1)))
    if "--plot" in sys.argv:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        out = sys.argv[sys.argv.index("--plot") + 1]
        fig, ax = plt.subplots(figsize=(8, 4.2))
        if "--compare" in sys.argv:
            oc = curve(hit_old)
            ax.plot([t / 60 for t, _ in oc], [v for _, v in oc], color="#999", lw=1.6, label="改前（换池时跟着组成跳）")
        ax.plot([t / 60 for t, _ in cv], [v for _, v in cv], color="#c0392b", lw=2.2, label="改后（渐入 + 显式折扣，单调）")
        for th in TH[1:]:
            ax.axvline(th["t"] / 60, color="#ddd", lw=0.8, zorder=0)
            ax.text(th["t"] / 60, ax.get_ylim()[1] if False else 2, th.get("name", ""), fontsize=8, color="#888", rotation=90, va="bottom")
        ax.set_xlabel("分钟")
        ax.set_ylabel("普通怪一下（池平均）")
        ax.set_title("普通怪单下伤害，常规档，5 秒步长")
        ax.legend(loc="upper left")
        fig.tight_layout()
        fig.savefig(out, dpi=130)
        print("图", out)
