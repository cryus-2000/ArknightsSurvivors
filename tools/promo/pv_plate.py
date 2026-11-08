# -*- coding: utf-8 -*-
"""片头第一镜 · 整幅底图版（用户 11-08：分层拼太潦草、海嗣爬得怪 → 直接用参考图一重出的「灭灯」版当整幅底图）：
底图 ×2 最近邻放大，镜头缓推；叠一道低分辨率（1/4）画再最近邻放大的暖色光束，从海面扫过来，72 重拍（197 帧）停在海嗣头上；
海嗣头部轻微呼吸起伏；浪花处零星像素闪光。0–296 帧（70–73 小节）。
  python tools/promo/pv_plate.py <底图.png> <输出目录>
"""
import math, os, random, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pv2d import W, H, FPS, BAR, track, ease_io, finish

SRC, OUT = sys.argv[1], sys.argv[2]
B = lambda k: int(round(k * BAR * FPS))
NF = B(3)
WARM = (255, 196, 120)
plate0 = Image.open(SRC).convert("RGB")
PW, PH = plate0.size
K = 2
plate = plate0.resize((PW * K, PH * K), Image.NEAREST)
LAMP = (201 * K, 233 * K)              # 灯（底图坐标 ×2）
HEAD = (905 * K, 150 * K)              # 海嗣头中心
HEAD_BOX = (818 * K, 82 * K, 995 * K, 222 * K)
FOAM = [(x * K, y * K) for x, y in ((470, 520), (560, 560), (640, 600), (720, 540), (800, 610), (1220, 340), (1250, 300), (1300, 360))]
rng = random.Random(7)
sparks = [(fx + rng.randint(-60, 60) * K, fy + rng.randint(-30, 30) * K, rng.uniform(0, 6.28)) for fx, fy in FOAM for _ in range(10)]
os.makedirs(OUT, exist_ok=True)
FR = [int(x) for x in os.environ.get("PV_FRAMES", "").split(",") if x] or range(NF)
for i in FR:
    t = i / FPS
    canvas = plate.copy()
    # 海嗣头呼吸：头部区域纵向 ±1.5% 缩放
    s = 1.0 + 0.015 * math.sin(t * 2.4)
    hb = canvas.crop(HEAD_BOX)
    hw, hh = hb.size
    hb2 = hb.resize((hw, int(hh * s)), Image.NEAREST)
    canvas.paste(hb2, (HEAD_BOX[0], HEAD_BOX[3] - hb2.height))
    # 光束：在 1/4 分辨率上画楔形再放大（像素感），72 拍前从海面扫到海嗣，之后停住
    q = 4
    low = Image.new("L", (canvas.width // q, canvas.height // q), 0)
    lx, ly = LAMP[0] / q, LAMP[1] / q
    hx, hy = HEAD[0] / q, HEAD[1] / q
    ang_lock = math.atan2(hy - ly, hx - lx)
    ang0 = ang_lock + 0.32          # 起点：偏下，扫在海面上
    u = track([(0, 0.0), (B(2), 1.0)], i)
    ang = ang0 + (ang_lock - ang0) * u
    sw = 0.05
    L = 2000
    ImageDraw.Draw(low).polygon([(lx, ly), (lx + L * math.cos(ang - sw), ly + L * math.sin(ang - sw)),
                                 (lx + L * math.cos(ang + sw), ly + L * math.sin(ang + sw))], fill=120)
    low = low.filter(ImageFilter.GaussianBlur(3))
    # 光束随距离衰减
    a = np.asarray(low).astype(np.float32)
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    d = np.hypot(xx - lx, yy - ly)
    a *= np.clip(1.15 - d / (L * 0.55), 0.25, 1.0)
    low = Image.fromarray(a.astype(np.uint8)).resize(canvas.size, Image.NEAREST)
    lay = Image.new("RGB", canvas.size, WARM)
    canvas = Image.composite(lay, canvas, low.point(lambda v: int(v * 0.85)))
    # 照住后：海嗣头一圈暖光
    hit = 0.0 if i < B(2) else min(1.0, (i - B(2)) / 8)
    if hit > 0:
        g = Image.new("L", canvas.size, 0)
        r = 120 * K
        ImageDraw.Draw(g).ellipse((HEAD[0] - r, HEAD[1] - r, HEAD[0] + r, HEAD[1] + r), fill=int(90 * hit))
        canvas = Image.composite(Image.new("RGB", canvas.size, WARM), canvas, g.filter(ImageFilter.GaussianBlur(40)))
    # 浪花闪光：零星 2×2 像素格亮一下
    d2 = ImageDraw.Draw(canvas)
    for sx, sy, ph in sparks:
        v = math.sin(t * 5 + ph)
        if v > 0.85:
            d2.rectangle((sx // K * K, sy // K * K, sx // K * K + 2 * K - 1, sy // K * K + 2 * K - 1), fill=(225, 238, 245))
    # 镜头：底图 2752×1536 内取 16:9 窗口，从全幅慢推到 86%，略向右上（海嗣）
    z = 1.0 + 0.12 * ease_io(i / NF)
    cw, ch = canvas.width / z, canvas.height / z
    cx = canvas.width / 2 + (HEAD[0] - canvas.width / 2) * 0.35 * (z - 1) / 0.16
    cy = canvas.height / 2 + (HEAD[1] - canvas.height / 2) * 0.25 * (z - 1) / 0.16
    x0 = min(max(0, cx - cw / 2), canvas.width - cw); y0 = 0   # 上沿贴底图顶：推近时海嗣的头不被遮幅切掉
    frame = canvas.crop((int(x0), int(y0), int(x0 + cw), int(y0 + ch))).resize((W, H), Image.LANCZOS)
    finish(frame, i).save(os.path.join(OUT, "p%04d.png" % i))
print(NF)
