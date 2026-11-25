"""冰爆源石虫死亡冰爆 · 两个方向样张（不实装，11-25 用户嫌「不像冰爆」）。

原作依据：客户端预制体 snslime_die_01_start（F:/sami_enemy_fx_ref/prefabs/summary.txt 1539 行）——
  baoshan 白闪 → baozha 爆团 白 → (0.18,0.73,1) → (0,0.13,1)、baoci 冰刺（白 / (0,0.79,1) / (0,0.34,1)）、
  xuekuai 雪块、yanjiang 青蓝拉伸火花、xingdian 青色星点、smoke 灰烟、dimian 白霜地 + andi 深蓝暗地、huan 冰蓝环。
本体是粉红源石晶体（PRTS 原样），所以爆的那一刻本体直接消失，不播粉红死亡帧条（用户：别用粉红肉块爆）。

方向 A 冰晶迸裂：白闪实心核 → 9 根冰晶刺从地面放射长出（白芯 / 冰青 / 深蓝边 + 暗描边）→ 停顿后逐根碎成冰片飞散；
                 脚下一片实心白霜（冰花点阵，按像素蚀掉，不做半透明盘）；青蓝拉伸火花。
方向 B 碎冰飞溅 + 寒雾：白闪 → 本体炸成 14 块冰块抛射（有高度、落地弹一次再滑，身后留霜点）；
                 贴地寒雾按点阵抖动（Bayer）往外滚、由密到疏散掉；冰块上闪白星。
画法：1 纹素 = 2 世界像素；1 倍镜头世界像素 = 屏幕像素；本体照局内体型 1.5。
输出 F:/sami_enemy_fx_ref/icebug_dirs/（mp4 + 总览）。需要 git 能读到 claude/sami-map-art-wip（雪地砖）。
"""
import math, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sami_final_fx_mock as FM

ROOT = FM.ROOT
OUT = "F:/sami_enemy_fx_ref/icebug_dirs"
FPS = 30
W, H = 1280, 720
TW, TH = 640, 360
BUG = (0, 0)          # 纹素坐标（相对画面中心）
SCALE = 1.5
T_BLAST = 0.45
DUR = 2.2
OL = (8, 14, 24, 255)
WHITE = (240, 250, 255)
ICE = (138, 227, 255)     # 0.54,0.89,1
CYAN = (0, 200, 255)      # 0,0.79,1
BLUE = (0, 87, 255)       # 0,0.34,1
DEEP = (0, 40, 108)       # 0,0.16,0.42
BAYER = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) + 0.5) / 16.0


def bug_frames():
    im = Image.open(os.path.join(ROOT, "game/art/enemies/sami/e_sami_icebug@2x.png")).convert("RGBA")
    n = 6
    fw, fh = im.width // n, im.height
    fr = [im.crop((i * fw, 0, (i + 1) * fw, fh)) for i in range(n)]
    return [f.resize((int(fw * SCALE / 2), int(fh * SCALE / 2)), Image.NEAREST) for f in fr]


def outline(lay):
    a = np.asarray(lay).copy()
    m = a[..., 3] > 0
    nb = np.zeros(m.shape, np.int32)
    for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        nb += np.roll(np.roll(m, dy, 0), dx, 1)
    e = (~m) & (nb >= 2)
    a[e] = OL
    return Image.fromarray(a)


def tc(x, y):
    return (TW / 2 + x, TH / 2 + y)


def shard(d, cx, cy, ang, L, wd, grow=1.0):
    """冰晶刺：根在 (cx,cy)，朝 ang 长 L；菱形长刺 + 白芯线"""
    L = L * grow
    if L < 1.5:
        return
    ux, uy = math.cos(ang), math.sin(ang) * 0.7
    nx, ny = -uy, ux
    tip = (cx + ux * L, cy + uy * L)
    mid = (cx + ux * L * 0.35, cy + uy * L * 0.35)
    body = [(cx, cy), (mid[0] + nx * wd, mid[1] + ny * wd), tip, (mid[0] - nx * wd, mid[1] - ny * wd)]
    d.polygon(body, fill=BLUE)
    inner = [(cx + ux * 1.5, cy + uy * 1.5), (mid[0] + nx * wd * 0.55, mid[1] + ny * wd * 0.55), (tip[0] - ux * 1.5, tip[1] - uy * 1.5), (mid[0] - nx * wd * 0.2, mid[1] - ny * wd * 0.2)]
    d.polygon(inner, fill=ICE)
    d.line([(cx + ux * 2, cy + uy * 2), (tip[0] - ux * 2.5, tip[1] - uy * 2.5)], fill=WHITE, width=1)


