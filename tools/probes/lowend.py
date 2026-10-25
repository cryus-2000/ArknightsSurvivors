"""低配帧率基准（docs/50 §28，10-25 用户「帧率你也要考虑到别人的电脑和手机配置不一定有我高」）。

  python tools/probes/lowend.py run  [--web 提交] [--only desk|web] [--tag 前缀]   # 跑整套（约 40 分钟，要安静窗口）
  python tools/probes/lowend.py show [--tag 前缀]                                    # 出表（docs/50 §28 用）+ 对比图 build/lowend/<前缀>.png

桌面「入门笔记本」模拟：画质中（核显机自动档就是中）、1280×720、限 4 / 2 个逻辑核（godot_runner ARK_CORES）。
  显卡没法降（本机 GL 后端固定用独显，--gpu-index 无效），单核也比入门本快约一倍，所以桌面数字偏乐观。
网页「中低端手机」模拟：Edge DevTools CPU 节流 4× / 6× + 手机横屏视口 844×390、3 倍像素、触屏、安卓 UA（自动档 = 中）。
场景：
  late   seed 13 浊心斯卡蒂 + 德克萨斯 + 能天使，9:00–11:00（m09 = 后期满屏，m10F = 10:00 最终 Boss），
         同局每 60 帧轮换自动降档的各级（网页 --stackab=60:0,6,15,143,160；桌面没有缩放级 60:0,6,15,32）
  title  启动 → 标题页揭开后 10 秒；hunt 揭开 3 秒后开寻访看 6 秒（tools/probes/ui_frametimes.py）
"""
import argparse, glob, json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)
sys.path.insert(0, HERE)
import godot_runner as gr

ROOT = os.path.dirname(TOOLS)
OUT = os.path.join(gr.common_root(), "build", "lowend")
LATE = ["--balance", "--nodeath", "--bot=expert", "--realtime", "--perf", "--perfmin", "--seed=13", "--op=skalter", "--squad=texas,exusiai",
        "--rtfrom=540", "--maxt=660", "--stackab=60:0,6,15,143,160"]
# 自动档各级对应的同局轮换掩码（optical 关层位 + 128 分辨率缩放）：现状 / 1 级 / 2 级 / 3 级（缩放，只网页高像素密度屏有）/ ≈ 4 级「低」的光学部分
LEVELS = [("0", "现状"), ("6", "降 1 级"), ("15", "降 2 级"), ("143", "降 3 级（缩放）"), ("160", "≈ 降 4 级（低）")]
DESK_LEVELS = "60:0,6,15,32"


def py(args):
    print(">>", " ".join(args), flush=True)
    subprocess.run([sys.executable] + args, cwd=ROOT)


def run(a):
    os.makedirs(OUT, exist_ok=True)
    t = a.tag
    if a.only in ("", "desk"):
        for c in (0, 4, 2):
            py([os.path.join(HERE, "perf_stack.py"), "run", "late", "%s_d%d_late" % (t, c), "--quality=mid", "--cores=%d" % c, "--maxother=1",
                "--more=--stackab=" + DESK_LEVELS])
            py([os.path.join(HERE, "ui_frametimes.py"), "run", "--tag", "%sd%d" % (t, c), "--scen", "title,hunt", "--maxother", "1",
                "--cores", str(c), "--more", "--quality=mid"])
    if a.only in ("", "web") and a.web:
        import perf_web
        for th in (4, 6):
            lp = perf_web.run(a.web, "%s_w%d_late" % (t, th), ["--"] + LATE, 1500, throttle=th, mobile=True)   # 网页参数前要有 "--" 才算游戏参数
            open(os.path.join(OUT, "%s_w%d_late.txt" % (t, th)), "w", encoding="utf-8").write(open(lp, encoding="utf-8").read())
            py([os.path.join(HERE, "ui_frametimes.py"), "run", "--web", a.web, "--tag", "%sw%d" % (t, th), "--scen", "title,hunt", "--maxother", "1",
                "--throttle", str(th), "--mobile"])


def _perf_from(path):
    perf = None
    for ln in open(path, encoding="utf-8", errors="replace").read().splitlines():
        if ln.startswith("PERF "):
            perf = json.loads(ln[5:])
    return perf


def _ui(tag, scen, seg):
    import ui_frametimes as uf
    fs = sorted(glob.glob(os.path.join(uf.OUT, "%s_%s_*.txt" % (tag, scen))))
    if not fs:
        return None
    return uf.parse(fs[0])[0].get(seg)


