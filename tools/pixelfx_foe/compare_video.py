# -*- coding: utf-8 -*-
"""pixelfx 敌方试点对照视频（docs/236）：读 rec_moves.py 录的逐帧截图（--fixed-fps 30、每帧一张、同 seed，原速），
左旧右新并排，1:1 像素裁 640×360（不缩放，像素不糊；裁框中心可按 tag 偏移到招式落点），H.264 30 帧，无音轨。
另存每段最亮一帧的并排 PNG（_peak_<tag>.png）给预审 / 汇报看细节。

    python tools/pixelfx_foe/compare_video.py <输出.mp4> carmen immortal:120,-40
    （tag 后面 :dx,dy 是裁框中心相对画面中心的偏移，屏幕像素）
"""
import os, shutil, subprocess, sys, tempfile
from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "build", "foe_fx")
CW, CH, FPS = 640, 360, 30


def shots(d):
    return sorted(f for f in os.listdir(d) if f.startswith("shot_bmframe_") and f.endswith(".png"))


def crop(p, dx, dy):
    im = Image.open(p).convert("RGB")
    w, h = im.size
    x0, y0 = (w - CW) // 2 + dx, (h - CH) // 2 + dy
    return im.crop((x0, y0, x0 + CW, y0 + CH))


def main():
    import imageio_ffmpeg
    dst, items = sys.argv[1], sys.argv[2:]
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 20)
    except OSError:
        font = None
    tmp = tempfile.mkdtemp(prefix="foefx_")
    k = 0
    for item in items:
        tag, _, off = item.partition(":")
        dx, dy = (int(v) for v in off.split(",")) if off else (0, 0)
        da, db = os.path.join(OUT, "before", tag), os.path.join(OUT, "after", tag)
        fa, fb = shots(da), shots(db)
        n = min(len(fa), len(fb))
        best = (-1, 0)
        for i in range(n):
            a, b = crop(os.path.join(da, fa[i]), dx, dy), crop(os.path.join(db, fb[i]), dx, dy)
            fr = Image.new("RGB", (CW * 2 + 8, CH), (10, 12, 18))
            fr.paste(a, (0, 0))
            fr.paste(b, (CW + 8, 0))
            dd = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v > 40 else 0).histogram()[255]
            if dd > best[0]:
                best = (dd, i)
                peak = fr.copy()
            d = ImageDraw.Draw(fr)
            for x, s in ((8, "旧"), (CW + 16, "新 pixelfx")):
                d.rectangle((x - 4, 4, x + (110 if "新" in s else 30), 30), fill=(0, 0, 0))
                d.text((x, 5), s, fill=(255, 230, 150), font=font)
            fr.save(os.path.join(tmp, "f%05d.png" % k))
            k += 1
        peak.save(os.path.join(os.path.dirname(dst), "_peak_%s.png" % tag))
        print(tag, "帧", n, "差异最大帧", best[1], best[0])
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(tmp, "f%05d.png"),
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", "slow", "-crf", "20", "-movflags", "+faststart", "-an", dst], check=True)
    shutil.rmtree(tmp, ignore_errors=True)
    print(dst, "%.1f MB" % (os.path.getsize(dst) / 1048576.0), k, "帧")


if __name__ == "__main__":
    main()