def chunk(d, x, y, s, rot, top=True):
    pts = [(x + math.cos(rot + k * 2.1 + (k % 2) * 0.4) * s, y + math.sin(rot + k * 2.1 + (k % 2) * 0.4) * s * 0.8) for k in range(3)]
    pts += [(x + math.cos(rot + 1.0) * s * 0.9, y + math.sin(rot + 1.0) * s * 0.7)]
    d.polygon(pts, fill=BLUE)
    d.polygon([(x, y), pts[0], pts[3]], fill=ICE)
    if top and s >= 2.5:
        d.point([(x - 0.5, y - 0.5)], fill=WHITE)


def flash(d, t, cx, cy):
    """白闪：实心不规则核，0.12 秒收掉"""
    u = t / 0.12
    if u >= 1:
        return
    r = 7 + 5 * u
    pts = [(cx + math.cos(k * 0.785 + 0.3) * r * (1.0 if k % 2 else 0.6), cy + math.sin(k * 0.785 + 0.3) * r * (0.75 if k % 2 else 0.45)) for k in range(8)]
    d.polygon(pts, fill=CYAN if u > 0.6 else WHITE)
    if u < 0.6:
        d.polygon([(cx + (p[0] - cx) * 0.5, cy + (p[1] - cy) * 0.5) for p in pts], fill=WHITE)


class DirA:
    """冰晶迸裂"""
    def __init__(self, seed):
        r = np.random.default_rng(seed)
        self.sp = [(i * math.tau / 9 + r.uniform(-0.2, 0.2), r.uniform(15, 27), r.uniform(3.0, 4.5), r.uniform(0.0, 0.06)) for i in range(9)]
        self.frags = [[(r.uniform(0.3, 1.0), r.uniform(-0.6, 0.6), r.uniform(40, 90), r.uniform(1.5, 3.0)) for _ in range(4)] for _ in range(9)]
        n = 260
        ang = r.uniform(0, math.tau, n)
        rad = np.sqrt(r.uniform(0, 1, n)) * 26
        self.frost = [(math.cos(a) * q, math.sin(a) * q * 0.62, r.uniform(0, 1), int(r.integers(0, 3))) for a, q in zip(ang, rad)]
        self.spk = [(r.uniform(0, math.tau), r.uniform(80, 170), r.uniform(0.18, 0.32)) for _ in range(12)]

    def ground(self, d, t, cx, cy):
        if t < 0.04:
            return
        u = min(1.0, (t - 0.04) / 0.14)
        erode = max(0.0, (t - 0.9) / 0.6)
        for x, y, k, kind in self.frost:
            if math.hypot(x, y / 0.62) > 26 * u or k < erode:
                continue
            px, py = cx + x, cy + y + 2
            if kind == 0:
                d.point([(px, py)], fill=WHITE)
            elif kind == 1:
                d.point([(px, py), (px + 1, py)], fill=(205, 236, 255))
            else:
                d.line([(px - 1, py), (px + 1, py)], fill=WHITE)
                d.point([(px, py - 1), (px, py + 1)], fill=ICE)

    def over(self, d, t, cx, cy):
        flash(d, t, cx, cy - 4)
        for i, (a, L, wd, dl) in enumerate(self.sp):
            tt = t - dl
            if tt <= 0:
                continue
            brk = 0.42 + 0.03 * i
            if tt < brk:
                g = 1 - (1 - min(1.0, tt / 0.09)) ** 3
                shard(d, cx, cy, a, L, wd, g)
            else:
                ft = tt - brk
                if ft > 0.4:
                    continue
                ux, uy = math.cos(a), math.sin(a) * 0.7
                for (f, side, sp, s) in self.frags[i]:
                    bx, by = cx + ux * L * f, cy + uy * L * f
                    vx, vy = ux * sp + side * uy * 30, uy * sp - 40
                    x, y = bx + vx * ft, by + vy * ft + 0.5 * 260 * ft * ft
                    if ft < 0.33 or int(ft * 30) % 2 == 0:
                        chunk(d, x, y, s * (1 - ft * 1.2), a + ft * 9)
        for a, sp, life in self.spk:
            tt = t - 0.02
            if tt <= 0 or tt > life:
                continue
            ux, uy = math.cos(a), math.sin(a) * 0.7
            x, y = cx + ux * sp * tt * 0.5, cy - 4 + uy * sp * tt * 0.5
            L = 6 * (1 - tt / life) + 1
            d.line([(x - ux * L, y - uy * L), (x, y)], fill=CYAN if tt < life * 0.6 else BLUE, width=1)
            d.point([(x, y)], fill=WHITE)


