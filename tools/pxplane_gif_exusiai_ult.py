#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""能天使终结技转平面（docs/262 §11，ult/px_plane；口径 Claude outputs/pxplane_briefs/ult_brief.md）送审稿：只用 Python，不开 Godot。

摆法照 ult_moves 的能天使段：锁定范围 545、扫射 2.5 秒、24 发 / 秒两把枪交替（枪口 = 脚底 (∓30, −30)）、弹速 2600 / 秒、精英每名 7 发、
普通目标一发一个、打完的发数打圈里空地；第一次 0.2 秒内落地 5 个爆点（或 1 秒）的那一发 = 整招最大的一下爆炸。
时间：之前 1 帧 = 1 拍；最大爆炸那一拍起共用的冲击（ult.impact）：冲击帧两拍（白底黑剪影 / 黑底白剪影，原样保留）+ 定格到 0.25 秒，
然后 0.45 秒 0.25 倍慢放、0.35 秒缓回（游戏里现有的 ult/imp_slow_t、imp_ease；brief 要的回速 0.15 秒与共用值不同，见 docs/262 §11）。
画面：帧条读 pxplane_bake_exusiai.py 烤的 pxp_ex_*（同游戏），粒子云 / 亮核 / 冲击环 / 喷散 / 锁定框 / 范围环 / 子弹用与 GDScript 同算法的 Python 版。
崩解：被打中的怪在最大爆炸冲击环推到它那一刻，按怪物贴图像素碎开（近似引擎 kill_burst）+ 本色像素喷散（ecol 四阶 + 白芯）。

  exusiai_ult_seq.gif   整段 1 倍（960×540，15 fps 原速）
  exusiai_ult_seq.mp4   同一段配音效（build/ult_sfx_exu_px 的候选 + 原 pop / sf）
  exusiai_ult_vs.gif    原终结技（GCP 实拍）与新版并排
