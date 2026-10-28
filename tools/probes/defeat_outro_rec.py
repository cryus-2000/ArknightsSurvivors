# -*- coding: utf-8 -*-
"""失败退场慢动作录像（10-28 用户「被击败的瞬间慢动作，然后屏幕变暗接上结算画面」）：tests/outro_rec --crowd 逐帧存图 → H.264 mp4。
桌面 1280×720、--fixed-fps 30 + --realtime（原速 30 帧，录完按「帧数 ÷ 秒数 ≈ 30」核对）；接一段手机横屏 1480×720（--touch）。
录完即删帧目录。输出主仓库 build/settle_redesign/defeat_outro.mp4。用法：python tools/probes/defeat_outro_rec.py
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


def run(name, res, extra):
    d = os.path.join(OUT, "raw_outro_%s" % name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    out, err, to = GR.run_godot([GR.find_godot(), "--path", GAME, "--resolution", res, "--fixed-fps", str(FPS),
                                 "res://tests/outro_rec.tscn", "--", "--shotdir=" + d, "--crowd", "--realtime"] + extra, 400)
    fr = sorted(glob.glob(os.path.join(d, "rec_*.png")))
    print(name, " ".join(l for l in (out + err).splitlines() if "OUTRO_REC" in l))
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
    path = os.path.join(OUT, "defeat_outro.mp4")
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
            lb = "失败退场慢动作 → 压暗 → 结算  ·  %s  ·  原速" % label
            dr.rectangle((0, 0, dr.textlength(lb, font=f) + 16, 24), fill=(0, 0, 0))
            dr.text((8, 2), lb, fill=(255, 220, 140), font=f)
            proc.stdin.write(canvas.tobytes())
            n += 1
    proc.stdin.close()
    proc.wait()
    for d, _ in segs:
        shutil.rmtree(d, ignore_errors=True)   # 帧目录用完即删
    print("写出", path, "%.1f MB" % (os.path.getsize(path) / 1048576), "帧", n, "≈ %.1f 秒" % (n / FPS))


if __name__ == "__main__":
    main()
