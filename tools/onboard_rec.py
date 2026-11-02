# -*- coding: utf-8 -*-
"""新手引导首局录像（docs/219 §6）：第一次进游戏的强制版（--onboard=ask），机器人代打，原速 30 帧（--realtime --fixed-fps 30），
问题框也录（--recintro）、选卡面板也录（--recchoice）；电脑（没玩过，--onboardpick=1）+ 手机触屏（玩过，--onboardpick=0）两段拼成一个 mp4。
演示局结束时测试局直接退出（onboard._drill_end），所以每段就是「问题框 → 演示局 → 演示结束」全程。
用法：python tools/onboard_rec.py <输出.mp4> [--op 干员]
"""
import glob, os, shutil, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
import exu_sync_rec as R

FPS = 30
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
OUT = os.path.join(ROOT, "build", "onboard_rec")
# 段名 → (标签, 窗口参数, 游戏参数)
SEGS = [
    ("pc", "电脑 · 第一次进游戏（选「没玩过」）", ["--resolution", "1280x720"], ["--onboardpick=1"]),
    ("phone", "手机 · 第一次进游戏（选「玩过」）", ["--resolution", "1600x900"], ["--touch", "--winsize=2178x1002", "--onboardpick=0"]),
]


def ffmpeg():
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def record(name, label, win, extra, op):
    fdir = os.path.join(OUT, "frames_" + name)
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir)
    GR.ensure_imported(GAME)
    args = [GR.find_godot(), "--path", GAME, "--audio-driver", "Dummy", "--fixed-fps", str(FPS)] + win + ["--",
            "--balance", "--realtime", "--seed=3", "--op=" + op, "--bot=master", "--nodeath", "--onboard=ask",
            "--recframes=0,%d" % (100 * FPS), "--recchoice", "--recintro", "--shotdir=" + fdir.replace(os.sep, "/"), "--maxt=120"] + extra
    out, err, to = GR.run_godot(args, 900)
    errs = GR.script_errors(out, err)
    for ln in out.splitlines():
        if ln.startswith("ONBOARD"):
            print(name, ln)
    frames = sorted(glob.glob(os.path.join(fdir, "rec_*.png")))
    if errs or not frames:
        print(name, "失败：", "超时" if to else ("；".join(errs[:3]) or "没有帧"))
        return None
    R.label_frames(fdir, label)
    mp4 = os.path.join(OUT, "seg_%s.mp4" % name)
    subprocess.run([ffmpeg(), "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(fdir, "rec_%05d.png"),
                    "-vf", "scale=1280:-2,pad=1280:720:(ow-iw)/2:(oh-ih)/2", "-c:v", "libx264", "-crf", "26", "-pix_fmt", "yuv420p", mp4], check=True)
    print(name, "帧数 %d（%.1f 秒）" % (len(frames), len(frames) / FPS), mp4)
    return mp4


def main():
    a = sys.argv[1:]
    final = a[0]
    op = a[a.index("--op") + 1] if "--op" in a else "mizuki"
    os.makedirs(OUT, exist_ok=True)
    segs = [record(n, lb, w, ex, op) for n, lb, w, ex in SEGS]
    if None in segs:
        return 1
    lst = os.path.join(OUT, "list.txt")
    open(lst, "w", encoding="utf-8").write("".join("file '%s'\n" % s.replace("\\", "/") for s in segs))
    os.makedirs(os.path.dirname(os.path.abspath(final)), exist_ok=True)
    subprocess.run([ffmpeg(), "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", final], check=True)
    print("视频", final, "%.1f MiB" % (os.path.getsize(final) / 1048576))
    return 0


if __name__ == "__main__":
    sys.exit(main())
