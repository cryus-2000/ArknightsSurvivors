# -*- coding: utf-8 -*-
"""Boss 弹幕第四轮：Noita 式运行时粒子 + pixelfx 动画主形（docs/302 §7，用户 11-07「这个版本没有我要的 noita 粒子感和 fx 的感觉」）。

静态图看不出「活」，这一轮出同帧对比录像（左现在 / 右新版，原速）：
  - 弹体（tools/danmaku_v2.py 的弹形）上加 pixelfx 式逐格动画：芯脉动（半径 ±0.4 格交替）、2 帧闪烁高光。
  - Noita 式粒子（全部 1 美术像素一颗，落在美术像素格上，加色、按年龄走色带 白 → 淡 → 亮 → 主 → 深、随机闪烁）：
      沿途掉落的发光像素（每颗弹按大小每帧 0.3–1.5 颗）；每个 Boss 一种环境粒子（见 AMBIENT）；
      发射：pixelfx 发射闪光帧 + 顺弹向溅出的火星（带重力、空气阻力，落到地面停住再熄）；
      消弹（弹在画面内消失）：pixelfx 消弹帧 + 碎屑（同样有重力、落地）；
      地面光：每颗弹在脚下地面投一圈加色柔光（2 档、棋盘抖动），弹幕越密地面越亮。
  - 粒子总数按 Boss 颗粒预算封顶（PART_CAP），与进游戏后走 BossBeam.take 的口径一致。

  python tools/danmaku_fx.py --cur <GCP 截图目录;…> --out <目录> [--only paranoia,carmen]
目录里每个 <spec>_cur / <spec>_hide 是同种子两遍（原样 / 不画 Boss 弹），fr_*.jpg|png 每帧截图，eb_*.json 每帧 Boss 弹位。
"""
import argparse, glob, json, math, os, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import concept_danmaku as V1
import danmaku_v2 as V2

DT = 0.05          # 探针每帧游戏时间（autotest 固定步长）
FPS = 20           # 原速
PART_CAP = 900     # 同屏粒子上限（Boss 颗粒预算）
GRAV = 320.0       # 世界像素 / 秒²（碎屑、火星下落）
HEIGHT = 16.0      # 弹飞行高度（world._ebp）：碎屑从这个高度落到地面

# 每 Boss 环境粒子：kind、每颗弹每帧发射率、寿命、速度
AMBIENT = {
    "path":     {"kind": "glint", "rate": 0.10, "life": (0.15, 0.35)},              # 菱晶闪点：原地一亮即灭，十字星
    "bishop":   {"kind": "foam", "rate": 0.25, "life": (0.3, 0.6)},                 # 浪花沫：横向散开、阻力大
    "immortal": {"kind": "mote", "rate": 0.35, "life": (0.3, 0.7)},                 # 刃后碎光：沿弹道拖出、慢慢停
    "iberia":   {"kind": "ember", "rate": 0.9, "life": (0.4, 0.9)},                 # 余烬：往上飘、发红、熄灭
    "carmen":   {"kind": "glint", "rate": 0.30, "life": (0.2, 0.45)},               # 金色闪点
    "izumik":   {"kind": "biolum", "rate": 0.25, "life": (0.6, 1.2)},               # 生物荧光：缓慢漂浮、呼吸明暗
    "ishar":    {"kind": "drip", "rate": 0.30, "life": (0.5, 0.9)},                 # 水滴：下落、溅开
    "paranoia": {"kind": "bubble", "rate": 0.12, "life": (0.5, 1.0)},               # 小泡：往上浮、左右摆
}


def ramp_col(ramp, k):
    """k 0 → 1：白 → 淡 → 亮 → 主 → 深。"""
    tones = [ramp["white"], ramp["pale"], ramp["light"], ramp["main"], ramp["deep"]]
    f = min(0.999, max(0.0, k)) * (len(tones) - 1)
    i = int(f)
    return tones[i]


