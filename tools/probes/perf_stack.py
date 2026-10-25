"""叠加后的帧时测量（docs/50 §26，10-25 帧率会话）：本机开窗口短局（godot_runner 屏幕外、静音），--perf 分桶，可选 --stackab 同局逐层关闭。

  python tools/probes/perf_stack.py run <场景> <标签> [--quality=mid|high] [--stackab=60:0,1,2] [--prof] [--more="--bal=x=y --foo"] [--gamedir=<另一份 game 目录>]
  python tools/probes/perf_stack.py show <标签> [<标签> …]        # 打印各桶 平均 / P50 / P95 / P99 / 最长 / GPU / 绘制调用 / 敌人
  python tools/probes/perf_stack.py stages <标签> [桶前缀]          # --prof 分段（毫秒 / 帧，探针会把各段放大约 2 倍，只看相对大小）

场景（都是 --balance --nodeath --bot=expert --fixed-fps 60 --realtime，快进到 rtfrom 后按真实步长）：
  c100   docs/50 §24：水月单人 seed 1，同屏上限压到 ~100（enemy/max_alive=250），360–600 秒
  late   seed 13 浊心斯卡蒂 + 德克萨斯 + 能天使，540–660 秒（9:00 后满屏 + 10:00 最终 Boss）
  skills  seed 13 乌尔比安 + 浊心斯卡蒂 + 维什戴尔（冲锋 / 水 / 连环爆颗粒齐放），--prog=8，360–600 秒，同屏上限 ~100
  skills2 seed 13 艾雅法拉 + 拉普兰德 + 德克萨斯（火 / 熔岩颗粒 + 两名近战刀光），其余同 skills（编队上限 3 人）
输出：<主仓库>/build/perf_stack/<标签>/out.txt、perf.json、load.txt（每 5 秒全机 Godot 数）。开测前等全机 Godot ≤ --maxother 个（缺省 0，最多等 20 分钟）。
"""
import json, os, sys, threading, time

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
import godot_runner as gr

ROOT = os.path.dirname(TOOLS)
OUT = os.path.join(gr.common_root(), "build", "perf_stack")
COMMON = ["--balance", "--nodeath", "--bot=expert", "--realtime", "--perf", "--perfmin"]
SCEN = {
    "c100": ["--seed=1", "--op=mizuki", "--norecruit", "--rtfrom=360", "--maxt=600", "--bal=enemy/max_alive=250"],
    "late": ["--seed=13", "--op=skalter", "--squad=texas,exusiai", "--rtfrom=540", "--maxt=660"],
    "skills": ["--seed=13", "--op=ulpianus", "--squad=skalter,wisadel", "--prog=8", "--rtfrom=360", "--maxt=600", "--bal=enemy/max_alive=250"],
    "skills2": ["--seed=13", "--op=eyjafjalla", "--squad=lappland,texas", "--prog=8", "--rtfrom=360", "--maxt=600", "--bal=enemy/max_alive=250"],
}


def run(scen, tag, quality, stackab, prof, more, maxother, res, gamedir=None):
    d = os.path.join(OUT, tag)
    os.makedirs(d, exist_ok=True)
    gr.ensure_imported(gamedir or os.path.join(ROOT, "game"))   # 合过 main 后新素材没导入会整局卡在解析错误里（10-25 实测）
    t0 = time.time()
    while gr.count_godot() > maxother and time.time() - t0 < 1200:
        time.sleep(15)
    args = [gr.find_godot(), "--path", gamedir or os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "60", "--resolution", res, "--"]
    args += COMMON + SCEN[scen] + ["--quality=" + quality]
    if stackab:
        args.append("--stackab=" + stackab)
    if prof:
        args.append("--prof")
    extra = [x for x in more.split(" ") if x]
    keys = {x.split("=", 1)[0] for x in extra if x.startswith("--") and "=" in x and not x.startswith("--bal=")}
    args = [x for x in args if not (x.startswith("--") and x.split("=", 1)[0] in keys and "=" in x)] + extra   # --more 里同名参数替换场景缺省（游戏里先出现的生效）
    load, stop = [], threading.Event()

    def watch():
        while not stop.is_set():
            load.append((round(time.time() - t0), gr.count_godot()))
            stop.wait(5)
    th = threading.Thread(target=watch, daemon=True)
    th.start()
    out, err, to = gr.run_godot(args, 3000)
    stop.set()
    open(os.path.join(d, "out.txt"), "w", encoding="utf-8").write(" ".join(args) + "\n" + out + "\n--- stderr\n" + err)
    open(os.path.join(d, "load.txt"), "w", encoding="utf-8").write("\n".join("%d %d" % x for x in load))
    perf = None
    for ln in out.splitlines():
        if ln.startswith("PERF "):
            perf = json.loads(ln[5:])
    if perf is None:
        print("没有 PERF 行（超时 %s）；脚本错误：%s" % (to, gr.script_errors(out, err)[:5]))
        return
    json.dump(perf, open(os.path.join(d, "perf.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    ls = [n for _, n in load]
    print("%s 完成：全机 Godot 数 中位 %s / 最多 %s（含本局 1 个）" % (tag, sorted(ls)[len(ls) // 2] if ls else "-", max(ls) if ls else "-"))
    show([tag])


def show(tags):
    print("| 标签 | 桶 | 帧数 | 平均 | P50 | P95 | P99 | 最长 | >16.7 | 渲染CPU | GPU | 绘制调用 | 敌人中位/峰值 |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for t in tags:
        p = json.load(open(os.path.join(OUT, t, "perf.json"), encoding="utf-8"))
        for w in sorted(k for k in p if isinstance(p[k], dict) and "n" in p[k]):
            b = p[w]
            if b["n"] < 120 or w.endswith("/sx"):
                continue
            print("| %s | %s | %d | %.2f | %.2f | %.2f | %.2f | %.1f | %.1f%% | %.2f | %.2f | %d | %d/%d |" % (t, w, b["n"], b["ft_mean"], b["ft_med"], b["ft_p95"], b["ft_p99"], b["ft_max"],
                  b["over16_pct"], b["rcpu_med"], b["gpu_med"], b["dc_med"], b["en_med"], b["en_peak"]))


def stages(tag, pre=""):
    p = json.load(open(os.path.join(OUT, tag, "perf.json"), encoding="utf-8"))
    for w in sorted(k for k in p if isinstance(p[k], dict) and "stage_ms" in p[k]):
        if not w.startswith(pre) or p[w]["n"] < 120:
            continue
        st = p[w]["stage_ms"]
        print(w, p[w]["n"], "  ".join("%s %.2f" % (k, v) for k, v in list(st.items())[:28]))


if __name__ == "__main__":
    a = sys.argv[1:]
    opt = {x.split("=", 1)[0]: (x.split("=", 1)[1] if "=" in x else "1") for x in a if x.startswith("--")}
    pos = [x for x in a if not x.startswith("--")]
    if pos[0] == "run":
        run(pos[1], pos[2], opt.get("--quality", "high"), opt.get("--stackab", ""), "--prof" in opt, opt.get("--more", ""), int(opt.get("--maxother", "0")),
            opt.get("--res", "1280x720"), opt.get("--gamedir"))
    elif pos[0] == "show":
        show(pos[1:])
    elif pos[0] == "stages":
        stages(pos[1], pos[2] if len(pos) > 2 else "")
