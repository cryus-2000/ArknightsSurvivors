"""地图美术方向概念样图（10-24 协调人单 / 用户定：围绕溟痕与黑潮缩圈，海嗣「把一切归于同一」——侵蚀表现成「被抹平」）。
只出样图，不改游戏：在光学观感下的实机截图（build/look_proto/map/<场景>/rec_*.png，tools 里用 godot_runner 截）上，
用程序画「溟痕新材质」与发光地标示意，输出 build/look_proto/map/concept_<场景>.png（1280×720）。

溟痕新材质（示意）：被侵蚀处把原本地面 / 礁石细节抹成光滑均匀的深色膜（颜色抽成统一深蓝），膜上规整、缓慢起伏的等距纹路（离边缘的距离等值线），
安静的青蓝荧光只在纹路与前沿上；未侵蚀处保留原画面（杂乱、有生机）。全部在 2 px 像素格上算（半分辨率算、最近邻放大），光晕三阶硬边。
地标：灯标 / 灯塔 / 商人用现有贴图 ×2，配三阶硬边光环；祭坛暂无贴图，用程序画的发光石台示意。

    python -X utf8 tools/probes/map_concept.py
"""
import math
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = "E:/ArknightsSurvivors/build/look_proto/map"
INC = os.path.join(ROOT, "art", "incoming")
W, H = 1280, 720
FILM = np.array([14, 26, 46], np.float32)          # 统一深蓝膜
FILM_HI = np.array([22, 40, 66], np.float32)       # 纹路之间的微微起伏
GLOW = np.array([80, 200, 230], np.float32)        # 安静的青蓝荧光
FONT = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 16)


def base(scene):
    d = os.path.join(SRC, scene)
    fs = sorted(f for f in os.listdir(d) if f.startswith("rec_") and f.endswith(".png"))
    return np.asarray(Image.open(os.path.join(d, fs[-1])).convert("RGB")).astype(np.float32)


def field(blobs, w, h):
    """若干软圆的叠加场（>1 = 被侵蚀）；返回半分辨率上的场值"""
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    f = np.zeros((h, w), np.float32)
    for (cx, cy, r) in blobs:
        d2 = ((xs - cx / 2) ** 2 + (ys - cy / 2) ** 2) / (r / 2) ** 2
        f += 1.0 / (d2 + 0.15)
    return f


def apply_film(img, inside, dist, front_glow=0.55, band=9.0):
    """inside：半分辨率布尔（被侵蚀）；dist：半分辨率上离边缘的距离（像素，侵蚀区内为正）。返回全分辨率图"""
    h, w = inside.shape
    small = img[::2, ::2].copy()
    # 抹平：原画面只留极少亮度起伏，颜色抽成统一深蓝
    lum = small.mean(axis=2, keepdims=True) / 255.0
    flat = FILM + (FILM_HI - FILM) * np.clip(lum * 0.6, 0, 1)
    # 规整缓慢的等距纹路（每 band 个半分辨率像素一条，2 px 宽），越深越暗
    ph = (dist % band)
    line = (ph < 1.0) & inside & (dist > band * 0.5)
    depth = np.clip(dist / 30.0, 0, 1)
    lines_a = (0.16 - 0.12 * depth)[..., None]   # 纹路很淡、越往里越暗：安静，不是血管
    out = np.where(inside[..., None], flat, small)
    out = np.where(line[..., None], out * (1 - lines_a) + GLOW * lines_a, out)
    # 前沿：边缘一圈亮线 + 三阶硬边外晕（侵蚀区外侧）
    edge = inside & (dist < 1.0)
    out = np.where(edge[..., None], out * (1 - front_glow) + GLOW * front_glow, out)
    for k, a in ((1.5, 0.22), (3.5, 0.12), (6.0, 0.06)):
        ring = (~inside) & (dist > -k) & (dist <= -(k - 2.0 if k > 1.5 else 0))
        out = np.where(ring[..., None], out * (1 - a) + GLOW * a, out)
    out = np.clip(out, 0, 255).astype(np.uint8)
    return np.asarray(Image.fromarray(out).resize((w * 2, h * 2), Image.NEAREST)).astype(np.float32)


def dist_from_field(f, thr=1.0):
    """侵蚀区的精确距离场（区内为正、区外为负，半分辨率像素），等距纹路因此严格等距"""
    from scipy.ndimage import distance_transform_edt
    inside = f > thr
    return distance_transform_edt(inside) - distance_transform_edt(~inside)


