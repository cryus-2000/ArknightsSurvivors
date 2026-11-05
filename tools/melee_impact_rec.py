#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""近战打击感包（docs/246 §12，fx/melee_impact）开 / 关对照：GCP 虚拟机上跑（Linux，xvfb + opengl3），本机不开 Godot。

  rec    斯卡蒂、星熊各一局（队长），同种子开 / 关两遍，--realtime --playclock（顿帧在玩家时钟下才看得见）30 帧原速连存 N 秒，
         拼成 2×2（上斯卡蒂、下星熊；左关右开）1920 宽 mp4，压到 30 MB 以内
  trace  同种子开 / 关 TRACE 逐行比（--fixed-fps 60 批跑模式，不消耗顿帧——顿帧在玩家时钟里本来就会停模拟，开关两局必然分岔）

用法（虚拟机仓库根目录）：python3 tools/melee_impact_rec.py all --out $OUT
"""
import argparse, glob, os, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as GR

OPS = [("skadi", ["--bal=fx/px_plane=1"]), ("hoshiguma", [])]


def godot(args, timeout=5400):
    if os.environ.get("DISPLAY") and os.environ.get("GODOT"):   # GCP 出图虚拟机（tools/gcp/render_prep.sh）：GODOT 已包成 opengl3、画在 Xvfb :99 上
        base = [os.environ["GODOT"], "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy"]
    else:
        base = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy"]
        if os.name != "nt":
            base = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24", base[0], "--rendering-driver", "opengl3"] + base[1:]
    p = subprocess.run(base + args, capture_output=True, text=True, timeout=timeout)
    return (p.stdout or "") + "\n" + (p.stderr or "")


def rec(out, t0, secs, seed):
    tiles = []
    for op, ex in OPS:
        for on in (0, 1):
            fdir = os.path.join(out, "fr_%s_%d" % (op, on))
            shutil.rmtree(fdir, ignore_errors=True)
            os.makedirs(fdir)
            log = godot(["--resolution", "1280x720", "--fixed-fps", "30", "--", "--balance", "--nodeath", "--realtime", "--playclock",
                         "--rtfrom=%d" % (t0 - 3), "--seed=%d" % seed, "--op=" + op, "--bot=expert", "--maxprog",
                         "--bal=fx/melee_impact=%d" % on, "--recframes=%d,%d" % (t0, secs * 30), "--shotdir=" + fdir, "--maxt=%d" % (t0 + secs + 2)] + ex)
            open(os.path.join(out, "rec_%s_%d.log" % (op, on)), "w").write(log)
            errs = [l for l in log.splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l]
            print(op, on, len(glob.glob(os.path.join(fdir, "rec_*.png"))), "帧", errs[:3], flush=True)
            tiles.append(fdir)
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    n = min(len(glob.glob(os.path.join(d, "rec_*.png"))) for d in tiles)
    mp4 = os.path.join(out, "melee_impact_onoff.mp4")
    fnt = os.environ.get("CJK_FONT", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
    labs = ["斯卡蒂 打击感包 关", "斯卡蒂 打击感包 开（fx/melee_impact=1）", "星熊 打击感包 关", "星熊 打击感包 开（fx/melee_impact=1）"]
    args = [ff, "-y", "-loglevel", "error"]
    for d in tiles:
        args += ["-framerate", "30", "-i", os.path.join(d, "rec_%05d.png")]
    fl = []
    for i, lb in enumerate(labs):
        dt = ",drawtext=fontfile=%s:text='%s':x=16:y=16:fontsize=30:fontcolor=white:box=1:boxcolor=black@0.6" % (fnt, lb) if os.path.exists(fnt) else ""
        fl.append("[%d:v]scale=960:540%s[v%d]" % (i, dt, i))
    fl.append("[v0][v1]hstack=inputs=2[t];[v2][v3]hstack=inputs=2[b];[t][b]vstack=inputs=2[v]")
    for crf in (23, 27, 31):
        subprocess.run(args + ["-filter_complex", ";".join(fl), "-map", "[v]", "-frames:v", str(n), "-c:v", "libx264", "-crf", str(crf),
                               "-preset", "slow", "-pix_fmt", "yuv420p", mp4], check=True)
        if os.path.getsize(mp4) <= 29 * 1024 * 1024:
            break
    print("录像", mp4, "%.1f MB" % (os.path.getsize(mp4) / 1048576.0), n, "帧", flush=True)
    for d in tiles:
        shutil.rmtree(d, ignore_errors=True)


def traces(log):
    return [l for l in log.splitlines() if l.startswith("TRACE")]


def trace(out, seed, maxt):
    ok = True
    for op, ex in OPS:
        tr = []
        for on in (0, 1):
            log = godot(["--resolution", "1280x720", "--fixed-fps", "60", "--", "--balance", "--nodeath", "--trace=1",
                         "--seed=%d" % seed, "--op=" + op, "--elite2", "--sptest", "--maxt=%d" % maxt, "--bal=fx/melee_impact=%d" % on] + ex)
            open(os.path.join(out, "trace_%s_%d.log" % (op, on)), "w").write(log)
            errs = [l for l in log.splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l]
            if errs:
                print("脚本错误", op, on, errs[:3], flush=True)
            tr.append(traces(log))
        diff = sum(1 for a, b in zip(tr[0], tr[1]) if a != b) + abs(len(tr[0]) - len(tr[1]))
        same = diff == 0 and len(tr[0]) > 0
        ok &= same
        print("TRACE %s 打击感包 关 vs 开：%d / %d 行，%s" % (op, len(tr[0]), len(tr[1]), "逐行一致" if same else "有差异 %d 行" % diff), flush=True)
    # 框架修复（docs/246 §11）：斯卡蒂 fx/px_plane 0 vs 1（打击感包开着）
    tr = []
    for px in (0, 1):
        log = godot(["--resolution", "1280x720", "--fixed-fps", "60", "--", "--balance", "--nodeath", "--trace=1", "--seed=%d" % seed, "--op=skadi",
                     "--elite2", "--sptest", "--maxt=%d" % maxt, "--bal=fx/melee_impact=1", "--bal=fx/px_plane=%d" % px, "--bal=growth/late_shape=1"])
        open(os.path.join(out, "trace_pxp_%d.log" % px), "w").write(log)
        errs = [l for l in log.splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l]
        if errs:
            print("脚本错误", px, errs[:3], flush=True)
        tr.append(traces(log))
    diff = sum(1 for a, b in zip(tr[0], tr[1]) if a != b) + abs(len(tr[0]) - len(tr[1]))
    same = diff == 0 and len(tr[0]) > 0
    ok &= same
    print("TRACE 斯卡蒂 转平面 0 vs 1（打击感包开、late_shape 开）：%d / %d 行，%s" % (len(tr[0]), len(tr[1]), "逐行一致" if same else "有差异 %d 行" % diff), flush=True)
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["rec", "trace", "all"])
    ap.add_argument("--out", default=os.environ.get("MEDIA", os.path.join(ROOT, "build", "melee_impact")))
    ap.add_argument("--from", dest="t0", type=int, default=90)
    ap.add_argument("--secs", type=int, default=12)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--maxt", type=int, default=300)
    a = ap.parse_args()
    a.out = os.path.abspath(a.out)   # Godot 带 --path game 启动：相对路径会落到 game/ 下存不进去
    os.makedirs(a.out, exist_ok=True)
    ok = True
    if a.cmd in ("trace", "all"):
        ok = trace(a.out, a.seed, a.maxt)
    if a.cmd in ("rec", "all"):
        rec(a.out, a.t0, a.secs, a.seed)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
