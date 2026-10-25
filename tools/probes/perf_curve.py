"""网页缺省画质 / 同屏上限的同局测法（docs/50 §26.9）：一局里每 60 帧轮换画质组合（--stackab），逐帧记 帧时 + 同屏敌人数（--perfline），
按「组合 × 敌人数档」出帧时表——跨局噪声（§26.8 网页单局对比下不了结论）不进比较。

  python tools/probes/perf_curve.py web <标签> <场景> [--ref=<提交>] [--masks=0,64,2,32]   # 网页（tools/perf_web.py 测量副本，Edge 屏外）
  python tools/probes/perf_curve.py desk <标签> <场景> [--masks=…] [--quality=mid]          # 桌面（godot_runner 屏外）
  python tools/probes/perf_curve.py ana <标签> [--bin=10]

场景同 perf_stack：c100（同屏上限压到 ~100，敌人数 60–118 都有，读上限曲线）/ late（9:00 后满屏 + 10:00 最终 Boss）。
掩码（optical.ab_mask）：0 = 现中档（改后：颗粒同高档）；64 = GPU 粒子爆发减半（近似池子减半）；2 = GPU 粒子全关；32 = 整套光学关（≈ 低档画面的主要部分，
低档另关水下滤镜 / 景深 / 演出，所以真低档还要再省一点）。切换后 3 帧不计。结果：build/perf_stack/curve_<标签>/pf.csv、table.md。
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)
sys.path.insert(0, HERE)
import godot_runner as gr
import perf_stack as ps

N = 60
NAMES = {0: "现中档（满量颗粒）", 64: "GPU 粒子减半", 2: "GPU 粒子全关", 32: "整套光学关（≈低档）", 1: "CPU 颗粒关", 8: "发光层关"}


def out_dir(tag):
    d = os.path.join(ps.OUT, "curve_" + tag)
    os.makedirs(d, exist_ok=True)
    return d


def _save(tag, lines):
    rows = []
    for ln in lines:
        if ln.startswith("PF "):
            rows += ln[3:].split(" ")
    open(os.path.join(out_dir(tag), "pf.csv"), "w", encoding="utf-8").write("frame,t,ft,en,boss,dc,mask\n" + "\n".join(rows) + "\n")
    print("PF 帧数", len(rows))


def web(tag, scen, ref, masks):
    import perf_web as pw
    args = list(ps.COMMON) + ps.SCEN[scen] + ["--quality=mid", "--stackab=%d:%s" % (N, masks), "--perfline"]
    log = pw.run(ref, "curve_" + tag, ["--fixed-fps", "60", "--"] + args, 2400)
    _save(tag, open(log, encoding="utf-8").read().splitlines())
    ana(tag)


def desk(tag, scen, masks, quality):
    ps.run(scen, "curve_" + tag, quality, "%d:%s" % (N, masks), False, "--perfline", 0, "1280x720")
    _save(tag, open(os.path.join(ps.OUT, "curve_" + tag, "out.txt"), encoding="utf-8").read().splitlines())
    ana(tag)


def _pct(a, q):
    a = sorted(a)
    return a[min(len(a) - 1, int(q * (len(a) - 1) + 0.5))] if a else float("nan")


def ana(tag, binw=10):
    rows = []
    for ln in open(os.path.join(out_dir(tag), "pf.csv"), encoding="utf-8").read().splitlines()[1:]:
        f, t, ft, en, boss, dc, m = ln.split(",")
        f = int(f)
        if 1 <= f % N <= 3:
            continue   # 切换后 3 帧
        rows.append((float(t), float(ft), int(en), int(boss), int(dc), int(m)))
    masks = sorted({r[5] for r in rows}, key=lambda m: (m != 0, m))
    md = ["## %s（%d 帧，切换后 3 帧已去掉）" % (tag, len(rows)), ""]

    def table(title, sel):
        md.append("### " + title)
        md.append("")
        md.append("| 敌人数 | " + " | ".join("%s 平均 / P50 / P95（帧数）" % NAMES.get(m, "掩码 %d" % m) for m in masks) + " |")
        md.append("|---|" + "---|" * len(masks))
        bins = sorted({(r[2] // binw) * binw for r in rows if sel(r)})
        for b in bins + ["全部"]:
            cells = []
            for m in masks:
                xs = [r[1] for r in rows if sel(r) and r[5] == m and (b == "全部" or b <= r[2] < b + binw)]
                cells.append("%.2f / %.2f / %.2f（%d）" % (sum(xs) / len(xs), _pct(xs, 0.5), _pct(xs, 0.95), len(xs)) if len(xs) >= 60 else "—（%d）" % len(xs))
            md.append("| %s | %s |" % (b if b == "全部" else "%d–%d" % (b, b + binw - 1), " | ".join(cells)))
        md.append("")
    table("非 Boss 段", lambda r: not r[3])
    if any(r[3] for r in rows):
        table("最终 Boss 在场", lambda r: r[3])
    open(os.path.join(out_dir(tag), "table.md"), "w", encoding="utf-8").write("\n".join(md) + "\n")
    print("\n".join(md))


if __name__ == "__main__":
    a = sys.argv[1:]
    opt = {x.split("=", 1)[0]: (x.split("=", 1)[1] if "=" in x else "1") for x in a if x.startswith("--")}
    pos = [x for x in a if not x.startswith("--")]
    masks = opt.get("--masks", "0,64,2,32")
    if pos[0] == "web":
        web(pos[1], pos[2], opt.get("--ref", "HEAD"), masks)
    elif pos[0] == "desk":
        desk(pos[1], pos[2], masks, opt.get("--quality", "mid"))
    else:
        ana(pos[1], int(opt.get("--bin", "10")))