class DirB:
    """碎冰飞溅 + 寒雾"""
    def __init__(self, seed):
        r = np.random.default_rng(seed)
        self.ch = []
        for i in range(14):
            a = i * math.tau / 14 + r.uniform(-0.25, 0.25)
            sp = r.uniform(55, 95)
            self.ch.append((a, sp, r.uniform(70, 120), r.uniform(2.2, 4.2), r.uniform(-8, 8)))
        self.puffs = [(i * math.tau / 11 + r.uniform(-0.25, 0.25), r.uniform(0.55, 1.05), r.uniform(4.5, 8.0), r.uniform(0.0, 0.15)) for i in range(11)]
        self.glint = [(int(r.integers(0, 14)), r.uniform(0.15, 0.9)) for _ in range(10)]

    def pos(self, c, t, cx, cy):
        a, sp, vz, s, spin = c
        ux, uy = math.cos(a), math.sin(a) * 0.65
        g = 420.0
        t1 = 2 * vz / g                    # 第一次落地
        if t < t1:
            z = vz * t - 0.5 * g * t * t
            dist = sp * t
        else:
            tb = t - t1
            vz2 = vz * 0.35
            t2 = 2 * vz2 / g
            if tb < t2:
                z = vz2 * tb - 0.5 * g * tb * tb
                dist = sp * t1 + sp * 0.6 * tb
            else:
                ts = tb - t2
                z = 0
                dist = sp * t1 + sp * 0.6 * t2 + sp * 0.4 * (1 - math.exp(-ts * 5)) / 5
        return cx + ux * dist * 0.45, cy + uy * dist * 0.45, z * 0.45, t >= t1

    def ground(self, d, t, cx, cy):
        # 贴地寒雾：密度场 → Bayer 点阵抖动（实心像素，不做半透明）
        if t < 0.05 or t > 1.5:
            return
        tt = t - 0.05
        R = 10 + 30 * (1 - math.exp(-tt * 3.2))
        x0, x1, y0, y1 = int(cx - 48), int(cx + 48), int(cy - 30), int(cy + 30)
        ys, xs = np.mgrid[y0:y1, x0:x1]
        dx, dy = (xs - cx), (ys - cy - 2) / 0.6
        rr = np.hypot(dx, dy)
        den = np.zeros(rr.shape)
        for a, k, s, dl in self.puffs:   # 一团团贴地往外滚的雾，团与团之间留空（不连成盘）
            q = max(0.0, tt - dl)
            rk = R * k * min(1.0, q / 0.4 + 0.3)
            px, py = cx + math.cos(a) * rk, cy + 2 + math.sin(a) * rk * 0.6
            ss = s * (1.0 + q * 0.8)
            den += 1.15 * np.exp(-((xs - px) ** 2 + ((ys - py) / 0.6) ** 2) / (ss * ss))
        den *= max(0.0, 1.0 - max(0.0, tt - 0.35) / 1.1) * min(1.0, tt / 0.1)
        th = BAYER[ys % 4, xs % 4]
        hi = den > th + 0.75
        mid = (den > th * 0.9 + 0.12) & ~hi
        for yy, xx in zip(*np.nonzero(mid)):
            d.point([(x0 + xx, y0 + yy)], fill=(180, 214, 240))
        for yy, xx in zip(*np.nonzero(hi)):
            d.point([(x0 + xx, y0 + yy)], fill=(236, 246, 255))
        # 冰块滑过留下的霜点
        for c in self.ch:
            for k in range(6):
                tk = t - T0 - k * 0.07
                if tk <= 0:
                    continue
                x, y, z, landed = self.pos(c, tk, cx, cy)
                if landed and t < 1.6:
                    d.point([(x, y + 1)], fill=WHITE)

    def over(self, d, t, cx, cy):
        flash(d, t, cx, cy - 4)
        for i, c in enumerate(self.ch):
            tt = t - 0.02
            if tt <= 0:
                continue
            x, y, z, landed = self.pos(c, tt, cx, cy - 3)
            if tt > 1.3 and int(tt * 30) % 2 == 0:
                continue
            if tt > 1.5:
                continue
            if z > 1:
                d.point([(x, y + 1), (x + 1, y + 1)], fill=(110, 120, 140))   # 影
            chunk(d, x, y - z, c[3], c[4] * min(tt, 0.4) * 3 if not landed else c[4] * 1.2)
        for i, tg in self.glint:
            if abs(t - tg) < 0.05:
                x, y, z, _ = self.pos(self.ch[i], t - 0.02, cx, cy - 3)
                d.point([(x, y - z - 3), (x - 1, y - z - 2), (x + 1, y - z - 2), (x, y - z - 1)], fill=WHITE)


