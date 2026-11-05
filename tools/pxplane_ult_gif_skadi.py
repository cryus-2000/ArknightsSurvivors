#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""斯卡蒂终结技转平面预览（docs/246 §16，本机不开 Godot）：pixelfx 直接出 up / gd 两层帧条，按游戏的层次拼成 GIF。
  起手（charge，0.5 真实秒，游戏里是起手慢放）→ 招式（ult，t = 出招后秒数）；劈浪那一拍按游戏的冲击帧画两拍「整屏白 + 黑剪影」。
用法：
  python tools/pxplane_ult_gif_skadi.py seq --out <目录>/ult_seq.gif [--bg <底图.png>] [--foot X,Y]
  python tools/pxplane_ult_gif_skadi.py sheet --out <目录>/sheet.png      （逐帧小图，自查用）
  python tools/pxplane_ult_gif_skadi.py side --orig <原版 mp4> --orig-from 秒 --out <目录>/ult_side.gif
"""
import argparse, json, os, subprocess, sys, tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PFX = os.path.join(os.path.dirname(ROOT), "pixelfx") if os.path.isdir(os.path.join(os.path.dirname(ROOT), "pixelfx")) else "E:/ArknightsSurvivors/build/pixelfx"
FX = "water/ak-skadi-ult-pp"
OP = os.path.join(ROOT, "game", "art", "operators", "skadi", "op_skadi_idle@2x.png")
OPA = os.path.join(ROOT, "game", "art", "operators", "skadi", "op_skadi_attack@2x.png")
FONT = "C:/Windows/Fonts/msyh.ttc"
FPS = 15
try:
    import imageio_ffmpeg
    FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
except Exception:
    FFMPEG = "ffmpeg"
W, H = 640, 360            # 屏幕（美术像素）= 1280×720 世界像素
CHG_N = 8                  # 起手 0.5 秒 ≈ 8 拍
HF_N = 2                   # 冲击帧两拍


def render(part, layer, tmp, opts=None):
    import shutil
    src = os.path.join(ROOT, "tools", "pixelfx_fx", "water", "ak-skadi-ult-pp.js")
    shutil.copy(src, os.path.join(PFX, "src", "fx", "water", "ak-skadi-ult-pp.js"))
    shutil.copy(src.replace("-ult-pp", "-pp"), os.path.join(PFX, "src", "fx", "water", "ak-skadi-pp.js"))   # 水花冠在这里
    d = os.path.join(tmp, "%s_%s" % (part, layer))
    o = {"part": part, "layer": layer}
    o.update(opts or {})
    p = subprocess.run(["node", "tools/ak_layers.mjs", FX, "--out", d, "--fps", str(FPS), "--opts", json.dumps(o)], cwd=PFX, capture_output=True, text=True)
    if p.returncode != 0:
        sys.exit(p.stderr[-800:])
    m = json.load(open(os.path.join(d, "meta.json")))
    col = Image.open(os.path.join(d, "color.png")).convert("RGBA")
    lit = Image.open(os.path.join(d, "light.png")).convert("RGB")
    fw, fh = m["frameSize"]
    fr = [col.crop((i * fw, 0, i * fw + fw, fh)) for i in range(m["frames"])]
    li = [lit.crop((i * fw, 0, i * fw + fw, fh)) for i in range(m["frames"])]
    return fr, li, m["pivot"]


def sprite(path, i=0, n=8):
    im = Image.open(path).convert("RGBA")
    w = im.width // n
    f = im.crop((i * w, 0, i * w + w, im.height))
    return f.resize((w // 2, im.height // 2), Image.NEAREST)


def glow(base, lit, at, k=0.55):
    """light 层：模糊后加色（近似游戏的发光层，不整屏发白）"""
    from PIL import ImageFilter
    L = lit.filter(ImageFilter.GaussianBlur(3))
    a = np.asarray(base).astype(np.float32)
    g = np.zeros_like(a[..., :3])
    l = np.asarray(L).astype(np.float32)
    x, y = at
    h, w = l.shape[:2]
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(a.shape[1], x + w), min(a.shape[0], y + h)
    if x1 > x0 and y1 > y0:
        g[y0:y1, x0:x1] = l[y0 - y:y1 - y, x0 - x:x1 - x]
    a[..., :3] = np.clip(a[..., :3] + g * k, 0, 255)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def build(tmp, bg, foot, dir_deg=0):
    opts = {"dir": dir_deg}
    cu, cul, piv = render("charge", "up", tmp, opts)
    cg, _, _ = render("charge", "gd", tmp, opts)
    uu, uul, _ = render("ult", "up", tmp, opts)
    ug, _, _ = render("ult", "gd", tmp, opts)
    ox, oy = foot[0] - piv[0], foot[1] - piv[1]
    idle = sprite(OP)
    atk = [sprite(OPA, i) for i in range(8)] if os.path.exists(OPA) else [idle] * 8
    fh = (32, 60)
    frames, tags = [], []
    # 冲击帧时刻（同 JS crashT）
    tc = 0.15
    while True:
        k = min(1.0, (tc - 0.15) / 0.8)
        if -100 + 850 * k * (1.35 - 0.35 * k) >= 260:
            break
        tc += 0.002
    ihf = int(np.ceil(tc * FPS))
    # 冲击帧两拍插在爆点那一拍之前：游戏里顿帧期间招式时间不走，冲击帧过后爆点两拍照常亮
    # 劈开慢动作：冲击帧后 SPLIT（0.25 游戏秒 ≈ 4 拍）按 0.3 倍速放（每拍停 3 帧），之后原速起爆
    ns = 4
    seq = [("charge", i) for i in range(CHG_N)] + [("ult", i) for i in range(ihf)] + [("hf", ihf)] * HF_N + [("ult", i) for i in range(ihf, ihf + ns) for _ in range(3)] + [("ult", i) for i in range(ihf + ns, len(uu))]
    for part, i in seq:
        im = bg.copy().convert("RGBA")
        hf = part == "hf"
        g = (cg if part == "charge" else ug)[i]
        u = (cu if part == "charge" else uu)[i]
        l = (cul if part == "charge" else uul)[i]
        im.alpha_composite(g, (ox, oy))
        op = atk[min(7, 2 + i // 2)] if part == "charge" else atk[min(7, 5 + i)] if i < 4 else idle
        im.alpha_composite(op, (foot[0] - fh[0], foot[1] - fh[1]))
        im.alpha_composite(u, (ox, oy))
        im = glow(im, l, (ox, oy))
        if hf:   # 冲击帧：整屏白 + 黑剪影（特效与干员的不透明像素）
            sil = Image.new("RGBA", im.size, (255, 255, 255, 255))
            m = Image.new("L", im.size, 0)
            for layer, at in ((u, (ox, oy)), (op, (foot[0] - fh[0], foot[1] - fh[1]))):   # 游戏里冲击帧只把劈浪这拍新建的立起件 + 干员进剪影，地面不进
                m.paste(Image.fromarray((np.asarray(layer)[..., 3] > 128).astype(np.uint8) * 255, "L"), at, Image.fromarray((np.asarray(layer)[..., 3] > 128).astype(np.uint8) * 255, "L"))
            sil.paste((0, 0, 0, 255), (0, 0), m)
            im = sil
        frames.append(im.convert("RGB"))
        tags.append("起手（慢放）" if part == "charge" else ("冲击帧" if hf else "下劈" if i < 3 else "推浪" if i < ihf - 2 else "预备（往劈口收）" if i < ihf else "爆点" if i < ihf + 2 else "冲击环 + 水爆" if i < ihf + 5 else "收尾"))
    return frames, tags


def default_bg():
    im = Image.new("RGB", (W, H), (34, 46, 52))
    a = np.asarray(im).astype(np.int16)
    rng = np.random.default_rng(3)
    a += (rng.integers(-3, 4, a.shape[:2])[..., None]).astype(np.int16)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def label(img, txt, sc=2):
    big = img.resize((img.width * sc, img.height * sc), Image.NEAREST)
    d = ImageDraw.Draw(big)
    f = ImageFont.truetype(FONT, 22)
    d.rectangle((0, 0, big.width, 32), fill=(10, 12, 16))
    d.text((10, 4), txt, fill=(230, 230, 230), font=f)
    return big


def save_gif(frames, out):
    os.makedirs(os.path.dirname(out), exist_ok=True)
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=int(1000 / FPS), loop=0, optimize=True)
    print("GIF", out, len(frames), "帧", "%.1f MB" % (os.path.getsize(out) / 1048576.0))


def orig_frames(mp4, t0, n, tmp):
    d = os.path.join(tmp, "orig")
    os.makedirs(d, exist_ok=True)
    subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-ss", str(t0), "-i", mp4, "-vf", "fps=%d,scale=%d:%d:flags=neighbor" % (FPS, W, H), "-frames:v", str(n), os.path.join(d, "o_%03d.png")], check=True)
    return [Image.open(os.path.join(d, "o_%03d.png" % (i + 1))).convert("RGB") for i in range(n) if os.path.exists(os.path.join(d, "o_%03d.png" % (i + 1)))]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["seq", "sheet", "side"])
    ap.add_argument("--out", required=True)
    ap.add_argument("--bg", default="")
    ap.add_argument("--foot", default="320,190")
    ap.add_argument("--dir", type=int, default=0)
    ap.add_argument("--orig", default="")
    ap.add_argument("--orig-from", type=float, default=0.0)
    a = ap.parse_args()
    tmp = tempfile.mkdtemp(prefix="ultgif_")
    bg = Image.open(a.bg).convert("RGB").resize((W, H), Image.NEAREST) if a.bg else default_bg()
    foot = tuple(int(v) for v in a.foot.split(","))
    frames, tags = build(tmp, bg, foot, a.dir)
    if a.cmd == "sheet":
        cols = 6
        th = [f.resize((W // 2, H // 2), Image.NEAREST) for f in frames]
        sh = Image.new("RGB", (cols * W // 2, ((len(th) + cols - 1) // cols) * H // 2), (0, 0, 0))
        for i, f in enumerate(th):
            sh.paste(f, ((i % cols) * W // 2, (i // cols) * H // 2))
        sh.save(a.out)
        print(a.out)
        return
    if a.cmd == "seq":
        save_gif([label(f, "新版（转平面）· %s · 第 %d 拍 · 15 fps 原速" % (t, i + 1)) for i, (f, t) in enumerate(zip(frames, tags))] + [label(frames[-1], "收尾")] * 4, a.out)
        return
    of = orig_frames(a.orig, a.orig_from, len(frames), tmp)
    out = []
    for i, f in enumerate(frames):
        o = of[min(i, len(of) - 1)]
        L = label(o, "原版")
        R = label(f, "新版（转平面）· " + tags[i])
        im = Image.new("RGB", (L.width + R.width + 8, L.height), (0, 0, 0))
        im.paste(L, (0, 0))
        im.paste(R, (L.width + 8, 0))
        out.append(im.resize((im.width // 2, im.height // 2), Image.NEAREST) if im.width > 2000 else im)
    save_gif(out, a.out)


if __name__ == "__main__":
    main()