def halo(img, cx, cy, r, col):
    """三阶硬边光环（加亮已有颜色 + 极少本色），2 px 格"""
    h, w, _ = img.shape
    ys, xs = np.mgrid[0:h, 0:w]
    d = np.sqrt(((xs // 2) * 2 - cx) ** 2 + ((ys // 2) * 2 - cy) ** 2) / r
    for lim, k in ((1.0, 0.18), (0.66, 0.3), (0.36, 0.45)):
        m = d < lim
        img[m] = img[m] * (1 + k) + np.array(col, np.float32) * k * 0.25
    return np.clip(img, 0, 255)


def paste(img, name, cx, cy, scale=2):
    im = Image.open(os.path.join(INC, name + ".png")).convert("RGBA")
    n = {"prop_beacon": 2, "prop_lighthouse": 2, "merchant": 2}.get(name, 1)   # 帧条只取首帧
    im = im.crop((0, 0, im.width // n, im.height))
    im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
    base_im = Image.fromarray(img.astype(np.uint8)).convert("RGBA")
    base_im.alpha_composite(im, (int(cx - im.width / 2), int(cy - im.height)))
    return np.asarray(base_im.convert("RGB")).astype(np.float32)


def altar(img, cx, cy):
    """祭坛示意：石台（暗灰 2 px 块）+ 顶上一点青白火"""
    d = ImageDraw.Draw(im := Image.fromarray(img.astype(np.uint8)))
    for i, (wd, ht) in enumerate(((36, 8), (28, 8), (20, 10))):
        y = cy - 8 * (i + 1)
        d.rectangle((cx - wd // 2, y, cx + wd // 2, y + ht), fill=(46 + i * 8, 56 + i * 8, 70 + i * 8))
    d.rectangle((cx - 3, cy - 40, cx + 3, cy - 30), fill=(200, 250, 255))
    return np.asarray(im).astype(np.float32)


def label(img, text):
    im = Image.fromarray(img.astype(np.uint8))
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 9 + 16 * len(text), 26), fill=(0, 0, 0))
    d.text((6, 3), text, font=FONT, fill=(230, 230, 230))
    return im


def scene_open():
    img = base("open")
    # 干净浅海：只加地标（一个灯标在画面边上，示意「随时看得到一两个」）
    img = halo(img, 1050, 520, 70, (255, 190, 110))
    img = paste(img, "prop_beacon", 1050, 540)
    img = halo(img, 210, 180, 90, (255, 210, 140))
    img = paste(img, "prop_lighthouse", 210, 210)
    return label(img, "① 开局 · 干净浅海（未侵蚀：原画面细节与色彩全留；地标：灯标 + 灯塔）")


def scene_mid():
    img = base("mid")
    blobs = [(120, 120, 150), (260, 60, 120), (1150, 600, 180), (1000, 680, 140), (1220, 380, 110), (80, 640, 160)]
    f = field(blobs, W // 2, H // 2)
    dist = dist_from_field(f)
    img = apply_film(img, f > 1.0, dist)
    img = halo(img, 980, 160, 80, (255, 190, 110))
    img = paste(img, "prop_beacon", 980, 180)
    img = halo(img, 330, 560, 70, (160, 240, 255))
    img = altar(img, 330, 590)
    return label(img, "② 中期 · 溟痕蔓延（被抹平的深蓝膜 + 等距纹路 + 青蓝前沿；地标：灯标、祭坛）")


def scene_tide():
    img = base("tide")
    ys, xs = np.mgrid[0:H // 2, 0:W // 2].astype(np.float32)
    cx, cy, R = 320, 180, 235
    wob = 6 * np.sin(np.arctan2(ys - cy, xs - cx) * 9)   # 前沿规整的起伏
    d = np.sqrt((xs - cx) ** 2 + ((ys - cy) * 1.25) ** 2) - (R + wob)
    img = apply_film(img, d > 0, dist_from_field(d, 0.0), front_glow=0.85, band=8.0)
    img = halo(img, 1150, 600, 70, (255, 150, 220))
    img = paste(img, "merchant", 1150, 630)
    img = halo(img, 140, 120, 80, (255, 190, 110))
    img = paste(img, "prop_beacon", 140, 140)
    return label(img, "③ 黑潮缩圈（圈外整片抹平，圈边发光侵蚀前沿；圈外地标：商人、熄灭的灯标）")


def scene_boss():
    img = base("boss")
    blobs = [(40, 40, 170), (1240, 40, 160), (1240, 690, 170), (40, 690, 160)]
    f = field(blobs, W // 2, H // 2)
    img = apply_film(img, f > 1.0, dist_from_field(f))
    img = halo(img, 640, 640, 90, (160, 240, 255))
    img = altar(img, 640, 660)
    return label(img, "④ Boss 场（四周被抹平，中间留出战斗区；地标：Boss 祭坛）")


def main():
    for n, fn in (("open", scene_open), ("mid", scene_mid), ("tide", scene_tide), ("boss", scene_boss)):
        out = os.path.join(SRC, "concept_%s.png" % n)
        fn().save(out)
        print(out)


if __name__ == "__main__":
    main()
