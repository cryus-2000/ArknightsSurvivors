# -*- coding: utf-8 -*-
"""Boss 演练 · 成品分队录片（用户 10-28）：选分队 → 打 Boss，原速 30 帧，存帧后 ffmpeg 合成 mp4。

用法：python tools/practice_squad_rec.py [--squad wisadel_m18] [--boss paranoia] [--fight 130] [--out build/practice_rec]
窗口经 godot_runner 放副屏 / 屏幕外，静音；ffmpeg 用 imageio_ffmpeg 自带的。
"""
import argparse, glob, os, shutil, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(GR.common_root(), "build", "practice_rec"))
    ap.add_argument("--squad", default="wisadel_m18")
    ap.add_argument("--boss", default="paranoia")
    ap.add_argument("--fight", type=float, default=130.0)
    a = ap.parse_args()
    name = "practice_%s_%s" % (a.squad, a.boss)
    fdir = os.path.join(a.out, name + "_frames")
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir, exist_ok=True)
    fps = 30
    game = os.path.join(ROOT, "game")
    GR.ensure_imported(game)
    args = [GR.find_godot(), "--path", game, "--audio-driver", "Dummy", "--fixed-fps", str(fps), "res://tests/practice_squad_rec.tscn", "--",
            "--recdir=" + fdir, "--squad=" + a.squad, "--boss=" + a.boss, "--fight=%g" % a.fight]
    out, err, to = GR.run_godot(args, 3600)
    for l in out.splitlines():
        if l.startswith("PRACTICEREC"):
            print(l)
    errs = GR.script_errors(out, err)
    if errs or to:
        print("失败：", "超时" if to else "；".join(errs[:3]))
    n = len(glob.glob(os.path.join(fdir, "rec_*.jpg")))
    print("帧数", n)
    if n == 0:
        return 1
    import imageio_ffmpeg
    mp4 = os.path.join(a.out, name + ".mp4")
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-framerate", str(fps), "-i", os.path.join(fdir, "rec_%05d.jpg"),
                    "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "24", mp4], check=True)
    shutil.rmtree(fdir, ignore_errors=True)
    print("视频", mp4)
    return 0


if __name__ == "__main__":
    sys.exit(main())
