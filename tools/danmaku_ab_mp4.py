# -*- coding: utf-8 -*-
"""Boss 弹幕新旧对照：把 GCP danmaku_ab.sh 回传的帧（<SPEC>_old / <SPEC>_new，fr_*.jpg，画面中央 1280×720 原像素）拼成左旧右新的 mp4（30 帧原速）。

  python tools/danmaku_ab_mp4.py --frames "<主仓库>/Claude outputs/render-danmaku-ab4/frames" --out <目录>
"""
import argparse, glob, os, subprocess, sys
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import concept_danmaku as V1

NAMES = {"path": "塑路者 · 探路分形", "bishop": "接潮主教 · 交错潮环", "immortal": "接潮斥亡体 · 斥亡旋刃", "iberia": "圣徒伊比利亚 · 散射",
         "carmen": "圣徒卡门 · 环射", "izumik2": "伊祖米克 · 螺旋弹臂", "ishar2": "伊莎玛拉 · 泪雨", "paranoia": "偏执泡影 · 偏执双旋"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--frames", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    try:
        import imageio_ffmpeg
        ff = imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        ff = "ffmpeg"
    f1, f2 = V1.font(30), V1.font(22)
    for spec, nm in NAMES.items():
        od, nd = os.path.join(a.frames, spec + "_old"), os.path.join(a.frames, spec + "_new")
        olds = sorted(glob.glob(os.path.join(od, "fr_*.*")))
        if not olds:
            continue
        tmp = os.path.join(a.out, "_ab_" + spec)
        os.makedirs(tmp, exist_ok=True)
        n = 0
        for f in olds:
            g = os.path.join(nd, os.path.basename(f))
            if not os.path.exists(g):
                break
            A, B = Image.open(f).convert("RGB"), Image.open(g).convert("RGB")
            W, H = A.size
            c = Image.new("RGB", (W * 2 + 12, H + 56), (14, 14, 18))
            c.paste(A, (0, 56))
            c.paste(B, (W + 12, 56))
            d = ImageDraw.Draw(c)
            d.text((14, 10), "现在", fill=(235, 235, 240), font=f1)
            d.text((W + 26, 10), "新版", fill=(235, 235, 240), font=f1)
            d.text((W - 420, 16), nm, fill=(190, 190, 200), font=f2)
            c.save(os.path.join(tmp, "f_%04d.png" % n))
            n += 1
        mp4 = os.path.join(a.out, "ab_%s.mp4" % spec)
        subprocess.run([ff, "-loglevel", "error", "-y", "-framerate", "30", "-i", os.path.join(tmp, "f_%04d.png"), "-c:v", "libx264",
                        "-pix_fmt", "yuv420p", "-crf", "18", "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2", mp4], check=True)
        for f in glob.glob(os.path.join(tmp, "*.png")):
            os.remove(f)
        os.rmdir(tmp)
        print(mp4, n, "帧")


if __name__ == "__main__":
    main()
