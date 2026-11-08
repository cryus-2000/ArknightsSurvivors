# -*- coding: utf-8 -*-
"""PV 2.5D 分层镜头（11-08 用户：要 AE 那种镜头滑动 / 位移 / 缩放）：游戏像素素材分层摆在不同深度，
镜头（x, y, 缩放）按关键帧走缓入缓出曲线，每层按视差系数 p 跟随（远景 p < 1 走得慢、前景 p > 1 走得快），快的时候加横 / 竖向运动模糊。
像素层一律整数倍最近邻；颗粒按 4 px 一格对齐。

  opening(out_dir)          开头 70–77 小节（7 小节 = 691 帧）：下沉进像素海底 → 横滑到灭着的灯塔 → 74 灯亮 → 推向灯光提亮到白
  name_card(out_dir, op)    干员出场名字卡 1 小节（99 帧）：镜头横滑推入 + 人物从剪影亮起 + 代号滑入故障 + 小字错开上滑
"""
import json, math, os, random, sys
import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pv_type as T

ART = T.ROOT + "/game/art"
W, H = 1920, 1080
LB = 131
FPS = 60
BAR = 4 * 60 / 145.99
CY = (94, 230, 230)
WARM = (255, 180, 90)


# ---------------------------------------------------------------- 曲线 / 关键帧
def ease_io(x):
    x = min(1.0, max(0.0, x))
    return x * x * x * (x * (6 * x - 15) + 10)


def expo_out(x):
    x = min(1.0, max(0.0, x))
    return 1.0 if x >= 1 else 1 - 2 ** (-10 * x)


def track(keys, f, curve=ease_io):
    """keys = [(帧, 值), …] → 帧 f 的值（段间按 curve 插值；值可为元组）"""
    if f <= keys[0][0]:
        return keys[0][1]
    for (f0, v0), (f1, v1) in zip(keys, keys[1:]):
        if f <= f1:
            u = curve((f - f0) / max(1e-6, f1 - f0))
            if isinstance(v0, tuple):
                return tuple(a + (b - a) * u for a, b in zip(v0, v1))
            return v0 + (v1 - v0) * u
    return keys[-1][1]


# ---------------------------------------------------------------- 素材
def px(im, k):
    return im.resize((im.width * k, im.height * k), Image.NEAREST)


_C = {}


def asset(name):
    if name in _C:
        return _C[name]
    if name == "bg":
        im = Image.open(ART + "/ui/title_deep/bg.png").convert("RGB")
        im = ImageEnhance.Color(px(im, 6)).enhance(0.75).convert("RGBA")   # 428×240 → 2568×1440
    elif name.startswith("jelly"):
        im = Image.open(ART + "/ui/title_deep/%s.png" % name).convert("RGBA")
    elif name == "lighthouse":
        s = Image.open(ART + "/world/props/prop_lighthouse@2x.png").convert("RGBA")
        im = s.crop((0, 0, 128, 128))
        im = im.crop(im.getbbox())
    elif name == "lighthouse_dim":
        lh = asset("lighthouse")
        im = ImageEnhance.Brightness(lh.convert("RGB")).enhance(0.42).convert("RGBA")
        im.putalpha(lh.getchannel("A"))
    elif name == "mound":   # 程序生成的像素暗礁（8 px 一格），压在灯塔脚下
        rnd = random.Random(8)
        g = 8
        w_, h_ = 1400 // g, 520 // g
        a = np.zeros((h_, w_), np.uint8)
        for xx in range(w_):
            u = (xx / w_ - 0.5) * 2
            top = int(h_ * (0.12 + 0.55 * u * u) + rnd.randint(-2, 2))
            a[max(0, top):, xx] = 1
        rgb = np.zeros((h_, w_, 4), np.uint8)
        rgb[..., 0], rgb[..., 1], rgb[..., 2] = 10, 18, 26
        rgb[..., 3] = a * 255
        rim = (a == 1) & (np.roll(a, 1, axis=0) == 0)
        rgb[rim, 0:3] = (40, 70, 84)
        im = Image.fromarray(rgb, "RGBA").resize((w_ * g, h_ * g), Image.NEAREST)
    else:
        raise KeyError(name)
    _C[name] = im
    return im