class Sim:
    def __init__(self, boss, scale, size, seed=7):
        self.boss = boss
        self.ramp = V2.STYLE[boss]["ramp"]
        self.s = scale
        self.W, self.H = size
        self.lw, self.lh = int(math.ceil(self.W / scale)), int(math.ceil(self.H / scale))
        self.rng = np.random.default_rng(seed)
        self.parts = []   # [x, y(屏), z(离地), vx, vy, vz, age, life, kind, phase]
        self.fx = []      # [kind, x, y, frame0, ang]
        self.prev = []    # [(id, x, y, vx, vy, r, b)]
        self.nid = 0
        self.ids = {}

    # 屏幕像素 ↔ 世界：xf 等比，世界 1 像素 = xf_k 屏幕像素
    def step_match(self, cur, js):
        """cur: [(x, y, vx, vy, r, b)] 屏幕坐标（弹心离地 16 之前的地面点）；返回 (带 id 的列表, 新弹, 消失弹)。"""
        k = self.k
        out, used = [], set()
        born, gone = [], []
        for c in cur:
            best, bd = None, 9.0 * k
            for j, p in enumerate(self.prev):
                if j in used or abs(p[5] - c[4]) > 0.1:
                    continue
                px, py = p[1] + p[3] * DT * k, p[2] + p[4] * DT * k
                d = math.hypot(px - c[0], py - c[1])
                if d < bd:
                    best, bd = j, d
            if best is None:
                self.nid += 1
                bid = self.nid
                born.append((bid,) + tuple(c))
            else:
                used.add(best)
                bid = self.prev[best][0]
            out.append((bid,) + tuple(c))
        for j, p in enumerate(self.prev):
            if j not in used:
                gone.append(p)
        self.prev = out
        return out, born, gone

    def emit(self, x, y, z, vx, vy, vz, life, kind, n=1):
        for _ in range(n):
            if len(self.parts) >= PART_CAP:
                return
            self.parts.append([x, y, z, vx, vy, vz, 0.0, life, kind, self.rng.random() * 6.28])

    def update(self, bullets, born, gone):
        rng, k = self.rng, self.k
        amb = AMBIENT[self.boss]
        for (bid, x, y, vx, vy, r, b) in bullets:
            sp = math.hypot(vx, vy)
            ux, uy = (vx / sp, vy / sp) if sp > 1 else (0.0, 0.0)
            # 沿途掉落的发光像素（Noita：弹本身在「掉光」）
            rate = 0.35 if r <= 6 else (0.8 if r < 10 else 1.5)
            n = int(rate) + (1 if rng.random() < rate - int(rate) else 0)
            for _ in range(n):
                j = rng.normal(0, r * 0.35)
                self.emit(x - ux * r * 0.6 * k + j * uy * k, y - uy * r * 0.6 * k - j * ux * k, HEIGHT,
                          -vx * 0.12 + rng.normal(0, 14), -vy * 0.12 + rng.normal(0, 14), rng.normal(0, 6),
                          rng.uniform(0.18, 0.45), "trail")
            # 环境粒子
            if rng.random() < amb["rate"] * (1.6 if r >= 10 else 1.0):
                L = rng.uniform(*amb["life"])
                kd = amb["kind"]
                if kd == "ember":
                    self.emit(x + rng.normal(0, r * k * 0.4), y + rng.normal(0, r * k * 0.4), HEIGHT, -vx * 0.2 + rng.normal(0, 10), -vy * 0.2, rng.uniform(25, 55), L, kd)
                elif kd == "drip":
                    self.emit(x + rng.normal(0, r * k * 0.3), y, HEIGHT - 2, vx * 0.1, vy * 0.1, rng.uniform(-10, 10), L, kd)
                elif kd == "bubble":
                    self.emit(x + rng.normal(0, r * k * 0.5), y + rng.normal(0, r * k * 0.5), HEIGHT, rng.normal(0, 6), 0, rng.uniform(14, 30), L, kd)
                elif kd == "foam":
                    side = rng.choice([-1, 1])
                    self.emit(x, y, HEIGHT, -vx * 0.15 + uy * side * rng.uniform(40, 80), -vy * 0.15 - ux * side * rng.uniform(40, 80), rng.uniform(0, 20), L, kd)
                elif kd == "biolum":
                    self.emit(x + rng.normal(0, r * k * 0.6), y + rng.normal(0, r * k * 0.6), HEIGHT, rng.normal(0, 8), rng.normal(0, 8), rng.uniform(4, 12), L, kd)
                else:   # glint / mote
                    self.emit(x + rng.normal(0, r * k * 0.7), y + rng.normal(0, r * k * 0.7), HEIGHT, -vx * (0.05 if kd == "glint" else 0.25), -vy * (0.05 if kd == "glint" else 0.25), 0, L, kd)
        for (bid, x, y, vx, vy, r, b) in born:
            # 发射：pixelfx 闪光帧 + 顺弹向火星（重力、落地）
            self.fx.append(["fire", x, y, 0, math.atan2(vy, vx)])
            sp = math.hypot(vx, vy) + 1
            for _ in range(3 if r <= 6 else 5):
                a = math.atan2(vy, vx) + rng.normal(0, 0.5)
                v = rng.uniform(90, 200)
                self.emit(x, y, HEIGHT, math.cos(a) * v, math.sin(a) * v * 0.7, rng.uniform(20, 90), rng.uniform(0.35, 0.7), "spark")
        for (bid, x, y, vx, vy, r, b) in gone:
            if not (20 < x < self.W - 20 and 20 < y < self.H - 20):
                continue
            # 消弹：pixelfx 碎光帧 + 碎屑（重力、落地、熄灭）
            self.fx.append(["cancel", x, y, 0, 0.0])
            for _ in range(6 if r <= 6 else 10):
                a = rng.uniform(0, math.tau)
                v = rng.uniform(40, 150)
                self.emit(x, y, HEIGHT, math.cos(a) * v, math.sin(a) * v * 0.7, rng.uniform(30, 120), rng.uniform(0.4, 0.9), "debris")
        # 推进
        keep = []
        for p in self.parts:
            x, y, z, vx, vy, vz, age, life, kd, ph = p
            age += DT
            if age >= life:
                continue
            drag = {"trail": 2.5, "foam": 4.0, "mote": 1.5, "glint": 6.0, "biolum": 0.6, "ember": 1.2, "bubble": 0.8, "drip": 0.3, "spark": 1.6, "debris": 1.2}[kd]
            f = math.exp(-drag * DT)
            vx *= f
            vy *= f
            g = {"spark": GRAV, "debris": GRAV, "drip": GRAV * 0.9, "trail": 0.0, "ember": -20.0, "bubble": -8.0}.get(kd, 0.0)
            vz -= g * DT
            if kd == "bubble":
                vx = 10 * math.sin(age * 9 + ph)
            x += vx * DT * k
            y += vy * DT * k
            z += vz * DT
            if z <= 0 and kd in ("spark", "debris", "drip"):
                z, vz, vx, vy = 0.0, 0.0, vx * 0.2, vy * 0.2   # 落地：停住，在地上熄灭（Noita 的落地碎屑）
                if kd == "drip" and age < life - 0.15:
                    # 水滴落地溅开 2 粒
                    for s in (-1, 1):
                        keep.append([x + s * self.s, y, 0.5, s * 25, 0, 30, 0.0, 0.18, "spark", ph])
                    continue
            keep.append([x, y, z, vx, vy, vz, age, life, kd, ph])
        self.parts = keep[:PART_CAP]

    def draw_ground_light(self, lo, bullets):
        """地面光：弹脚下 2 档加色柔光，棋盘抖动外圈（Noita 光照的像素版）。"""
        main = np.array(self.ramp["main"], np.float32) / 255.0
        for (bid, x, y, vx, vy, r, b) in bullets:
            cx, cy = x / self.s, y / self.s
            R = r * 0.5 * 2.6
            x0, x1 = int(cx - R - 1), int(cx + R + 2)
            y0, y1 = int(cy - R * 0.6 - 1), int(cy + R * 0.6 + 2)
            for yy in range(max(0, y0), min(self.lh, y1)):
                for xx in range(max(0, x0), min(self.lw, x1)):
                    d = math.hypot(xx - cx, (yy - cy) / 0.6)
                    if d < R * 0.55:
                        lo[yy, xx] += main * 0.16
                    elif d < R and (xx + yy) % 2 == 0:
                        lo[yy, xx] += main * 0.09

    def draw_parts(self, lo, t):
        rng = self.rng
        for (x, y, z, vx, vy, vz, age, life, kd, ph) in self.parts:
            kage = age / life
            if kd in ("trail", "spark", "debris", "mote") and rng.random() < 0.18:
                continue   # 闪烁
            if kd == "biolum":
                a = 0.5 + 0.5 * math.sin(age * 7 + ph)
                col = np.array(self.ramp["pale"] if a > 0.6 else self.ramp["light"], np.float32) / 255.0 * (0.4 + 0.6 * a) * (1 - kage)
            elif kd == "ember":
                col = np.array(ramp_col(self.ramp, 0.25 + kage * 0.75), np.float32) / 255.0 * (1.2 - kage)
            elif kd == "bubble":
                col = np.array(self.ramp["pale"], np.float32) / 255.0 * 0.8 * (1 - kage)
            elif kd == "glint":
                col = np.array(self.ramp["white"] if kage < 0.4 else self.ramp["light"], np.float32) / 255.0 * (1.1 - kage)
            else:
                col = np.array(ramp_col(self.ramp, kage), np.float32) / 255.0 * (1.15 - 0.6 * kage)
            px = int(x / self.s)
            py = int((y - z * self.k) / self.s)
            if not (1 <= px < self.lw - 1 and 1 <= py < self.lh - 1):
                continue
            lo[py, px] += col
            if kd == "glint" and kage < 0.35:   # 十字星芒
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    lo[py + dy, px + dx] += col * 0.55
            if kd == "bubble" and kage < 0.7:   # 小泡：空心 1 格环（上下左右），中间不亮
                lo[py, px] -= col * 0.6
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    lo[py + dy, px + dx] += col * 0.5
            if z <= 0.01 and kd in ("spark", "debris"):
                lo[py, px] += col * 0.3   # 落地余光

    def draw_fx(self, cv):
        keep = []
        for f in self.fx:
            kind, x, y, fr, ang = f
            frames = V2.fx_v2(self.boss, kind)
            if fr < len(frames):
                V1.composite(cv, frames[fr], x, y - HEIGHT * self.k, self.s)
                f[3] += 1
                keep.append(f)
        self.fx = keep


