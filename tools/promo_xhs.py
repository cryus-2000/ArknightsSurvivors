# -*- coding: utf-8 -*-
"""小红书发布素材（界面与美术 2026-10-01）：只用本项目资产，输出到 art/promo/xhs/。
  首图 3:4（1242×1656）：封面 F 水月原配色版的竖构图——标题上、人物中、灯标与海嗣下；背景 6 色量化，人物原色。
  图文 8 张 3:4（1242×1656）：实机截图裁成竖幅、保住主体，顶部一条深色带压一行中文像素大字。
  视频（1080×1440，3:4，H.264 mp4，无音乐）：片头封面 2 秒 + 三段实机（宣传 GIF 的 1280×720 原始帧，1:1 居中裁 1080 宽，不放大）+ 片尾 2 秒。
用法：python tools/promo_xhs.py [输出目录，缺省 art/promo/xhs] [--only cover,cards,video] [--phone 触屏截图.png] [--rec 帧目录根]
"""
import os, sys, glob, random
import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import promo_keyart as K
import promo_cover as C
import promo_cover_bust as B
import promo_cover_pal as P
import promo_roster as R

ROOT = K.ROOT
PROMO = os.path.join(ROOT, "art", "promo")
W, H = 1242, 1656
BAND = 250          # 图文顶部说明带高度
NAVY0, NAVY1, ORANGE0, ORANGE1, GREY, CREAM = P.PAL
PLATFORMS = "免费 · 网页 / 手机 / PC"

# 图文 8 张：(文件, 说明大字, 裁切中心 x（占原图宽的比例；截图有 1280 宽也有 1920 宽）, 裁切框（比例）)；裁切宽 > 填满所需 / 给了裁切框时按宽适配、上下留暗底
CARDS = [
    ("roster", "13 名干员自由编队", None, None),
    ("shot_02_beacon.png", "点亮灯标 驱散深海", 0.53, None),
    ("shot_10_beacon_glow.png", "灯火越亮越强", 0.52, None),
    ("shot_03_levelup.png", "升级三选一 组出流派", None, (0.13, 0.0, 0.87, 1.0)),   # 三张卡横向太宽：裁卡片那一段（整高），按宽适配
    ("shot_01_tell.png", "读懂预警 躲开杀招", 0.46, None),
    ("shot_08_paranoia_hatch.png", "10 位 Boss · 4 个结局", 0.5, None),
    ("shot_04_horde.png", "大群来袭 撑住！", 0.47, None),
    ("phone", "手机也能玩", None, None),
]
# 视频三段：(帧目录名, 片段说明)
CLIPS = [("rec_growth", "开局 30 秒 编队成型"), ("rec_boss", "读懂预警 躲开 Boss"), ("rec_horde", "大群来袭 一扫而空")]


def font(size):
    return ImageFont.truetype(K.FONT_UI, size)


def big_caption(text, max_w):
    """一行像素大字：放大倍数从 6 往下试，放得下为止"""
    for k in (6, 5, 4, 3):
        t = C.pixel_text(text, 17, k, CREAM, GREY, outline=NAVY0)
        if t.width <= max_w:
            return t
    return t


def navy_bg(w, h):
    im = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(im)
    for y in range(h):
        t = y / max(1, h - 1)
        c = tuple(int(NAVY0[i] + (NAVY1[i] - NAVY0[i]) * (0.3 + 0.7 * (1 - abs(t - 0.5) * 2))) for i in range(3))
        d.line([(0, y), (w, y)], fill=c + (255,))
    return im


