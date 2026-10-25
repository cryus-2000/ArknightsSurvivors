"""帧率优化的画面对照（docs/50 §26）：同 seed、同帧，改前副本跑两次（旧对旧 = 噪声底）、改后跑一次，逐像素比。

  python tools/probes/perf_pixcmp.py rec <标签> [--base=<提交>] [--t=560] [--n=30] [--more="--bal=fx/grains=0"]
  D:/Anaconda/python.exe tools/probes/perf_pixcmp.py cmp <标签>      # 要 PIL：每帧 旧对旧 / 旧对新 的差异像素数，另存差异最大一帧的三联图

--balance 非实时（每帧步长固定）、--fixed-fps 60、1280×720 窗口（godot_runner 屏幕外、静音），录 [t, t + n 帧)。
CPU 颗粒用画面随机流且受屏外不发 / 帧时自适应影响，颗粒位置两边必然不同；比其余改动时加 --more="--bal=fx/grains=0"。
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)
ROOT = os.path.dirname(TOOLS)


def rec(tag, base, t, n, more):
    import godot_runner as gr
    import perf_window as pw
    out = os.path.join(gr.common_root(), "build", "perf_stack", "pix_" + tag)
    gdb = os.path.join(pw.base_dir(base), "game")
    for name, gd in (("base1", gdb), ("base2", gdb), ("new", os.path.join(ROOT, "game"))):
        d = os.path.join(out, name)
        os.makedirs(d, exist_ok=True)
        args = [gr.find_godot(), "--path", gd, "--audio-driver", "Dummy", "--fixed-fps", "60", "--resolution", "1280x720", "--",
                "--balance", "--nodeath", "--bot=expert", "--seed=13", "--op=skalter", "--squad=texas,exusiai", "--quality=mid",
                "--maxt=%g" % (t + 5), "--recframes=%g,%d" % (t, n), "--shotdir=" + d.replace(os.sep, "/")] + [x for x in more.split(" ") if x]
        o, e, to = gr.run_godot(args, 2400)
        print(name, "超时" if to else "完成", len([f for f in os.listdir(d) if f.endswith(".png")]), "帧", gr.script_errors(o, e)[:3])


def cmp(tag):
    from PIL import Image, ImageChops
    import godot_runner as gr
    out = os.path.join(gr.common_root(), "build", "perf_stack", "pix_" + tag)
    fs = sorted(f for f in os.listdir(os.path.join(out, "base1")) if f.endswith(".png"))
    worst = (-1, None)
    tot = [0, 0]
    for f in fs:
        a = Image.open(os.path.join(out, "base1", f)).convert("RGB")
        b = Image.open(os.path.join(out, "base2", f)).convert("RGB")
        c = Image.open(os.path.join(out, "new", f)).convert("RGB")
        n_ab = sum(1 for p in ImageChops.difference(a, b).getdata() if p != (0, 0, 0))
        n_ac = sum(1 for p in ImageChops.difference(a, c).getdata() if p != (0, 0, 0))
        tot[0] += n_ab
        tot[1] += n_ac
        print("%s 旧对旧 %d  旧对新 %d" % (f, n_ab, n_ac))
        if n_ac > worst[0]:
            worst = (n_ac, f)
    print("合计 旧对旧 %d 像素，旧对新 %d 像素（%d 帧，每帧 %d 像素）" % (tot[0], tot[1], len(fs), 1280 * 720))
    if worst[1]:
        f = worst[1]
        a = Image.open(os.path.join(out, "base1", f)).convert("RGB")
        c = Image.open(os.path.join(out, "new", f)).convert("RGB")
        d = ImageChops.difference(a, c).point(lambda v: 255 if v else 0)
        trip = Image.new("RGB", (a.width * 3, a.height))
        for i, im in enumerate((a, c, d)):
            trip.paste(im, (a.width * i, 0))
        trip.save(os.path.join(out, "worst_%s" % f))
        print("差异最大一帧三联图（改前 / 改后 / 差异）：", os.path.join(out, "worst_%s" % f))


if __name__ == "__main__":
    a = sys.argv[1:]
    opt = {x.split("=", 1)[0]: (x.split("=", 1)[1] if "=" in x else "1") for x in a if x.startswith("--")}
    pos = [x for x in a if not x.startswith("--")]
    if pos[0] == "rec":
        rec(pos[1], opt.get("--base", "1dab9d3b2"), float(opt.get("--t", "560")), int(opt.get("--n", "30")), opt.get("--more", ""))
    else:
        cmp(pos[1])
