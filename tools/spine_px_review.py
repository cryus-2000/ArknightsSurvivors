# -*- coding: utf-8 -*-
"""新干员 B 方案帧条审阅（docs/365 §5）：同屏站位对照（1 倍 + 放大）与逐动作循环录像（原速 30 帧 mp4）。

    python tools/spine_px_review.py ling --vs suzuran angelina mizuki texas
    python tools/spine_px_review.py ling --video-only

站位：各人待机首帧按游戏原点（128 画布 (64,120) / 192 画布 (96,152)）对齐到同一地线，原色原尺寸；放大图 ×4 最近邻。
录像：每个动作一格，按 build/spine_px/<id>/summary.json 的逐帧时长原速循环；30 帧、×3 最近邻、底色与审阅图同。
产物在 build/spine_px/<id>/review/。
"""
import argparse, glob, json, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as _GR
COMMON = _GR.common_root()
BG = (48, 61, 77, 255)
NAMES = {"ling": "令", "suzuran": "铃兰", "angelina": "安洁莉娜", "mizuki": "水月", "texas": "德克萨斯", "phantom": "傀影", "dusk": "夕", "shu": "黍", "surtr": "史尔特尔", "fiammetta": "菲亚梅塔"}


def font(sz):
    for f in ("C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/simhei.ttf"):
        if os.path.exists(f):
            return ImageFont.truetype(f, sz)
    return ImageFont.load_default()


def origin(size):
    return (size // 2, {128: 120, 192: 152, 256: 184}[size])


def lineup(oid, vs, out):
    cells = []
    for o in [oid] + vs:
        d = os.path.join(ROOT, "game", "art", "operators", o)
        cand = [os.path.join(d, "op_%s_idle@2x.png" % o)] + sorted(glob.glob(os.path.join(d, "*idle*@2x.png")))
        p = next(c for c in cand if os.path.exists(c))
        im = Image.open(p).convert("RGBA")
        s = im.height
        cells.append((o, im.crop((0, 0, s, s)), origin(s)))
    W, UP, DN = 120, 100, 16          # 每人格宽、原点以上 / 以下高度（@2x 像素）
    img = Image.new("RGBA", (W * len(cells), UP + DN), BG)
    for i, (o, im, (ox, oy)) in enumerate(cells):
        img.alpha_composite(im.crop((ox - W // 2, oy - UP, ox + W // 2, oy + DN)), (i * W, 0))
    d = ImageDraw.Draw(img)
    d.line((0, UP, img.width, UP), fill=(90, 105, 125, 255))
    img.save(os.path.join(out, "lineup_x1.png"))
    big = img.resize((img.width * 4, img.height * 4), Image.NEAREST)
    lab = Image.new("RGBA", (big.width, big.height + 44), (24, 28, 36, 255))
    lab.paste(big, (0, 44))
    dd = ImageDraw.Draw(lab)
    f = font(26)
    for i, (o, _, _) in enumerate(cells):
        dd.text((i * W * 4 + 12, 8), NAMES.get(o, o) + ("（B 方案）" if o == oid else ""), font=f, fill=(235, 235, 235, 255))
    lab.save(os.path.join(out, "lineup_x4.png"))
    return os.path.join(out, "lineup_x1.png"), os.path.join(out, "lineup_x4.png")


def video(oid, out, fps=30, secs=None, scale=3):
    base = os.path.join(COMMON, "build", "spine_px", oid)
    summ = json.load(open(os.path.join(base, "summary.json"), encoding="utf-8"))
    acts = [a for a in summ if os.path.exists(os.path.join(base, "strips", "op_%s_%s@2x.png" % (oid, a)))]
    strips = {}
    for a in acts:
        im = Image.open(os.path.join(base, "strips", "op_%s_%s@2x.png" % (oid, a))).convert("RGBA")
        s = im.height
        strips[a] = [im.crop((s * k, 0, s * (k + 1), s)) for k in range(im.width // s)]
    size = next(iter(strips.values()))[0].width
    crop = (size // 2 - 64, 8, size // 2 + 64, size - 8)            # 192 画布裁 128×176，人物与提灯都在内
    cw, ch = (crop[2] - crop[0]) * scale, (crop[3] - crop[1]) * scale
    cols = 5
    rows = (len(acts) + cols - 1) // cols
    W, H = cols * cw, rows * (ch + 34)
    W += W % 2
    H += H % 2
    total = secs or max(4.0, max(sum(summ[a]["durations"]) for a in acts) * 2)
    fr = os.path.join(out, "_vid")
    os.makedirs(fr, exist_ok=True)
    for f in glob.glob(os.path.join(fr, "*.png")):
        os.remove(f)
    f = font(22)
    n = int(total * fps)
    for k in range(n):
        t = k / fps
        img = Image.new("RGB", (W, H), (24, 28, 36))
        d = ImageDraw.Draw(img)
        for i, a in enumerate(acts):
            durs = summ[a]["durations"]
            L = sum(durs)
            tt = t % L
            j = 0
            while j < len(durs) - 1 and tt >= durs[j]:
                tt -= durs[j]
                j += 1
            cell = Image.new("RGBA", (crop[2] - crop[0], crop[3] - crop[1]), BG)
            cell.alpha_composite(strips[a][j].crop(crop))
            x, y = (i % cols) * cw, (i // cols) * (ch + 34)
            img.paste(cell.resize((cw, ch), Image.NEAREST).convert("RGB"), (x, y + 34))
            d.text((x + 8, y + 4), "%s  %d 帧 %.2fs" % (a, len(durs), L), font=f, fill=(230, 230, 230))
        img.save(os.path.join(fr, "%05d.png" % k))
    import imageio_ffmpeg
    mp4 = os.path.join(out, "%s_anims.mp4" % oid)
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-framerate", str(fps), "-i", os.path.join(fr, "%05d.png"),
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16", "-r", str(fps), mp4], check=True)
    for f2 in glob.glob(os.path.join(fr, "*.png")):
        os.remove(f2)
    os.rmdir(fr)
    return mp4


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("id")
    ap.add_argument("--vs", nargs="*", default=["suzuran", "angelina", "mizuki", "texas"])
    ap.add_argument("--video-only", action="store_true")
    ap.add_argument("--secs", type=float)
    a = ap.parse_args()
    out = os.path.join(COMMON, "build", "spine_px", a.id, "review")
    os.makedirs(out, exist_ok=True)
    if not a.video_only:
        print(*lineup(a.id, a.vs, out))
    print(video(a.id, out, secs=a.secs))


if __name__ == "__main__":
    main()