T0 = 0.02


def frame(bg, bug, fx, t, zoom, label, font):
    cx, cy = TW / 2, TH / 2
    gl = Image.new("RGBA", (TW, TH))
    ov = Image.new("RGBA", (TW, TH))
    tb = t - T_BLAST
    if tb >= 0:
        fx.ground(ImageDraw.Draw(gl), tb, cx, cy)
        fx.over(ImageDraw.Draw(ov), tb, cx, cy)
        ov = outline(ov)
    img = bg.copy()
    img.alpha_composite(gl.resize((W, H), Image.NEAREST))
    if tb < 0:
        f = bug[int(t * 8) % len(bug)]
        if tb > -0.07:   # 爆前两帧本体刷白
            a = np.asarray(f).copy()
            a[a[..., 3] > 0, :3] = (235, 245, 255)
            f = Image.fromarray(a)
        img.alpha_composite(f, (int(W / 2 - f.width / 2), int(H / 2 - f.height * 0.85)))
    img.alpha_composite(ov.resize((W, H), Image.NEAREST))
    if zoom > 1:
        img = img.crop((W // 4, H // 4, W * 3 // 4, H * 3 // 4)).resize((W, H), Image.NEAREST)
    img = img.convert("RGB")
    d = ImageDraw.Draw(img)
    d.text((24, 16), label, font=font, fill=(255, 255, 255), stroke_width=3, stroke_fill=(0, 0, 0))
    return img


def main():
    import imageio_ffmpeg
    os.makedirs(OUT, exist_ok=True)
    bg = Image.fromarray(FM.background(False, W, H).astype(np.uint8)).convert("RGBA")
    bug = bug_frames()
    font = ImageFont.truetype("C:/Windows/Fonts/msyhbd.ttc", 26)
    plan = [("A", "方向 A · 冰晶迸裂", 1), ("A", "方向 A · 冰晶迸裂", 1), ("A", "方向 A · 冰晶迸裂", 2),
            ("B", "方向 B · 碎冰飞溅 + 寒雾", 1), ("B", "方向 B · 碎冰飞溅 + 寒雾", 1), ("B", "方向 B · 碎冰飞溅 + 寒雾", 2)]
    mp4 = os.path.join(OUT, "sami_icebug_fx_dirs_1125.mp4")
    wr = imageio_ffmpeg.write_frames(mp4, (W, H), fps=FPS, codec="libx264", output_params=["-crf", "20", "-pix_fmt", "yuv420p", "-an"], macro_block_size=1)
    wr.send(None)
    shots = {}
    for k, (key, name, z) in enumerate(plan):
        fx = DirA(7) if key == "A" else DirB(7)
        lab = "冰爆源石虫 · %s · %s" % (name, "1 倍" if z == 1 else "2 倍放大")
        for i in range(int(DUR * FPS)):
            t = i / FPS
            im = frame(bg, bug, fx, t, z, lab, font)
            wr.send(np.asarray(im).tobytes())
            if z == 2:
                for tt in (0.0, 0.08, 0.2, 0.45, 0.8, 1.2):
                    if abs(t - (T_BLAST + tt)) < 0.5 / FPS:
                        shots[(key, tt)] = im
    wr.close()
    keys = sorted(shots)
    cw, ch = 400, 225
    ov = Image.new("RGB", (cw * 6, ch * 2))
    for j, kk in enumerate(keys):
        r = 0 if kk[0] == "A" else 1
        c = [0.0, 0.08, 0.2, 0.45, 0.8, 1.2].index(kk[1])
        ov.paste(shots[kk].crop((320, 180, 960, 540)).resize((cw, ch), Image.NEAREST), (c * cw, r * ch))
    ov.save(os.path.join(OUT, "sami_icebug_fx_dirs_1125_overview.jpg"), quality=88)
    print(mp4, os.path.getsize(mp4))


if __name__ == "__main__":
    main()
