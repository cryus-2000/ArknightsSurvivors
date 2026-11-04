#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""配方特效开 / 关对照录像 + TRACE 逐行比（docs/245 §5，本机 Windows 版；云端 Linux 版是 tools/fx_recipe_compare.py）。

rec：同种子同一局跑两遍（fx/recipe = 0 / 1），--rtfrom 快进到起始秒后按真实步长（--realtime，--fixed-fps 30）连存 N 帧，
     拼成左关右开的 mp4（原色原速，30 帧）；同一局顺带收 TRACE（--trace=1）逐行比。
trace：只比 TRACE（--fixed-fps 60 非实时，不存帧），默认推进之王队长 + 逻各斯、精二 + 技力常满。
窗口在屏幕外、静音（godot_runner）。

用法（仓库根目录）：
    python tools/fx_canon_rec.py rec   --op logos --squad siege --seed 11 --from 480 --secs 20
    python tools/fx_canon_rec.py trace --op siege --squad logos --seed 23 --maxt 300 --extra "--elite2 --sptest"
    python tools/fx_canon_rec.py grid  --op logos --squad siege --seed 11 --from 480 --secs 20     # §5.9 三项实验四宫格：全关 / 只开描边 / 只开命中照地 / 三项全开
输出：build/fx_canon/rec/late_<起始秒>_onoff.mp4、build/fx_canon/rec/logs/*.log
"""
import argparse, glob, os, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "build", "fx_canon", "rec")
LOGS = os.path.join(OUT, "logs")


def run(tag, extra, fps, fdir=None):
    os.makedirs(LOGS, exist_ok=True)
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--resolution", "1280x720", "--fixed-fps", str(fps), "--",
            "--balance", "--nodeath", "--trace=1"] + extra
    if fdir:
        shutil.rmtree(fdir, ignore_errors=True)
        os.makedirs(fdir)
        args += ["--shotdir=" + fdir.replace(os.sep, "/")]
    out, err, to = GR.run_godot(args, 5400)
    open(os.path.join(LOGS, tag + ".log"), "w", encoding="utf-8").write(out + "\n" + err)
    errs = GR.script_errors(out, err)
    return tag, len([l for l in out.splitlines() if l.startswith("TRACE")]), errs[:3], to


def traces(tag):
    p = os.path.join(LOGS, tag + ".log")
    return [l for l in open(p, encoding="utf-8").read().splitlines() if l.startswith("TRACE")] if os.path.exists(p) else []


def balance(tag):
    p = os.path.join(LOGS, tag + ".log")
    return [l for l in open(p, encoding="utf-8").read().splitlines() if l.startswith("BALANCE")] if os.path.exists(p) else []


def diff(a, b):
    ta, tb = traces(a), traces(b)
    n = sum(1 for x, y in zip(ta, tb) if x != y)
    same = n == 0 and len(ta) == len(tb) and len(ta) > 0
    print("%s vs %s：TRACE %d / %d 行，%s" % (a, b, len(ta), len(tb), "逐行一致" if same else "有差异 %d 行" % (n + abs(len(ta) - len(tb)))))
    for i, (x, y) in enumerate(zip(ta, tb)):
        if x != y:
            print("  第 %d 行：\n   %s\n   %s" % (i + 1, x[:200], y[:200]))
            break
    return same


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["rec", "trace", "diff", "grid"])
    ap.add_argument("--op", default="logos")
    ap.add_argument("--squad", default="siege")
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--from", dest="t0", type=int, default=480)
    ap.add_argument("--secs", type=int, default=20)
    ap.add_argument("--maxt", type=int, default=300)
    ap.add_argument("--extra", default="")
    a = ap.parse_args()
    base = ["--seed=%d" % a.seed, "--op=" + a.op] + (["--squad=" + a.squad] if a.squad else []) + a.extra.split()
    tags = []
    if a.cmd == "rec":
        jobs = []
        for on in (0, 1):
            tag = "%s_rec%d_s%d_%d" % (a.op, on, a.seed, a.t0)
            ex = base + ["--bal=fx/recipe=%d" % on, "--realtime", "--rtfrom=%d" % a.t0, "--recframes=%d,%d" % (a.t0, a.secs * 30), "--maxt=%d" % (a.t0 + a.secs + 1)]
            jobs.append((tag, ex, 30, os.path.join(OUT, tag + "_frames")))
            tags.append(tag)
        with ThreadPoolExecutor(2) as ex:
            for r in ex.map(lambda j: run(*j), jobs):
                print(r, flush=True)
        import imageio_ffmpeg
        ff = imageio_ffmpeg.get_ffmpeg_exe()
        d0, d1 = [os.path.join(OUT, t + "_frames") for t in tags]
        n = min(len(glob.glob(os.path.join(d0, "rec_*.png"))), len(glob.glob(os.path.join(d1, "rec_*.png"))))
        mp4 = os.path.join(OUT, "late_%s_%dm%02d_onoff.mp4" % (a.op, a.t0 // 60, a.t0 % 60))
        # 左关右开，各 1280×720 原尺寸并排，30 帧原速
        subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(d0, "rec_%05d.png"), "-framerate", "30", "-i", os.path.join(d1, "rec_%05d.png"),
                        "-filter_complex", "[0:v][1:v]hstack=inputs=2,drawbox=x=1278:y=0:w=4:h=ih:color=black@1:t=fill[v]", "-map", "[v]", "-frames:v", str(n),
                        "-c:v", "libx264", "-crf", "20", "-pix_fmt", "yuv420p", mp4], check=True)
        print("录像", mp4, "%d 帧" % n)
    elif a.cmd == "trace":
        jobs = []
        for on in (0, 1):
            tag = "%s_trace%d_s%d" % (a.op, on, a.seed)
            jobs.append((tag, base + ["--bal=fx/recipe=%d" % on, "--maxt=%d" % a.maxt], 60, None))
            tags.append(tag)
        with ThreadPoolExecutor(2) as ex:
            for r in ex.map(lambda j: run(*j), jobs):
                print(r, flush=True)
    elif a.cmd == "grid":
        # 配方开着，三项实验（docs/245 §5.9）按四种组合各跑一遍，拼 2×2（每格 1280×720 → 整体缩到 1920×1080），TRACE 四局两两比
        CFG = [("全关（v4）", []), ("只开 1 描边", ["--bal=fx/recipe_outline=1"]), ("只开 2 命中照地", ["--bal=fx/recipe_hitlight=1"]),
               ("三项全开（1 描边 + 2 命中照地 + 3 受击反应）", ["--bal=fx/recipe_outline=1", "--bal=fx/recipe_hitlight=1", "--bal=fx/recipe_hitreact=1"])]
        jobs = []
        for k, (lab, ex2) in enumerate(CFG):
            tag = "%s_grid%d_s%d_%d" % (a.op, k, a.seed, a.t0)
            ex = base + ["--bal=fx/recipe=1"] + ex2 + ["--realtime", "--rtfrom=%d" % a.t0, "--recframes=%d,%d" % (a.t0, a.secs * 30), "--maxt=%d" % (a.t0 + a.secs + 1)]
            jobs.append((tag, ex, 30, os.path.join(OUT, tag + "_frames")))
            tags.append(tag)
        with ThreadPoolExecutor(4) as ex:
            for r in ex.map(lambda j: run(*j), jobs):
                print(r, flush=True)
        import imageio_ffmpeg
        from PIL import Image, ImageDraw, ImageFont
        ff = imageio_ffmpeg.get_ffmpeg_exe()
        lab = os.path.join(OUT, "_grid_labels.png")
        im = Image.new("RGBA", (2560, 1440), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        fnt = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 30)
        for k, (t, _) in enumerate(CFG):
            x, y = (k % 2) * 1280, (k // 2) * 720
            d.rectangle((x + 10, y + 640, x + 30 + int(d.textlength(t, font=fnt)), y + 690), fill=(0, 0, 0, 170))
            d.text((x + 20, y + 645), t, fill=(255, 255, 255, 255), font=fnt)
        im.save(lab)
        dirs = [os.path.join(OUT, t + "_frames") for t in tags]
        n = min(len(glob.glob(os.path.join(dd, "rec_*.png"))) for dd in dirs)
        mp4 = os.path.join(OUT, "exp3_%dm%02d_grid.mp4" % (a.t0 // 60, a.t0 % 60))
        args = [ff, "-y", "-loglevel", "error"]
        for dd in dirs:
            args += ["-framerate", "30", "-i", os.path.join(dd, "rec_%05d.png")]
        args += ["-i", lab, "-filter_complex", "[0:v][1:v]hstack=inputs=2[t];[2:v][3:v]hstack=inputs=2[b];[t][b]vstack=inputs=2[g];[g][4:v]overlay=0:0,scale=1920:-2[v]",
                 "-map", "[v]", "-frames:v", str(n), "-c:v", "libx264", "-crf", "26", "-preset", "slow", "-pix_fmt", "yuv420p", mp4]
        subprocess.run(args, check=True)
        print("录像", mp4, "%d 帧" % n)
        ok = True
        for t in tags[1:]:
            ok &= diff(tags[0], t)
        sys.exit(0 if ok else 1)
    else:
        tags = [os.path.basename(f)[:-4] for f in sorted(glob.glob(os.path.join(LOGS, "*0_s*.log")))]
        tags = [t for p in tags for t in (p, p.replace("rec0", "rec1").replace("trace0", "trace1"))]
    ok = True
    for i in range(0, len(tags), 2):
        ok &= diff(tags[i], tags[i + 1])
        b0, b1 = balance(tags[i]), balance(tags[i + 1])
        if b0 != b1:
            print("  BALANCE 不同（画面计数字段，见日志）")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
