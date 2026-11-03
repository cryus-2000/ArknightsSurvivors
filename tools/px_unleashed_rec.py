# -*- coding: utf-8 -*-
"""pixelfx 放开版统一录像（漏项 #27）：按人顺序一次录完，各人交付不再自己录。

每名干员依次录：
  - 展示段（tools/px_showcase_rec.py：普攻 / S1 / S2 / S3 / 终结技 / 队友版拼一条），按 --modes 录全档 full、网页低档 lo、只剩核心 deco0；
  - 实战段：本人当队长，同种子从 --at 起录 --secs 秒，只录新版（docs/242 §5）。
原速 30 帧（--realtime --fixed-fps 30），--playclock 让命中定格照玩家局生效（批跑 / TRACE 不受影响），1920×1080，原色，静音。
输出 <out>/<干员>/：showcase.mp4、showcase_lo.mp4、showcase_deco0.mp4、live.mp4；某段失败重录一次，再失败记进 <out>/rec_log.txt 接着录下一段。
帧先存到 --tmp（1080p 每帧约 2–3 MB），编码完删掉。一次只开一个 Godot（别和别的会话抢机器）。
用法：python tools/px_unleashed_rec.py skadi,saria,exusiai [--modes full,lo,deco0] [--live-secs 60] [--at 420] [--seed 13]
                                     [--squad saria,exusiai,suzuran] [--skip-live] [--skip-showcase] [--out 目录] [--tmp 目录]
"""
import argparse, glob, os, shutil, subprocess, sys, tempfile, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
import imageio_ffmpeg

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FF = imageio_ffmpeg.get_ffmpeg_exe()
FILL = ["suzuran", "hoshiguma", "texas", "saria", "exusiai", "skadi"]   # 实战段编队凑满 3 人用


def enc(fdir, mp4, secs, max_mib=25.0):
    """按时长定码率，保证不超过 max_mib（留 8% 余量）"""
    kbps = int(max_mib * 0.92 * 8 * 1024 / secs)
    subprocess.run([FF, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(fdir, "rec_%05d.png"), "-c:v", "libx264", "-preset", "slow",
                    "-b:v", "%dk" % kbps, "-maxrate", "%dk" % int(kbps * 1.3), "-bufsize", "%dk" % (kbps * 2), "-pix_fmt", "yuv420p", mp4], check=True)


def live(a, op, squad, out):
    fdir = os.path.join(a.tmp, "pxul_live_" + op)
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir)
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--resolution", "1920x1080", "--audio-driver", "Dummy", "--fixed-fps", "30", "--",
            "--balance", "--realtime", "--playclock", "--rtfrom=%g" % max(0.0, a.at - 3), "--nodeath", "--seed=%d" % a.seed, "--op=" + op, "--squad=" + squad,
            "--bot=expert", "--recframes=%g,%d" % (a.at, int(a.live_secs * 30)), "--shotdir=" + fdir.replace(os.sep, "/"),
            "--maxt=%d" % (a.at + a.live_secs + 10), "--bal=fx/px_unleashed=1"] + a.extra.split()
    o, e, to = GR.run_godot(args, 3600)
    n = len(glob.glob(os.path.join(fdir, "rec_*.png")))
    err = GR.script_errors(o, e)[:3]
    if n < int(a.live_secs * 30 * 0.9):
        shutil.rmtree(fdir, ignore_errors=True)
        raise RuntimeError("实战段只录到 %d 帧 %s%s" % (n, err, " 超时" if to else ""))
    mp4 = os.path.join(out, "live.mp4")
    enc(fdir, mp4, a.live_secs)
    shutil.rmtree(fdir, ignore_errors=True)
    return "live %d 帧 %.1f MiB %s" % (n, os.path.getsize(mp4) / 1048576, err or "")


def showcase(a, op, mode, mate, out):
    flag = {"full": [], "lo": ["--lo"], "deco0": ["--deco0"]}[mode]
    secs = [] if mode == "full" else ["--secs", "5"]
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "px_showcase_rec.py"), op, "--mate", mate, "--seed", str(a.seed), "--out", out, "--tmp", a.tmp] + secs + flag,
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    src = os.path.join(out, "%s_showcase%s.mp4" % (op, "" if mode == "full" else "_" + mode))
    if r.returncode or not os.path.exists(src):
        raise RuntimeError("展示段 %s 失败：%s" % (mode, (r.stderr or r.stdout).strip().splitlines()[-1:] or "无输出"))
    dst = os.path.join(out, "showcase%s.mp4" % ("" if mode == "full" else "_" + mode))
    os.replace(src, dst)
    return "showcase %s %.1f MiB" % (mode, os.path.getsize(dst) / 1048576)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ops", help="逗号分隔的干员 id，按顺序录")
    ap.add_argument("--modes", default="full,lo,deco0")
    ap.add_argument("--seed", type=int, default=13)
    ap.add_argument("--at", type=float, default=420.0, help="实战段从第几秒起录")
    ap.add_argument("--live-secs", type=float, default=60.0)
    ap.add_argument("--squad", default="", help="实战段编队（缺省用这批里的其他人，不够用 suzuran 等补满 3 人）")
    ap.add_argument("--extra", default="", help="实战段额外命令行参数（以 -- 开头时写成 --extra=\"--maxprog\"）")
    ap.add_argument("--skip-live", action="store_true")
    ap.add_argument("--skip-showcase", action="store_true")
    ap.add_argument("--tmp", default=tempfile.gettempdir())
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "px_unleashed"))
    a = ap.parse_args()
    ops = [x for x in a.ops.split(",") if x]
    log = os.path.join(a.out, "rec_log.txt")
    os.makedirs(a.out, exist_ok=True)
    for op in ops:
        out = os.path.join(a.out, op)
        os.makedirs(out, exist_ok=True)
        others = [x for x in ops if x != op] + [x for x in FILL if x not in ops and x != op]
        squad = a.squad or ",".join(others[:3])
        mate = next(x for x in ops + FILL if x != op)   # 队友版：别人当队长、本人进编队
        jobs = ([] if a.skip_showcase else [("showcase " + m, lambda m=m: showcase(a, op, m, mate, out)) for m in a.modes.split(",") if m]) + \
               ([] if a.skip_live else [("live", lambda: live(a, op, squad.replace(op, "").strip(",").replace(",,", ","), out))])
        for tag, fn in jobs:
            t0 = time.time()
            msg = None
            for k in range(2):   # 失败重录一次
                try:
                    msg = fn()
                    break
                except Exception as ex:
                    msg = "!! %s 第 %d 次失败：%s" % (tag, k + 1, ex)
            line = "%s %s（%.0f 秒）" % (op, msg, time.time() - t0)
            print(line, flush=True)
            with open(log, "a", encoding="utf-8") as f:
                f.write(time.strftime("%m-%d %H:%M ") + line + "\n")


if __name__ == "__main__":
    main()
