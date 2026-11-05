#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""能天使终结技转平面（docs/262 §11，ult/px_plane）送审 GIF：只用 Python，不开 Godot。

摆法照 ult_moves 的能天使段：锁定范围 545、扫射 2.5 秒、24 发 / 秒两把枪交替（枪口 = 脚底 (∓30, −30)）、弹速 2600 / 秒、
精英每名 7 发、普通目标一发一个；第一次 0.2 秒内落地 5 个爆点（或 1 秒）时打冲击帧（白底黑剪影一拍 + 黑底白剪影一拍，原样保留）。
帧条读 pxplane_bake_exusiai.py 烤的 pxp_ex_ult_* / pxp_ex_mz_*（与游戏同一份），锁定框 / 范围环 / 连锁线 / 子弹用与游戏同算法的 Python 版。
起手 / 蓄力（ult.gd 的舞台压暗、超必杀暂停）只近似成整屏压暗，不是本稿改的部分。

  exusiai_ult_seq.gif      整段（1 倍，960×540 画面，15 fps 原速）：起手 → 蓄力 → 释放 → 冲击帧 → 收尾
  exusiai_ult_vs.gif       原终结技（GCP 实拍 mp4，--orig 给路径）与新版并排（各缩到 640 宽）

用法：python tools/pxplane_gif_exusiai_ult.py [--orig <原版 mp4>] [--orig_t0 秒]
"""
import argparse, math, os, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pxplane_exu_art as A
import pxplane_exu_ult_art as U
import pxplane_gif_exusiai as GF

ROOT = GF.ROOT
MAIN = GF.MAIN
W, H = 960, 540
OPP = (360, 330)          # 能天使脚底（画面坐标，世界像素）
MZ = [(-30, -30), (30, -30)]
R = 545.0
RATE = 24.0
BSPD = 2600.0 / 15.0      # 每拍
DUR = 2.5
PRE = 10                  # 起手 4 拍 + 蓄力 6 拍
FONT = GF.FONT


def snap(v):
    return (round(v[0] / 2) * 2, round(v[1] / 2) * 2)


def enemies():
    out = []
    pts = [(560, 300), (600, 360), (640, 280), (690, 330), (720, 390), (760, 300), (520, 400), (480, 230), (820, 360), (860, 280),
           (300, 450), (230, 380), (200, 280), (270, 220), (580, 200), (900, 430)]
    for i, p in enumerate(pts):
        out.append({"p": p, "elite": i in (3, 9), "r": 22 if i in (3, 9) else 12, "dead": 10 ** 9, "id": i})
    return out


class Sim:
    def __init__(self):
        self.es = enemies()
        el = sorted([e for e in self.es if e["elite"]], key=lambda e: math.dist(e["p"], OPP))
        no = sorted([e for e in self.es if not e["elite"]], key=lambda e: math.dist(e["p"], OPP))
        self.queue = []
        for e in el:
            self.queue += [e] * 7
        self.queue += no
        self.locks = [{"e": e, "out": None, "h": e["r"] + (26 if e["elite"] else 16)} for e in (el + no)[:24]]
        self.items = []     # 帧条 {k, t0, c, flip, gd, loop, until, burst}
        self.buls = []      # {p0, d, t0, t1, gun}
        self.lines = []
        self.rings = []     # (t0, r, grow)
        self.grains = []
        self.lights = []
        self.hf = None
        self.bt = []        # 爆点时刻
        self.fired = 0
        self.lastfire = -99

    def add(self, k, t, c, flip=False, gd=False, loop=False, until=None, burst=False):
        self.items.append({"k": k, "t0": t, "c": snap(c), "flip": flip, "gd": gd, "loop": loop, "until": until, "burst": burst})

    def run(self):
        t0 = PRE
        ct = OPP
        for k in range(2):
            mz = (ct[0] + MZ[k][0], ct[1] + MZ[k][1])
            self.add("ult_raise", t0, mz, flip=(k == 0))
            self.lights.append((mz[0], mz[1] + 30, 150, 0.9, t0, 3))
        self.add("ult_pillar", t0, ct)
        self.add("ult_halo", t0, (ct[0], ct[1] - 80), loop=True, until=t0 + int(DUR * 15) + 4)
        self.rings.append((t0, R, True))
        for i in range(1, 5):
            self.rings.append((t0 + int(i * 7.5), R, False))
        nshots = int(DUR * RATE)   # 60 发：目标打完后剩下的打锁定圈里的空地（游戏里 kind = ground，只有爆点）
        ground = [{"p": (OPP[0] + math.cos(i * 2.39996) * (160 + 37 * (i % 9)), OPP[1] + math.sin(i * 2.39996) * (110 + 23 * (i % 7)) * 0.72), "elite": False, "r": 12,
                   "dead": 10 ** 9, "id": 100 + i, "ground": True} for i in range(nshots)]
        for n in range(nshots):
            ts = t0 + n * 15.0 / RATE
            tk = int(ts)
            e = self.queue[n] if n < len(self.queue) else ground[n]
            gun = n % 2
            mz = (ct[0] + MZ[gun][0], ct[1] + MZ[gun][1])
            dest = (e["p"][0], e["p"][1] - 12)
            d = (dest[0] - mz[0], dest[1] - mz[1])
            L = math.hypot(*d)
            d = (d[0] / L, d[1] / L)
            dp, fl = GF.pick_dir(math.degrees(math.atan2(d[1], d[0])))
            for it in self.items:
                if it["k"].startswith("mz_") and it["until"] is None and it["c"] == snap(mz):
                    it["until"] = tk
            self.add("mz_g_e2_v%d_d%d" % (n % 2, dp), tk, mz, flip=fl)
            self.lastfire = tk
            arr = ts + L / BSPD
            self.buls.append({"p0": (mz[0] + d[0] * 16, mz[1] + d[1] * 16), "d": d, "t0": ts, "t1": arr, "gun": gun})
            ta = int(math.ceil(arr))
            self.bt.append(ta)
            self.add("ult_burst_v%d" % (n % 2), ta, (e["p"][0], e["p"][1] - 12), burst=True)
            self.add("ult_scorch_gd", ta, e["p"], gd=True)
            if n % 2 == 0:
                self.lights.append((e["p"][0], e["p"][1], 160, 0.8, ta, 2))
            for j in range(2 + n % 2):   # 碎屑（rock 4–6 px，往外溅、落地弹）
                a = j * 2.1 + n
                self.grains.append({"p": (e["p"][0], e["p"][1] - 12), "v": (math.cos(a) * 90, -150 - 40 * (j % 2)), "t0": ta, "gy": e["p"][1] + 2, "sz": 4 + 2 * ((n + j) % 2)})
            if not e["elite"] and not e.get("ground"):
                e["dead"] = min(e["dead"], ta + 2)
            for lk in self.locks:
                if lk["e"] is e and lk["out"] is None and (not e["elite"] or self.queue[n + 1:].count(e) == 0):
                    lk["out"] = ta
            if n % 4 == 1:   # 爆裂溅射的连锁闪线
                o2 = min((x for x in self.es if x is not e and not x["elite"]), key=lambda x: math.dist(x["p"], e["p"]))
                if math.dist(o2["p"], e["p"]) < 120:
                    self.lines.append({"a": (e["p"][0], e["p"][1] - 12), "b": (o2["p"][0], o2["p"][1] - 10), "t0": ta})
            if self.hf is None:
                recent = [b for b in self.bt if ta - 3 <= b <= ta]
                if len(recent) >= 5 or ta - t0 >= 15:
                    self.hf = ta
                    self.hf_at = (e["p"][0], e["p"][1] - 12)
        end = t0 + int(DUR * 15) + 2
        for lk in self.locks:
            if lk["out"] is None:
                lk["out"] = end
        self.end = end
        self.n_ticks = end + 10


def render(sim, lib, tk):
    img = Image.new("RGBA", (W, H), GF.GROUND + (255,))
    rng = np.random.default_rng(7)
    g = np.asarray(img).copy()
    noise_ = rng.integers(-5, 6, size=(H // 2, W // 2, 1))
    g[..., :3] = np.clip(g[..., :3].astype(int) + np.repeat(np.repeat(noise_, 2, 0), 2, 1), 0, 255)
    img = Image.fromarray(g.astype(np.uint8), "RGBA")
    emit = Image.new("RGB", (W, H), (0, 0, 0))
    ed = ImageDraw.Draw(emit)
    dr = ImageDraw.Draw(img)
    hf_phase = None
    if sim.hf is not None and sim.hf <= tk < sim.hf + 2:
        hf_phase = tk - sim.hf

    def px(x, y, c, glow=False, d=None):
        x, y = snap((x, y))
        (d or dr).rectangle([x, y, x + 1, y + 1], fill=c)
        if glow:
            ed.rectangle([x, y, x + 1, y + 1], fill=c[:3])

    def strip(it, sil=None):
        if tk < it["t0"] or (it["until"] is not None and tk >= it["until"]):
            return
        fi = (tk - it["t0"]) if not it["loop"] else tk
        r = lib.frame(it["k"], fi, it["loop"])
        if r is None:
            return
        fr, m = r
        if it["flip"]:
            fr = fr.transpose(Image.FLIP_LEFT_RIGHT)
        big = fr.resize((fr.width * 2, fr.height * 2), Image.NEAREST)
        if sil is not None:
            a = np.asarray(big)
            s2 = np.zeros_like(a)
            s2[..., :3] = sil
            s2[..., 3] = a[..., 3]
            big = Image.fromarray(s2, "RGBA")
        gx, gy = it["c"]
        left = gx - (m["w"] - m["ox"]) * 2 if it["flip"] else gx - m["ox"] * 2
        top = gy - m["oy"] * 2
        img.alpha_composite(big, dest=(max(0, int(left)), max(0, int(top))), source=(max(0, -int(left)), max(0, -int(top))))
        if sil is None:
            fi2 = fi % m["n"] if it["loop"] else fi
            for q in m["emit"][fi2]:
                x = q[0] if not it["flip"] else m["w"] - 1 - q[0]
                ed.rectangle([left + x * 2, top + q[1] * 2, left + x * 2 + 1, top + q[1] * 2 + 1], fill=tuple(int(q[2][i:i + 2], 16) for i in (0, 2, 4)))

    if hf_phase is not None:   # 冲击帧：白底黑剪影 → 黑底白剪影（主体 = 爆点帧条）
        bg = (235, 230, 220) if hf_phase == 0 else (5, 5, 8)
        fg = (0, 0, 0) if hf_phase == 0 else (255, 255, 255)
        img = Image.new("RGBA", (W, H), bg + (255,))
        dr = ImageDraw.Draw(img)
        for it in sim.items:
            if it["burst"] and it["t0"] <= tk < it["t0"] + 5:
                strip(it, fg)
        # 原样保留的那一下：原爆点帧条 fx_ult_exusiai_burst_front 放大 2.4 倍 + 半径 170 碎环（ult_moves 冲击帧那几行，不改）
        bf = Image.open(os.path.join(ROOT, "game", "art", "fx", "fx_ult_exusiai_burst_front@2x.png")).convert("RGBA")
        nfr = 6   # art.gd V6_FRAMES：6 帧
        fw = bf.width // nfr
        fr0 = bf.crop((fw * min(nfr - 1, 1 + hf_phase), 0, fw * min(nfr, 2 + hf_phase), bf.height))
        sc = 2.4 * 2 / 2.0   # 世界尺寸 = g.PX × sc / 高清倍率 2
        fr0 = fr0.resize((int(fr0.width * sc), int(fr0.height * sc)), Image.NEAREST)
        a2 = np.asarray(fr0)
        s2 = np.zeros_like(a2)
        s2[..., :3] = fg
        s2[..., 3] = (a2[..., 3] > 60) * 255
        sil = Image.fromarray(s2, "RGBA")
        cx, cy = sim.hf_at
        img.alpha_composite(sil, dest=(int(cx - sil.width / 2), int(cy - sil.height / 2)))
        dr.ellipse([cx - 170, cy - 170, cx + 170, cy + 170], outline=fg, width=10)
        return img.convert("RGB")

    for t0, r, grow in sim.rings:   # 贴地：范围环
        b = tk - t0
        if b < 0 or b > 3:
            continue
        rr = r * ([0.45, 0.8, 1.0, 1.0][min(b, 3)] if grow else 1.0)
        for (x, y, c) in U.ring_px(rr, b):
            px(OPP[0] + x, OPP[1] + y, A.hx(c))
    for it in sim.items:
        if it["gd"]:
            strip(it)
    sort = []
    for e in sim.es:
        if tk < e["dead"]:
            sort.append((e["p"][1], "e", e))
    sort.append((OPP[1], "op", None))
    for it in sim.items:
        if not it["gd"]:
            gy = it["c"][1] + (80 if it["k"] == "ult_halo" else (12 if it["burst"] else 30))
            sort.append((gy, "strip", it))
    sort.sort(key=lambda s: s[0])
    for _, kind, v in sort:
        if kind == "e":
            spr = GF.ENEMY if not v["elite"] else GF.ENEMY.resize((GF.ENEMY.width * 3 // 2, GF.ENEMY.height * 3 // 2), Image.NEAREST)
            img.alpha_composite(spr, dest=(int(v["p"][0] - spr.width // 2), int(v["p"][1] - spr.height + 6)))
        elif kind == "op":
            kick = -2 if 0 <= tk - sim.lastfire_at(tk) < 1 else 0
            img.alpha_composite(GF.OPS["exusiai"], dest=snap((OPP[0] - 64 + kick, OPP[1] - 120)))
        else:
            strip(v)
    for lk in sim.locks:   # 锁定框
        e = lk["e"]
        if tk < PRE:
            continue
        if lk["out"] is not None and tk >= lk["out"]:
            f = 6 + (tk - lk["out"]) * 2
            if f > 7:
                continue
        else:
            j = int((tk - PRE) / 15 * 24)
            f = j if j < 4 else 4 + (j - 4) % 2
        for (x, y, c) in U.reticle_px(lk["h"], f, e["elite"]):
            px(e["p"][0] + x, e["p"][1] - 12 + y, A.hx(c))
    for b in sim.buls:   # 子弹（肉鸽式光弹）
        if b["t0"] <= tk < b["t1"]:
            u = tk - b["t0"]
            p = (b["p0"][0] + b["d"][0] * BSPD * u, b["p0"][1] + b["d"][1] * BSPD * u)
            buf = A.bullet("n" if b["gun"] == 0 else "g", 2, b["d"], tk)
            hd = snap(p)
            for (x, y), c in buf.p.items():
                px(hd[0] + x * 2, hd[1] + y * 2, A.hx(c), glow=c == "#ffffff")
    for ln in sim.lines:
        f = tk - ln["t0"]
        if 0 <= f < 2:
            a, b2 = ln["a"], ln["b"]
            n = max(1, int(math.dist(a, b2) / 2))
            for i in range(n + 1):
                uu = i / n
                if f == 1 and uu < 0.5:
                    continue
                px(a[0] + (b2[0] - a[0]) * uu, a[1] + (b2[1] - a[1]) * uu, A.hx(A.RAMP["n"][5] if i % 2 == 0 else A.GOLD[5]))
    for gr in sim.grains:
        u = (tk - gr["t0"]) / 15.0
        if u < 0 or u > 0.9:
            continue
        x = gr["p"][0] + gr["v"][0] * u
        y = min(gr["gy"], gr["p"][1] + gr["v"][1] * u + 0.5 * 1100 * u * u)
        c = A.hx(A.RAMP["n"][3] if u < 0.15 else "#4a4448")
        x, y = snap((x, y))
        dr.rectangle([x, y, x + gr["sz"] - 1, y + gr["sz"] - 1], fill=c)
    # 光照近似：舞台压暗（起手 / 蓄力更暗）+ 照地光
    amb = 0.8
    if tk < 4:
        amb = 0.8 - 0.05 * tk
    elif tk < PRE:
        amb = 0.45
    glow = np.asarray(emit.filter(ImageFilter.GaussianBlur(3))).astype(np.float32) * 0.6
    base = np.asarray(img.convert("RGB")).astype(np.float32) * amb
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    lit = np.zeros((H, W), np.float32)
    for (lx, ly, lr, li, lt0, ln) in sim.lights:
        if lt0 <= tk < lt0 + ln:
            k = li * (1.0 - (tk - lt0) / (ln + 0.5))
            dd = np.sqrt((xx - lx) ** 2 + ((yy - ly) / 0.72) ** 2) / lr
            lit += k * np.clip(1.0 - dd, 0.0, 1.0) ** 2
    lc = np.array(GF.LIGHT_COL, np.float32)
    base = base * (1.0 + np.minimum(lit, 1.6)[..., None] * 1.3 * lc) + np.minimum(lit, 1.6)[..., None] * 40.0 * lc
    if 4 <= tk < PRE:   # 蓄力：几点金光往她身上收
        for i in range(10):
            a = i / 10 * math.tau + tk * 0.4
            rr = 120 * (1 - (tk - 4) / 6)
            x, y = snap((OPP[0] + math.cos(a) * rr, OPP[1] - 40 + math.sin(a) * rr * 0.6))
            base[y:y + 2, x:x + 2] = (255, 220, 120)
    return Image.fromarray(np.clip(base + glow, 0, 255).astype(np.uint8), "RGB")


def phase_name(sim, tk):
    if tk < 4:
        return "起手"
    if tk < PRE:
        return "蓄力"
    if sim.hf is not None and sim.hf <= tk < sim.hf + 2:
        return "冲击帧（原样保留）"
    if tk < sim.end:
        return "释放：扫射 + 爆裂弹"
    return "收尾"


def save_gif(frames, path):
    pal = frames[len(frames) // 2].quantize(colors=255, method=Image.MEDIANCUT)
    q = [f.quantize(palette=pal, dither=Image.NONE) for f in frames]
    dur = [70 if i % 3 != 1 else 60 for i in range(len(q))]
    q[0].save(path, save_all=True, append_images=q[1:], duration=dur, loop=0, optimize=False, disposal=1)
    print(path, len(q), "帧", "%.0f KB" % (os.path.getsize(path) / 1024))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "ult_px_exusiai_1105"))
    ap.add_argument("--orig", default="")
    ap.add_argument("--orig_t0", type=float, default=-1.0, help="原版 mp4 里终结技释放（举枪）那一刻的秒数")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    GF.ENEMY, GF.OPS = GF.load_sprites()
    lib = GF.Lib()
    sim = Sim()
    sim.run()
    fires = sorted(set(int(it["t0"]) for it in sim.items if it["k"].startswith("mz_")))
    sim.lastfire_at = lambda tk: max([f for f in fires if f <= tk], default=-99)
    font = ImageFont.truetype(FONT, 16)
    frames = []
    news = []
    for tk in range(sim.n_ticks):
        im = render(sim, lib, tk)
        news.append(im)
        sheet = Image.new("RGB", (W, H + 30), (14, 16, 18))
        sheet.paste(im, (0, 30))
        d = ImageDraw.Draw(sheet)
        d.text((8, 5), "能天使终结技 · 转平面（ult/px_plane = 1）· %s · 1 倍 · 15 fps 原速" % phase_name(sim, tk), fill=(235, 225, 200), font=font)
        frames.append(sheet)
    save_gif(frames, os.path.join(a.out, "exusiai_ult_seq.gif"))
    if a.orig and os.path.exists(a.orig):
        import imageio_ffmpeg, subprocess, tempfile
        ff = imageio_ffmpeg.get_ffmpeg_exe()
        td = tempfile.mkdtemp()
        t_start = max(0.0, a.orig_t0 - PRE / 15.0)
        subprocess.run([ff, "-loglevel", "error", "-y", "-ss", "%.3f" % t_start, "-i", a.orig, "-t", "%.3f" % (sim.n_ticks / 15.0 + 0.1), "-vf", "fps=15",
                        os.path.join(td, "o_%04d.png")], check=True)
        olds = sorted(os.listdir(td))
        vs = []
        for tk in range(sim.n_ticks):
            sheet = Image.new("RGB", (1284, 360 + 30), (14, 16, 18))
            d = ImageDraw.Draw(sheet)
            if tk < len(olds):
                o = Image.open(os.path.join(td, olds[tk])).convert("RGB")
                o = o.crop((0, 0, o.width, o.width * 9 // 16)).resize((640, 360), Image.NEAREST)
                sheet.paste(o, (0, 30))
            sheet.paste(news[tk].resize((640, 360), Image.NEAREST), (644, 30))
            d.text((8, 5), "原终结技（当前游戏，GCP 实拍）", fill=(235, 225, 200), font=font)
            d.text((652, 5), "新版（转平面）· %s" % phase_name(sim, tk), fill=(235, 225, 200), font=font)
            vs.append(sheet)
        save_gif(vs, os.path.join(a.out, "exusiai_ult_vs.gif"))


if __name__ == "__main__":
    main()
