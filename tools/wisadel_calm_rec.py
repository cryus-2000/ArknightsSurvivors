# -*- coding: utf-8 -*-
"""维什戴尔收特效对照（11-01，docs/220）：同 seed，改前（--bal=fx/wd_calm=0）/ 改后各录一段，当队长 / 当队友 × 前期 / 后期；
原速 30 帧（--realtime），游戏里 --wdfxstat 每秒打印 WDFX 行，这里汇总成「平均每秒新生成数 / 平均同屏层数」。
出：build/wdcalm/<tag>/<role>_<phase>_<calm>.mp4、stats.json；--pair 时另把改前 | 改后左右拼成 <role>.mp4（前期 + 后期接起来）。
用法：python tools/wisadel_calm_rec.py [--roles lead,mate] [--phases early,late] [--secs 30] [--mate-lead hoshiguma] [--tag now] [--jobs 4] [--pair] [--crf 28] [--abkey fx/wd_ring --abvals 1,0]
--abkey / --abvals：对照的旋钮与改前、改后两个值（缺省 fx/wd_calm 0,1）；--out 把拼好的对照另存一份"""
import argparse, glob, json, os, re, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ap = argparse.ArgumentParser()
ap.add_argument("--roles", default="lead,mate"); ap.add_argument("--phases", default="early,late"); ap.add_argument("--secs", type=float, default=30.0)
ap.add_argument("--mate-lead", default="hoshiguma"); ap.add_argument("--tag", default="now"); ap.add_argument("--jobs", type=int, default=4)
ap.add_argument("--seed", type=int, default=3); ap.add_argument("--pair", action="store_true"); ap.add_argument("--crf", type=int, default=28)
ap.add_argument("--abkey", default="fx/wd_calm"); ap.add_argument("--abvals", default="0,1"); ap.add_argument("--width", type=int, default=800)
ap.add_argument("--norec", action="store_true", help="只统计不录像（无头）")
a = ap.parse_args()
out = os.path.join(ROOT, "build", "wdcalm", a.tag); os.makedirs(out, exist_ok=True)
import imageio_ffmpeg
FF = imageio_ffmpeg.get_ffmpeg_exe()
PH = {"early": (30.0, []), "late": (240.0, ["--maxprog"])}
CATS = ["boom", "soul", "spark", "smoke", "ring"]


def one(job):
    role, phase, calm = job
    at, ex = PH[phase]
    name = "%s_%s_%d" % (role, phase, calm)
    fdir = os.path.join(out, "fr_" + name); shutil.rmtree(fdir, ignore_errors=True); os.makedirs(fdir)
    sq = ["--op=wisadel"] if role == "lead" else ["--op=" + a.mate_lead, "--squad=wisadel"]
    rec = [] if a.norec else ["--realtime", "--rtfrom=%g" % max(0.0, at - 3), "--recframes=%g,%d" % (at, int(a.secs * 30)), "--shotdir=" + fdir.replace(os.sep, "/")]
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy"] + (["--headless"] if a.norec else ["--fixed-fps", "30"]) + ["--",
            "--balance", "--nodeath", "--seed=%d" % a.seed, "--bot=expert", "--wdfxstat", "--bal=%s=%s" % (a.abkey, a.abvals.split(",")[calm])] + sq + ex + rec + ["--maxt=%d" % (at + a.secs + 2)]
    o, e, to = GR.run_godot(args, 2400)
    rows = []
    for ln in (o or "").splitlines():
        m = re.match(r"WDFX t=(\d+) lead=(\d) spawn=(\{.*?\}) live=(\{.*\})", ln.strip())
        if m and at <= int(m.group(1)) < at + a.secs:
            rows.append((json.loads(m.group(3)), json.loads(m.group(4))))
    n = max(1, len(rows))
    sp = {c: round(sum(r[0].get(c, 0) for r in rows) / n, 1) for c in CATS + ["capped", "boom_capped"]}
    lv = {c: round(sum(r[1].get(c, 0) for r in rows) / n, 1) for c in CATS}
    allk = sorted({k for r in rows for k in r[0]})
    res_k = {k: round(sum(r[0].get(k, 0) for r in rows) / n, 1) for k in allk if k.startswith(("k_", "b_"))}
    res = {"by_kind": res_k, "name": name, "secs": len(rows), "spawn_per_s": sp, "spawn_total_per_s": round(sum(sp[c] for c in CATS), 1),
           "live_avg": lv, "live_total": round(sum(lv.values()), 1), "errors": GR.script_errors(o, e)[:3], "timeout": to}
    if not a.norec:
        nfr = len(glob.glob(os.path.join(fdir, "rec_*.png")))
        res["frames"] = nfr
        subprocess.run([FF, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(fdir, "rec_%05d.png"), "-vf", "scale=960:-2",
                        "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", os.path.join(out, name + ".mp4")])
    shutil.rmtree(fdir, ignore_errors=True)
    print(json.dumps(res, ensure_ascii=False), flush=True)
    return res


jobs = [(r, p, c) for r in a.roles.split(",") for p in a.phases.split(",") for c in (0, 1)]
with ThreadPoolExecutor(a.jobs) as ex:
    res = list(ex.map(one, jobs))
json.dump(res, open(os.path.join(out, "stats.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
if a.pair and not a.norec:
    # 左改前 | 右改后，各 800 宽；左上角标字；前期、后期接成一段
    lab = "drawtext=text='%s':x=12:y=10:fontsize=26:fontcolor=white:box=1:boxcolor=black@0.55:fontfile='C\\:/Windows/Fonts/msyh.ttc'"
    for r in a.roles.split(","):
        parts = []
        for p in a.phases.split(","):
            seg = os.path.join(out, "%s_%s_pair.mp4" % (r, p))
            f0, f1 = (os.path.join(out, "%s_%s_%d.mp4" % (r, p, c)) for c in (0, 1))
            fc = "[0:v]scale=%d:-2,%s[l];[1:v]scale=%d:-2,%s[r];[l][r]hstack=inputs=2[v]" % (a.width, lab % ("改前 " + p), a.width, lab % ("改后 " + p))
            subprocess.run([FF, "-y", "-loglevel", "error", "-i", f0, "-i", f1, "-filter_complex", fc, "-map", "[v]", "-r", "30",
                            "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", seg])
            parts.append(seg)
        lst = os.path.join(out, r + "_list.txt")
        open(lst, "w").write("".join("file '%s'\n" % q.replace("\\", "/") for q in parts))
        subprocess.run([FF, "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c:v", "libx264", "-crf", str(a.crf), "-pix_fmt", "yuv420p", "-r", "30",
                        os.path.join(out, "wisadel_%s.mp4" % r)])
        print(r, os.path.getsize(os.path.join(out, "wisadel_%s.mp4" % r)) / 2 ** 20, "MiB", flush=True)
