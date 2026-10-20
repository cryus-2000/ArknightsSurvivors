# -*- coding: utf-8 -*-
"""指挥模式观感录片（docs/114 §6）：机器人局（队长持续走位），按 --cmdat 时刻切模式，存帧后用 ffmpeg 合成 mp4。

用法：python tools/command_rec.py [--out build/command_rec] [--seed 3] [--squad mizuki,siege,wisadel,kaltsit]
    [--start 50] [--secs 40] [--cmdat 62,80]
缺省：50 秒开录 40 秒；62 秒按一次（随行 → 突击），80 秒再按（突击 → 归队，归位后自动回随行）。
窗口经 godot_runner 放副屏 / 屏幕外，静音；ffmpeg 用 imageio_ffmpeg 自带的。
"""
import argparse, glob, os, shutil, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(GR.common_root(), "build", "command_rec"))
    ap.add_argument("--name", default="command_mode")
    ap.add_argument("--seed", type=int, default=3)
    ap.add_argument("--squad", default="mizuki,siege,wisadel,kaltsit")
    ap.add_argument("--start", type=float, default=50.0)
    ap.add_argument("--secs", type=float, default=40.0)
    ap.add_argument("--cmdat", default="62,80")
    ap.add_argument("--extra", default="")
    a = ap.parse_args()
    sq = a.squad.split(",")
    fdir = os.path.join(a.out, a.name + "_frames")
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir, exist_ok=True)
    fps = 30
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", str(fps), "--",
            "--balance", "--seed=%d" % a.seed, "--op=" + sq[0], "--bot=expert", "--realtime", "--rtfrom=%g" % max(0.0, a.start - 2.0),
            "--recframes=%g,%d" % (a.start, int(a.secs * fps)), "--shotdir=" + fdir, "--cmdat=" + a.cmdat, "--trace=5"]
    if len(sq) > 1:
        args.append("--squad=" + ",".join(sq[1:]))
    args += a.extra.split()
    out, err, to = GR.run_godot(args, 1800)
    for l in out.splitlines():
        if l.startswith("CMD "):
            print(l)
    errs = GR.script_errors(out, err)
    if errs or to:
        print("失败：", "超时" if to else "；".join(errs[:3]))
        return 1
    n = len(glob.glob(os.path.join(fdir, "rec_*.png")))
    print("帧数", n)
    if n == 0:
        return 1
    import imageio_ffmpeg
    mp4 = os.path.join(a.out, a.name + ".mp4")
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-framerate", str(fps), "-i", os.path.join(fdir, "rec_%05d.png"),
                    "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "23", mp4], check=True)
    print("视频", mp4)
    return 0


if __name__ == "__main__":
    sys.exit(main())
