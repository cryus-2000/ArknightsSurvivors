"""安静窗口一键测量（docs/50 §26.6，帧率会话 10-25）：协调人发「可以测」（全机暂停本地 Godot）后一次跑完桌面 + 网页，出前 / 后对照表。

  python tools/probes/perf_window.py prep [--base=<提交>]   # 窗口前做：导出改前代码副本（桌面）+ 前 / 后两份网页测量副本；不量帧时
  python tools/probes/perf_window.py run [--base=<提交>] [--only=名1,名2] [--skipweb]
  python tools/probes/perf_window.py report                  # 只重出汇总（build/perf_stack/window.md）

改前 = --base（缺省 1dab9d3b2：已带 --stackab 测量开关、未做优化）；改后 = 当前工作树（HEAD 须已提交，网页副本按 HEAD 导出）。
桌面每局开测前要求全机没有别的 Godot（--maxother=0，最多等 20 分钟，逐 5 秒记负载）；网页局不起 Godot。顺序按重要性排，窗口不够时从后面砍。
"""
import json, os, shutil, subprocess, sys, tarfile, io

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)
sys.path.insert(0, HERE)
import godot_runner as gr
import perf_stack as ps

ROOT = os.path.dirname(TOOLS)
OUT = ps.OUT
LAYERS = "60:0,1,2,4,8,16,32"
# (名, 场景, 画质, 前 / 后, 额外参数)：前 = 改前副本，后 = 当前工作树
DESK = [
    ("c100_mid_new", "c100", "mid", "new", "--stackab=" + LAYERS),
    ("c100_mid_base", "c100", "mid", "base", "--stackab=" + LAYERS),
    ("c100_high_base", "c100", "high", "base", "--stackab=" + LAYERS),
    ("late_mid_new", "late", "mid", "new", ""),
    ("late_high_base", "late", "high", "base", ""),
    ("late_mid_base", "late", "mid", "base", ""),
    ("skills_mid_new", "skills", "mid", "new", ""),
    ("skills2_mid_new", "skills2", "mid", "new", ""),
    ("c100_mid_noadapt", "c100", "mid", "new", "--more=--bal=fx/grains_adapt=0"),
    ("c100_high_new", "c100", "high", "new", "--stackab=" + LAYERS),
]
WEB_C100 = ["--balance", "--nodeath", "--bot=expert", "--realtime", "--perf", "--perfmin", "--seed=1", "--op=mizuki", "--norecruit",
            "--rtfrom=360", "--maxt=600", "--bal=enemy/max_alive=250", "--quality=mid"]
WEB_LATE = ["--balance", "--nodeath", "--bot=expert", "--realtime", "--perf", "--perfmin", "--seed=13", "--op=skalter", "--squad=texas,exusiai",
            "--rtfrom=540", "--maxt=660", "--quality=mid"]
WEB = [
    ("web_c100_mid_new", "new", WEB_C100 + ["--stackab=" + LAYERS]),
    ("web_late_mid_new", "new", WEB_LATE),
    ("web_late_mid_base", "base", WEB_LATE),
]


def sha(ref):
    return subprocess.run(["git", "-C", ROOT, "rev-parse", "--short=9", ref], capture_output=True, text=True, check=True).stdout.strip()


def base_dir(base):
    return os.path.join(OUT, "_src_" + sha(base))


def prep(base):
    d = base_dir(base)
    if not os.path.exists(os.path.join(d, "art", "incoming")):
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d)
        data = subprocess.run(["git", "archive", "--format=tar", base, "game", "art/incoming"], cwd=ROOT, stdout=subprocess.PIPE, check=True).stdout   # 桌面版从项目外 ../art/incoming 读原图
        tarfile.open(fileobj=io.BytesIO(data)).extractall(d, filter="data")
        shutil.copytree(os.path.join(ROOT, "game", ".godot"), os.path.join(d, "game", ".godot"))   # 导入缓存借当前工作树的（美术相同）
        print("[改前副本]", d, "缺导入", len(gr.stale_imports(os.path.join(d, "game"))))
    import perf_web as pw
    for ref in (base, "HEAD"):
        print("[网页副本]", pw.export(ref))


def run(base, only, skipweb):
    gd = os.path.join(base_dir(base), "game")
    if not os.path.exists(os.path.join(gd, "project.godot")):
        sys.exit("先跑 prep")
    for name, scen, q, which, extra in DESK:
        if only and name not in only:
            continue
        more = extra[len("--more="):] if extra.startswith("--more=") else ""
        stack = extra[len("--stackab="):] if extra.startswith("--stackab=") else ""
        ps.run(scen, "w_" + name, q, stack, False, more, 0, "1280x720", gd if which == "base" else None)
    if skipweb:
        return
    import perf_web as pw
    for name, which, args in WEB:
        if only and name not in only:
            continue
        log = pw.run(base if which == "base" else os.environ.get("PW_NEW", "HEAD"), "w_" + name, ["--fixed-fps", "60", "--"] + args, 1800)
        perf = [l for l in open(log, encoding="utf-8").read().splitlines() if l.startswith("PERF ")]
        if perf:
            d = os.path.join(OUT, "w_" + name)
            os.makedirs(d, exist_ok=True)
            open(os.path.join(d, "perf.json"), "w", encoding="utf-8").write(perf[-1][5:])
    report()


def report():
    rows = []
    for name in [x[0] for x in DESK] + [x[0] for x in WEB]:
        p = os.path.join(OUT, "w_" + name, "perf.json")
        if not os.path.exists(p):
            continue
        pf = json.load(open(p, encoding="utf-8"))
        ld = os.path.join(OUT, "w_" + name, "load.txt")
        mx = max((int(l.split()[1]) for l in open(ld).read().splitlines() if l.strip()), default=0) if os.path.exists(ld) else 0
        for w in sorted(k for k in pf if isinstance(pf[k], dict) and "n" in pf[k]):
            b = pf[w]
            if b["n"] < 120 or w.endswith("/sx"):
                continue
            rows.append("| %s | %s | %d | %.2f | %.2f | %.2f | %.2f | %.1f | %.1f%% | %.2f | %.2f | %d | %d/%d | %d |" % (name, w, b["n"], b["ft_mean"], b["ft_med"], b["ft_p95"],
                        b["ft_p99"], b["ft_max"], b["over16_pct"], b["rcpu_med"], b["gpu_med"], b["dc_med"], b["en_med"], b["en_peak"], mx))
    md = ["| 局 | 桶 | 帧数 | 平均 | P50 | P95 | P99 | 最长 | >16.7 | 渲染CPU | GPU | 绘制调用 | 敌人中位/峰值 | 全机 Godot 最多 |",
          "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"] + rows
    open(os.path.join(OUT, "window.md"), "w", encoding="utf-8").write("\n".join(md) + "\n")
    print("\n".join(md))


if __name__ == "__main__":
    a = sys.argv[1:]
    opt = {x.split("=", 1)[0]: (x.split("=", 1)[1] if "=" in x else "1") for x in a if x.startswith("--")}
    base = opt.get("--base", "1dab9d3b2")
    cmd = [x for x in a if not x.startswith("--")][0]
    if cmd == "prep":
        prep(base)
    elif cmd == "run":
        run(base, set(opt["--only"].split(",")) if "--only" in opt else None, "--skipweb" in opt)
    else:
        report()
