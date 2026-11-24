# -*- coding: utf-8 -*-
"""萨米密文板宣告面板演示录片（docs/411）：机器人局，--totemdemo 到点打开面板，面板里每步停 --pickframes 帧再选（布局 → 本因 → 自选时机），存帧后 ffmpeg 合成 mp4。

用法：python tools/totem_rec.py [--out build/totem_rec] [--seed 3] [--op skadi] [--start 212] [--secs 16] [--at 215]
缺省：3:32 开录 16 秒；3:35（中期 Boss 在场）打开面板，演示手牌：猎手 / 眼睛 + 歌唱 / 惊讶 / 呼救。
窗口经 godot_runner 放副屏 / 屏幕外，静音；ffmpeg 用 imageio_ffmpeg 自带的。
"""
import argparse, glob, os, shutil, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(GR.common_root(), "build", "totem_rec"))
    ap.add_argument("--name", default="totem_panel")
    ap.add_argument("--seed", type=int, default=3)
    ap.add_argument("--squad", default="skadi")
    ap.add_argument("--start", type=float, default=212.0)
    ap.add_argument("--secs", type=float, default=16.0)
    ap.add_argument("--at", type=float, default=215.0)
    ap.add_argument("--pickframes", type=int, default=60)
    ap.add_argument("--extra", default="")
    a = ap.parse_args()
    sq = a.squad.split(",")
    fdir = os.path.join(a.out, a.name + "_frames")
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir, exist_ok=True)
    fps = 30
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", str(fps), "--",
            "--balance", "--seed=%d" % a.seed, "--op=" + sq[0], "--bot=expert", "--realtime", "--rtfrom=%g" % max(0.0, a.start - 2.0),
            "--recframes=%g,%d" % (a.start, int(a.secs * fps)), "--shotdir=" + fdir, "--recchoice", "--pickframes=%d" % a.pickframes,
            "--theme=sami", "--god", "--totem=demo", "--totemdemo=%g" % a.at]
    if len(sq) > 1:
        args.append("--squad=" + ",".join(sq[1:]))
    args += a.extra.split()
    out, err, to = GR.run_godot(args, 1800)
    for l in out.splitlines():
        if "宣告" in l or l.startswith("TOTEM"):
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