def snow_layer(seed, n, sizes, alpha, area=(3600, 2200)):
    """一层方块海雪（世界坐标，比画面大，供视差平移）"""
    rnd = random.Random(seed)
    return [(rnd.uniform(-area[0] / 2, area[0] / 2), rnd.uniform(-area[1] / 2, area[1] / 2), rnd.choice(sizes), rnd.randint(*alpha),
             rnd.uniform(0.6, 1.4)) for _ in range(n)]


# ---------------------------------------------------------------- 合成
class Frame:
    """一帧：按镜头 (cx, cy, s) 把各层放到屏幕上。层的世界坐标以画面中心为原点；视差 p：屏幕位移 = (世界 - 镜头 * p) * (1 + (s - 1) * p)"""

    def __init__(self, cam, bgcol=(4, 9, 16)):
        self.cx, self.cy, self.s = cam
        self.im = Image.new("RGBA", (W, H), bgcol + (255,))

    def _xf(self, x, y, p):
        sp = 1 + (self.s - 1) * p
        return W / 2 + (x - self.cx * p) * sp, H / 2 + (y - self.cy * p) * sp, sp

    def sprite(self, im, x, y, p, scale=1.0, anchor=(0.5, 0.5), alpha=1.0):
        X, Y, sp = self._xf(x, y, p)
        k = scale * sp
        w, h = max(1, int(im.width * k)), max(1, int(im.height * k))
        g = im.resize((w, h), Image.NEAREST)
        if alpha < 1:
            g.putalpha(g.getchannel("A").point(lambda v: int(v * alpha)))
        self.im.alpha_composite(g, (int(X - w * anchor[0]), int(Y - h * anchor[1])))

    def snow(self, pts, p, t, rise=20, col=(200, 240, 245)):
        lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(lay)
        for (x, y, sz, a, sp_) in pts:
            yy = y - rise * sp_ * t
            X, Y, s = self._xf(x, yy, p)
            q = max(4, int(sz * s) // 4 * 4)
            X, Y = int(X) // 4 * 4, int(Y) // 4 * 4
            if -q < X < W and -q < Y < H:
                d.rectangle((X, Y, X + q, Y + q), fill=col + (a,))
        self.im.alpha_composite(lay)

    def glow(self, x, y, p, r, col, a):
        X, Y, sp = self._xf(x, y, p)
        R = r * sp
        m = Image.new("L", (W, H), 0)
        ImageDraw.Draw(m).ellipse((X - R, Y - R, X + R, Y + R), fill=int(255 * min(1, a)))
        self.im.paste(col + (255,), (0, 0), m.filter(ImageFilter.GaussianBlur(R * 0.45)))

    def shaft(self, x_top, x_bot, wtop, wbot, p, a, col=(170, 235, 240)):
        X0, _, sp = self._xf(x_top, 0, p)
        X1, _, _ = self._xf(x_bot, 0, p)
        m = Image.new("L", (W, H), 0)
        ImageDraw.Draw(m).polygon([(X0 - wtop * sp, 0), (X0 + wtop * sp, 0), (X1 + wbot * sp, H), (X1 - wbot * sp, H)], fill=int(a))
        self.im.paste(col + (255,), (0, 0), m.filter(ImageFilter.GaussianBlur(30)))


def motion_blur(img, vx, vy):
    """按镜头速度（屏幕 px / 帧）做方向模糊：沿速度方向平均 n 份位移"""
    n = int(min(24, max(abs(vx), abs(vy)) * 0.6))
    if n < 2:
        return img
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    acc = np.zeros_like(a)
    for k in range(n):
        u = (k / (n - 1) - 0.5)
        acc += np.roll(np.roll(a, int(round(vx * 0.6 * u)), axis=1), int(round(vy * 0.6 * u)), axis=0)
    return Image.fromarray(np.clip(acc / n, 0, 255).astype(np.uint8))


def finish(img, i, white=0.0):
    out = T.letterbox_post(img.convert("RGB"), i, bars=False)
    if white > 0:
        out = Image.blend(out, Image.new("RGB", out.size, (245, 248, 250)), min(1.0, white))
    d = ImageDraw.Draw(out)
    d.rectangle((0, 0, W, LB), fill=(0, 0, 0))
    d.rectangle((0, H - LB, W, H), fill=(0, 0, 0))
    return out


# ---------------------------------------------------------------- 开头 70–77 小节
def opening(out_dir, n=None):
    """镜头关键帧（帧 / 世界坐标 / 缩放）：
         0–198   从上方黑水里下沉到海底（cy -900 → 0），轻推
       198–395   沿海底横滑到灯塔（cx 0 → 520），灯灭
           395   74 重拍：灯亮（暖光一闪）
       395–691   推向灯光（s 1.0 → 2.6，对准灯），最后 0.35 秒提亮到白"""
    S1, S2 = int(round(2 * BAR * FPS)), int(round(4 * BAR * FPS))
    NF = n or int(round(7 * BAR * FPS))
    LH = (760, 120)          # 灯塔脚底世界坐标
    LAMP = (LH[0], LH[1] - 128 * 5 * 0.83)   # 灯的位置（灯塔 ×5）
    cam_x = [(0, -60), (S1, 0), (S2, 520), (NF, LAMP[0] - 40)]
    cam_y = [(0, -900), (S1, -40), (S2, 0), (NF, LAMP[1] + 30)]
    cam_s = [(0, 1.08), (S1, 1.0), (S2, 1.0), (NF, 2.6)]
    snow_far = snow_layer(1, 220, (4, 4, 8), (40, 110))
    snow_mid = snow_layer(2, 120, (8, 12), (70, 150))
    snow_near = snow_layer(3, 10, (24, 32), (25, 50))
    os.makedirs(out_dir, exist_ok=True)
    prev = None
    for i in range(NF):
        t = i / FPS
        cam = (track(cam_x, i), track(cam_y, i), track(cam_s, i, ease_io if i < S2 else (lambda x: x ** 2.2)))
        F = Frame(cam)
        F.sprite(asset("bg"), 0, 0, 0.35)
        F.shaft(-200, 80, 90, 260, 0.35, 34)
        for k, (jx, jy, jk) in enumerate(((-700, -260, 3), (-150, -420, 2), (520, -330, 3), (1100, -200, 2))):
            j = asset("jelly_%d" % (k % 3))
            F.sprite(j, jx, jy - 18 * t, 0.55, jk, alpha=0.45)
        F.snow(snow_far, 0.5, t, 14)
        # 灯塔：74 拍前灭（压暗），之后灯亮
        lit = 0.0 if i < S2 else min(1.0, (i - S2) / 6)
        lh2 = asset("lighthouse_dim")   # 塔身一直是暗的（灯亮只照亮灯室附近）
        F.sprite(asset("mound"), LH[0], LH[1] + 6, 1.0, 1, anchor=(0.5, 0.18))   # 灯塔脚下的暗礁
        F.sprite(lh2, LH[0], LH[1], 1.0, 5, anchor=(0.5, 1.0))
        if lit > 0:
            flash = max(0.0, 1 - (i - S2) / 18)
            F.glow(LAMP[0], LAMP[1], 1.0, 70 + 260 * flash, WARM, 0.55 * lit + 0.45 * flash)
            F.shaft(LAMP[0], LAMP[0] + 120, 30, 340, 1.0, 26 * lit, WARM)
        F.snow(snow_mid, 1.0, t, 24)
        F.snow(snow_near, 1.7, t, 40)
        img = F.im
        if prev is not None:
            vx = (prev[0] - cam[0]) * 0.35 * cam[2]
            vy = (prev[1] - cam[1]) * 0.35 * cam[2]
            img = motion_blur(img, vx, vy)
        prev = cam
        white = max(0.0, (i - (NF - 21)) / 21) ** 1.5
        finish(img, i, white).save(os.path.join(out_dir, "o%04d.png" % i))
    return NF


if __name__ == "__main__":
    if sys.argv[1] == "opening":
        print(opening(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else None))
