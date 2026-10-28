# -*- coding: utf-8 -*-
"""作战记录改版 + 对局记录面板录像（10-29 用户截图反馈）：tests/run_log_rec 逐帧存图 → H.264 mp4（原速 30 帧）。
桌面 1280×720 一段 + 手机横屏 1480×720（--touch）一段。对局记录读 runs.jsonl 的副本（--runslog=，放 build/ 不进 git）：
  python tools/probes/run_log_rec.py [runs.jsonl 路径]   缺省取本机最新的对内包记录。
录完即删帧目录。输出主仓库 build/settle_redesign/run_log.mp4
"""
import os, sys, glob, shutil, subprocess
from PIL import Image, ImageDraw, ImageFont

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
import godot_runner as GR

GAME = os.path.join(ROOT, "game")
OUT = os.path.join(GR.common_root(), "build", "settle_redesign")
W, H, FPS = 1480, 720, 30


def newest_runs():
    base = os.path.join(os.environ.get("APPDATA", ""))
    c = glob.glob(os.path.join(base, "ArknightsSurvivors*", "runs", "runs.jsonl"))
    return max(c, key=os.path.getmtime) if c else ""


def run(name, res, runs, extra):
    d = os.path.join(OUT, "raw_runlog_%s" % name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    out, err, to = GR.run_godot([GR.find_godot(), "--path", GAME, "--resolution", res, "--fixed-fps", str(FPS), "--audio-driver", "Dummy",
                                 "res://tests/run_log_rec.tscn", "--", "--shotdir=" + d, "--runslog=" + runs] + extra, 400)
    fr = sorted(glob.glob(os.path.join(d, "rec_*.png")))
    errs = [l for l in (out + err).splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l]
    if to or not fr or errs:
        print(name, "失败", to, "\n".join(errs[:10]))
    return d, fr


def main():
    import imageio_ffmpeg
    src = sys.argv[1] if len(sys.argv) > 1 else newest_runs()
    os.makedirs(OUT, exist_ok=True)
    runs = os.path.join(OUT, "runs_copy.jsonl")
    shutil.copyfile(src, runs)
    GR.ensure_imported(GAME)
    segs = [run("desktop", "1280x720", runs, []), run("phone", "1480x720", runs, ["--touch"])]
    f = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 16) if os.path.exists(r"C:\Windows\Fonts\msyh.ttc") else ImageFont.load_default()
    path = os.path.join(OUT, "run_log.mp4")
    proc = subprocess.Popen([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
                             "-s", "%dx%d" % (W, H), "-r", str(FPS), "-i", "-",
                             "-vf", "scale=out_color_matrix=bt709:out_range=tv", "-c:v", "libx264", "-preset", "slow", "-crf", "20",
                             "-pix_fmt", "yuv420p", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
                             "-color_range", "tv", "-movflags", "+faststart", path], stdin=subprocess.PIPE)
    n = 0
    for (d, fr), label in zip(segs, ["桌面 16:9", "手机横屏（触屏）"]):
        for p in fr:
            im = Image.open(p).convert("RGB")
            canvas = Image.new("RGB", (W, H), (0, 0, 0))
            canvas.paste(im, ((W - im.width) // 2, (H - im.height) // 2))
            dr = ImageDraw.Draw(canvas)
            lb = "结算 → 作战记录 → 返回 → 对局记录 → 进一局  ·  %s  ·  原速" % label
            dr.rectangle((0, 0, dr.textlength(lb, font=f) + 16, 24), fill=(0, 0, 0))
            dr.text((8, 2), lb, fill=(255, 220, 140), font=f)
            proc.stdin.write(canvas.tobytes())
            n += 1
    proc.stdin.close()
    proc.wait()
    for d, _ in segs:
        shutil.rmtree(d, ignore_errors=True)
    os.remove(runs)
    print("写出", path, "%.1f MB" % (os.path.getsize(path) / 1048576), "帧", n, "≈ %.1f 秒" % (n / FPS))


if __name__ == "__main__":
    main()
