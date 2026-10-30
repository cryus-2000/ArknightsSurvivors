# -*- coding: utf-8 -*-
"""干员小人大小对照（10-30）：tests/op_fig_sheet 桌面 1280×720 与手机横屏 1480×720（--touch）各一组 → 逐张停 2.5 秒的 mp4。
按 review 规矩只交 mp4（不拼图）。用法：python tools/probes/op_fig_sheet.py；输出主仓库 build/record_sprite_scale/op_fig_sheet.mp4，录完删图。
"""
import os, sys, glob, shutil, subprocess
from PIL import Image, ImageDraw, ImageFont

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
import godot_runner as GR

GAME = os.path.join(ROOT, "game")
OUT = os.path.join(GR.common_root(), "build", "record_sprite_scale")
W, H, FPS, HOLD = 1480, 720, 30, 2.5
NAMES = ["作战记录总览", "作战记录详情"]


def run(name, res, extra):
    d = os.path.join(OUT, "raw_%s" % name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    out, err, to = GR.run_godot([GR.find_godot(), "--path", GAME, "--resolution", res, "--audio-driver", "Dummy",
                                 "res://tests/op_fig_sheet.tscn", "--", "--shotdir=" + d] + extra, 300)
    fr = sorted(glob.glob(os.path.join(d, "sheet_*.png")))
    errs = [l for l in (out + err).splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l]
    if to or not fr or errs:
        print(name, "失败", to, "\n".join(errs[:10]))
    return d, fr


def main():
    import imageio_ffmpeg
    GR.ensure_imported(GAME)
    os.makedirs(OUT, exist_ok=True)
    segs = [run("desktop", "1280x720", []), run("phone", "1480x720", ["--touch"])]
    f = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 16) if os.path.exists(r"C:\Windows\Fonts\msyh.ttc") else ImageFont.load_default()
    path = os.path.join(OUT, "op_fig_sheet.mp4")
    proc = subprocess.Popen([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
                             "-s", "%dx%d" % (W, H), "-r", str(FPS), "-i", "-",
                             "-vf", "scale=out_color_matrix=bt709:out_range=tv", "-c:v", "libx264", "-preset", "slow", "-crf", "18",
                             "-pix_fmt", "yuv420p", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
                             "-color_range", "tv", "-movflags", "+faststart", path], stdin=subprocess.PIPE)
    n = 0
    for (d, fr), label in zip(segs, ["桌面 16:9", "手机横屏（触屏）"]):
        for i, p in enumerate(fr):
            im = Image.open(p).convert("RGB")
            canvas = Image.new("RGB", (W, H), (0, 0, 0))
            canvas.paste(im, ((W - im.width) // 2, (H - im.height) // 2))
            dr = ImageDraw.Draw(canvas)
            what = "对局记录" if i == len(fr) - 1 else "%s · 第 %d 批" % (NAMES[i % 2], i // 2 + 1)
            lb = "干员小人同一比例 · %s · %s" % (label, what)
            dr.rectangle((0, 0, dr.textlength(lb, font=f) + 16, 24), fill=(0, 0, 0))
            dr.text((8, 2), lb, fill=(255, 220, 140), font=f)
            b = canvas.tobytes()
            for _ in range(int(HOLD * FPS)):
                proc.stdin.write(b)
            n += 1
    proc.stdin.close()
    proc.wait()
    for d, _ in segs:
        shutil.rmtree(d, ignore_errors=True)
    print("写出", path, "%.1f MB" % (os.path.getsize(path) / 1048576), "张", n)


if __name__ == "__main__":
    main()