def load_frames(root, spec):
    cd, hd = os.path.join(root, spec + "_cur"), os.path.join(root, spec + "_hide")
    js = sorted(glob.glob(os.path.join(hd, "eb_*.json")))
    def img(d, i):
        for ext in (".jpg", ".png"):
            f = os.path.join(d, "fr_%05d%s" % (i, ext))
            if os.path.exists(f):
                return f
        return None
    out = []
    for f in js:
        i = int(os.path.basename(f)[3:8])
        out.append((i, f, img(cd, i), img(hd, i)))
    return out


def nearest(frames, i, which):
    best = None
    for (j, f, c, h) in frames:
        p = c if which == "cur" else h
        if p and (best is None or abs(j - i) < abs(best[0] - i)):
            best = (j, p)
    return best[1] if best else None


def render(root, spec, boss, outdir):
    frames = load_frames(root, spec)
    if not frames:
        print("缺", spec)
        return
    js0 = json.load(open(frames[0][1], encoding="utf-8"))
    k = math.hypot(js0["xf"][0], js0["xf"][1]) * js0["img"][0] / 1920.0
    scale = 2 * k
    W, H = js0["img"]
    sim = Sim(boss, scale, (W, H))
    sim.k = k
    # 取景：Boss 与队长中点（第一帧），整段固定
    bx, by = V1.world_to_img(js0, js0["boss"][0], js0["boss"][1])
    px, py = V1.world_to_img(js0, js0["pp"][0], js0["pp"][1])
    cw, ch = 1240, 820
    x0 = int(min(max(0, (bx + px) / 2 - cw / 2), W - cw))
    y0 = int(min(max(0, (by + py) / 2 - ch / 2), H - ch))
    box = (x0, y0, x0 + cw, y0 + ch)
    tmp = os.path.join(outdir, "_frames_" + boss)
    os.makedirs(tmp, exist_ok=True)
    for f in glob.glob(os.path.join(tmp, "*.png")):
        os.remove(f)
    st = V2.STYLE[boss]
    font = V1.font(18)
    t = 0.0
    n_written = 0
    peak = 0
    for (i, jf, cf, hf) in frames:
        js = json.load(open(jf, encoding="utf-8"))
        cur = []
        for b in js["b"]:
            bb = b[8] if len(b) > 8 and b[8] in V2.STYLE else boss
            if bb == "knight_boss":
                continue
            x, y = V1.world_to_img(js, b[0], b[1])
            cur.append((x, y, b[2], b[3], float(b[4]), b))
        bullets, born, gone = sim.step_match(cur, js)
        if i == frames[0][0]:
            born = []   # 第一帧已在场的不算新弹
        sim.update(bullets, born, gone)
        bgf = hf or nearest(frames, i, "hide")
        cuf = cf or nearest(frames, i, "cur")
        bg = np.array(Image.open(bgf).convert("RGBA"))
        lo = np.zeros((sim.lh, sim.lw, 3), np.float32)
        sim.draw_ground_light(lo, bullets)
        # 加色层（地面光）先叠，再画弹
        up = V1._up(lo, scale)[:H, :W]
        bg[:up.shape[0], :up.shape[1], :3] = np.clip(bg[:up.shape[0], :up.shape[1], :3] + up * 255, 0, 255).astype(np.uint8)
        items = []
        for (bid, x, y, vx, vy, r, b) in bullets:
            sh, R = V2.kind_for(boss if not (len(b) > 8 and b[8] in V2.STYLE) else b[8], b)
            # pixelfx 逐格动画：芯脉动（每 2 帧在 R 与 R+0.4 之间切换，按弹错相）
            if sh not in ("crescent", "shell"):
                R = R + (0.4 if (i + bid) % 4 < 2 else 0.0)
            items.append((sh, R, x, y - HEIGHT * k, vx, vy, bid * 1.7 + i * 0.35))
        for lay in ("glow", "body", "core"):
            for sh, R, x, y, vx, vy, ph in items:
                V2.draw(bg, boss, sh, R, x, y, vx, vy, scale, ph=ph, layer=lay)
        lo2 = np.zeros((sim.lh, sim.lw, 3), np.float32)
        sim.draw_parts(lo2, t)
        up2 = V1._up(lo2, scale)[:H, :W]
        bg[:up2.shape[0], :up2.shape[1], :3] = np.clip(bg[:up2.shape[0], :up2.shape[1], :3] + up2 * 255, 0, 255).astype(np.uint8)
        sim.draw_fx(bg)
        peak = max(peak, len(sim.parts))
        newim = Image.fromarray(bg, "RGBA").crop(box)
        curim = Image.open(cuf).convert("RGBA").crop(box)
        canvas = Image.new("RGB", (cw * 2 + 30, ch + 70), (16, 16, 20))
        dr = ImageDraw.Draw(canvas)
        dr.text((12, 8), "%s · %s · 同一局同种子 · 原速 · 新版：%s + Noita 粒子（掉光 / 地面光 / %s / 发射火星 / 消弹碎屑落地）" % (
            st["name"], V2.MOVE.get(boss, ""), st["shape_name"], {"glint": "闪点", "foam": "浪花沫", "mote": "碎光", "ember": "余烬", "biolum": "生物荧光", "drip": "水滴", "bubble": "小泡"}[AMBIENT[boss]["kind"]]),
            fill=(235, 235, 240), font=font)
        for ti, (nm, im) in enumerate([("现在（实机）", curim), ("新版", newim)]):
            canvas.paste(im.convert("RGB"), (10 + ti * (cw + 10), 60))
            dr.text((16 + ti * (cw + 10), 38), nm, fill=(235, 235, 240), font=V1.font(15))
        canvas.save(os.path.join(tmp, "f_%04d.png" % n_written))
        n_written += 1
        t += DT
    mp4 = os.path.join(outdir, "fx_%s.mp4" % boss)
    try:
        import imageio_ffmpeg
        ff = imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        ff = "ffmpeg"
    subprocess.run([ff, "-loglevel", "error", "-y", "-framerate", str(FPS), "-i", os.path.join(tmp, "f_%04d.png"),
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2", mp4], check=True)
    # 留一张中段静帧给文档
    mid = os.path.join(tmp, "f_%04d.png" % (n_written * 2 // 3))
    Image.open(mid).save(os.path.join(outdir, "fx_%s_still.png" % boss))
    print(mp4, "frames", n_written, "peak particles", peak)


SPECS = {"path": "path", "bishop": "bishop", "immortal": "immortal", "iberia": "iberia", "carmen": "carmen", "izumik2": "izumik", "ishar2": "ishar", "paranoia": "paranoia"}

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--cur", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    only = set(x for x in a.only.split(",") if x)
    for spec, boss in SPECS.items():
        if only and boss not in only:
            continue
        roots = [r for r in a.cur.split(";") if os.path.isdir(os.path.join(r, spec + "_hide"))]
        if roots:
            render(roots[0], spec, boss, a.out)
