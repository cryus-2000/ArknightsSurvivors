# -*- coding: utf-8 -*-
"""片头第一镜 · Veo 关键帧版合成（用户 11-08：按分镜 70–73 小节、加镜头运动）。
素材：veo_climb（冒头 → 爬上礁顶，无光，4 秒 24 帧）+ veo_c 末段（光束照住后的侧光 A，24 帧）。
时间：0–72 重拍（197 帧）放爬升，1.216 倍速；72 重拍硬切到照住，切点一下暖色闪；到 73 小节末（296 帧）。
镜头（后期，AE 式缓入缓出）：爬升时从低处冒头的特写跟着往上摇、略拉开；切点冲进 1.22 倍再用 expo_out 缓缓拉回 1.04，露出灯塔和光束。
整幅最后统一 4×4 像素化 + 96 色（64 色光束出色带）（镜头推拉后再像素化，像素格大小不随缩放变）。
  python tools/promo/pv_open1.py <爬升帧目录> <照住帧目录> <输出目录>
"""
import glob, os, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pv2d import W, H, FPS, BAR, track, ease_io, expo_out, finish

CLIMB, LIT, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
B = lambda k: int(round(k * BAR * FPS))
CUT, NF = B(2), B(3)
climb = sorted(glob.glob(os.path.join(CLIMB, "*.png")))
lit = sorted(glob.glob(os.path.join(LIT, "*.png")))
SRC_FPS = 24
os.makedirs(OUT, exist_ok=True)


EXT = 160   # 源画面海嗣头离上沿太近、会被遮幅吃掉：上方补一条天空（顶部 120 行拉伸）


def ext(im):
    c = Image.new("RGB", (W, H + EXT))
    c.paste(im.crop((0, 0, W, 120)).resize((W, EXT + 120), Image.BILINEAR), (0, 0))
    c.paste(im, (0, EXT))
    return c


def cam(im, cx, cy, z):
    im = ext(im)
    cw, ch = W / z, H / z
    x0 = min(max(0, cx - cw / 2), W - cw)
    y0 = min(max(0, cy - ch / 2), im.height - ch)
    return im.crop((int(x0), int(y0), int(x0 + cw), int(y0 + ch))).resize((W, H), Image.LANCZOS)


def pixel(im, px=4):
    s = im.convert("RGB").resize((W // px, H // px), Image.BOX)
    s = s.quantize(colors=96, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    return s.resize((W, H), Image.NEAREST)


for i in range(NF):
    if i < CUT:
        u = i / CUT
        src = climb[min(len(climb) - 1, int(u * len(climb)))]
        # 跟着海嗣往上：低处冒头特写 → 礁顶
        cx = track([(0, 700), (CUT, 1120)], i)
        cy = track([(0, 780), (int(CUT * 0.45), 500), (CUT, 530)], i)
        z = track([(0, 1.42), (CUT, 1.18)], i)
        white = 0.0
    else:
        k = i - CUT
        src = lit[min(len(lit) - 1, int(k / FPS * SRC_FPS))]
        u = expo_out(min(1.0, k / (NF - CUT)))
        cx = 1120 + (960 - 1120) * u
        cy = 530 + (640 - 530) * u
        z = 1.22 + (1.0 - 1.22) * u
        white = 0.0
    frame = pixel(cam(Image.open(src).convert("RGB"), cx, cy, z))
    if i >= CUT and i - CUT < 8:   # 照住瞬间暖色闪一下
        a = 0.35 * (1 - (i - CUT) / 8)
        frame = Image.blend(frame, Image.new("RGB", (W, H), (255, 210, 150)), a)
    finish(frame, i, white).save(os.path.join(OUT, "o%04d.png" % i))
print(NF, CUT)
