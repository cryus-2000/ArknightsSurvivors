"""原生敌人绘制（docs/50 §30 EnemyRender）的画面对照：同一份代码、同 seed、同帧，--optold=OPT_NR（GDScript 原路径）跑两次（旧对旧 = 噪声底）、
原生跑一次，逐像素比；另录 --autotest --worldspec / --fxtest 摆拍各一组。随机噪声源关掉（CPU 颗粒、GPU 粒子常关、焦散、地面荧光斑）。

  python tools/probes/nr_pixcmp.py rec <标签> [--t=560] [--n=30] [--seed=13] [--squad=skalter,texas,exusiai] [--quality=mid] [--more="..."] [--groups=run,worldspec,fxtest] [--opt=4194304]
  --opt：对照的优化位（缺省 OPT_NR；德克萨斯刀痕缓存 OPT_TXS = 8388608，docs/50 §31）
  D:/Anaconda/python.exe tools/probes/nr_pixcmp.py cmp <标签>      # 要 PIL：逐帧 旧对旧 / 旧对新 差异像素数，差异最大一帧另存三联图
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)
ROOT = os.path.dirname(TOOLS)
OPT_NR = 4194304
QUIET = ["--bal=fx/grains=0", "--stackab=1000000:2", "--bal=render/optical_caustics=0", "--bal=render/optical_ground_glow=0"]


def out_dir(tag):
    import godot_runner as gr
    return os.path.join(gr.common_root(), "build", "perf_stack", "nrpix_" + tag)


def rec(tag, t, n, seed, squad, quality, more, groups, opt=OPT_NR):
    import godot_runner as gr
    gr.ensure_imported(os.path.join(ROOT, "game"))
    out = out_dir(tag)
    sq = squad.split(",")
    for name, extra in ((("old1", ["--optold=%d" % opt]), ("old2", ["--optold=%d" % opt]), ("new", [])) if "run" in groups else ()):
        d = os.path.join(out, "run", name)
        os.makedirs(d, exist_ok=True)
        args = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "60", "--resolution", "1280x720", "--",
                "--balance", "--nodeath", "--bot=expert", "--seed=%d" % seed, "--op=" + sq[0], "--squad=" + ",".join(sq[1:]), "--quality=" + quality,
                "--maxt=%g" % (t + 5), "--recframes=%g,%d" % (t, n), "--shotdir=" + d.replace(os.sep, "/")] + QUIET + extra + [x for x in more.split(" ") if x]
        o, e, to = gr.run_godot(args, 2400)
        print(name, "超时" if to else "完成", len([f for f in os.listdir(d) if f.endswith(".png")]), "帧", gr.script_errors(o, e)[:3])
    for flag in [f for f in ("--worldspec", "--fxtest") if f[2:] in groups]:
        for name, extra in (("old1", ["--optold=%d" % opt]), ("old2", ["--optold=%d" % opt]), ("new", [])):
            d = os.path.join(out, flag[2:], name)
            os.makedirs(d, exist_ok=True)
            args = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "60", "--resolution", "1280x720", "--",
                    "--autotest", "--seed=1", "--op=skalter", "--squad=texas,exusiai", "--quality=" + quality, flag, "--shotdir=" + d.replace(os.sep, "/")] + QUIET + extra
            o, e, to = gr.run_godot(args, 900)
            print(flag, name, len([f for f in os.listdir(d) if f.endswith(".png")]), "张", gr.script_errors(o, e)[:3])


def cmp(tag):
    from PIL import Image, ImageChops
    out = out_dir(tag)
    tot = {}
    worst = (-1, None, None)
    for grp in ("run", "worldspec", "fxtest"):
        gd = os.path.join(out, grp)
        if not os.path.isdir(os.path.join(gd, "old1")):
            continue
        fs = sorted(f for f in os.listdir(os.path.join(gd, "old1")) if f.endswith(".png"))
        s = [0, 0, 0]
        for f in fs:
            try:
                a, b, c = [Image.open(os.path.join(gd, nm, f)).convert("RGB") for nm in ("old1", "old2", "new")]
            except FileNotFoundError:
                continue
            n_ab = sum(1 for p in ImageChops.difference(a, b).getdata() if p != (0, 0, 0))
            n_ac = sum(1 for p in ImageChops.difference(a, c).getdata() if p != (0, 0, 0))
            s[0] += 1
            s[1] += n_ab
            s[2] += n_ac
            if n_ac > worst[0]:
                worst = (n_ac, grp, f)
        tot[grp] = s
        print("%-10s %3d 张：旧对旧 %d 像素，旧对新 %d 像素" % (grp, s[0], s[1], s[2]))
    if worst[1] and worst[0] > 0:
        gd = os.path.join(out, worst[1])
        a = Image.open(os.path.join(gd, "old1", worst[2])).convert("RGB")
        c = Image.open(os.path.join(gd, "new", worst[2])).convert("RGB")
        d = ImageChops.difference(a, c).point(lambda v: 255 if v else 0)
        trip = Image.new("RGB", (a.width * 3, a.height))
        for i, im in enumerate((a, c, d)):
            trip.paste(im, (a.width * i, 0))
        p = os.path.join(out, "worst_%s_%s" % (worst[1], worst[2]))
        trip.save(p)
        print("差异最大一帧（旧 / 新 / 差异）：", p)


if __name__ == "__main__":
    a = sys.argv[1:]
    opt = {x.split("=", 1)[0]: (x.split("=", 1)[1] if "=" in x else "1") for x in a if x.startswith("--")}
    pos = [x for x in a if not x.startswith("--")]
    if pos[0] == "rec":
        rec(pos[1], float(opt.get("--t", "560")), int(opt.get("--n", "30")), int(opt.get("--seed", "13")), opt.get("--squad", "skalter,texas,exusiai"),
            opt.get("--quality", "mid"), opt.get("--more", ""), opt.get("--groups", "run,worldspec,fxtest").split(","), int(opt.get("--opt", str(OPT_NR))))
    else:
        cmp(pos[1])
