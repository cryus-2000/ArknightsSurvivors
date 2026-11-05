#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""推进之王终结技转平面送审 GIF（docs/264 §10）：只用 Python 拼帧条，不开 Godot。

整段：起跳 → 空中蓄力（0.6 秒，落点预兆）→ 砸落 → 冲击帧（白底黑剪影 / 黑底白剪影各 1 拍，剪影主体 = 裂网）→ 四拍余震 + 敌人震上半空 0.8 秒后落地。
时序照 ult_moves_c._sg_*：ult/sg_air 0.6、ult/sg_lift 0.8、四拍间隔 0.18；判定半径 540 世界 = 270 美术像素。1 倍 = 实机大小（1 美术像素 = 2 屏幕像素），15 fps 原速。
用法：python tools/pxplane_ult_gif.py [--orig <原版录像 mp4> --orig_from 秒 --orig_secs 秒] [--out 目录]
"""
import argparse, json, math, os, subprocess

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

import pxplane_gif as PG

ROOT = PG.ROOT
PX = 2
W, H = 1240, 820           # 1 倍画面（世界像素）
OX, OY = 300, 470          # 起跳点（她脚底）
SY = 0.72
FONT = "C:/Windows/Fonts/msyh.ttc"


class Lib(PG.Lib):
    def __init__(self):
        self.meta, self.tex = {}, {}
        for name in ("pxp_siege.json", "pxp_siege_ult.json"):
            for k, v in json.load(open(os.path.join(ROOT, "game", "data", name), encoding="utf-8")).items():
                if k != "_doc":
                    self.meta[k] = v


def paste_strip(img, lib, k, fi, gp, emit_draw):
    r = lib.frame(k, fi)
    if r is None:
        return
    fr, m = r
    gx, gy = round((OX + gp[0] * PX) / 2) * 2, round((OY + gp[1] * PX) / 2) * 2
    left, top = int(gx - m["ox"] * PX), int(gy - m["oy"] * PX)
    big = fr.resize((fr.width * PX, fr.height * PX), Image.NEAREST)
    img.alpha_composite(big, dest=(max(0, left), max(0, top)), source=(max(0, -left), max(0, -top)))
    for q in (m["emit"][fi] if fi < len(m["emit"]) else []):
        emit_draw.rectangle([left + q[0] * PX, top + q[1] * PX, left + q[0] * PX + PX - 1, top + q[1] * PX + PX - 1], fill=tuple(int(q[2][i:i + 2], 16) for i in (0, 2, 4)))


def scene(lib, n_ticks):
    """返回每拍一张 RGB（1 倍）。坐标：美术像素，相对起跳点"""
    C = (190, 0)                 # 落点
    T_AIR, HAIR = 9, 85          # 0.6 秒 = 9 拍；ult/sg_h 170 世界 = 85 美术
    R = 270
    rng = np.random.default_rng(5)
    ens = []                     # 敌人：落点周围一大群
    for i in range(46):
        a, r = rng.uniform(0, math.tau), R * math.sqrt(rng.uniform(0.02, 1.15))
        ens.append([C[0] + math.cos(a) * r, C[1] + math.sin(a) * r * SY, r <= R])
    en = PG.sprite_frames(os.path.join(ROOT, "game", "art", "enemies", "offspring", "e_offspring@2x.png"), 4)[0]
    arr = np.asarray(en).astype(np.float32)
    arr[..., :3] = arr[..., :3] * 0.32 + np.array([10, 12, 14])
    ENEMY = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    OP = PG.sprite_frames(os.path.join(ROOT, "game", "art", "operators", "siege", "op_siege_idle@2x.png"), 8)[0]
    noise = rng.integers(-5, 6, size=(H // 2, W // 2, 1))
    base = np.zeros((H, W, 4), np.uint8)
    base[..., :3] = np.clip(np.array(PG.GROUND) + np.repeat(np.repeat(noise, 2, 0), 2, 1), 0, 255)
    base[..., 3] = 255
    items = [("sg_crash_gd", 1, (0, 0)), ("sg_ult_warn_gd", 1, C)]
    items_up = [("sg_ult_charge_up", 1, "op")]
    t_hit = 1 + T_AIR
    items += [("sg_ult_smash_gd", t_hit, C)]
    items_up += [("sg_ult_smash_up", t_hit, C), ("sg_ult_lion_up", t_hit, C)]
    t_fall = t_hit + 12          # ult/sg_lift 0.8 秒
    fall_items = []
    out = []
    for tk in range(n_ticks):
        # 她的位置
        if tk < 1:
            op = (0.0, 0.0, 0.0)
        elif tk < t_hit:
            k = (tk - 1) / T_AIR
            op = (C[0] * k, C[1] * k, math.sin(k * math.pi) * HAIR)
        else:
            op = (C[0], C[1], 0.0)
        # 冲击帧两拍
        if tk in (t_hit, t_hit + 1):
            white = tk == t_hit
            img = Image.new("RGB", (W, H), (235, 230, 220) if white else (5, 5, 8))
            d = ImageDraw.Draw(img)   # 剪影主体：同 ult_moves_c._sg_px_hf，14 道裂缝折线（游戏里平时看不见，冲击帧时显形）
            cx, cy = OX + C[0] * PX, OY + C[1] * PX
            hr = np.random.default_rng(3)
            for j in range(14):
                ang = math.tau * (j + hr.uniform() * 0.6) / 14
                p0 = (cx + math.cos(ang) * 20, cy + math.sin(ang) * 20)
                L = 540 * (0.45 + 0.45 * hr.uniform())
                for q in range(5):
                    a2 = ang + (hr.uniform() - 0.5) * 0.7
                    p1 = (p0[0] + math.cos(a2) * L / 5, p0[1] + math.sin(a2) * 0.72 * L / 5)
                    d.line([p0, p1], fill=(0, 0, 0) if white else (255, 255, 255), width=7 - q)
                    p0 = p1
            out.append(img)
            continue
        img = Image.fromarray(base.copy(), "RGBA")
        em = Image.new("RGB", (W, H), (0, 0, 0))
        ed = ImageDraw.Draw(em)
        for k, t0, gp in items + fall_items:
            if tk >= t0:
                paste_strip(img, lib, k, tk - t0, gp, ed)
        # 立起层 + 敌人 + 她：按脚底 y 排
        srt = []
        lift = 0.0
        if t_hit <= tk < t_fall:   # 震上半空：抛起 0.8 秒
            u = (tk - t_hit) / 12.0
            lift = 4 * 18 * u * (1 - u)
        for e in ens:
            srt.append((e[1], "e", e))
        srt.append((op[1], "op", op))
        for k, t0, gp in items_up:
            if tk >= t0:
                g = (op[0], op[1] - op[2]) if gp == "op" else gp
                srt.append(((op[1] if gp == "op" else gp[1]) + 1, "fx", (k, tk - t0, g)))
        srt.sort(key=lambda s: s[0])
        for _, kind, v in srt:
            if kind == "e":
                z = lift if v[2] else 0.0
                x, y = OX + v[0] * PX - ENEMY.width // 2, OY + (v[1] - z) * PX - ENEMY.height + 6
                img.alpha_composite(ENEMY, dest=(int(x), int(y)))
            elif kind == "op":
                x, y = OX + v[0] * PX - 32 * PX, OY + (v[1] - v[2]) * PX - 60 * PX
                img.alpha_composite(OP, dest=(int(round(x / 2) * 2), int(round(y / 2) * 2)))
            else:
                paste_strip(img, lib, v[0], v[1], v[2], ed)
        if tk == t_fall:   # 落地：前 8 只各一小圈尘
            for e in [e for e in ens if e[2]][:8]:
                fall_items.append(("sg_crash_gd", tk, (e[0], e[1])))
        glow = np.asarray(em.filter(ImageFilter.GaussianBlur(3))).astype(np.float32) * 0.45
        rgb = np.clip(np.asarray(img.convert("RGB")).astype(np.float32) + glow, 0, 255).astype(np.uint8)
        out.append(Image.fromarray(rgb, "RGB"))
    return out, (OX + C[0] * PX, OY + C[1] * PX)


def save_gif(frames, path):
    mos = Image.new("RGB", (frames[0].width, frames[0].height * min(len(frames), 12)))
    step = max(1, len(frames) // 12)
    for i, f in enumerate(frames[::step][:12]):
        mos.paste(f, (0, i * f.height))
    pal = mos.quantize(colors=255, method=Image.MAXCOVERAGE)
    q = [f.quantize(palette=pal, dither=Image.NONE) for f in frames]
    q[0].save(path, save_all=True, append_images=q[1:], duration=[70 if i % 3 != 1 else 60 for i in range(len(q))], loop=0, disposal=1)
    print(path, len(q), "帧", "%.1f MB" % (os.path.getsize(path) / 1048576))


def label(img, text, sz=22):
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(FONT, sz)
    d.rectangle((6, 6, 18 + d.textlength(text, font=f), 14 + sz + 8), fill=(0, 0, 0))
    d.text((12, 8), text, fill=(240, 230, 210), font=f)
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(PG.MAIN, "Claude outputs", "pxplane_siege_1105", "ult"))
    ap.add_argument("--orig", default="")
    ap.add_argument("--orig_from", type=float, default=0.0)
    ap.add_argument("--orig_secs", type=float, default=2.6)
    ap.add_argument("--orig_crop", default="")   # x,y,w,h（1280×720 录像里推进之王落点附近）
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    lib = Lib()
    N = 38
    frames, cc = scene(lib, N)
    phases = [(0, "起跳"), (1, "空中蓄力 · 落点预兆"), (10, "砸落 · 冲击帧"), (12, "裂地 · 四拍余震 · 狮吼"), (22, "浮空落地 · 收尾")]
    whole = []
    for i, f in enumerate(frames):
        ph = [p for t, p in phases if i >= t][-1]
        g = f.copy()
        label(g, "推进之王 终结技 Q · 新版（ult/px_plane）· %s · 1 倍 15 fps" % ph)
        whole.append(g.resize((g.width * 3 // 4, g.height * 3 // 4), Image.NEAREST))
    save_gif(whole, os.path.join(a.out, "siege_ult_new.gif"))
    if a.orig:   # 原版 vs 新版并排：原版取 GCP 录像的那一段（30 fps → 15 fps 抽帧），裁到落点附近、缩放到同一高度
        import imageio_ffmpeg
        ff = imageio_ffmpeg.get_ffmpeg_exe()
        tmp = os.path.join(ROOT, "build", "ult_orig_frames")
        os.makedirs(tmp, exist_ok=True)
        for f in os.listdir(tmp):
            os.remove(os.path.join(tmp, f))
        subprocess.run([ff, "-y", "-loglevel", "error", "-ss", str(a.orig_from), "-t", str(a.orig_secs), "-i", a.orig, "-vf", "fps=15", os.path.join(tmp, "o_%03d.png")], check=True)
        of = sorted(os.listdir(tmp))
        th = 520
        pair = []
        for i in range(min(len(of), N)):
            o = Image.open(os.path.join(tmp, of[i])).convert("RGB")
            if a.orig_crop:
                x, y, w, h = [int(v) for v in a.orig_crop.split(",")]
                o = o.crop((x, y, x + w, y + h))
            o = o.resize((int(o.width * th / o.height), th), Image.NEAREST)
            n = frames[min(i, len(frames) - 1)]
            n = n.resize((int(n.width * th / n.height), th), Image.NEAREST)
            sh = Image.new("RGB", (o.width + n.width + 6, th), (12, 12, 14))
            sh.paste(label(o, "原版（当前游戏）", 20), (0, 0))
            sh.paste(label(n.copy(), "新版（ult/px_plane = 1）", 20), (o.width + 6, 0))
            pair.append(sh)
        save_gif(pair, os.path.join(a.out, "siege_ult_before_after.gif"))


if __name__ == "__main__":
    main()