# ---------------------------------------------------------------- 首图
def cover():
    s = W / 630.0                      # ≈ 1.97：背景元素按封面 F 放大
    img = navy_bg(W, H)
    sea_y = int(H * 0.83)
    lx = int(W * 0.74)
    bk = K.up(K.frame("prop_beacon", 2, 1, trim=True), 7)
    bx, by = lx - bk.width // 2, sea_y + 10 - bk.height
    lamp = (lx, by + int(bk.height * 0.2))
    img = K.add(img, K.radial((W, H), lamp, int(250 * s), ORANGE0, 80), (0, 0))
    img = K.add(img, K.radial((W, H), lamp, int(80 * s), ORANGE1, 120), (0, 0))
    rnd = random.Random(9)
    for i in range(10):
        f = B.solid(K.frame(rnd.choice(B.WALL), 2, 0, trim=True))
        if rnd.random() < 0.5:
            f = f.transpose(Image.FLIP_LEFT_RIGHT)
        e = K.up(f, rnd.choice([4, 5, 6, 6]))
        ex = int(W * (0.05 + i * 0.1)) + rnd.randint(-30, 30) - e.width // 2
        ey = sea_y - e.height + rnd.randint(8, 50)
        B.rim(img, e, ORANGE1, 2.0, 8.0, (ex, ey))
        img.alpha_composite(K.tint(e, NAVY0), (ex, ey))
    img.alpha_composite(Image.new("RGBA", (W, H - sea_y), NAVY0 + (255,)), (0, sea_y))
    img.alpha_composite(bk, (bx, by))
    img = K.add(img, K.radial((W, H), lamp, int(26 * s), CREAM, 255), (0, 0))
    vig = Image.new("L", (W, H), 0)
    ImageDraw.Draw(vig).ellipse((-W * 0.2, -H * 0.12, W * 1.2, H * 1.1), fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(110))
    dark = Image.new("RGBA", (W, H), NAVY0 + (255,))
    dark.putalpha(vig.point(lambda v: int((255 - v) * 0.8)))
    img.alpha_composite(dark)
    out = P.quantize(img).convert("RGBA")
    # 人物：水月原配色（不量化），居中偏左、面朝右下的灯标；底部被前景触须压住
    o = P.OPS["mizuki"]
    f = K.frame(o["tex"], 4, 0, trim=True)
    bust = f.crop((0, 0, f.width, int(f.height * 0.86)))   # 多带一截身体，底边压到前景触须后面（不留一刀切的横边）
    bust = ImageEnhance.Brightness(ImageEnhance.Color(bust).enhance(0.88)).enhance(0.95)
    k = 14
    bu = K.up(bust, k)
    ox, oy = int(W * 0.40) - bu.width // 2, H - 236 - bu.height
    B.rim(out, bu, ORANGE1, 3.0, 6.0, (ox + 6, oy))
    out.alpha_composite(bu, (ox, oy))
    out = B.eye_glow(out, ox, oy, k, o["eyes"], o["eye"], 2.0)
    # 前景触须（调色板色，叠在人物之上）
    mass = K.load("fx_mizuki_tentacle_mass@2x")
    fw = mass.width // 6
    x, i = -60, 0
    while x < W:
        fr = mass.crop((fw * [2, 1, 4, 3][i % 4], 0, fw * ([2, 1, 4, 3][i % 4] + 1), mass.height))
        bb = fr.getbbox()
        fr = fr.crop(bb) if bb else fr
        t = K.up(fr, 4)
        lum = t.convert("L")
        col = Image.new("RGBA", t.size, NAVY1 + (255,))
        col.paste(Image.new("RGBA", t.size, GREY + (255,)), (0, 0), lum.point(lambda v: 255 if v > 200 else 0))
        col.putalpha(t.split()[3])
        out.alpha_composite(col, (x, H - t.height + 20))
        x += t.width - 70
        i += 1
    # 标题：上方居中
    t1 = C.pixel_text(C.TITLE, 17, 7, CREAM, GREY, outline=NAVY0)
    t2 = C.pixel_text(C.TITLE_EN, 9, 4, ORANGE1, ORANGE0, outline=NAVY0)
    ty = 90
    out.alpha_composite(t1, ((W - t1.width) // 2, ty))
    out.alpha_composite(t2, ((W - t2.width) // 2, ty + t1.height + 18))
    d = ImageDraw.Draw(out)
    d.fontmode = "1"
    f2 = font(30)
    d.text(((W - d.textlength(C.TINY, font=f2)) // 2, ty + t1.height + t2.height + 38), C.TINY, font=f2, fill=GREY)
    # 右下角平台小字（压在深色底上，留 40 边距）
    f3 = font(34)
    tw = d.textlength(PLATFORMS, font=f3)
    pad = 14
    bx0, by0 = W - 40 - tw - pad * 2, H - 40 - 34 - pad * 2
    d.rectangle((bx0, by0, W - 40, H - 40), fill=NAVY0)
    d.rectangle((bx0, by0, bx0 + 4, H - 40), fill=ORANGE1)
    d.text((bx0 + pad + 4, by0 + pad - 2), PLATFORMS, font=f3, fill=CREAM)
    return out.convert("RGB")


# ---------------------------------------------------------------- 图文
def fit_shot(src, cx, cw, aw, ah):
    """截图（1280 或 1920 宽）：按中心 cx（比例）裁一段（缺省裁到刚好填满 aw×ah），缩放进 aw×ah；裁得更宽时按宽适配、上下居中"""
    sw, sh = src.size
    if isinstance(cw, tuple):
        crop = src.crop((int(cw[0] * sw), int(cw[1] * sh), int(cw[2] * sw), int(cw[3] * sh)))
        k = min(aw / crop.width, ah / crop.height)
        im = crop.resize((int(crop.width * k), int(crop.height * k)), Image.LANCZOS)
        area = Image.new("RGB", (aw, ah), NAVY0)
        area.paste(im, ((aw - im.width) // 2, (ah - im.height) // 2))
        return area
    need = int(round(sh * aw / ah))
    cw = need
    cx = cx * sw
    x0 = int(min(max(cx - cw // 2, 0), sw - cw))
    crop = src.crop((x0, 0, x0 + cw, sh))
    k = min(aw / crop.width, ah / crop.height)
    im = crop.resize((int(crop.width * k), int(crop.height * k)), Image.LANCZOS)
    area = Image.new("RGB", (aw, ah), NAVY0)
    area.paste(im, ((aw - im.width) // 2, (ah - im.height) // 2))
    return area


def phone_mock(shot_path, aw, ah):
    """横屏手机外框 + 触屏实机截图（手机按 19.5:9 横放）"""
    area = navy_bg(aw, ah).convert("RGB")
    shot = Image.open(shot_path).convert("RGB")
    sw = aw - 160
    sh = int(sw * shot.height / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    bx, by = (aw - sw) // 2, (ah - sh) // 2 - 60
    d = ImageDraw.Draw(area)
    d.rounded_rectangle((bx - 40, by - 26, bx + sw + 40, by + sh + 26), radius=46, fill=(8, 10, 14), outline=GREY, width=4)
    area.paste(shot, (bx, by))
    d.rounded_rectangle((bx - 30, by + sh // 2 - 50, bx - 22, by + sh // 2 + 50), radius=4, fill=(30, 34, 40))   # 听筒 / 刘海示意
    f = font(40)
    for j, line in enumerate(["横屏 · 左半屏拖动移动 · 右下冲刺", "网页打开即玩，不用下载"]):
        tw = d.textlength(line, font=f)
        d.text(((aw - tw) // 2, by + sh + 80 + j * 62), line, font=f, fill=CREAM if j == 0 else GREY)
    return area


def card(i, spec, phone_path):
    name, text, cx, cw = spec
    aw, ah = W, H - BAND
    if name == "roster":
        area = R.compose(aw, ah)
    elif name == "phone":
        area = phone_mock(phone_path, aw, ah)
    else:
        area = fit_shot(Image.open(os.path.join(PROMO, name)).convert("RGB"), cx, cw, aw, ah)
    im = Image.new("RGB", (W, H), NAVY0)
    im.paste(area, (0, BAND))
    d = ImageDraw.Draw(im)
    d.rectangle((0, BAND - 6, W, BAND - 1), fill=ORANGE1)
    t = big_caption(text, W - 100)
    im.paste(t, ((W - t.width) // 2, (BAND - 6 - t.height) // 2 + 6), t)
    f = font(26)
    tag = "%02d / %02d" % (i + 1, len(CARDS))
    d.text((W - 40 - d.textlength(tag, font=f), 18), tag, font=f, fill=GREY)
    d.text((40, 18), "方舟幸存者", font=f, fill=GREY)
    return im


# ---------------------------------------------------------------- 视频
VW, VH = 1080, 1440
FPS = 20        # 原始帧 20 帧/秒；--fps 10 时隔帧取（OpenCV 的 H.264 码率不可调，10 帧/秒才压得进 50 MB）


def video_frame_bg():
    return navy_bg(VW, VH).convert("RGB")


def clip_frames(dirpath, text):
    """1280×720 原始帧 → 1:1 居中裁 1080×720，放进 1080×1440：上方说明大字，下方标题与平台"""
    files = sorted(glob.glob(os.path.join(dirpath, "*.png")))
    bg = video_frame_bg()
    d = ImageDraw.Draw(bg)
    t = big_caption(text, VW - 80)
    bg.paste(t, ((VW - t.width) // 2, 360 - 40 - t.height), t)
    d.rectangle((0, 356, VW, 360), fill=ORANGE1)
    d.rectangle((0, 1080, VW, 1084), fill=ORANGE1)
    t1 = C.pixel_text(C.TITLE, 17, 4, CREAM, GREY, outline=NAVY0)
    bg.paste(t1, ((VW - t1.width) // 2, 1150), t1)
    f = font(34)
    tw = d.textlength(PLATFORMS, font=f)
    d.text(((VW - tw) // 2, 1150 + t1.height + 30), PLATFORMS, font=f, fill=GREY)
    step = max(1, round(20 / FPS))
    for fp in files[::step]:
        fr = Image.open(fp).convert("RGB")
        x0 = (fr.width - VW) // 2
        fr = fr.crop((x0, 0, x0 + VW, fr.height))
        im = bg.copy()
        im.paste(fr, (0, 360))
        yield im


def still(im, secs):
    for _ in range(int(secs * FPS)):
        yield im


def end_card():
    im = video_frame_bg()
    d = ImageDraw.Draw(im)
    t1 = C.pixel_text(C.TITLE, 17, 5, CREAM, GREY, outline=NAVY0)
    im.paste(t1, ((VW - t1.width) // 2, 470), t1)
    lines = [("itch 搜", 56, GREY), ("Arknights Survivors", 64, ORANGE1), (PLATFORMS, 40, CREAM), (C.TINY, 32, GREY)]
    y = 470 + t1.height + 90
    for txt, sz, col in lines:
        f = font(sz)
        tw = d.textlength(txt, font=f)
        d.text(((VW - tw) // 2, y), txt, font=f, fill=col)
        y += sz + 40
    return im


def video(out_path, cover_img, rec_root):
    import cv2
    wr = cv2.VideoWriter(out_path, cv2.VideoWriter_fourcc(*"avc1"), FPS, (VW, VH))
    if not wr.isOpened():
        sys.exit("OpenCV 写不了 H.264（avc1）")
    n = 0
    head = cover_img.resize((VW, int(cover_img.height * VW / cover_img.width)), Image.LANCZOS).crop((0, 0, VW, VH))
    frames = [still(head, 2.0)]
    for dname, text in CLIPS:
        frames.append(clip_frames(os.path.join(rec_root, dname), text))
    frames.append(still(end_card(), 2.0))
    for gen in frames:
        for im in gen:
            wr.write(cv2.cvtColor(np.asarray(im), cv2.COLOR_RGB2BGR))
            n += 1
    wr.release()
    return n


if __name__ == "__main__":
    args = sys.argv[1:]
    out = args[0] if args and not args[0].startswith("--") else os.path.join(PROMO, "xhs")
    only = args[args.index("--only") + 1].split(",") if "--only" in args else ["cover", "cards", "video"]
    phone = args[args.index("--phone") + 1] if "--phone" in args else os.path.join(PROMO, "xhs", "src_touch_hud.png")
    rec_root = args[args.index("--rec") + 1] if "--rec" in args else os.path.join(ROOT, "build", "promo", "shots_g")
    if "--fps" in args:
        FPS = int(args[args.index("--fps") + 1])
    os.makedirs(out, exist_ok=True)
    cov = None
    if "cover" in only or "video" in only:
        cov = cover()
        if "cover" in only:
            cov.save(os.path.join(out, "xhs_00_cover_1242x1656.png"), optimize=True)
            print("cover")
    if "cards" in only:
        for i, spec in enumerate(CARDS):
            p = os.path.join(out, "xhs_%02d_%s.png" % (i + 1, os.path.splitext(spec[0])[0].replace("shot_", "")))
            card(i, spec, phone).save(p, optimize=True)
            print(p)
    if "video" in only:
        p = os.path.join(out, "xhs_video_1080x1440.mp4")
        n = video(p, cov, rec_root)
        print(p, n, "frames", "%.1f s" % (n / FPS), os.path.getsize(p) // 1024, "KB")