def show(a):
    t = a.tag
    rows = []
    cfgs = [("桌面 不限核", "d0", os.path.join(gr.common_root(), "build", "perf_stack", "%s_d0_late" % t, "out.txt")),
            ("桌面 4 核", "d4", os.path.join(gr.common_root(), "build", "perf_stack", "%s_d4_late" % t, "out.txt")),
            ("桌面 2 核", "d2", os.path.join(gr.common_root(), "build", "perf_stack", "%s_d2_late" % t, "out.txt")),
            ("网页 手机 4× 节流", "w4", os.path.join(OUT, "%s_w4_late.txt" % t)),
            ("网页 手机 6× 节流", "w6", os.path.join(OUT, "%s_w6_late.txt" % t))]
    print("| 设备模拟 | 场景 | " + " | ".join(n for _, n in LEVELS) + " |")
    print("|---|---|" + "---|" * len(LEVELS))
    chart = []
    for name, key, path in cfgs:
        perf = _perf_from(path) if os.path.exists(path) else None
        for seg, sname in (("m09", "后期 9–10 分钟"), ("m10F", "10:00 最终 Boss")):
            cells = []
            for m, _ in LEVELS:
                mm = {"143": "15", "160": "32"}.get(m, m) if key.startswith("d") else m   # 桌面没有缩放级：3 级同 2 级，4 级 = 光学整套关
                v = (perf or {}).get("%s/s%s" % (seg, mm))
                cells.append("%.1f / %.1f" % (v["ft_med"], v["ft_p95"]) if v else "—")
                chart.append((name, sname, m, v["ft_med"] if v else None, v["ft_p95"] if v else None))
            print("| %s | %s（P50 / P95） | %s |" % (name, sname, " | ".join(cells)))
        for scen, seg, sname in (("title", "reveal", "主页揭开后 10 秒"), ("hunt", "hunt", "寻访 6 秒")):
            v = _ui("%s%s" % (t, key), scen, seg)
            cell = "P50 %.1f / P95 %.1f / 最长 %.0f" % (v["p50"], v["p95"], v["max"]) if v else "—"
            print("| %s | %s | %s |" % (name, sname, cell + " | " * (len(LEVELS) - 1)))
    json.dump(chart, open(os.path.join(OUT, "%s_chart.json" % t), "w", encoding="utf-8"), ensure_ascii=False)
    _plot(t, chart)


def _plot(t, chart):
    """对比图（用户在手机上看）：每个「设备 × 场景」一组柱，柱 = 自动档各级的 P50，细线 = P95；横线 16.7 / 33.3 ms。要 matplotlib（D:/Anaconda/python.exe）"""
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        from matplotlib import font_manager
    except ImportError:
        print("没有 matplotlib，跳过对比图（用 D:/Anaconda/python.exe 跑 show）")
        return
    for f in ("Microsoft YaHei", "SimHei"):
        if any(f in x.name for x in font_manager.fontManager.ttflist):
            plt.rcParams["font.family"] = f
            break
    groups = []
    for name, sname, m, p50, p95 in chart:
        k = name + "\n" + sname
        if k not in groups:
            groups.append(k)
    cols = ["#3b6e8f", "#5aa0c8", "#8cc7e3", "#c9a227", "#b55d4c"]
    fig, ax = plt.subplots(figsize=(10, 6.5), dpi=150)
    w = 0.16
    for li, (m, lname) in enumerate(LEVELS):
        xs, ys, es = [], [], []
        for gi, k in enumerate(groups):
            for name, sname, mm, p50, p95 in chart:
                if name + "\n" + sname == k and mm == m and p50 is not None:
                    xs.append(gi + (li - 2) * w)
                    ys.append(p50)
                    es.append(max(0.0, p95 - p50))
        ax.bar(xs, ys, w, color=cols[li], label=lname, yerr=[[0] * len(es), es], error_kw={"elinewidth": 0.8, "capsize": 2})
    ax.axhline(16.7, color="#2e8b57", lw=1, ls="--")
    ax.axhline(33.3, color="#cc7a00", lw=1, ls="--")
    ax.text(len(groups) - 0.5, 17.5, "60 帧", color="#2e8b57", ha="right", fontsize=9)
    ax.text(len(groups) - 0.5, 34.1, "30 帧", color="#cc7a00", ha="right", fontsize=9)
    ax.set_xticks(range(len(groups)))
    ax.set_xticklabels(groups, fontsize=8)
    ax.set_ylabel("帧时 毫秒（柱 = P50，细线到 P95）")
    ax.set_title("低配模拟：后期满屏 / 10:00 Boss，自动降档各级")
    ax.legend(fontsize=8, ncol=5, loc="upper left")
    ax.set_ylim(0, min(200, max([p95 for *_, p95 in chart if p95] + [40]) * 1.1))
    fig.tight_layout()
    out = os.path.join(OUT, "%s.png" % t)
    fig.savefig(out)
    print("对比图：", out)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["run", "show"])
    ap.add_argument("--web", default="")
    ap.add_argument("--only", default="")
    ap.add_argument("--tag", default="le")
    a = ap.parse_args()
    run(a) if a.cmd == "run" else show(a)
