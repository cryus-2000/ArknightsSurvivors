"""界面帧时测量（docs/50 §27）：跑游戏里的 --ftrec 记录器（game/scripts/core/frame_rec.gd），按场景汇总 P50 / P95 / 最长帧。

  python tools/probes/ui_frametimes.py run  [--src DIR] [--tag T] [--reps N] [--scen title,hunt,gallery,settle] [--maxother K]
  python tools/probes/ui_frametimes.py show [--tag T ...]

- 桌面：经 tools/godot_runner.py 起窗口（屏幕外 / 副屏、静音、不抢焦点）。屏幕外窗口垂直同步不起作用，缺省 --max-fps 60
  模拟玩家的「最高帧率 60」（量玩家看到的帧，16.7 封顶；超线的帧就是掉帧）；--fps 0 不限帧看余量。
- --src：另一份游戏目录（例如改前副本 build/uift/_src_<提交>/game），用来同一时段交替跑改前 / 改后。
- 开测前等全机 Godot ≤ --maxother（缺省 1）。每局原始输出存 build/uift/<tag>_<场景>_<n>.txt。
- 网页：--web <提交>（tools/perf_web.py 的测量副本，Edge 屏幕外；PF 行由副本回传）。
"""
import argparse, glob, json, os, re, sys, time

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
import godot_runner as gr

ROOT = os.path.dirname(TOOLS)
OUT = os.path.join(gr.common_root(), "build", "uift")
SCEN = {
    # 启动页 → 标题页首帧后 10 秒（含开场动画）
    "title": ["--ftrec", "--ftquit=title:10"],
    # 标题页 4 秒后打开寻访，看 6 秒
    "hunt": ["--ftrec", "--ftdo=title:4:hunt", "--ftquit=hunt:6"],
    # 标题页 4 秒后开图鉴，2.5 秒后换条目，再 2.5 秒换页签，看 3 秒
    "gallery": ["--ftrec", "--ftdo=title:4:gallery", "--ftdo=gallery:2.5:gal_next", "--ftdo=gal_next:2.5:gal_tab", "--ftquit=gal_tab:3"],
    # 机器人打 20 秒直接胜利，停在结算页 6 秒
    "settle": ["--ftrec", "--autotest", "--statsshot=20,hold", "--ftquit=settle:6"],
    # 走玩家路径进局（载入页）：对局第一帧后看 10 秒
    "enter": ["--ftrec", "--autotest", "--loadprof", "--ftquit=game:10"],
}
SEG_RE = re.compile(r"PF FTSEG (\S+) n=(\d+) mean=([\d.]+) p50=([\d.]+) p95=([\d.]+) p99=([\d.]+) max=([\d.]+) over16=(\d+) over33=(\d+)")
LONG_RE = re.compile(r"PF FTLONG seg=(\S+) t=([\d.]+) ms=([\d.]+)(.*)")


def run(a):
    os.makedirs(OUT, exist_ok=True)
    gdir = a.src or os.path.join(ROOT, "game")
    for rep in range(a.reps):
        for sc in a.scen.split(","):
            t0 = time.time()
            while gr.count_godot() > a.maxother and time.time() - t0 < 1800:
                time.sleep(5)
            busy = gr.count_godot()
            if a.web:
                # 网页：perf_web 的测量副本（按提交导出），参数前要有 "--" 才算游戏参数
                import perf_web
                lp = perf_web.run(a.web, "%s_%s_%d" % (a.tag, sc, rep), ["--"] + SCEN[sc], 300)
                out, err, to = open(lp, encoding="utf-8").read(), "", "PF FTDONE" not in open(lp, encoding="utf-8").read()
            else:
                args = [gr.find_godot(), "--path", gdir, "--audio-driver", "Dummy", "--resolution", a.res, "--max-fps", str(a.fps), "--"] + SCEN[sc]
                out, err, to = gr.run_godot(args, 300)
            p = os.path.join(OUT, "%s_%s_%d.txt" % (a.tag, sc, rep))
            open(p, "w", encoding="utf-8").write("# other_godot=%d timeout=%s\n%s\n--- stderr\n%s" % (busy, to, out, err))
            segs = SEG_RE.findall(out)
            print("%s %s #%d 其他 Godot %d%s：%s" % (a.tag, sc, rep, busy, " 超时" if to else "",
                  "  ".join("%s p95=%s max=%s" % (s[0], s[4], s[6]) for s in segs) or ("无结果 " + "; ".join(gr.script_errors(out, err)[:3]))))


def parse(path):
    txt = open(path, encoding="utf-8").read()
    segs = {s[0]: dict(zip(["n", "mean", "p50", "p95", "p99", "max", "o16", "o33"], map(float, s[1:]))) for s in SEG_RE.findall(txt)}
    longs = [(m[0], float(m[1]), float(m[2]), m[3].strip()) for m in LONG_RE.findall(txt)]
    return segs, longs


def show(a):
    tags = a.tag or sorted({os.path.basename(p).split("_")[0] for p in glob.glob(os.path.join(OUT, "*_*_*.txt"))})
    want = {"title": ["boot", "title"], "hunt": ["hunt"], "gallery": ["gallery", "gal_next", "gal_tab"], "settle": ["settle"], "enter": ["loading", "game"]}
    print("| 版本 | 场景 | 段 | 局数 | 平均 | P50 | P95 | P99 | 最长（各局） | >16.9 帧占比 |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for t in tags:
        for sc, segnames in want.items():
            files = sorted(glob.glob(os.path.join(OUT, "%s_%s_*.txt" % (t, sc))))
            if not files:
                continue
            data = [parse(f)[0] for f in files]
            for sn in segnames:
                rows = [d[sn] for d in data if sn in d]
                if not rows:
                    continue
                k = len(rows)
                med = lambda key: sorted(r[key] for r in rows)[k // 2]
                print("| %s | %s | %s | %d | %.2f | %.2f | %.2f | %.2f | %s | %.0f%% |" % (t, sc, sn, k, med("mean"), med("p50"), med("p95"), med("p99"),
                      " / ".join("%.0f" % r["max"] for r in rows), 100.0 * sum(r["o16"] for r in rows) / max(1, sum(r["n"] for r in rows))))
    if a.longs:
        for t in tags:
            for f in sorted(glob.glob(os.path.join(OUT, "%s_*_*.txt" % t))):
                for lg in parse(f)[1]:
                    print(os.path.basename(f), lg)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["run", "show"])
    ap.add_argument("--src")
    ap.add_argument("--tag", action="append")
    ap.add_argument("--reps", type=int, default=1)
    ap.add_argument("--scen", default="title,hunt,gallery,settle")
    ap.add_argument("--maxother", type=int, default=1)
    ap.add_argument("--res", default="1280x720")
    ap.add_argument("--fps", type=int, default=60, help="桌面帧率上限（同玩家缺省设置「最高帧率 60」；0 = 不限，看余量）")
    ap.add_argument("--longs", action="store_true")
    ap.add_argument("--web", help="网页：测量副本的提交（tools/perf_web.py export 的 --ref）")
    a = ap.parse_args()
    if a.cmd == "run":
        a.tag = (a.tag or ["cur"])[0]
        run(a)
    else:
        show(a)