用法：python tools/pxplane_gif_exusiai_ult.py [--orig <原版 mp4>] [--orig_t0 <原版放出那一刻秒数>]
"""
import argparse, json, math, os, subprocess, sys, tempfile, wave

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pxplane_exu_art as A
import pxplane_exu_ult_art as U
import pxplane_gif_exusiai as GF

ROOT = GF.ROOT
MAIN = GF.MAIN
W, H = 960, 540
OPP = (360, 330)
MZ = [(-30, -30), (30, -30)]
R = 545.0
RATE = 24.0
BSPD = 2600.0 / 15.0
DUR = 2.5
PRE = 10                   # 起手（超必杀暂停 + 切入）4 拍 + 蓄力 6 拍（共用演出，这里只近似压暗）
RB = 170.0                 # 最大爆炸的判定边缘（原冲击帧碎环半径）
FRZ, SLOW, EASE, LO = 0.25, 0.45, 0.35, 0.25
FONT = GF.FONT
SFXD = os.path.join(ROOT, "game", "audio", "sfx")
CAND = os.path.join(MAIN, "build", "ult_sfx_exu_px")


def snap(v):
    return (round(v[0] / 2) * 2, round(v[1] / 2) * 2)


def enemies():
    pts = [(560, 300), (600, 360), (640, 280), (690, 330), (720, 390), (760, 300), (520, 400), (480, 230), (820, 360), (860, 280),
           (300, 450), (230, 380), (200, 280), (270, 220), (580, 200), (900, 430), (650, 440), (540, 250), (780, 240), (700, 260)]
    return [{"p": p, "elite": i in (3, 9), "r": 22 if i in (3, 9) else 12, "dead": 10 ** 9, "id": i, "hit": None} for i, p in enumerate(pts)]


def ecol_ramp():
    try:
        d = json.load(open(os.path.join(ROOT, "game", "data", "enemies.json"), encoding="utf-8"))
        c = d.get("offspring", {}).get("ecol")
        if isinstance(c, list):
            r, g, b = [int(255 * x) for x in c[:3]]
        else:
            raise KeyError
    except Exception:
        r, g, b = 150, 200, 210
    lt = lambda k: "#%02x%02x%02x" % tuple(min(255, int(x + (255 - x) * k)) for x in (r, g, b))
    dk = "#%02x%02x%02x" % (int(r * 0.7), int(g * 0.7), int(b * 0.7))
    return [lt(0.45), lt(0.15), "#%02x%02x%02x" % (r, g, b), dk]


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
        self.items, self.buls, self.lines, self.rings, self.grains, self.lights, self.clouds = [], [], [], [], [], [], []
        self.hf = None
        self.bt = []
        self.fires = []
        self.sfx = []    # (游戏拍, 文件, dB)

    def add(self, k, t, c, flip=False, gd=False, loop=False, until=None, burst=False):
        self.items.append({"k": k, "t0": t, "c": snap(c), "flip": flip, "gd": gd, "loop": loop, "until": until, "burst": burst})

    def run(self):
        t0 = PRE
        ct = OPP
        self.sfx += [(0.0, os.path.join(SFXD, "ult_exusiai_sf.wav"), -5), (4.0, os.path.join(CAND, "ult_exusiai_charge.wav"), -10),
                     (t0, os.path.join(CAND, "ult_exusiai_cast.wav"), -4)]
        for k in range(2):
            mz = (ct[0] + MZ[k][0], ct[1] + MZ[k][1])
            self.add("ult_raise", t0, mz, flip=(k == 0))
            self.lights.append((mz[0], mz[1] + 30, 150, 0.9, t0, 3))
        self.add("ult_pillar", t0, ct)
        self.add("ult_halo", t0, (ct[0], ct[1] - 80), loop=True, until=t0 + int(DUR * 15) + 4)
        self.rings.append((t0, R, True))
        for i in range(1, 5):
            self.rings.append((t0 + i * 7.5, R, False))
        nshots = int(DUR * RATE)
        ground = [{"p": (OPP[0] + math.cos(i * 2.39996) * (160 + 37 * (i % 9)), OPP[1] + math.sin(i * 2.39996) * (110 + 23 * (i % 7)) * 0.72), "elite": False, "r": 12,
                   "dead": 10 ** 9, "id": 100 + i, "ground": True, "hit": None} for i in range(nshots)]
        last_pop = -9.0
        for n in range(nshots):
            ts = t0 + n * 15.0 / RATE
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
                    it["until"] = ts
            self.add("mz_g_e2_v%d_d%d" % (n % 2, dp), ts, mz, flip=fl)
            self.fires.append(ts)
            arr = ts + L / BSPD
            self.buls.append({"p0": (mz[0] + d[0] * 16, mz[1] + d[1] * 16), "d": d, "t0": ts, "t1": arr, "gun": gun})
            self.bt.append(arr)
            big = False
            if self.hf is None:
                recent = [b for b in self.bt if arr - 0.2 * 15 <= b <= arr]
                if len(recent) >= 5 or arr - t0 >= 15:
                    big = True
                    self.hf = arr
                    self.hf_at = dest
                    self.sfx.append((arr, os.path.join(CAND, "ult_exusiai_blast.wav"), 0))
            if not big:   # 路上的爆：两拍硬星芯 + 闪烁粒子云 + 焦痕 + 2–3 颗碎屑
                self.add("ult_burst_v%d" % (n % 2), arr, dest, burst=True)
                self.add("ult_scorch_gd", arr, e["p"], gd=True)
                self.clouds.append({"c": dest, "t0": arr, "sd": n * 7 + 3, "size": 30, "n": 40})
                if n % 2 == 0:
                    self.lights.append((e["p"][0], e["p"][1], 160, 0.6, arr, 2))
                for j in range(2 + n % 2):
                    a = j * 2.1 + n
                    self.grains.append({"p": dest, "v": (math.cos(a) * 90, -150 - 40 * (j % 2)), "t0": arr, "gy": e["p"][1] + 2, "sz": 4 + 2 * ((n + j) % 2)})
                if arr - last_pop >= 0.06 * 15:
                    self.sfx.append((arr, os.path.join(SFXD, "ult_exusiai_pop_%d.wav" % (1 + n % 3)), -6))
                    last_pop = arr
            if not e.get("ground"):
                if e["hit"] is None:
                    e["hit"] = arr
                if not e["elite"]:
                    e["dead"] = min(e["dead"], arr + 2)
            for lk in self.locks:
                if lk["e"] is e and lk["out"] is None and (not e["elite"] or self.queue[n + 1:].count(e) == 0):
                    lk["out"] = arr
            if n % 4 == 1:
                o2 = min((x for x in self.es if x is not e and not x["elite"]), key=lambda x: math.dist(x["p"], e["p"]))
                if math.dist(o2["p"], e["p"]) < 120:
                    self.lines.append({"a": dest, "b": (o2["p"][0], o2["p"][1] - 10), "t0": arr})
        end = t0 + DUR * 15 + 2
        for lk in self.locks:
            if lk["out"] is None:
                lk["out"] = end
        self.end = end
        self.sfx.append((end, os.path.join(CAND, "ult_exusiai_end.wav"), -6))
        # 崩解：最大爆炸时被打中过的怪（含已倒下的）各碎一次，时刻 = 冲击环推到它那一刻（圈外的怪在冲击环到边时）
        F = self.hf
        self.shat = []
        for e in self.es:
            if e["hit"] is not None and e["hit"] <= F + 6:
                dd = math.dist(e["p"], self.hf_at)
                u = min(1.0, max(0.0, (dd - RB * 0.16) / (RB * 0.84)))
                ta = F + 0.5 + 3.5 * (1 - math.sqrt(1 - u))   # 冲击环 r(t) 的反函数（先快后慢）
                out = ((e["p"][0] - self.hf_at[0]) / max(1, dd), (e["p"][1] - self.hf_at[1]) / max(1, dd))
                self.shat.append({"e": e, "t": ta, "out": out})
                e["dead"] = min(e["dead"], ta)
        self.n_game = end + 10

    # 真实帧 → 游戏拍：冲击前 1:1；冲击那一拍起定格 FRZ 秒，再 LO 倍慢放 SLOW 秒，再 EASE 秒按 k² 缓回
    def frames(self):
        out = []
        g = 0.0
        F = self.hf
        rt = 0.0
        while g < self.n_game:
            out.append(g)
            if g < F:
                g = min(F, g + 1.0) if g + 1.0 > F and g < F else g + 1.0
                if abs(g - F) < 1e-6:
                    rt = 0.0
                continue
            rt += 1.0 / 15.0
            if rt < FRZ:
                sp = 0.0
            elif rt < FRZ + SLOW:
                sp = LO
            elif rt < FRZ + SLOW + EASE:
                k = (rt - FRZ - SLOW) / EASE
                sp = LO + (1 - LO) * k * k
            else:
                sp = 1.0
            g += sp
        return out


def render(sim, lib, tg, rt_since_hf):
    img = Image.new("RGBA", (W, H), GF.GROUND + (255,))
    rng = np.random.default_rng(7)
    a0 = np.asarray(img).copy()
    noise_ = rng.integers(-5, 6, size=(H // 2, W // 2, 1))
    a0[..., :3] = np.clip(a0[..., :3].astype(int) + np.repeat(np.repeat(noise_, 2, 0), 2, 1), 0, 255)
    img = Image.fromarray(a0.astype(np.uint8), "RGBA")
    emit = Image.new("RGB", (W, H), (0, 0, 0))
    ed = ImageDraw.Draw(emit)
    dr = ImageDraw.Draw(img)
    F = sim.hf
    hc = sim.hf_at
    tb = tg - F   # 最大爆炸后的拍数

    def px(x, y, c, glow=False, sz=1, d=None):
        x, y = snap((x, y))
        (d or dr).rectangle([x, y, x + 2 * sz - 1, y + 2 * sz - 1], fill=c)
        if glow:
            ed.rectangle([x, y, x + 2 * sz - 1, y + 2 * sz - 1], fill=c[:3])

    def strip(it, sil=None):
        if tg < it["t0"] or (it["until"] is not None and tg >= it["until"]):
            return
        fi = int(tg - it["t0"]) if not it["loop"] else int(tg)
        r = lib.frame(it["k"], fi, it["loop"])
        if r is None:
            return
        fr, m = r
        if it["flip"]:
            fr = fr.transpose(Image.FLIP_LEFT_RIGHT)
        big = fr.resize((fr.width * 2, fr.height * 2), Image.NEAREST)
        if sil is not None:
            arr = np.asarray(big)
            s2 = np.zeros_like(arr)
            s2[..., :3] = sil
            s2[..., 3] = arr[..., 3]
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

    # 冲击帧（原样保留）：前两帧真实时间
    if 0 <= rt_since_hf < 2:
        ph = rt_since_hf
        bg = (235, 230, 220) if ph == 0 else (5, 5, 8)
        fg = (0, 0, 0) if ph == 0 else (255, 255, 255)
        img = Image.new("RGBA", (W, H), bg + (255,))
        dr = ImageDraw.Draw(img)
        bf = Image.open(os.path.join(ROOT, "game", "art", "fx", "fx_ult_exusiai_burst_front@2x.png")).convert("RGBA")
        fw = bf.width // 6
        fr0 = bf.crop((fw * (1 + ph), 0, fw * (2 + ph), bf.height)).resize((int(fw * 2.4), int(bf.height * 2.4)), Image.NEAREST)
        arr = np.asarray(fr0)
        s2 = np.zeros_like(arr)
        s2[..., :3] = fg
        s2[..., 3] = (arr[..., 3] > 60) * 255
        sil = Image.fromarray(s2, "RGBA")
        img.alpha_composite(sil, dest=(int(hc[0] - sil.width / 2), int(hc[1] - sil.height / 2)))
        dr.ellipse([hc[0] - 170, hc[1] - 170, hc[0] + 170, hc[1] + 170], outline=fg, width=10)
        for it in sim.items:
            if it["burst"] and it["t0"] <= tg < it["t0"] + 2:
                strip(it, fg)
        return img.convert("RGB"), 0

    # 贴地：范围环、最大爆炸冲击环与环后地面一闪、焦痕
    for t0, r, grow in sim.rings:
        b = int(tg - t0)
        if b < 0 or b > 3:
            continue
        rr = r * ([0.45, 0.8, 1.0, 1.0][b] if grow else 1.0)
        for (x, y, c) in U.ring_px(rr, b):
            px(OPP[0] + x, OPP[1] + y, A.hx(c))
    for (x, y, c, al) in U.blast_ring(RB * 0.16 / 2, RB / 2, tb - 0.5):
        if al <= 0.02:
            continue
        cc = A.hx(c)
        if al < 0.99:
            continue_ok = (int(x) + int(y)) % 2 == 0 or al > 0.6
            if not continue_ok:
                continue
        px(hc[0] + x * 2, hc[1] + 12 + y * 2, cc, glow=c == "#ffffff" and al > 0.9)
    for it in sim.items:
        if it["gd"]:
            strip(it)
    # 立起：怪 / 她 / 帧条，按脚底 y 排
    sort = []
    for e in sim.es:
        if tg < e["dead"]:
            sort.append((e["p"][1], "e", e))
    sort.append((OPP[1], "op", None))
    for it in sim.items:
        if not it["gd"]:
            gy = it["c"][1] + (80 if it["k"] == "ult_halo" else (12 if it["burst"] else 30))
            sort.append((gy, "strip", it))
    sort.sort(key=lambda s: s[0])
    kick = -2 if any(0 <= tg - f < 1 for f in sim.fires) else 0
    for _, kind, v in sort:
        if kind == "e":
            spr = GF.ENEMY if not v["elite"] else GF.ENEMY.resize((GF.ENEMY.width * 3 // 2, GF.ENEMY.height * 3 // 2), Image.NEAREST)
            img.alpha_composite(spr, dest=(int(v["p"][0] - spr.width // 2), int(v["p"][1] - spr.height + 6)))
        elif kind == "op":
            img.alpha_composite(GF.OPS["exusiai"], dest=snap((OPP[0] - 64 + kick, OPP[1] - 120)))
        else:
            strip(v)
    # 锁定框
    for lk in sim.locks:
        e = lk["e"]
        if tg < PRE:
            continue
        if lk["out"] is not None and tg >= lk["out"]:
            f = 6 + int((tg - lk["out"]) * 2)
            if f > 7:
                continue
        else:
            j = int((tg - PRE) / 15 * 24)
            f = j if j < 4 else 4 + (j - 4) % 2
        for (x, y, c) in U.reticle_px(lk["h"], f, e["elite"]):
            px(e["p"][0] + x, e["p"][1] - 12 + y, A.hx(c))
    # 子弹
    for b in sim.buls:
        if b["t0"] <= tg < b["t1"]:
            u = tg - b["t0"]
            p = (b["p0"][0] + b["d"][0] * BSPD * u, b["p0"][1] + b["d"][1] * BSPD * u)
            buf = A.bullet("n" if b["gun"] == 0 else "g", 2, b["d"], int(tg))
            hd = snap(p)
            for (x, y), c in buf.p.items():
                px(hd[0] + x * 2, hd[1] + y * 2, A.hx(c), glow=c == "#ffffff")
    # 连锁线
    for ln in sim.lines:
        f = tg - ln["t0"]
        if 0 <= f < 2:
            a, b2 = ln["a"], ln["b"]
            n = max(1, int(math.dist(a, b2) / 2))
            for i in range(n + 1):
                uu = i / n
                if f >= 1 and uu < 0.5:
                    continue
                px(a[0] + (b2[0] - a[0]) * uu, a[1] + (b2[1] - a[1]) * uu, A.hx(A.RAMP["n"][5] if i % 2 == 0 else A.GOLD[5]))
    # 路上的粒子云
    for cl in sim.clouds:
        age = (tg - cl["t0"]) / 15.0
        for (x, y, c, gl, sz) in U.cloud_px(age, cl["sd"], cl["size"], cl["n"]):
            px(cl["c"][0] + x * 2, cl["c"][1] + y * 2, A.hx(c), glow=gl, sz=sz)
    # 最大爆炸：预备（往中心收）→ 亮核 → 大粒子云
    if -0.0 <= tb < 0.5:
        for i in range(16):
            a = i / 16 * math.tau + 0.4
            rr = RB * (0.8 - 1.2 * tb)
            px(hc[0] + math.cos(a) * rr, hc[1] + math.sin(a) * rr * 0.72, A.hx(A.GOLD[5]), glow=True)
    for (x, y, c, gl) in U.blast_core(int(math.floor(tb - 0.5)) if tb >= 0.5 else -1):
        px(hc[0] + x * 2, hc[1] + y * 2, A.hx(c), glow=gl)
    for (x, y, c, gl, sz) in U.cloud_px((tb - 0.5) / 15.0 * 1.0, 977, RB * 0.6 / 2, 160):
        px(hc[0] + x * 2, hc[1] + y * 2, A.hx(c), glow=gl, sz=sz)
    # 崩解：怪物贴图像素碎开（近似 kill_burst）+ 本色喷散
    cols = ecol_ramp()
    for sh in sim.shat:
        age = (tg - sh["t"]) / 15.0
        if age < 0 or age > 1.3:
            continue
        e = sh["e"]
        for (x, y, c, al, sz) in U.spray_px(age, e["id"] * 13 + 5, sh["out"], 22, 1.6 if True else 1.0, cols):
            if al > 0.1:
                px(e["p"][0] + x, e["p"][1] - 10 + y, A.hx(c), glow=c == "#ffffff", sz=sz)
        if age < 0.6:   # 贴图像素碎开：每 3×3 取一点，按离中心方向飞散
            spr = np.asarray(GF.ENEMY_COL)
            hh, ww = spr.shape[:2]
            for yy in range(0, hh, 6):
                for xx in range(0, ww, 6):
                    if spr[yy, xx, 3] < 120:
                        continue
                    dx, dy = xx - ww / 2, yy - hh
                    k = 1 + age * 5
                    X = e["p"][0] + dx * k + sh["out"][0] * age * 90
                    Y = e["p"][1] + 6 + dy * (1 + age * 2) + 260 * age * age
                    px(X, Y, tuple(int(v) for v in spr[yy, xx, :3]) + (255,))
    for gr in sim.grains:
        u = (tg - gr["t0"]) / 15.0
        if u < 0 or u > 0.9:
            continue
        x = gr["p"][0] + gr["v"][0] * u
        y = min(gr["gy"], gr["p"][1] + gr["v"][1] * u + 0.5 * 1100 * u * u)
        c = A.hx(A.RAMP["n"][3] if u < 0.15 else "#4a4448")
        x, y = snap((x, y))
        dr.rectangle([x, y, x + gr["sz"] - 1, y + gr["sz"] - 1], fill=c)
    # 光照：舞台压暗 + 照地光（最大爆炸那盏打满 240）+ 预备时圈内再压暗
    amb = 0.8
    if tg < 4:
        amb = 0.8 - 0.05 * tg
    elif tg < PRE:
        amb = 0.45
    glow = np.asarray(emit.filter(ImageFilter.GaussianBlur(3))).astype(np.float32) * 0.6
    base = np.asarray(img.convert("RGB")).astype(np.float32) * amb
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    lit = np.zeros((H, W), np.float32)
    lights = list(sim.lights) + [(hc[0], hc[1] + 12, 240, 1.4, F + 0.5, 4)]
    for (lx, ly, lr, li, lt0, ln) in lights:
        if lt0 <= tg < lt0 + ln:
            k = li * (1.0 - (tg - lt0) / (ln + 0.5))
            dd = np.sqrt((xx - lx) ** 2 + ((yy - ly) / 0.72) ** 2) / lr
            lit += k * np.clip(1.0 - dd, 0.0, 1.0) ** 2
    if 0 <= tb < 0.5:
        dd = np.sqrt((xx - hc[0]) ** 2 + ((yy - hc[1] - 12) / 0.72) ** 2) / RB
        base *= (1.0 - 0.28 * (dd < 1.0))[..., None]
    lc = np.array(GF.LIGHT_COL, np.float32)
    lit = np.minimum(lit, 1.6)
    base = base * (1.0 + lit[..., None] * 1.3 * lc) + lit[..., None] * 40.0 * lc
    if 4 <= tg < PRE:
        for i in range(10):
            a = i / 10 * math.tau + tg * 0.4
            rr = 120 * (1 - (tg - 4) / 6)
            x, y = snap((OPP[0] + math.cos(a) * rr, OPP[1] - 40 + math.sin(a) * rr * 0.6))
            base[y:y + 2, x:x + 2] = (255, 220, 120)
    out = Image.fromarray(np.clip(base + glow, 0, 255).astype(np.uint8), "RGB")
    shake = 3 if 0.5 <= tb < 0.5 + 0.12 * 15 * LO else 0   # 轻震 3px / 0.12 秒（慢放里按游戏拍）
    return out, shake


def phase_name(sim, tg, rt):
    if tg < 4:
        return "起手"
    if tg < PRE:
        return "蓄力"
    if 0 <= rt < 2:
        return "冲击帧（原样保留）"
    tb = tg - sim.hf
    if 0 <= tb < 0.5:
        return "最大爆炸 · 预备（定格中）"
    if 0.5 <= tb < 6:
        return "最大爆炸 · 慢动作（亮核 → 冲击环 → 崩解）"
    if tg < sim.end:
        return "释放：扫射 + 爆裂弹（粒子云）"
    return "收尾"


def save_gif(frames, path):
    pal = frames[len(frames) // 2].quantize(colors=255, method=Image.MEDIANCUT)
    q = [f.quantize(palette=pal, dither=Image.NONE) for f in frames]
    dur = [70 if i % 3 != 1 else 60 for i in range(len(q))]
    q[0].save(path, save_all=True, append_images=q[1:], duration=dur, loop=0, optimize=False, disposal=1)
    print(path, len(q), "帧", "%.0f KB" % (os.path.getsize(path) / 1024))


def load_wav(p):
    w = wave.open(p)
    a = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32) / 32768.0
    return a.reshape(-1, w.getnchannels()).mean(1), w.getframerate()


def audio_track(sim, real_of_game, n_frames, path):
    """按真实时间混音：每个音效在它那一拍对应的真实时间响（慢放里不变调，同游戏）"""
    SR = 44100
    out = np.zeros(int((n_frames / 15.0 + 3.0) * SR), np.float32)
    for (gt, f, gdb) in sim.sfx:
        if not os.path.exists(f):
            continue
        a, sr = load_wav(f)
        i = int(real_of_game(gt) * SR)
        n = min(len(a), len(out) - i)
        out[i:i + n] += a[:n] * 10 ** (gdb / 20)
    out = out[:int(n_frames / 15.0 * SR) + SR]
    pk = np.abs(out).max()
    if pk > 0.95:
        out *= 0.95 / pk
    w = wave.open(path, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((out * 32767).astype(np.int16).tobytes())
    w.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "ult_px_exusiai_1105"))
    ap.add_argument("--orig", default="")
    ap.add_argument("--orig_t0", type=float, default=-1.0)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    GF.ENEMY, GF.OPS = GF.load_sprites()
    GF.ENEMY_COL = GF.sprite(os.path.join(ROOT, "game", "art", "enemies", "offspring", "e_offspring@2x.png"), 4)
    lib = GF.Lib()
    sim = Sim()
    sim.run()
    gts = sim.frames()
    hf_idx = next(i for i, g in enumerate(gts) if g >= sim.hf)
    font = ImageFont.truetype(FONT, 16)
    frames, news = [], []
    for i, tg in enumerate(gts):
        rt = i - hf_idx
        im, shake = render(sim, lib, tg, rt)
        if shake:
            im = Image.fromarray(np.roll(np.asarray(im), (shake if i % 2 else -shake), axis=1))
        news.append(im)
        sheet = Image.new("RGB", (W, H + 30), (14, 16, 18))
        sheet.paste(im, (0, 30))
        d = ImageDraw.Draw(sheet)
        d.text((8, 5), "能天使终结技 · 转平面（ult/px_plane = 1）· %s · 1 倍 · 15 fps 原速" % phase_name(sim, tg, rt), fill=(235, 225, 200), font=font)
        frames.append(sheet)
    save_gif(frames, os.path.join(a.out, "exusiai_ult_seq.gif"))
    # 带音效的 mp4
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    td = tempfile.mkdtemp()
    for i, f in enumerate(frames):
        f.save(os.path.join(td, "f_%04d.png" % i))

    def real_of_game(gt):
        for i, g in enumerate(gts):
            if g >= gt - 1e-6:
                return i / 15.0
        return len(gts) / 15.0
    wav = os.path.join(td, "a.wav")
    audio_track(sim, real_of_game, len(frames), wav)
    mp4 = os.path.join(a.out, "exusiai_ult_seq.mp4")
    subprocess.run([ff, "-loglevel", "error", "-y", "-framerate", "15", "-i", os.path.join(td, "f_%04d.png"), "-i", wav, "-c:v", "libx264", "-pix_fmt", "yuv420p",
                    "-r", "30", "-c:a", "aac", "-b:a", "160k", "-shortest", mp4], check=True)
    print(mp4, "%.1f MB" % (os.path.getsize(mp4) / 1048576))
    sim.real_sfx = [(round(real_of_game(g), 2), os.path.basename(f), db) for g, f, db in sim.sfx]
    json.dump(sim.real_sfx, open(os.path.join(a.out, "sfx_timeline.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0)
    if a.orig and os.path.exists(a.orig):
        t_start = max(0.0, a.orig_t0 - PRE / 15.0)
        td2 = tempfile.mkdtemp()
        subprocess.run([ff, "-loglevel", "error", "-y", "-ss", "%.3f" % t_start, "-i", a.orig, "-t", "%.3f" % (len(frames) / 15.0 + 0.1), "-vf", "fps=15",
                        os.path.join(td2, "o_%04d.png")], check=True)
        olds = sorted(os.listdir(td2))
        vs = []
        for i, tg in enumerate(gts):
            sheet = Image.new("RGB", (1284, 360 + 30), (14, 16, 18))
            d = ImageDraw.Draw(sheet)
            if i < len(olds):
                o = Image.open(os.path.join(td2, olds[i])).convert("RGB")
                o = o.crop((0, 0, o.width, o.width * 9 // 16)).resize((640, 360), Image.LANCZOS)
                sheet.paste(o, (0, 30))
            sheet.paste(news[i].resize((640, 360), Image.LANCZOS), (644, 30))
            d.text((8, 5), "原终结技（当前游戏，GCP 实拍，按真实时间）", fill=(235, 225, 200), font=font)
            d.text((652, 5), "新版（转平面）· %s" % phase_name(sim, tg, i - hf_idx), fill=(235, 225, 200), font=font)
            vs.append(sheet)
        save_gif(vs, os.path.join(a.out, "exusiai_ult_vs.gif"))


if __name__ == "__main__":
    main()
