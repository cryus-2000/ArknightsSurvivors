# -*- coding: utf-8 -*-
"""片头第一镜「海嗣爬上礁石」· 生成图分层版（用户 11-08 选 1：按参考图一用 pixgen 分层生成，海嗣用游戏贴图）。
层（远 → 近，视差 p）：天空和月 0.15 / 海岬灯塔 0.3 / 海面 0.55 / 礁石 1.0 / 前景暗礁 1.7；
灯塔光束扫过海面，72 重拍（第 197 帧）停在礁顶的海嗣身上；海嗣（游戏滑动者帧条）沿礁石爬上顶，照住时透出暖光。
70–73 小节 = 0–296 帧。镜头缓推 + 横移。
  python tools/promo/pv_reef2d.py <生成图根目录 build/imagegen> <游戏素材目录> <输出目录>
"""
import glob, math, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pv2d
from pv2d import Frame, W, H, FPS, BAR, track, ease_io, finish

GEN, AS, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
B = lambda k: int(round(k * BAR * FPS))
NF = B(3)
WARM = (255, 190, 110)


def cut(tag, soft=False):
    """洋红底抠图（按洋红度给 alpha；soft = 保留渐隐）"""
    p = sorted(glob.glob(os.path.join(GEN, tag, "raw_*.png")))[-1]
    im = Image.open(p).convert("RGB")
    a = np.asarray(im).astype(np.float32) / 255
    mag = (a[..., 0] - a[..., 1]) + (a[..., 2] - a[..., 1])
    al = np.clip(1 - (mag - 0.3) / 0.5, 0, 1)
    if not soft:
        al = (al > 0.5).astype(np.float32)
    # 收边 1 像素：去掉残留的洋红描边
    al = np.asarray(Image.fromarray((al * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3))).astype(np.float32) / 255
    rgb = np.asarray(im).astype(np.float32)
    # 去洋红溢色：红、蓝通道压到不超过 绿 + 原有冷色偏移，边缘不再发紫
    g = rgb[..., 1]
    rgb[..., 0] = np.minimum(rgb[..., 0], g + 10)
    rgb[..., 2] = np.minimum(rgb[..., 2], g + 40)
    out = np.dstack([np.clip(rgb, 0, 255), al * 255]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def fit(im, width):
    k = width / im.width
    return im.resize((int(im.width * k), int(im.height * k)), Image.NEAREST)


sky = fit(Image.open(sorted(glob.glob(os.path.join(GEN, "pl_sky", "raw_*.png")))[-1]).convert("RGBA"), int(W * 1.15))
cliff = fit(cut("pl_cliff", True), int(W * 1.1))
sea = fit(cut("pl_sea"), int(W * 1.25))
rock = fit(cut("pl_rock"), int(W * 0.95))
fore = fit(cut("pl_fore"), int(W * 1.3))
# 灯塔灯的位置：在海岬图里找最亮的一小块（灯室），换算成世界坐标
ca = np.asarray(cliff)[..., 3] > 160
left = ca[:, : cliff.width // 3]
rows = np.where(left.any(1))[0]
tip_y = rows[0]
tip_x = int(np.mean(np.where(left[tip_y + 3])[0]))
tower_w = int(left[tip_y + 40].sum())
LAMP_W = (tip_x - cliff.width / 2, tip_y + max(18, tower_w * 0.9) - cliff.height / 2)   # 塔尖往下约一个塔宽 = 灯室
# 海嗣：游戏滑动者 5 帧
sl = [Image.open(os.path.join(AS, "slider_%d.png" % i)).convert("RGBA") for i in range(4)]   # 帧条按透明缝切出 4 帧
K = 6
# 礁顶位置（礁石层坐标，层中心为原点）：在礁石 alpha 里找最高点
ra = np.asarray(rock)[..., 3] > 128
cols = np.where(ra.any(0))[0]
top_y = np.argmax(ra.any(1))
top_x = int(np.mean(np.where(ra[top_y + 6])[0]))
TOP = (top_x - rock.width / 2, top_y - rock.height / 2)
BOT = (TOP[0] - 130, TOP[1] + 340)   # 沿礁石左坡往上爬

cam_x = [(0, -60), (NF, 40)]
cam_s = [(0, 1.0), (NF, 1.07)]
os.makedirs(OUT, exist_ok=True)
FR = [int(x) for x in os.environ.get('PV_FRAMES', '').split(',') if x] or range(NF)
for i in FR:
    t = i / FPS
    F = Frame((track(cam_x, i), 0, track(cam_s, i)), bgcol=(8, 14, 22))
    F.sprite(sky, 0, -60, 0.15)
    F.sprite(cliff, -40, -10, 0.3)
    # 灯塔光束：从灯出发的暖色楔形，扫过海面后在 72 拍停到海嗣身上（屏幕坐标里画）
    lx, ly, ls = F._xf(LAMP_W[0] - 40, LAMP_W[1] - 10, 0.3)
    u = track([(0, 0.0), (B(1), 0.5), (B(2) - 20, 0.98), (B(2), 1.0)], i)
    prog = min(1.0, i / max(1, B(2)))
    sx, sy, _ = F._xf(420 + BOT[0] + (TOP[0] - BOT[0]) * prog * 0.98, 400 + BOT[1] + (TOP[1] - BOT[1]) * prog * 0.98 - 120, 1.0)
    ang_lock = math.atan2(sy - ly, sx - lx)
    ang = 0.02 + (ang_lock - 0.02) * u if i < B(2) else ang_lock   # 从贴着海平线开始扫
    sw = 0.045 + 0.01 * math.sin(t * 2)
    L = 2600
    beam = Image.new("L", (W, H), 0)
    ImageDraw.Draw(beam).polygon([(lx, ly), (lx + L * math.cos(ang - sw), ly + L * math.sin(ang - sw)), (lx + L * math.cos(ang + sw), ly + L * math.sin(ang + sw))], fill=110)
    beam = beam.filter(ImageFilter.GaussianBlur(14))
    F.im.paste(WARM + (255,), (0, 0), beam)
    F.glow(LAMP_W[0] - 40, LAMP_W[1] - 10, 0.3, 18, WARM, 1.0)
    F.sprite(sea, 0, -40 + 4 * math.sin(t * 1.3), 0.55)   # 海面上沿对齐天空图的海平线
    F.sprite(rock, 420, 400, 1.0)
    # 海嗣沿礁石往上爬（8 fps 换帧），照住后透出暖光
    fr = sl[(i // 8) % 4]
    hit = 0.0 if i < B(2) else min(1.0, (i - B(2)) / 6)
    if hit > 0:
        lay = Image.new("RGBA", fr.size, WARM + (0,))
        lay.putalpha(fr.getchannel("A").point(lambda v: int(v * 0.45 * hit)))
        fr = fr.copy(); fr.alpha_composite(lay)
        fr = ImageEnhance.Brightness(fr).enhance(1.0 + 0.6 * hit)
    else:
        fr = ImageEnhance.Brightness(fr).enhance(0.6)
    px = BOT[0] + (TOP[0] - BOT[0]) * prog * 0.98
    py = BOT[1] + (TOP[1] - BOT[1]) * prog * 0.98
    F.sprite(fr, 420 + px, 400 + py, 1.0, K, anchor=(0.5, 0.92))
    F.sprite(fore, 0, 520, 1.7)
    finish(F.im, i).save(os.path.join(OUT, "a%04d.png" % i))
print(NF, "LAMP", LAMP_W, "TOP", TOP)
