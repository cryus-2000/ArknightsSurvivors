#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""星熊终结技「般若反震」转平面送审稿（docs/254 §8，ult/px_plane）：只用 Python、不开 Godot。画法读 tools/ult_px_hoshiguma_art.py。
时间轴照游戏（ult_moves_c._ho_start / _ho_step，玩法不动）：超必杀暂停 0.33 秒 → 起手慢放 0.53 秒（蓄力）→ 0 秒盾砸地（顿帧 0.1 秒）+ 吸怪
→ 0–1.5 秒挡住，每 0.3 秒一跳（裂纹长一截、盾前粒子云、盾阵闪），盾越挡越热（青绿 → 暖金）→ 最后 2 拍预备（光点吸进盾心 + 压暗）
→ 1.5 秒反震：冲击帧两拍（白底黑剪影 / 黑底白剪影）→ 慢放 0.3 倍 0.47 秒 + 0.15 秒缓回（只在这一下）；亮核 2 拍 + 照地灯打满 + 轻震
→ 六边形冲击环 3.5 拍推到判定边、地面一闪 → 粒子云往外喷 + 盾甲碎片 → 冲击环扫到的怪炸成自身颜色的像素（崩解）→ 裂网冷却。
输出（15 fps 原速）：ult_hoshiguma_1x.gif、ult_hoshiguma_x2.gif（中心 2 倍）、ult_hoshiguma_preview.mp4（配音效）、new_frames/。
用法：python tools/ult_px_hoshiguma_gif.py [--out 目录]
"""
import argparse, math, os, subprocess, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ult_px_hoshiguma_art as A

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
PX = 2
W, H = 1240, 860
C = (600, 440)
GROUND = (36, 46, 48)
FONT = "C:/Windows/Fonts/msyh.ttc"
R = 251.0            # 判定半径（美术像素）
PR = 219.0           # 吸怪半径
BOOM = A.HOLD
ECOL = [(0.45, 0.7, 1.0), (0.6, 0.9, 0.5), (0.7, 0.7, 0.75)]


def hx(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)


def snap(v):
    return (round(v[0] / 2) * 2, round(v[1] / 2) * 2)


def sprite(path, n, fi=0):
    im = Image.open(path).convert("RGBA")
    fw = im.width // n
    return im.crop((fi * fw, 0, (fi + 1) * fw, im.height))


# ---------------------------------------------------------------- 时间轴
SF, WU = 5, 8


def timeline():
    """[(阶段, 招式时间 t, 冲击帧拍 0/1/-1, 世界速度)]，每项 = 一拍（1/15 秒真实时间）"""
    out = [("sf", 0.0, -1, 0)] * SF + [("wu", (i + 1) / WU, -1, 0) for i in range(WU)]
    out += [("cast", 0.0, -1, 0)] * 2   # 盾砸地顿帧 0.1 秒
    t = 0.0
    while t < BOOM - 1e-6:
        out.append(("cast", t, -1, 1))
        t += 1 / 15
    t = BOOM
    out += [("cast", t, 0, 0), ("cast", t, 1, 0)]   # 冲击帧两拍
    for i in range(7):   # 慢放 0.3 倍 0.47 秒
        t += 0.3 / 15
        out.append(("cast", t, -1, 0.3))
    for i in range(2):   # 0.15 秒缓回
        sp = 0.3 + 0.7 * (i + 1) / 2
        t += sp / 15
        out.append(("cast", t, -1, sp))
    while t < BOOM + 2.1:
        t += 1 / 15
        out.append(("cast", t, -1, 1))
    return out


# ---------------------------------------------------------------- 场景（世界坐标）
def enemies():
    out = []
    for i in range(30):
        a = i * 2.39996 + 0.5
        r = (70 + 520 * ((i * 0.618) % 1.0))
        out.append({"p0": (C[0] + math.cos(a) * r, C[1] + math.sin(a) * r * 0.62), "col": ECOL[i % 3], "i": i})
    for e in out:
        dx, dy = e["p0"][0] - C[0], (e["p0"][1] - C[1]) / A.SQ
        d = math.hypot(dx, dy) / PX
        e["d0"] = d
        if d < PR and d > 50:   # 吸到盾前约 50 美术像素（100 世界）
            k = 50.0 / d
            e["p1"] = (C[0] + dx * k, C[1] + dy * k * A.SQ)
        else:
            e["p1"] = e["p0"]
        e["d1"] = math.hypot(e["p1"][0] - C[0], (e["p1"][1] - C[1]) / A.SQ) / PX
        e["ang"] = math.atan2(e["p1"][1] - C[1], e["p1"][0] - C[0])
        e["boom"] = A.shock_at(R, e["d1"]) if e["d1"] <= R else None
    return out


ENS = enemies()


def epos(e, t):
    if t < 0:
        return e["p0"]
    k = min(1.0, t / 0.25)
    k = 1 - (1 - k) ** 2
    return (e["p0"][0] + (e["p1"][0] - e["p0"][0]) * k, e["p0"][1] + (e["p1"][1] - e["p0"][1]) * k)


# ---------------------------------------------------------------- 绘制
def render(tk, ph, t, hfk):
    img = Image.new("RGBA", (W, H), GROUND + (255,))
    rng = np.random.default_rng(7)
    g = np.asarray(img).copy()
    nz = rng.integers(-5, 6, size=(H // 2, W // 2, 1))
    g[..., :3] = np.clip(g[..., :3].astype(int) + np.repeat(np.repeat(nz, 2, 0), 2, 1), 0, 255)
    img = Image.fromarray(g.astype(np.uint8), "RGBA")
    emit = Image.new("RGB", (W, H), (0, 0, 0))
    ed = ImageDraw.Draw(emit)
    dr = ImageDraw.Draw(img)

    def put(x, y, c, glow=False, a=1.0, sz=1):
        x, y = snap((x, y))
        if not (0 <= x < W - 4 and 0 <= y < H - 4):
            return
        cc = hx(c) if isinstance(c, str) else tuple(int(v * 255) for v in c[:3]) + (255,)
        if isinstance(c, tuple) and len(c) == 4:
            a = c[3]
        if a < 1.0:
            base = img.getpixel((x, y))
            cc = tuple(int(base[i] * (1 - a) + cc[i] * a) for i in range(3)) + (255,)
        dr.rectangle([x, y, x + PX * sz - 1, y + PX * sz - 1], fill=cc)
        if glow:
            ed.rectangle([x, y, x + PX * sz - 1, y + PX * sz - 1], fill=cc[:3])

    def pts(o, lst):
        for q in lst:
            sz = int(q[4]) if len(q) > 4 else 1
            if isinstance(q[3], bool):
                put(o[0] + q[0] * PX, o[1] + q[1] * PX, q[2], glow=q[3], sz=sz)
            else:
                put(o[0] + q[0] * PX, o[1] + q[1] * PX, q[2], a=q[3], sz=sz)

    if hfk >= 0:   # 冲击帧：整屏底 + 剪影（盾、盾阵两圈六边形、裂网）——中村丰式两拍，保留
        bg = (235, 230, 220) if hfk == 0 else (5, 5, 8)
        fg = "#000000" if hfk == 0 else "#ffffff"
        im2 = Image.new("RGB", (W, H), bg)
        d2 = ImageDraw.Draw(im2)
        lst = A.shield_rim(BOOM, 1.0) + A.hex_pts(55, 0.0, 3, fg) + A.hex_pts(35, math.pi / 6, 2, fg) + A.cracks(BOOM - 0.01)
        for q in lst:
            x, y = snap((C[0] + q[0] * PX, C[1] + q[1] * PX))
            d2.rectangle([x, y, x + 1, y + 1], fill=fg)
        return im2

    ct = t if ph == "cast" else -1.0
    lights = []
    # ---- 地面层：裂网、盾阵
    if ct >= 0:
        pts(C, A.cracks(ct, BOOM))
        if ct < BOOM:
            k = A.heat(ct)
            tk_age = (ct % A.TICK) if ct >= A.TICK else 9.0
            flash = tk_age < 2 / 15
            c1 = A.JD[6] if k < 0.4 else A.AM[4]
            c2 = A.JD[5] if k < 0.4 else A.AM[3]
            pts(C, A.hex_pts(55, 0.0, 3 if flash else 2, [c1, c2, A.JD[2]], 1.0))
            pts(C, A.hex_pts(35, math.pi / 6, 2, [A.JD[6] if not flash else "#ffffff", A.JD[4]], 0.9))
            if ct < 0.25:   # 砸地那一下：盾下小冲击环
                pts((C[0] + A.SH[0] * PX, C[1]), A.hex_pts(20 + 120 * ct, 0.0, 2, [A.JD[7], A.JD[5]], 1 - ct / 0.25))
    # 怪物影子 + 本体
    alive = []
    for e in ENS:
        p = epos(e, ct)
        if ct >= BOOM and e["boom"] is not None and ct - BOOM >= e["boom"]:
            continue
        alive.append(p)
        dr.ellipse([p[0] - 10, p[1] + 1, p[0] + 10, p[1] + 7], fill=(18, 22, 24, 255))
    for p in sorted(alive, key=lambda q: q[1]):
        img.alpha_composite(ENEMY, dest=(int(p[0] - ENEMY.width // 2), int(p[1] - ENEMY.height + 6)))
    img.alpha_composite(HER, dest=snap((C[0] - 64, C[1] - 120)))
    dr = ImageDraw.Draw(img)
    # ---- 上层
    if ph == "wu":
        pts(C, A.windup(t, tk))
    if ct >= 0:
        for e in ENS:   # 吸怪残影
            dx = (e["p1"][0] - e["p0"][0]) / PX
            dy = (e["p1"][1] - e["p0"][1]) / PX
            if abs(dx) + abs(dy) > 4:
                pts(epos(e, ct), A.pull_streak(dx, dy, ct, e["col"]))
        if ct < BOOM:
            pts(C, A.shield_rim(ct))
            for i in range(1, 6):
                if ct >= i * A.TICK - 0.01:
                    pts(C, A.tick_cloud(ct - i * A.TICK, 30 + i, A.heat(ct)))
            pts(C, A.prep(BOOM - ct))
            k = A.heat(ct)
            lights.append((C[0] + A.SH[0] * PX, C[1] - 30, 120 + 60 * k, 0.35 + 0.35 * k, (0.6 + 0.6 * k, 1.0, 0.85 - 0.3 * k)))
            if ct < 0.12:
                lights.append((C[0] + A.SH[0] * PX, C[1], 200, 0.7, (0.55, 1.0, 0.85)))
            if BOOM - ct < A.PREP_T:   # 预备：压暗
                kd = 1 - (BOOM - ct) / A.PREP_T
                ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
                ImageDraw.Draw(ov).ellipse([C[0] - R * PX * 1.05, C[1] - R * PX * 1.05 * A.SQ, C[0] + R * PX * 1.05, C[1] + R * PX * 1.05 * A.SQ], fill=(0, 0, 5, int(255 * 0.28 * kd)))
                img.alpha_composite(ov)
                dr = ImageDraw.Draw(img)
        else:
            tau = ct - BOOM
            bf = int(math.floor(tau * 15 / 0.3)) if tau < 7 * 0.3 / 15 else 99   # 亮核按真实拍数（慢放里也只亮 2 拍真实时间 → 用慢放后的拍）
            bf = 0 if tau < 0.3 / 15 * 1.01 else 1 if tau < 0.6 / 15 * 1.01 else 99
            sc = (C[0] + A.SH[0] * PX, C[1] - 16 * PX // 2)
            for rx, col in A.core(bf):
                dr.ellipse([sc[0] - rx * PX, sc[1] - rx * PX * A.SQ, sc[0] + rx * PX, sc[1] + rx * PX * A.SQ], fill=hx(col))
                ed.ellipse([sc[0] - rx * PX * 0.5, sc[1] - rx * PX * 0.5 * A.SQ, sc[0] + rx * PX * 0.5, sc[1] + rx * PX * 0.5 * A.SQ], fill=hx(col)[:3])
            if tau < 0.6 / 15 * 1.01:
                lights.append((sc[0], C[1], 480, 0.9, (1.0, 0.95, 0.75)))
            elif tau < 0.5:
                lights.append((sc[0], C[1], 480, 0.9 * (1 - tau / 0.5), (0.6, 1.0, 0.85)))
            pts(C, A.shock_hex(R, tau))
            pts((C[0] + A.SH[0] * PX, C[1] - 16), A.cloud(tau, 777, R * 0.75, 240))
            pts(C, A.shards(tau))
            for e in ENS:   # 崩解：冲击环扫到的那一拍，怪物炸成自身颜色的像素往外喷
                if e["boom"] is None:
                    continue
                age = tau - e["boom"]
                p = epos(e, 1.0)
                for q in A.spray(age, e["i"] * 7 + 3, e["ang"], 1.0 + 0.6 * (1 - e["d1"] / R), e["col"]):
                    put(p[0] + q[0] * PX, p[1] - 12 + q[1] * PX, q[2], glow=q[3], sz=q[4])
    # ---- 光照
    glow = np.asarray(emit.filter(ImageFilter.GaussianBlur(3))).astype(np.float32) * 0.55
    amb = 0.8
    base = np.asarray(img.convert("RGB")).astype(np.float32) * amb
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    lit = np.zeros((H, W, 3), np.float32)
    for (lx, ly, lr, li, lc) in lights:
        dd = np.sqrt((xx - lx) ** 2 + ((yy - ly) / 0.72) ** 2) / lr
        lit += (li * np.clip(1.0 - dd, 0.0, 1.0) ** 2)[..., None] * np.array(lc, np.float32)
    base = base * (1.0 + lit * 1.3) + lit * 40.0
    out = np.clip(base + glow, 0, 255)
    if ph == "sf":
        k = np.full((H, W, 1), 0.35, np.float32)
        y0, x0 = int(C[1] - 120), int(C[0] - 64)
        k[max(0, y0):y0 + 128, max(0, x0):x0 + 128] = 1.0
        out = out * k
    if ph == "wu":
        out = out * 0.75
    im = Image.fromarray(out.astype(np.uint8), "RGB")
    if ph == "cast" and BOOM <= ct < BOOM + 0.12:   # 轻震 3px / 0.12 秒（真实时间）
        s = 3 if int(tk) % 2 == 0 else -3
        im = im.transform(im.size, Image.AFFINE, (1, 0, s, 0, 1, -s // 2), fillcolor=GROUND)
    return im


# ---------------------------------------------------------------- 音效（docs/254 §8.3 清单；按真实时间铺）
SFX_DIR = os.path.join(ROOT, "game", "audio", "sfx")
NEW_DIR = os.path.join(MAIN, "build", "ult_sfx", "hoshiguma_1105")


def cues(tl):
    """[(真实秒, 文件, 音量 dB)]"""
    out = [(0.0, os.path.join(SFX_DIR, "ult_hoshiguma_sf.wav"), -5.0), (SF / 15, os.path.join(SFX_DIR, "ult_hoshiguma_charge.wav"), -10.0)]
    t0 = (SF + WU) / 15
    out += [(t0, os.path.join(SFX_DIR, "ult_hoshiguma_cast.wav"), -4.0), (t0 + 0.02, os.path.join(SFX_DIR, "ult_hoshiguma_pull.wav"), -4.0),
            (t0 + 0.13, os.path.join(SFX_DIR, "ult_hoshiguma_block.wav"), -3.0)]
    real = {}
    for i, (ph, t, hfk, sp) in enumerate(tl):
        if ph == "cast":
            real.setdefault(round(t, 4), i / 15)
    def at(tt):
        for i, (ph, t, hfk, sp) in enumerate(tl):
            if ph == "cast" and t >= tt - 1e-6:
                return i / 15
        return len(tl) / 15
    for i in range(1, 6):
        out.append((at(i * A.TICK), os.path.join(SFX_DIR, "ult_hoshiguma_crack_%d.wav" % i), -3.0))
    hf0 = next(i for i, q in enumerate(tl) if q[2] == 0) / 15
    out.append((hf0, os.path.join(NEW_DIR, "ult_hoshiguma_boom.wav"), 0.0))
    out.append((hf0 + 1.05, os.path.join(NEW_DIR, "ult_hoshiguma_settle.wav"), -2.0))
    return out


def mix(tl, path):
    import soundfile as sf
    SR = 44100
    n = int((len(tl) / 15 + 2.5) * SR)
    buf = np.zeros(n)
    for (t, f, db) in cues(tl):
        x, sr = sf.read(f, always_2d=True)
        x = x.mean(1)
        i0 = int(t * SR)
        m = min(len(x), n - i0)
        buf[i0:i0 + m] += x[:m] * 10 ** (db / 20)
    pk = np.abs(buf).max()
    if pk > 0.98:
        buf = np.tanh(buf / pk * 1.2) * 0.95
    sf.write(path, buf, SR)


def main():
    global ENEMY, HER
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "ult_px_hoshiguma_1105"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    fdir = os.path.join(a.out, "new_frames")
    os.makedirs(fdir, exist_ok=True)
    en = sprite(os.path.join(ROOT, "game", "art", "enemies", "offspring", "e_offspring@2x.png"), 4)
    arr = np.asarray(en).astype(np.float32)
    arr[..., :3] = arr[..., :3] * 0.32 + np.array([10, 12, 14])
    ENEMY = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    HER = sprite(os.path.join(ROOT, "game", "art", "operators", "hoshiguma", "op_hoshiguma_idle@2x.png"), 7)
    font = ImageFont.truetype(FONT, 18)
    tl = timeline()
    names = {"sf": "起手（超必杀暂停，共用演出）", "wu": "蓄力（起手慢放）", "cast": "释放"}
    big, small = [], []
    for tk, (ph, t, hfk, sp) in enumerate(tl):
        im = render(tk, ph, t, hfk)
        lab = names[ph]
        if ph == "cast":
            lab = ("盾砸地 + 吸怪" if t < 0.3 else "挡住（每 0.3 秒裂一圈，越挡越热）" if t < BOOM - A.PREP_T else "预备（吸进盾心、压暗）" if t < BOOM else
                   ("冲击帧（保留）" if hfk >= 0 else ("反震 · 慢放 ×%.2f" % sp if sp < 1 else "反震 → 崩解 → 冷却")))
        im.save(os.path.join(fdir, "f%03d.png" % tk))
        sheet = im.copy()
        d = ImageDraw.Draw(sheet)
        d.text((10, 8), "星熊「般若反震」· 转平面版 · 1 倍 · 15 fps 原速 · " + lab, fill=(235, 225, 200) if hfk != 0 else (20, 20, 20), font=font)
        big.append(sheet)
        cx, cy = C
        small.append(im.crop((cx - 300, cy - 210, cx + 300, cy + 210)).resize((1200, 840), Image.NEAREST))
    for frames, nm in ((big, "ult_hoshiguma_1x.gif"), (small, "ult_hoshiguma_x2.gif")):
        pick = frames[:: max(1, len(frames) // 12)][:12]
        mos = Image.new("RGB", (frames[0].width, frames[0].height * len(pick)))
        for i, fr in enumerate(pick):
            mos.paste(fr, (0, i * frames[0].height))
        pal = mos.quantize(colors=255, method=Image.MEDIANCUT)
        q = [f.quantize(palette=pal, dither=Image.NONE) for f in frames]
        dur = [70 if i % 3 != 1 else 60 for i in range(len(q))]
        q[0].save(os.path.join(a.out, nm), save_all=True, append_images=q[1:], duration=dur, loop=0, optimize=False, disposal=1)
        print(nm, len(q), "帧", "%.0f KB" % (os.path.getsize(os.path.join(a.out, nm)) / 1024))
    # 配音效的预览 mp4（GIF 不带声音）
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    wav = os.path.join(a.out, "ult_hoshiguma_sfx_mix.wav")
    mix(tl, wav)
    sd = os.path.join(a.out, "_sheets")
    os.makedirs(sd, exist_ok=True)
    for i, im in enumerate(big):
        im.save(os.path.join(sd, "s%03d.png" % i))
    mp4 = os.path.join(a.out, "ult_hoshiguma_preview.mp4")
    subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", "15", "-i", os.path.join(sd, "s%03d.png"), "-i", wav, "-c:v", "libx264", "-crf", "20", "-pix_fmt", "yuv420p",
                    "-r", "30", "-c:a", "aac", "-b:a", "160k", "-shortest", mp4], check=True)
    print("预览", mp4)
    for c in cues(tl):
        print("音效 %.2f s  %-32s %+.0f dB" % (c[0], os.path.basename(c[1]), c[2]))


if __name__ == "__main__":
    main()
