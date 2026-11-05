#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""艾雅法拉终结技「海底火山」转平面版的本机样稿（docs/259 §7）：只用 Python + 本机 pixelfx 库出帧条，按原终结技的时序合成 GIF，不开 Godot。

时序照 ult_moves_b._ey_start / _ey_step（不动）：0–0.4 秒蓄压（裂网爬开）→ 0.4 秒喷发（顿帧 + 冲击帧整屏白 + 黑剪影，保留）
→ 0.55–1.0 秒 38 发火山弹从斜上方砸下、落地小爆团 + 浮石 → 熔岩池（半径 300 世界像素）0.9 秒漫开、到 3.2 秒判定结束再留 1.6 秒结壳淡掉。
画面：1 美术像素 = 2 屏幕像素，15 fps 节拍；贴地层压扁 0.72；最亮的芯做一层辉光（模拟游戏里的发光层），其余靠本色。
用法：python tools/ult_eyja_mock.py --out <目录> [--orig <原版 mp4>]
"""
import argparse, json, math, os, subprocess, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import pxplane_bake_eyja as BK   # noqa: E402

W, H, PX = 640, 360, 2
FPS = 15
ART = os.path.join(ROOT, "game", "art")
FONT = "C:/Windows/Fonts/msyh.ttc"


def h(x):
    return (math.sin(x * 12.9898 + 78.233) * 43758.5453) % 1.0


def strips(tmp):
    """本样稿要用的帧条：终结技件按大尺寸现烤，其余用游戏里已烤好的 pxp_ey_*"""
    BK.TMP = tmp
    need = [("ucrack", {"part": "ucrack", "layer": "gd", "el": 2, "R": 221, "seed": 11}, 1.5, False),
            ("ufount", {"part": "ufount", "layer": "up", "el": 2, "R": 165, "seed": 12}, 1.2, False),
            ("pumice", {"part": "pumice", "layer": "gd", "el": 2, "R": 4, "seed": 13, "dur": 2.6}, 2.6, False),
            ("pool", {"part": "upool", "layer": "gd", "el": 2, "R": 150, "k": 0, "seed": 9, "dur": 1.2}, 1.2, True),
            ("poolc", {"part": "upool", "layer": "gd", "el": 2, "R": 150, "k": 0.8, "seed": 9, "dur": 1.2}, 1.2, True),
            ("poolup", {"part": "lavaup", "layer": "up", "el": 2, "R": 150, "k": 1, "seed": 9, "dur": 1.2}, 1.2, True)]
    out = {}
    for key, o, dur, loop in need:
        k, d, du, lp = BK.render(key, o, dur, loop)
        meta = json.load(open(os.path.join(d, "meta.json")))
        fw, fh = meta["frameSize"]
        col = Image.open(os.path.join(d, "color.png")).convert("RGBA")
        n = min(meta["frames"], int(round(du * FPS)))
        out[key] = {"fr": [col.crop((i * fw, 0, (i + 1) * fw, fh)) for i in range(n)], "o": tuple(meta["pivot"]), "loop": lp}
    gm = json.load(open(os.path.join(ROOT, "game", "data", "pxp_eyjafjalla.json"), encoding="utf-8"))
    for key in ["splash_r22_up", "splash_r22_gd", "s3boom_r38_up", "s3boom_r38_gd"] + ["ball_rock_d%d" % d for d in (-90, -45, 0, 45, 90)]:
        m = gm[key]
        im = Image.open(os.path.join(ART, "fx", "pxp", "pxp_ey_%s.png" % key.replace("_d-", "_dm"))).convert("RGBA")
        out[key] = {"fr": [im.crop((i * m["w"], 0, (i + 1) * m["w"], m["h"])) for i in range(m["n"])], "o": (m["ox"], m["oy"]), "loop": m["loop"]}
    return out


def pick_dir(ang):
    a = math.degrees(math.atan2(math.sin(ang), math.cos(ang)))
    flip = False
    if abs(a) > 90:
        a = 180 - a if a > 0 else -180 - a
        flip = True
    best = min((-90, -45, 0, 45, 90), key=lambda d: abs(a - d))
    return best, flip


def put(canvas, S, key, fi, x, y, flip=False, alpha=1.0, sil=None):
    s = S[key]
    n = len(s["fr"])
    if s["loop"]:
        fi %= n
    elif fi < 0 or fi >= n:
        return
    im = s["fr"][fi]
    ox, oy = s["o"]
    if flip:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
        ox = im.width - 1 - ox
    if alpha < 1.0:
        a = np.asarray(im).copy()
        a[..., 3] = (a[..., 3] * alpha).astype(np.uint8)
        im = Image.fromarray(a)
    canvas.alpha_composite(im, (int(round(x - ox)), int(round(y - oy))))
    if sil is not None:
        sil.alpha_composite(im, (int(round(x - ox)), int(round(y - oy))))


def background():
    rng = np.random.default_rng(3)
    base = np.zeros((H, W, 3), np.float32)
    base[:] = (22, 34, 42)
    n = rng.random((H // 8 + 1, W // 8 + 1))
    n = np.kron(n, np.ones((8, 8)))[:H, :W]
    base += (n[..., None] - 0.5) * np.array([10, 12, 14])
    sp = rng.random((H, W)) > 0.996
    base[sp] = (60, 78, 88)
    return Image.fromarray(np.clip(base, 0, 255).astype(np.uint8)).convert("RGBA")


def sprites():
    ey = Image.open(os.path.join(ART, "operators", "eyjafjalla", "op_eyjafjalla_idle@1x.png")).convert("RGBA").crop((0, 0, 64, 64))
    en = []
    for p in ("floater/e_floater@2x.png", "duck/e_duck@2x.png"):
        im = Image.open(os.path.join(ART, "enemies", p)).convert("RGBA")
        fh = im.height
        fr = im.crop((0, 0, fh, fh))
        en.append(fr.resize((fh // 2, fh // 2), Image.NEAREST))
    return ey, en


def bloom(img):
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    luma = a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722
    m = np.where(luma[..., None] > 200, a, 0)
    g = Image.fromarray(m.astype(np.uint8)).filter(ImageFilter.GaussianBlur(5))
    out = np.clip(a + np.asarray(g).astype(np.float32) * 0.55, 0, 255)
    return Image.fromarray(out.astype(np.uint8))


def render(S, out_dir):
    bg = background()
    ey, en = sprites()
    C = (400, 200)   # 落点（美术像素）
    R = 295.0        # 判定半径 590 世界像素
    ex = (170, 236)  # 艾雅法拉脚底
    rng = np.random.default_rng(5)
    foes = []
    for i in range(18):
        a = rng.random() * math.tau
        r = math.sqrt(rng.random()) * 150
        foes.append((C[0] + math.cos(a) * r, C[1] + math.sin(a) * r * 0.72, i % 2))
    # 火山弹：黄金角从里往外落（同 _spiral），0.55 + 0.45 · i / 38 秒落地
    bombs = []
    for i in range(38):
        rr = R * 0.97 * math.sqrt((i + 0.5) / 38)
        an = i * 2.39996 + 0.4
        p = (C[0] + math.cos(an) * rr, C[1] + math.sin(an) * rr)
        hb = h(p[0] * 0.017 + p[1] * 0.031)
        p0 = (p[0] - 70 - 60 * hb, p[1] - 210 - 80 * h(hb * 5))
        bombs.append((p, p0, 0.55 + 0.45 * i / 38 + 0.06 * h(hb * 37), hb))
    frames = []
    T = 4.8
    for fi in range(int(T * FPS)):
        t = fi / FPS
        cv = bg.copy()
        sil = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        # 贴地层
        put(cv, S, "ucrack", fi, *C)
        if t >= 0.4:
            pa = min(1.0, (t - 0.4) / 0.9)   # 熔岩池 0.9 秒漫开（这里用透明度近似漫开，游戏里按半径长大）
            fade = 1.0 - max(0.0, (t - 3.2) / 1.6)
            if fade > 0:   # 判定结束（3.2 秒）后换结壳版、慢慢淡掉
                put(cv, S, "pool" if t < 3.2 else "poolc", fi, *C, alpha=pa * fade)
        for p, p0, tl, hb in bombs:
            if t >= tl:
                put(cv, S, "splash_r22_gd", int((t - tl) * FPS), *p)
                put(cv, S, "pumice", int((t - tl) * FPS), p[0], p[1] + 1)
        # 立起层：按脚底 y 排序
        ups = [(ex[1], "ey", None)]
        for x, y, k in foes:
            ups.append((y, "foe", (x, y, k)))
        if t >= 0.4:
            ups.append((C[1] + 2, "fount", None))
            if t <= 3.2 + 1.6:
                ups.append((C[1] + 1, "poolup", None))
        for p, p0, tl, hb in bombs:
            if tl - 0.16 <= t < tl:
                ups.append((p[1] - 1, "bomb", (p, p0, tl)))
            elif t >= tl:
                ups.append((p[1], "splash", (p, tl)))
        ups.sort(key=lambda u: u[0])
        for _, kind, d in ups:
            if kind == "ey":
                cv.alpha_composite(ey, (ex[0] - 32, ex[1] - 60))
                sil.alpha_composite(ey, (ex[0] - 32, ex[1] - 60))
            elif kind == "foe":
                x, y, k = d
                im = en[k]
                cv.alpha_composite(im, (int(x - im.width / 2), int(y - im.height + 4)))
                sil.alpha_composite(im, (int(x - im.width / 2), int(y - im.height + 4)))
            elif kind == "fount":
                put(cv, S, "ufount", int((t - 0.4) * FPS), *C, sil=sil)
            elif kind == "poolup":
                put(cv, S, "poolup", fi, *C)
            elif kind == "bomb":
                p, p0, tl = d
                k = 1 - (tl - t) / 0.16
                pos = (p0[0] + (p[0] - p0[0]) * k, p0[1] + (p[1] - p0[1]) * k)
                dd, fl = pick_dir(math.atan2(p[1] - p0[1], p[0] - p0[0]))
                put(cv, S, "ball_rock_d%d" % dd, fi, pos[0], pos[1] - 6, fl)
            elif kind == "splash":
                p, tl = d
                put(cv, S, "splash_r22_up", int((t - tl) * FPS), *p)
        img = bloom(cv)
        if abs(t - 0.4) < 0.5 / FPS:   # 冲击帧（保留）：整屏白 + 黑剪影
            m = np.asarray(sil)[..., 3] > 100
            a = np.full((H, W, 3), 245, np.uint8)
            a[m] = (12, 8, 10)
            img = Image.fromarray(a)
        frames.append(img.resize((W * PX, H * PX), Image.NEAREST))
    return frames


def label(im, s):
    d = ImageDraw.Draw(im)
    f = ImageFont.truetype(FONT, 26)
    d.rectangle((0, 0, d.textlength(s, font=f) + 20, 40), fill=(10, 10, 14))
    d.text((10, 4), s, fill=(235, 235, 235), font=f)
    return im


def save_gif(frames, path, scale=1.0):
    fr = [f.resize((int(f.width * scale), int(f.height * scale)), Image.NEAREST) if scale != 1.0 else f for f in frames]
    pal = [f.convert("P", palette=Image.ADAPTIVE, colors=200) for f in fr]
    pal[0].save(path, save_all=True, append_images=pal[1:], duration=int(1000 / FPS), loop=0, optimize=True, disposal=1)
    print(path, len(fr), "帧", "%.1f MB" % (os.path.getsize(path) / 1048576))


def orig_frames(mp4, n, t_imp):
    """原版录像（GCP ult_rec，30 帧）：找冲击帧（整屏最白的那一帧），按 15 fps 取 n 帧，让冲击帧和新版对齐"""
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    tmp = os.path.join(os.path.dirname(mp4), "_of")
    os.makedirs(tmp, exist_ok=True)
    subprocess.run([ff, "-loglevel", "error", "-y", "-i", mp4, "-vf", "fps=15,scale=1280:720", os.path.join(tmp, "f%04d.png")], check=True)
    fs = sorted(os.listdir(tmp))
    br = [np.asarray(Image.open(os.path.join(tmp, f)).convert("L").resize((64, 36))).mean() for f in fs]
    ki = int(np.argmax(br))
    st = ki - int(round(t_imp * FPS))
    out = []
    for i in range(n):
        j = min(len(fs) - 1, max(0, st + i))
        out.append(Image.open(os.path.join(tmp, fs[j])).convert("RGB"))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--orig", default="")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    S = strips(os.path.join(ROOT, "build", "ult_eyja_mock"))
    fr = render(S, a.out)
    save_gif([label(f.copy(), "艾雅法拉 终结技「海底火山」· 转平面样稿（本机合成，15 fps）") for f in fr], os.path.join(a.out, "ult_eyja_new.gif"), 0.75)
    if a.orig:
        of = orig_frames(a.orig, len(fr), 0.4)
        both = []
        for o, n in zip(of, fr):
            im = Image.new("RGB", (1280 * 2 + 8, 720), (10, 10, 14))
            im.paste(label(o.copy(), "① 当前游戏（GCP 录像）"), (0, 0))
            im.paste(label(n.copy(), "② 转平面样稿（本机合成）"), (1288, 0))
            both.append(im)
        save_gif(both, os.path.join(a.out, "ult_eyja_before_after.gif"), 0.5)


if __name__ == "__main__":
    main()
