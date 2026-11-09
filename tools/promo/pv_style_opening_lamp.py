"""片头概念第二版「灯火将熄」（battle2 第 70–77 小节）：开头给一个钩子——黑暗里唯一一盏灯火，被越围越近的海嗣逼到熄灭，水月在黑里亮起。

用游戏里的像素素材：HUD 提灯帧（ui/hud/console_lantern.png，亮 / 暗 / 灭）、海嗣（runner / skimmer / offspring / floater）、水月技能帧。
低分辨率 480×270 画，×4 最近邻放大；2.39:1 遮幅；成片可在 Godot / Blender 里做动。

用法：python tools/promo/pv_style_opening_lamp.py <输出目录> [名字卡 png]
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pv_style_typecard as tc  # noqa: E402
from pv_style_opening_concept import finish  # noqa: E402

ART = tc.ROOT + "/game/art"
LW, LH, K = 480, 270, 4
WARM = (255, 178, 84)
BG = (5, 10, 16)


def lantern(row):
    """HUD 提灯：第 row 行（0 亮、1 稍暗、2 暗、3 灭），取第 1 列。"""
    sh = Image.open(ART + "/ui/hud/console_lantern.png").convert("RGBA")
    fr = sh.crop((0, row * 72, 56, row * 72 + 72))
    return fr.crop(fr.getbbox())


def enemy(eid, n):
    sh = Image.open(ART + "/enemies/%s/e_%s@2x.png" % (eid, eid)).convert("RGBA")
    fw = sh.width // n
    fr = sh.crop((0, 0, fw, sh.height))
    fr = fr.crop(fr.getbbox())
    return fr                                                                       # @2x 原样（低分辨率里显大一倍，看得清是什么）


ENEMIES = [("runner", 6), ("skimmer", 7), ("offspring", 4), ("floater", 5)]   # 帧数按贴图实测


def light_disc(img, cx, cy, r, strength):
    g = Image.new("L", img.size, 0)
    ImageDraw.Draw(g).ellipse((cx - r, cy - r, cx + r, cy + r), fill=strength)
    g = g.filter(ImageFilter.GaussianBlur(r * 0.6))
    # 像素化光：有序抖动（4×4 Bayer）代替硬边同心环——边缘是散开的像素点，不是一圈圈环
    bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
    px = g.load()
    w, h = g.size
    for y in range(h):
        for x in range(w):
            v = px[x, y]
            t = (bayer[(y % 4) * 4 + x % 4] + 0.5) / 16 * 24
            px[x, y] = int((v + t) // 24 * 24)
    img.paste(WARM + (255,), (0, 0), g)


def eyes(d, rnd, n, rmin, cx, cy):
    for _ in range(n):
        a = rnd.uniform(0, math.tau)
        r = rnd.uniform(rmin, 300)
        x, y = int(cx + math.cos(a) * r * 1.6), int(cy + math.sin(a) * r)
        col = (200, 236, 240) if rnd.random() < 0.8 else (230, 70, 80)
        d.rectangle((x, y, x + 1, y + 1), fill=col)
        d.rectangle((x + 4, y, x + 5, y + 1), fill=col)


def ring_of_enemies(img, rnd, n, r, cx, cy, lit):
    for i in range(n):
        a = i / n * math.tau + rnd.uniform(-0.1, 0.1)
        eid, fn = ENEMIES[i % len(ENEMIES)]
        e = enemy(eid, fn)
        x = int(cx + math.cos(a) * r * 1.5 - e.width / 2)
        y = int(cy + math.sin(a) * r - e.height / 2)
        sil = ImageEnhance.Brightness(e).enhance(lit)
        img.alpha_composite(sil, (x, y))


def up(lo):
    return lo.resize((lo.width * K, lo.height * K), Image.NEAREST)


def s1():
    """70：黑里只有一盏灯火的特写，火苗在呼吸。"""
    lo = Image.new("RGBA", (LW, LH), BG + (255,))
    light_disc(lo, LW // 2, LH // 2, 80, 120)
    lt = lantern(0)
    lt = lt.resize((lt.width * 3, lt.height * 3), Image.NEAREST)
    lo.alpha_composite(lt, (LW // 2 - lt.width // 2, LH // 2 - lt.height // 2))
    return up(lo)


def s2(seed=1):
    """71：拉开——灯火圈外，黑暗里一双双眼睛亮起。"""
    rnd = random.Random(seed)
    lo = Image.new("RGBA", (LW, LH), BG + (255,))
    cx, cy = LW // 2, LH // 2 + 20
    light_disc(lo, cx, cy, 70, 110)
    d = ImageDraw.Draw(lo)
    eyes(d, rnd, 40, 90, cx, cy)
    ring_of_enemies(lo, rnd, 6, 100, cx, cy, 0.3)
    lt = lantern(0)
    lo.alpha_composite(lt, (cx - lt.width // 2, cy - lt.height // 2))
    return up(lo)


def s3(seed=2):
    """72：灯火一闪、圈缩一格，海嗣逼到光边（被照亮的一侧是暖色）。"""
    rnd = random.Random(seed)
    lo = Image.new("RGBA", (LW, LH), BG + (255,))
    cx, cy = LW // 2, LH // 2 + 20
    light_disc(lo, cx, cy, 46, 90)
    d = ImageDraw.Draw(lo)
    eyes(d, rnd, 60, 70, cx, cy)
    ring_of_enemies(lo, rnd, 9, 64, cx, cy, 0.75)
    lt = lantern(2)
    lo.alpha_composite(lt, (cx - lt.width // 2, cy - lt.height // 2))
    return up(lo)


def s4(seed=3):
    """73：俯视大远景——整片海嗣，正中一个小暖点（尺度反差）。"""
    rnd = random.Random(seed)
    lo = Image.new("RGBA", (LW, LH), BG + (255,))
    cx, cy = LW // 2, LH // 2
    light_disc(lo, cx, cy, 14, 120)
    small = []
    for eid, fn in ENEMIES:
        e = enemy(eid, fn)
        small.append(e.resize((max(1, e.width // 4), max(1, e.height // 4)), Image.NEAREST))
    for _ in range(900):
        x, y = rnd.randrange(-10, LW), rnd.randrange(-10, LH)
        if math.hypot((x - cx) / 1.5, y - cy) < 26:
            continue
        e = rnd.choice(small)
        lo.alpha_composite(ImageEnhance.Brightness(e).enhance(rnd.uniform(0.25, 0.55)), (x, y))
    ImageDraw.Draw(lo).rectangle((cx - 1, cy - 1, cx + 1, cy + 1), fill=(255, 220, 160))
    return up(lo)


def s5():
    """74 重拍：灯灭。全黑，只剩灯芯一点余烬。"""
    lo = Image.new("RGBA", (LW, LH), (1, 2, 4, 255))
    lt = ImageEnhance.Brightness(lantern(3)).enhance(0.12)
    lt = lt.resize((lt.width * 3, lt.height * 3), Image.NEAREST)
    lo.alpha_composite(lt, (LW // 2 - lt.width // 2, LH // 2 - lt.height // 2))
    ImageDraw.Draw(lo).rectangle((LW // 2 - 1, LH // 2 + 4, LW // 2, LH // 2 + 5), fill=(160, 70, 30))
    return up(lo)


def s6():
    """75–76：黑里亮起青色——水月的轮廓（伞）先亮，接名字卡。"""
    lo = Image.new("RGBA", (LW, LH), (1, 3, 6, 255))
    sh = Image.open(ART + "/operators/mizuki/mizuki_runtime_skill_start@1x.png").convert("RGBA")
    fr = sh.crop((0, 0, sh.height, sh.height))
    fr = fr.crop(fr.getbbox())
    fr = fr.resize((fr.width * 4, fr.height * 4), Image.NEAREST)
    rim = Image.new("RGBA", fr.size, (94, 230, 230, 0))
    rim.putalpha(fr.getchannel("A"))
    dark = ImageEnhance.Brightness(fr).enhance(0.12)
    x, y = LW // 2 - fr.width // 2, LH - 30 - fr.height
    glow = Image.new("L", lo.size, 0)
    ImageDraw.Draw(glow).ellipse((x - 20, y - 10, x + fr.width + 20, y + fr.height + 10), fill=50)
    lo.paste((94, 230, 230, 255), (0, 0), glow.filter(ImageFilter.GaussianBlur(24)))
    lo.alpha_composite(rim, (x + 1, y - 1))
    lo.alpha_composite(dark, (x, y))
    return up(lo)


def board(frames, card):
    caps = [
        ("70 · 灯火", "黑里只有一盏灯火，火苗呼吸"),
        ("71 · 眼睛", "拉开：光圈外一双双眼睛亮起"),
        ("72 · 逼近", "灯火一闪、光圈缩小，海嗣逼到光边"),
        ("73 · 尺度", "俯视大远景：整片海嗣，正中一个小暖点"),
        ("74 重拍 · 熄灭", "灯灭，全黑，只剩一点余烬（急停）"),
        ("75–76 · 青光", "黑里亮起青色轮廓：水月"),
        ("77 · 名字卡 → 实机", "MIZUKI 故障出字 → 她的技能清场（drop）"),
    ]
    out = Image.new("RGB", (1920, 140 + 3 * 400), (14, 18, 24))
    d = ImageDraw.Draw(out)
    tc.tracked(d, (40, 26), "片头第二版「灯火将熄」（battle2 第 70–77 小节）：开头先给钩子——最后一盏灯火被海嗣围住、熄灭，水月在黑里亮起", tc.sans(26, 600), tc.INK, 0.02)
    tc.tracked(d, (40, 72), "全用游戏像素素材：HUD 提灯（亮 / 暗 / 灭帧）、海嗣、水月；低分辨率画再 4 倍放大", tc.sans(20, 400), tc.INK_DIM, 0.02)
    for i, im in enumerate(frames + [card]):
        x, y = (i % 3) * 640, 120 + (i // 3) * 400
        out.paste(im.resize((640, 360), Image.LANCZOS), (x, y))
        tc.tracked(d, (x + 16, y + 352), caps[i][0], tc.sans(18, 700), tc.CYAN, 0.02)
        tc.tracked(d, (x + 200, y + 352), caps[i][1], tc.sans(18, 400), tc.INK, 0.02)
    return out


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    frames = [finish(f(), 0.3) for f in (s1, s2, s3, s4, s5, s6)]
    for i, im in enumerate(frames):
        im.save(os.path.join(out, "lamp_%d.png" % (i + 1)))
    cp = sys.argv[2] if len(sys.argv) > 2 else os.path.join(out, "opcard_name.png")
    card = Image.open(cp).convert("RGB") if os.path.exists(cp) else Image.new("RGB", (1920, 1080))
    board(frames, card).save(os.path.join(out, "lamp_board.jpg"), quality=90)
    print("ok", out)
