"""片头第三版「海嗣上岸」概念（用户 11-08 构想；docs/327 §18）：
夜里一只海嗣从浪里爬上岸 → 灯塔光扫过来照住它 → 镜头下沉穿过水面 → 摇臂下潜拉远，从几只到满屏 → 闪出 logo → 正片。

2D 概念：低分辨率 480×270 画（游戏像素素材），×4 最近邻放大；成片由 Blender 做连续摇臂、穿水面和体积光束。
用法：python tools/promo/pv_style_opening_shore.py <输出目录> [名字卡 png]
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pv_style_typecard as tc  # noqa: E402
from pv_style_opening_concept import finish  # noqa: E402
from pv_style_opening_lamp import enemy, ENEMIES  # noqa: E402

ART = tc.ROOT + "/game/art"
LW, LH, K = 480, 270, 4
WARM = (255, 182, 96)
HORIZON = 120


def up(lo):
    return lo.resize((lo.width * K, lo.height * K), Image.NEAREST)


def vgrad(img, y0, y1, c0, c1):
    d = ImageDraw.Draw(img)
    for y in range(y0, y1):
        t = (y - y0) / max(1, y1 - y0 - 1)
        d.line((0, y, img.width, y), fill=tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3)))


def lighthouse_img(on):
    sh = Image.open(ART + "/world/props/prop_lighthouse@1x.png").convert("RGBA")
    fr = sh.crop((0, 0, 64, 64))
    fr = fr.crop(fr.getbbox())
    return fr if on else ImageEnhance.Brightness(fr).enhance(0.5)


def crawler(lit, k=3):
    e = enemy("slider", 5)                                           # 带触须、贴地爬，像在往岸上爬
    e = e.resize((e.width * k, e.height * k), Image.NEAREST)          # 主角：放大到前景
    if lit:
        warm = Image.new("RGBA", e.size, WARM + (0,))
        warm.putalpha(e.getchannel("A").point(lambda a: int(a * 0.35)))
        e = e.copy()
        e.alpha_composite(warm)
        return e
    return ImageEnhance.Brightness(e).enhance(0.35)


def shore(beam_on_creature, seed=1):
    rnd = random.Random(seed)
    lo = Image.new("RGBA", (LW, LH), (0, 0, 0, 255))
    vgrad(lo, 0, HORIZON, (8, 14, 30), (22, 36, 58))              # 夜空
    d = ImageDraw.Draw(lo)
    for _ in range(70):                                             # 星
        d.point((rnd.randrange(LW), rnd.randrange(HORIZON - 20)), fill=(170, 190, 210))
    vgrad(lo, HORIZON, 200, (14, 30, 46), (10, 22, 34))             # 海
    for y in range(HORIZON + 4, 200, 6):                            # 像素浪线
        for x in range(rnd.randrange(8), LW, rnd.randrange(14, 30)):
            d.line((x, y, x + rnd.randrange(4, 12), y), fill=(40, 70, 90))
    # 浪花边（白色像素带）
    for x in range(0, LW, 2):
        yy = 200 + int(3 * math.sin(x * 0.09)) + int(2 * math.sin(x * 0.31))
        d.rectangle((x, yy - 2, x + 1, yy), fill=(150, 190, 200))
    vgrad(lo, 203, LH, (26, 26, 30), (12, 12, 16))                  # 湿沙 / 礁石（暗）
    for _ in range(40):
        x, y = rnd.randrange(LW), rnd.randrange(210, LH)
        d.rectangle((x, y, x + rnd.randrange(3, 10), y + 2), fill=(36, 36, 40))
    # 右侧崖上的灯塔
    d.polygon([(400, HORIZON + 30), (418, HORIZON + 8), (452, HORIZON + 4), (480, HORIZON + 10), (480, HORIZON + 30)], fill=(8, 10, 14))
    lh = lighthouse_img(True)
    lx, ly = 428, HORIZON + 6 - lh.height                            # 远处崖上的小灯塔
    lo.alpha_composite(lh, (lx, ly))
    lamp = (lx + lh.width // 2, ly + 7)
    # 灯塔光束（体积光）：没照到时扫向海面，照到时打在海嗣身上
    cx, cy = 200, 246                                              # 海嗣爬上岸的位置（前景）
    target = (cx, cy) if beam_on_creature else (40, 160)
    beam = Image.new("L", lo.size, 0)
    ang = math.atan2(target[1] - lamp[1], target[0] - lamp[0])
    L = math.hypot(target[0] - lamp[0], target[1] - lamp[1]) + 60
    spread = 0.05
    p1 = (lamp[0] + math.cos(ang - spread) * L, lamp[1] + math.sin(ang - spread) * L)
    p2 = (lamp[0] + math.cos(ang + spread) * L, lamp[1] + math.sin(ang + spread) * L)
    ImageDraw.Draw(beam).polygon([lamp, p1, p2], fill=70)
    if beam_on_creature:
        ImageDraw.Draw(beam).ellipse((cx - 90, cy - 14, cx + 90, cy + 24), fill=120)
    lo.paste(WARM + (255,), (0, 0), beam.filter(ImageFilter.GaussianBlur(3)))
    d.rectangle((lamp[0] - 2, lamp[1] - 2, lamp[0] + 1, lamp[1] + 1), fill=(255, 236, 190))
    # 海嗣：半身在浪里往上爬
    c = crawler(beam_on_creature)
    lo.alpha_composite(c, (cx - c.width // 2, cy - c.height + 6))
    if beam_on_creature:   # 被照住：眼睛反光两点
        d.rectangle((cx + c.width // 4, cy - c.height + c.height // 3, cx + c.width // 4 + 2, cy - c.height + c.height // 3 + 2), fill=(255, 250, 220))
    return lo


def waterline():
    """73：分屏——上半岸上夜色（水面有灯塔光的倒影），下半水下深蓝。"""
    rnd = random.Random(4)
    lo = Image.new("RGBA", (LW, LH), (0, 0, 0, 255))
    vgrad(lo, 0, 120, (14, 22, 40), (20, 34, 52))
    d = ImageDraw.Draw(lo)
    for x in range(0, LW, 3):                                      # 水面上的暖色倒影碎光
        if 150 < x < 330 and rnd.random() < 0.5:
            yy = 112 + rnd.randrange(6)
            d.rectangle((x, yy, x + 2, yy + 1), fill=WARM)
    vgrad(lo, 126, LH, (16, 46, 62), (6, 14, 24))
    for x in range(0, LW, 2):                                      # 水线（像素波纹）
        yy = 122 + int(3 * math.sin(x * 0.07)) + int(2 * math.sin(x * 0.23))
        d.rectangle((x, yy, x + 1, yy + 2), fill=(150, 210, 220))
    rays = Image.new("L", lo.size, 0)                              # 水下光柱
    for x0 in (120, 200, 300):
        ImageDraw.Draw(rays).polygon([(x0, 126), (x0 + 16, 126), (x0 + 70, LH), (x0 + 40, LH)], fill=36)
    lo.paste((180, 230, 235, 255), (0, 0), rays.filter(ImageFilter.GaussianBlur(4)))
    c = crawler(False, 2)                                          # 水下：海嗣往深处游
    lo.alpha_composite(c, (200, 170))
    for _ in range(30):                                            # 气泡 / 海雪
        x, y = rnd.randrange(LW), rnd.randrange(130, LH)
        d.rectangle((x, y, x + 1, y + 1), fill=(190, 230, 235, 160))
    return lo


def depth(n_near, n_mid, n_far, eyes_n, seed):
    """74–76：水下，按远近三层放海嗣（近大暗虚、远小密），眼睛一层层亮。"""
    rnd = random.Random(seed)
    lo = Image.new("RGBA", (LW, LH), (0, 0, 0, 255))
    vgrad(lo, 0, LH, (14, 36, 52), (4, 8, 14))
    rays = Image.new("L", lo.size, 0)
    for x0 in (140, 260):
        ImageDraw.Draw(rays).polygon([(x0, 0), (x0 + 20, 0), (x0 + 80, LH), (x0 + 44, LH)], fill=26)
    lo.paste((180, 230, 235, 255), (0, 0), rays.filter(ImageFilter.GaussianBlur(5)))
    d = ImageDraw.Draw(lo)
    small = [enemy(e, n) for e, n in ENEMIES]
    for _ in range(n_far):                                         # 远：小、密、暗
        e = rnd.choice(small)
        e = e.resize((max(1, e.width // 4), max(1, e.height // 4)), Image.NEAREST)
        lo.alpha_composite(ImageEnhance.Brightness(e).enhance(0.3), (rnd.randrange(LW), rnd.randrange(30, LH)))
    for _ in range(n_mid):
        e = rnd.choice(small)
        e = e.resize((max(1, e.width // 2), max(1, e.height // 2)), Image.NEAREST)
        lo.alpha_composite(ImageEnhance.Brightness(e).enhance(0.45), (rnd.randrange(LW), rnd.randrange(20, LH)))
    for _ in range(eyes_n):                                        # 眼睛（青白为主，少数红）
        x, y = rnd.randrange(LW), rnd.randrange(10, LH)
        col = (200, 236, 240) if rnd.random() < 0.85 else (230, 70, 80)
        d.rectangle((x, y, x, y), fill=col)
        d.rectangle((x + 3, y, x + 3, y), fill=col)
    for _ in range(n_near):                                        # 近：大、暗、虚（前景遮挡）
        e = rnd.choice(small)
        e = e.resize((e.width * 2, e.height * 2), Image.NEAREST)
        e = ImageEnhance.Brightness(e).enhance(0.18).filter(ImageFilter.GaussianBlur(2))
        lo.alpha_composite(e, (rnd.choice((-30, LW - 120)) + rnd.randrange(40), rnd.randrange(60, LH - 40)))
    return lo


def logo_flash(base_lo):
    """77 drop：青白一闪后，满屏海嗣压暗，正中 logo。"""
    im = up(ImageEnhance.Brightness(base_lo).enhance(0.45)).convert("RGB")
    flash = Image.new("RGB", im.size, (210, 246, 248))
    im = Image.blend(im, flash, 0.18)
    d = ImageDraw.Draw(im)
    tc.tracked(d, (960, 404), "方舟幸存者", tc.serif(132, 600), tc.INK, 0.12, "m")
    tc.tracked(d, (960, 596), "ARKNIGHTS  SURVIVORS", tc.latin(30, True), tc.INK, 0.42, "m")
    d.line((960 - 330, 648, 960 - 22, 648), fill=tc.CYAN, width=2)
    d.line((960 + 22, 648, 960 + 330, 648), fill=tc.CYAN, width=2)
    d.polygon([(960, 639), (969, 648), (960, 657), (951, 648)], fill=tc.CYAN)
    tc.tracked(d, (960, 680), "水月与深蓝之树", tc.serif(40, 400), tc.INK, 0.32, "m")
    return im


def board(frames, card):
    caps = [
        ("70–71 · 岸", "夜里的海滩，一只海嗣从浪里爬上来；灯塔光扫向海面"),
        ("72 重拍 · 照住", "光束扫回来，停在它身上；眼睛反光——全片第一个暖色"),
        ("73 · 入水", "镜头下沉穿过水面：上半岸上、下半水下（分屏）"),
        ("74 · 几只", "摇臂下潜：近处几只海嗣，大、暗、虚"),
        ("75–76 · 满屏", "继续拉远：几十双、几百双眼睛一层层亮起"),
        ("77 drop · logo", "青白一闪，「方舟幸存者」定 1–2 拍"),
        ("→ 正片", "故障硬切：第一位干员出场（§17）"),
    ]
    out = Image.new("RGB", (1920, 140 + 3 * 400), (14, 18, 24))
    d = ImageDraw.Draw(out)
    tc.tracked(d, (40, 26), "片头第三版「海嗣上岸」（用户构想；battle2 第 70–77 小节，约 11.5 s）：一个连续的摇臂镜头，从岸上沉进深海，越拉越远", tc.sans(26, 600), tc.INK, 0.02)
    tc.tracked(d, (40, 72), "2D 概念，只定构图、明暗、节奏；成片由 Blender 做连续镜头、穿水面和体积光束。素材：灯塔、海嗣（上岸的是 slider，水下是 runner / skimmer / offspring / floater）、水月", tc.sans(20, 400), tc.INK_DIM, 0.02)
    for i, im in enumerate(frames + [card]):
        x, y = (i % 3) * 640, 120 + (i // 3) * 400
        out.paste(im.resize((640, 360), Image.LANCZOS), (x, y))
        tc.tracked(d, (x + 16, y + 352), caps[i][0], tc.sans(18, 700), tc.CYAN, 0.02)
        tc.tracked(d, (x + 190, y + 352), caps[i][1], tc.sans(16, 400), tc.INK, 0.02)
    return out


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    swarm = depth(2, 140, 900, 260, 9)
    frames = [finish(up(shore(False))), finish(up(shore(True))), finish(up(waterline())),
              finish(up(depth(3, 4, 0, 14, 7))), finish(up(swarm)), finish(logo_flash(swarm), 0.2)]
    for i, im in enumerate(frames):
        im.save(os.path.join(out, "shore_%d.png" % (i + 1)))
    cp = sys.argv[2] if len(sys.argv) > 2 else os.path.join(out, "opcard_name.png")
    card = Image.open(cp).convert("RGB") if os.path.exists(cp) else Image.new("RGB", (1920, 1080))
    board(frames, card).save(os.path.join(out, "shore_board.jpg"), quality=90)
    print("ok", out)
