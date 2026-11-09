"""片头「像素深海下潜」概念图（docs/327 §18 草案；battle2 第 70–77 小节，约 11.5 s）。

2D 概念：整张深海世界先在 480 宽的低分辨率里画（游戏像素素材 1 倍），再 ×4 最近邻放大到 1920，保证全是方块像素；
成片由 Blender（pv3d_pixel.py）做真纵深、体积光和镜头运动，本脚本只定构图、明暗和节奏。

出：opening_A…E.png（各 1920×1080）+ opening_board.jpg（含名字卡共 6 格）
用法：python tools/promo/pv_style_opening_concept.py <输出目录> [名字卡 png]
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pv_style_typecard as tc  # noqa: E402

ART = tc.ROOT + "/game/art"
K = 4                    # 低分辨率 → 1920 的放大倍数
LW, LH = 480, 270        # 一屏的低分辨率
WORLD_H = LH * 3         # 海面 / 中层 / 海底 三屏高
LB = 138                 # 2.39:1 遮幅（全分辨率）
WARM = (255, 180, 90)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def frame(path, idx, size):
    sh = Image.open(path).convert("RGBA")
    fr = sh.crop((idx * size, 0, idx * size + size, sh.height))
    return fr.crop(fr.getbbox())


def silhouette(im, col, alpha):
    s = Image.new("RGBA", im.size, col + (0,))
    s.putalpha(im.getchannel("A").point(lambda a: int(a * alpha)))
    return s


def world(lamp_on):
    rnd = random.Random(7)
    img = Image.new("RGBA", (LW, WORLD_H), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    # 竖向渐变：海面青 → 中层深蓝 → 海底近黑蓝（暗而不死黑，最低亮度 ≈ 0.04）
    stops = [(0, (86, 150, 166)), (60, (30, 78, 96)), (LH, (12, 34, 48)), (2 * LH, (8, 20, 32)), (WORLD_H, (6, 14, 24))]
    for y in range(WORLD_H):
        for i in range(len(stops) - 1):
            if stops[i][0] <= y <= stops[i + 1][0]:
                t = (y - stops[i][0]) / max(1, stops[i + 1][0] - stops[i][0])
                d.line((0, y, LW, y), fill=lerp(stops[i][1], stops[i + 1][1], t))
                break
    # 海面：一条亮的波纹边（像素阶梯）
    for x in range(0, LW, 2):
        yy = 6 + int(2 * math.sin(x * 0.11)) + int(1.5 * math.sin(x * 0.37))
        d.rectangle((x, 0, x + 1, yy), fill=(170, 220, 228))
    # 顶光光柱：从海面斜下，越深越淡
    rays = Image.new("L", (LW, WORLD_H), 0)
    rd = ImageDraw.Draw(rays)
    for x0, w0, a in ((70, 26, 60), (150, 14, 40), (230, 34, 70), (330, 18, 45), (400, 12, 30)):
        rd.polygon([(x0, 0), (x0 + w0, 0), (x0 + w0 + 90, int(LH * 1.6)), (x0 + 60, int(LH * 1.6))], fill=a)
    rays = rays.filter(ImageFilter.GaussianBlur(3))
    # 光柱随深度渐隐：到第二屏中段归零，不留硬边
    fade = Image.new("L", (LW, WORLD_H), 0)
    fd = ImageDraw.Draw(fade)
    for y in range(WORLD_H):
        fd.line((0, y, LW, y), fill=int(255 * max(0.0, 1 - y / (LH * 1.5)) ** 1.5))
    img.paste((190, 235, 240, 255), (0, 0), Image.composite(rays, Image.new("L", rays.size, 0), fade))
    # 中层：远处水母（标题页素材，1 倍 / 半倍）+ 巨大的育母剪影（海嗣，只见轮廓）
    for (x, y, i, half, al) in ((60, 120, 0, True, 0.5), (360, 90, 1, True, 0.45), (300, 330, 2, False, 0.35), (40, 400, 0, True, 0.3)):
        j = Image.open(ART + "/ui/title_deep/jelly_%d.png" % i).convert("RGBA")
        if half:
            j = j.resize((j.width // 2, j.height // 2), Image.NEAREST)
        img.alpha_composite(silhouette(j, (150, 210, 220), al), (x, y))
    mom = frame(ART + "/enemies/mother/e_mother@2x.png", 0, 136)
    mom = mom.resize((mom.width * 2, mom.height * 2), Image.NEAREST)
    img.alpha_composite(silhouette(mom, (4, 10, 18), 0.75), (250, LH + 120))
    # 海底：标题页像素海底（428×240，1 倍）放在最下一屏，两侧补暗
    bg = Image.open(ART + "/ui/title_deep/bg.png").convert("RGB")
    bg = ImageEnhance.Brightness(bg).enhance(0.85).convert("RGBA")
    mask = Image.linear_gradient("L").resize((bg.width, bg.height)).point(lambda v: min(255, v * 3))
    bg.putalpha(mask)
    img.alpha_composite(bg, ((LW - bg.width) // 2, WORLD_H - bg.height))
    # 灯塔（游戏道具，1 倍）立在右侧礁石上
    lh = frame(ART + "/world/props/prop_lighthouse@1x.png", 0, 64)
    lx, ly = 318, WORLD_H - 118
    if lamp_on:
        glow = Image.new("L", (LW, WORLD_H), 0)
        ImageDraw.Draw(glow).ellipse((lx + lh.width // 2 - 40, ly - 30, lx + lh.width // 2 + 40, ly + 40), fill=150)
        glow = glow.filter(ImageFilter.GaussianBlur(14))
        img.paste(WARM + (255,), (0, 0), glow)
        # 灯光投到海底的一束光（暖，斜向左下，光尽头是人物站的地方）
        beam = Image.new("L", (LW, WORLD_H), 0)
        ImageDraw.Draw(beam).polygon([(lx + 30, ly + 6), (lx + 36, ly + 6), (176, WORLD_H - 34), (120, WORLD_H - 34)], fill=60)
        img.paste((255, 205, 140, 255), (0, 0), beam.filter(ImageFilter.GaussianBlur(4)))
    else:
        lh = ImageEnhance.Brightness(lh).enhance(0.55)
    img.alpha_composite(lh, (lx, ly))
    if lamp_on:
        ImageDraw.Draw(img).rectangle((lx + 30, ly + 9, lx + 33, ly + 12), fill=(255, 235, 190))
    # 海雪：1–2 像素的方块，往上漂
    for _ in range(260):
        x, y = rnd.randrange(LW), rnd.randrange(WORLD_H)
        s = rnd.choice((1, 1, 1, 2))
        ImageDraw.Draw(img).rectangle((x, y, x + s - 1, y + s - 1), fill=(200, 236, 240, rnd.randint(70, 180)))
    return img


def up(lo):
    return lo.resize((lo.width * K, lo.height * K), Image.NEAREST)


def finish(im, vignette=0.45):
    im = im.convert("RGB")
    W, H = im.size
    v = Image.radial_gradient("L").resize((W, H)).point(lambda p: int(255 * (1 - vignette * min(1, max(0, (p - 120) / 135)))))
    im = Image.composite(im, Image.new("RGB", (W, H), (0, 0, 0)), v)
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, W, LB), fill=(0, 0, 0))
    d.rectangle((0, H - LB, W, H), fill=(0, 0, 0))
    return tc._add_noise(im, Image.effect_noise((W, H), 30).point(lambda p: 128 + (p - 128) * 0.2))


def shot_a():
    """70：全黑，正中一点光 + 小标志。"""
    im = Image.new("RGB", (1920, 1080), (2, 4, 8))
    g = Image.new("L", im.size, 0)
    ImageDraw.Draw(g).ellipse((960 - 220, 470 - 160, 960 + 220, 470 + 160), fill=40)
    im.paste((140, 210, 220), (0, 0), g.filter(ImageFilter.GaussianBlur(60)))
    d = ImageDraw.Draw(im)
    d.rectangle((958, 380, 962, 384), fill=(236, 241, 244))          # 一点光（方块像素）
    tc.tracked(d, (960, 520), "方舟幸存者", tc.serif(40, 600), tc.INK, 0.3, "m")
    tc.tracked(d, (960, 584), "明日方舟同人作品", tc.sans(16, 400), tc.INK_DIM, 0.3, "m")
    return finish(im, 0.2)


def window(w, y0):
    return up(w.crop((0, y0, LW, y0 + LH)))


def shot_e(w):
    """75–76：推向灯光尽头，光里站着一个人（逆光，半剪影，接名字卡的「贴近」）。"""
    cx, cy = 150, WORLD_H - 70
    lo = w.crop((cx - 120, cy - 68, cx + 120, cy + 67)).copy()
    d = ImageDraw.Draw(lo)
    # 灯光尽头在她脚下：一圈暖色地面光 + 从右上斜下的光束
    pool = Image.new("L", lo.size, 0)
    ImageDraw.Draw(pool).ellipse((120 - 46, 112, 120 + 46, 130), fill=150)
    beam = Image.new("L", lo.size, 0)
    ImageDraw.Draw(beam).polygon([(240, 0), (240, 22), (150, 126), (92, 122)], fill=70)
    glow = Image.composite(pool, beam, pool).filter(ImageFilter.GaussianBlur(3))
    lo.paste((255, 196, 120, 255), (0, 0), glow)
    mz = frame(ART + "/operators/mizuki/mizuki_runtime_idle@1x.png", 0, 96)
    dark = ImageEnhance.Brightness(mz).enhance(0.28)               # 逆光：正面压暗但看得出是谁
    rim = silhouette(mz, (255, 214, 150), 1.0)
    px_, py_ = 120 - mz.width // 2, 122 - mz.height
    lo.alpha_composite(rim, (px_ + 1, py_ - 1))
    lo.alpha_composite(dark, (px_, py_))
    return lo.resize((1920, 1080), Image.NEAREST)


def board(frames, card):
    caps = [
        ("70 · 1.6 s", "全黑，一点光；小标志 + 同人声明"),
        ("71 · 海面", "镜头从海面沉下：顶光光柱、水母、海雪上漂"),
        ("72–73 · 中层", "越沉越暗；远处只见海嗣的大剪影"),
        ("74 重拍 · 海底", "灯塔暖灯亮起——全片第一个暖色"),
        ("75–76 · 推近", "推向灯光尽头：逆光里站着一个人，脚下一圈暖光"),
        ("77 · 名字卡", "剪影亮起 → 拉开 → MIZUKI 故障出字（§17）"),
    ]
    out = Image.new("RGB", (1920, 160 + 2 * 420), (14, 18, 24))
    d = ImageDraw.Draw(out)
    tc.tracked(d, (40, 30), "片头「像素深海下潜」概念（battle2 第 70–77 小节，约 11.5 s；2D 概念，成片用 Blender 做纵深）", tc.sans(28, 600), tc.INK, 0.02)
    tc.tracked(d, (40, 80), "全部用游戏里的像素素材：标题页海底、灯塔、水母、育母（海嗣）、水月；低分辨率画再 4 倍放大，保持方块像素", tc.sans(20, 400), tc.INK_DIM, 0.02)
    for i, im in enumerate(frames + [card]):
        x, y = (i % 3) * 640, 140 + (i // 3) * 420
        out.paste(im.resize((640, 360), Image.LANCZOS), (x, y))
        tc.tracked(d, (x + 16, y + 366), caps[i][0], tc.sans(20, 700), tc.CYAN, 0.02)
        tc.tracked(d, (x + 16, y + 392), caps[i][1], tc.sans(18, 400), tc.INK, 0.02)
    return out


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    w_off, w_on = world(False), world(True)
    frames = [shot_a(),
              finish(window(w_off, 0)),
              finish(window(w_off, LH + 40)),
              finish(window(w_on, WORLD_H - LH)),
              finish(shot_e(w_on))]
    for n, im in zip("ABCDE", frames):
        im.save(os.path.join(out, "opening_%s.png" % n))
    card_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(out, "opcard_name.png")
    card = Image.open(card_path).convert("RGB") if os.path.exists(card_path) else Image.new("RGB", (1920, 1080))
    board(frames, card).save(os.path.join(out, "opening_board.jpg"), quality=90)
    print("ok", out)
