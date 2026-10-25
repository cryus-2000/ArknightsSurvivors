"""Boss 分幕示意图（docs/142 §3）：每只 Boss 一张，每幕一栏——本体（现有帧条第 0 帧）+ 这一幕的预警形状 / 弹体 / 地面 / 颗粒，
下面写这一幕新多了什么。只是设计示意（程序画的形状，不是游戏截图），不开 Godot。

    python tools/probes/boss_phase_sheets.py            # 输出 build/boss_phase_sheets/<boss>.png
"""
import json, math, os, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
INC = os.path.join(ROOT, "art", "incoming")
OUT = os.path.join(ROOT, "build", "boss_phase_sheets")
PIX = json.load(open(os.path.join(ROOT, "game", "data", "enemy_pixels.json"), encoding="utf-8"))
FONT = os.path.join(ROOT, "game", "fonts", "ui.ttf")
PW, PH = 520, 360          # 每栏画面
TXT_H = 190
BG = (16, 20, 30)
FRAMES = {"prop_ice_stake": 2}   # enemy_pixels.json 里没有尺寸的道具帧条


def font(n):
    return ImageFont.truetype(FONT, n)


def frame0(key, scale):
    p = os.path.join(INC, key + "@2x.png")
    im = Image.open(p).convert("RGBA")
    spec = PIX.get(key, {})
    fs = spec.get("frame_size")
    if key in FRAMES:
        im = im.crop((0, 0, im.width // FRAMES[key], im.height))
    elif fs:
        im = im.crop((0, 0, fs[0], fs[1]))
    else:
        h = im.height
        n = max(1, round(im.width / h))
        im = im.crop((0, 0, im.width // n, h))
    im = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))), Image.NEAREST)
    return im


def tinted(im, tint):
    r, g, b, a = im.split()
    r = r.point(lambda v: min(255, int(v * tint[0])))
    g = g.point(lambda v: min(255, int(v * tint[1])))
    b = b.point(lambda v: min(255, int(v * tint[2])))
    return Image.merge("RGBA", (r, g, b, a))


def rgb(c, k=1.0, a=255):
    return (min(255, int(c[0] * 255 * k)), min(255, int(c[1] * 255 * k)), min(255, int(c[2] * 255 * k)), a)


# ---- 地面纹理（低亮度，0 区域样式）
def ground(d, kind, col, cx, cy, rng):
    if kind == "none":
        return
    if kind == "mist_ring":     # 光环可见化
        for r in range(150, 0, -6):
            d.ellipse((cx - r * 1.7, cy - r * 0.85, cx + r * 1.7, cy + r * 0.85), outline=rgb(col, 0.6, 110), width=2)
    elif kind == "cracks":      # 裂纹从中心铺开
        for _ in range(14):
            a = rng.uniform(0, math.tau); x, y = cx, cy
            for _ in range(7):
                a += rng.uniform(-0.5, 0.5)
                nx, ny = x + math.cos(a) * 24, y + math.sin(a) * 12
                d.line((x, y, nx, ny), fill=rgb(col, 0.55, 150), width=2)
                x, y = nx, ny
    elif kind == "blood":
        for _ in range(9):
            x, y = cx + rng.uniform(-220, 220), cy + rng.uniform(-60, 90)
            r = rng.uniform(10, 26)
            d.ellipse((x - r * 1.6, y - r * 0.6, x + r * 1.6, y + r * 0.6), fill=rgb(col, 0.4, 120))
    elif kind == "sound":
        for r in range(40, 360, 34):
            d.ellipse((cx - r, cy - r * 0.5, cx + r, cy + r * 0.5), outline=rgb(col, 0.5, 70), width=2)
    elif kind == "roots":
        for _ in range(16):
            a = rng.uniform(0, math.tau); x, y = cx, cy + 20
            for i in range(9):
                a += rng.uniform(-0.35, 0.35)
                nx, ny = x + math.cos(a) * 20, y + math.sin(a) * 10
                d.line((x, y, nx, ny), fill=rgb(col, 0.6 - i * 0.04, 170), width=3 if i < 3 else 2)
                x, y = nx, ny
    elif kind == "fog":
        for _ in range(700):
            x, y = rng.uniform(0, PW), rng.uniform(0, PH)
            if any(((x - lx) / 60) ** 2 + ((y - ly) / 30) ** 2 < 1 for lx, ly in ((110, 320), (PW - 110, 320))):
                continue   # 灯柱光圈里是清的
            d.rectangle((x, y, x + 3, y + 3), fill=rgb(col, 0.35, 90))
    elif kind == "frost":
        for _ in range(30):
            x, y = rng.uniform(20, PW - 20), rng.uniform(40, PH - 20)
            s = rng.uniform(6, 14)
            for k in range(3):
                a = k * math.pi / 3
                d.line((x - math.cos(a) * s, y - math.sin(a) * s * 0.5, x + math.cos(a) * s, y + math.sin(a) * s * 0.5), fill=rgb(col, 0.6, 120), width=1)
    elif kind == "abyss":
        for _ in range(10):
            x, y = cx + rng.uniform(-230, 230), cy + rng.uniform(-80, 100)
            w = rng.uniform(30, 70)
            d.polygon([(x - w, y), (x - w * 0.3, y - 8), (x + w, y - 2), (x + w * 0.4, y + 9)], fill=(10, 24, 52, 200), outline=rgb(col, 0.8, 200))
    elif kind == "fractal":
        for _ in range(18):
            x, y = cx + rng.uniform(-240, 240), cy + rng.uniform(-90, 110)
            s = rng.uniform(8, 20)
            d.polygon([(x, y - s), (x + s, y + s * 0.6), (x - s, y + s * 0.6)], outline=rgb(col, 0.6, 140))
    elif kind == "scorch":
        for _ in range(7):
            x, y = cx + rng.uniform(-220, 220), cy + rng.uniform(-60, 100)
            r = rng.uniform(14, 28)
            d.ellipse((x - r, y - r * 0.5, x + r, y + r * 0.5), fill=(28, 18, 14, 200), outline=rgb(col, 0.5, 160))
    elif kind == "cross_cracks":
        for _ in range(5):
            x, y = cx + rng.uniform(-200, 200), cy + rng.uniform(-50, 100)
            d.line((x - 26, y, x + 26, y), fill=rgb(col, 0.6, 170), width=2)
            d.line((x, y - 13, x, y + 13), fill=rgb(col, 0.6, 170), width=2)
    elif kind == "tide":
        for i in range(-6, 7):
            y = cy + 30 + i * 4
            d.line((70, y, PW - 70, y + math.sin(i) * 3), fill=rgb(col, 0.45, 90), width=2)


# ---- 本体颗粒（fx_grains 模板示意：2×2 格的像素颗粒）
def grains(d, kind, col, cx, cy, rng):
    n = {"none": 0}.get(kind, 70)
    for _ in range(n):
        if kind == "rise":
            x, y = cx + rng.gauss(0, 40), cy - rng.uniform(0, 140)
        elif kind == "fall":
            x, y = cx + rng.gauss(0, 60), cy - 100 + rng.uniform(0, 160)
        elif kind == "drip":
            x, y = cx + rng.gauss(0, 35), cy - rng.uniform(-40, 80)
        elif kind == "stream":     # 从场边流向本体
            t = rng.random(); a = rng.choice([-1, 1])
            x, y = cx + a * (60 + 200 * t), cy + 30 - 60 * t * rng.random()
        elif kind == "orbit":
            a = rng.uniform(0, math.tau); r = rng.uniform(60, 90)
            x, y = cx + math.cos(a) * r, cy - 40 + math.sin(a) * r * 0.5
        elif kind == "smoke":
            x, y = cx + rng.gauss(0, 25), cy - 60 - rng.uniform(0, 120)
        elif kind == "pairflow":
            t = rng.random()
            x, y = 130 + (PW - 260) * t, cy - 20 + rng.gauss(0, 4)
        else:
            x, y = cx + rng.gauss(0, 50), cy - rng.uniform(0, 120)
        x, y = int(x) // 2 * 2, int(y) // 2 * 2
        k = rng.uniform(0.8, 1.6)
        c = (60, 60, 60, 220) if kind in ("fall", "smoke") and rng.random() < 0.6 else rgb(col, k, 230)
        d.rectangle((x, y, x + 3, y + 3), fill=c)


# ---- 预警形状
def fill_style(style, col):
    return {"solid": (rgb(col, 1.0, 110), rgb(col, 1.3, 255)), "dark": (rgb(col, 0.45, 120), rgb(col, 1.3, 255)),
            "stripe": (rgb(col, 0.7, 80), rgb(col, 1.2, 255)), "ring": (None, rgb(col, 1.0, 255))}[style]


def circle(d, x, y, r, col, style="solid", pattern=None):
    f, o = fill_style(style, col)
    d.ellipse((x - r, y - r * 0.5, x + r, y + r * 0.5), fill=f, outline=(255, 255, 255, 230), width=2)
    d.ellipse((x - r + 3, y - r * 0.5 + 2, x + r - 3, y + r * 0.5 - 2), outline=o, width=2)
    if pattern == "hex":
        for k in range(3):
            a = k * math.pi / 3
            d.line((x - math.cos(a) * r * 0.8, y - math.sin(a) * r * 0.4, x + math.cos(a) * r * 0.8, y + math.sin(a) * r * 0.4), fill=(255, 255, 255, 200), width=2)
    if pattern == "double":
        d.ellipse((x - r * 0.6, y - r * 0.3, x + r * 0.6, y + r * 0.3), outline=(255, 255, 255, 200), width=2)
    if pattern == "tri":
        d.polygon([(x, y - r * 0.4), (x + r * 0.7, y + r * 0.3), (x - r * 0.7, y + r * 0.3)], outline=(255, 255, 255, 200))


def beam(d, x0, y0, x1, y1, w, col, pattern=None):
    ang = math.atan2(y1 - y0, x1 - x0); nx, ny = -math.sin(ang) * w / 2, math.cos(ang) * w / 2
    d.polygon([(x0 + nx, y0 + ny), (x1 + nx, y1 + ny), (x1 - nx, y1 - ny), (x0 - nx, y0 - ny)], fill=rgb(col, 0.7, 100), outline=(255, 255, 255, 230))
    L = math.hypot(x1 - x0, y1 - y0)
    step = 14 if pattern != "zig" else 10
    for i in range(int(L / step)):
        t = i * step / L
        px, py = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
        if pattern == "eye" and i % 4 == 0:
            d.ellipse((px - 5, py - 3, px + 5, py + 3), outline=(255, 255, 255, 220))
        elif pattern == "zig":
            s = 6 if i % 2 else -6
            d.line((px, py, px + nx / max(1, w / 2) * s, py + ny / max(1, w / 2) * s), fill=(235, 250, 255, 230), width=2)
        else:
            d.line((px + nx * 0.6, py + ny * 0.6, px + nx * 0.6 + (x1 - x0) / L * 6, py + ny * 0.6 + (y1 - y0) / L * 6), fill=rgb(col, 1.3, 200))


def fan(d, x, y, r, a0, half, col, pattern=None):
    pts = [(x, y)] + [(x + math.cos(a0 - half + 2 * half * i / 20) * r, y + math.sin(a0 - half + 2 * half * i / 20) * r * 0.5) for i in range(21)]
    d.polygon(pts, fill=rgb(col, 0.45, 120), outline=(255, 255, 255, 230))
    d.line(pts[1:], fill=rgb(col, 1.3, 255), width=3)
    if pattern == "arcs":
        for k in (0.35, 0.55, 0.75):
            d.arc((x - r * k, y - r * k * 0.5, x + r * k, y + r * k * 0.5), math.degrees(a0 - half), math.degrees(a0 + half), fill=(255, 255, 255, 180), width=2)


def gap_ring(d, x, y, r, gap_a, gap, col, bullets=0, shape="dot", offset=0.0):
    a0, a1 = math.degrees(gap_a + gap / 2), math.degrees(gap_a - gap / 2 + math.tau)
    if bullets:
        for i in range(bullets):
            a = i / bullets * math.tau + offset
            da = (a - gap_a + math.pi) % math.tau - math.pi
            if abs(da) < gap / 2:
                continue
            bx, by = x + math.cos(a) * r, y + math.sin(a) * r * 0.5
            if shape == "tear":
                d.polygon([(bx + math.cos(a) * 9, by + math.sin(a) * 4.5), (bx - 4, by - 4), (bx - 4, by + 4)], fill=rgb(col, 1.3, 255), outline=(255, 255, 255))
            elif shape == "blade":
                d.line((bx - math.sin(a) * 7, by + math.cos(a) * 3.5, bx + math.sin(a) * 7, by - math.cos(a) * 3.5), fill=(240, 250, 255), width=3)
            elif shape == "scale":
                d.polygon([(bx, by - 5), (bx + 5, by), (bx, by + 5), (bx - 5, by)], fill=rgb(col, 1.2, 255), outline=(255, 255, 255))
            else:
                d.ellipse((bx - 5, by - 5, bx + 5, by + 5), fill=rgb(col, 1.3, 255), outline=(255, 255, 255))
    else:
        d.arc((x - r, y - r * 0.5, x + r, y + r * 0.5), a0, a1, fill=rgb(col, 1.0, 255), width=4)
    gx, gy = x + math.cos(gap_a) * r, y + math.sin(gap_a) * r * 0.5
    d.ellipse((gx - 6, gy - 4, gx + 6, gy + 4), outline=(255, 255, 255), width=2)


def spiral(d, x, y, col, arms=2):
    for k in range(arms):
        pts = []
        for i in range(60):
            t = i / 60
            a = k * math.tau / arms + t * 4.0
            r = 20 + t * 210
            pts.append((x + math.cos(a) * r, y + math.sin(a) * r * 0.5))
        for i, (px, py) in enumerate(pts[::3]):
            d.ellipse((px - 4, py - 4, px + 4, py + 4), fill=rgb(col, 1.3, 255), outline=(255, 255, 255))


def players(d, pts):
    for i, (x, y) in enumerate(pts):
        r = 7 if i == 0 else 5
        d.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255) if i == 0 else (180, 190, 210), outline=(0, 0, 0))


def draw_panel(boss, act, rng):
    im = Image.new("RGBA", (PW, PH), BG + (255,))
    d = ImageDraw.Draw(im, "RGBA")
    col = act["col"]
    cx, cy = PW // 2, 150
    ground(d, act.get("ground", "none"), col, cx, cy + 40, rng)
    P = [(cx + 10, cy + 150), (cx - 110, cy + 120), (cx + 140, cy + 125)]   # 队长 + 2 队友
    for sh in act["shapes"]:
        k = sh[0]
        if k == "circle":
            circle(d, *sh[1:])
        elif k == "beam":
            beam(d, *sh[1:])
        elif k == "fan":
            fan(d, *sh[1:])
        elif k == "ring":
            gap_ring(d, *sh[1:])
        elif k == "spiral":
            spiral(d, *sh[1:])
        elif k == "sprite":
            sp = frame0(sh[1], sh[2])
            if len(sh) > 5:
                sp = tinted(sp, sh[5])
            im.alpha_composite(sp, (int(sh[3] - sp.width / 2), int(sh[4] - sp.height)))
        elif k == "text":
            d.text(sh[1], sh[2], font=font(15), fill=(255, 255, 255))
    players(d, P)
    sp = frame0(act["sprite"], act.get("scale", 0.55))
    sp = tinted(sp, act.get("tint", (1, 1, 1)))
    if act.get("ghosts"):
        for gx in (-60, 60, 0):
            g2 = sp.copy(); g2.putalpha(g2.split()[3].point(lambda v: v // 4))
            im.alpha_composite(g2, (int(cx - sp.width / 2 + gx), int(cy + 50 - sp.height - (14 if gx == 0 else 0))))
    if act.get("aura"):
        glow = Image.new("RGBA", im.size, (0, 0, 0, 0))
        ImageDraw.Draw(glow).ellipse((cx - 70, cy - 40, cx + 70, cy + 60), fill=rgb(col, 1.0, 90))
        im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(18)))
    im.alpha_composite(sp, (int(cx - sp.width / 2), int(cy + 50 - sp.height)))
    grains(d, act.get("grains", "none"), col, cx, cy + 30, rng)
    return im


def wrap(text, n):
    out, line = [], ""
    for ch in text:
        line += ch
        if len(line) >= n or ch == "\n":
            out.append(line.rstrip("\n")); line = ""
    if line:
        out.append(line)
    return out


def sheet(key, title, acts):
    rng = random.Random(7)
    W = PW * len(acts) + 10 * (len(acts) + 1)
    H = 56 + PH + TXT_H + 10
    im = Image.new("RGBA", (W, H), (8, 10, 16, 255))
    d = ImageDraw.Draw(im)
    d.text((12, 12), title, font=font(24), fill=(240, 240, 240))
    for i, act in enumerate(acts):
        x = 10 + i * (PW + 10)
        im.alpha_composite(draw_panel(key, act, rng), (x, 56))
        d.rectangle((x, 56, x + PW - 1, 56 + 30), fill=(0, 0, 0, 200))
        d.text((x + 10, 60), act["name"], font=font(18), fill=rgb(act["col"], 1.3))
        y = 56 + PH + 8
        for ln in act["lines"]:
            for w in wrap(ln, 34):
                d.text((x + 6, y), w, font=font(14), fill=(215, 220, 230))
                y += 19
    if acts and acts[-1].get("note"):
        pass
    os.makedirs(OUT, exist_ok=True)
    p = os.path.join(OUT, key + ".png")
    im.convert("RGB").save(p, optimize=True)
    print(p)


CX, CY = PW // 2, 150
PL = (CX + 10, CY + 150)      # 队长
T1, T2 = (CX - 110, CY + 120), (CX + 140, CY + 125)

PURPLE, MAGENTA, VOID = (0.8, 0.4, 1.0), (1.0, 0.35, 0.8), (0.55, 0.25, 0.8)
SHEETS = {
    "paranoia": ("“偏执泡影”（结局一）· 分幕对照", [
        {"name": "一 · 凝望（100–66）", "col": PURPLE, "sprite": "e_paranoia", "grains": "rise",
         "shapes": [("beam", 60, CY + 160, PW - 60, CY + 140, 18, PURPLE), ("beam", 60, CY + 190, PW - 60, CY + 170, 18, PURPLE),
                    ("circle", PL[0], PL[1], 34, PURPLE, "solid"), ("ring", CX, CY + 40, 200, math.pi / 2, 0.5, PURPLE, 30)],
         "lines": ["悬浮远程。凝视 = 两道平行光束（横移躲）；叠影 = 队长脚下 3 个实心圈；泡影环 = 圆泡弹缺口环。", "特效：淡紫雾颗粒缓缓上升。地面无变化。"]},
        {"name": "二 · 狂望（66–33）", "col": MAGENTA, "sprite": "e_paranoia", "tint": (1.15, 0.8, 1.05), "ghosts": True, "grains": "rise", "ground": "mist_ring",
         "shapes": [("beam", 80, CY + 60, PW - 60, CY + 230, 18, MAGENTA, "eye"), ("beam", PW - 80, CY + 60, 60, CY + 230, 18, MAGENTA, "eye"),
                    ("circle", T1[0], T1[1], 30, MAGENTA, "solid", "double"), ("circle", T2[0], T2[1], 30, MAGENTA, "solid", "double"), ("circle", PL[0], PL[1], 30, MAGENTA, "solid", "double"),
                    ("ring", CX, CY + 40, 215, -math.pi / 2, 0.5, MAGENTA, 26, "tear")],
         "lines": ["招式换形：凝视改成在队长身上交叉的 X（斜出躲），光束带「眼纹」；叠影分落队长和两名队友，圈改成同心双环；泡影环弹改泪滴形。", "特效：身后常驻 3 个半透明残影；光环 r260 画成低亮度同心纹。", "转场：本体分出 3 个残影向外滑开再归位（0.6 秒，单发）。"]},
        {"name": "三 · 失声（33–0）", "col": VOID, "sprite": "e_paranoia_phase2", "scale": 0.5, "grains": "fall", "ground": "cracks",
         "shapes": [("fan", CX, CY + 40, 230, math.pi / 2, 0.8, VOID, "arcs"), ("ring", CX, CY + 40, 230, 0.3, 0.5, VOID, 30), ("ring", CX, CY + 40, 180, 2.4, 0.5, VOID, 26)],
         "lines": ["落地近战。呼号 = 扇形里画同心声波弧；泡影环改 2 波错位缺口（每次都放）；凝视 3 道。", "特效：暗紫黑配色，黑色颗粒往下落（「失声」）；地面从落点铺开紫黑裂纹 r300。", "转场：坠地砸开地面，裂纹由中心铺开 1 秒 + 一圈尘颗粒。"]},
        {"name": "茧后 · 重生", "col": (0.9, 0.75, 1.0), "sprite": "e_paranoia_phase2", "scale": 0.5, "aura": True, "grains": "orbit", "ground": "cracks",
         "shapes": [("circle", PL[0], PL[1], 26, (0.9, 0.75, 1.0), "solid", "double"), ("circle", T1[0], T1[1], 26, (0.9, 0.75, 1.0), "solid", "double"), ("circle", T2[0], T2[1], 26, (0.9, 0.75, 1.0), "solid", "double"),
                    ("circle", PL[0] - 60, PL[1] - 30, 26, (0.9, 0.75, 1.0), "solid", "double"), ("circle", PL[0] + 70, PL[1] - 20, 26, (0.9, 0.75, 1.0), "solid", "double"),
                    ("fan", CX, CY + 40, 200, math.pi / 2 + 0.9, 0.6, (0.9, 0.75, 1.0), "arcs")],
         "lines": ["原作第二形态 5 目标：叠影 5 重分落 5 处；呼号 2 段（第二段转 60°）。", "特效：亮紫白芯，茧壳碎片颗粒绕身旋转。"]},
    ]),
}

TEAL, BLOODTEAL, WHITETEAL = (0.2, 1.0, 0.85), (1.0, 0.3, 0.38), (0.75, 1.0, 0.95)
SHEETS["ishar"] = ("伊莎玛拉，腐化之心（结局三）· 分幕对照", [
    {"name": "一 · 大群（变身后 100–66）", "col": TEAL, "sprite": "e_ishar_t", "scale": 0.42, "grains": "rise",
     "shapes": [("circle", PL[0] - 90, PL[1] - 10, 34, TEAL), ("circle", PL[0], PL[1], 34, TEAL), ("circle", PL[0] + 90, PL[1] - 10, 34, TEAL),
                ("beam", CX, CY + 40, 40, CY + 210, 12, TEAL), ("beam", CX, CY + 40, PW - 40, CY + 210, 12, TEAL)],
     "lines": ["四招轮转：三点落击（实心圈）/ 三线扫射（直线）/ 大群之歌（缺口环）/ 撕咬（扇形）。", "特效：青色水雾颗粒上升。"]},
    {"name": "二 · 濒死强化（66–33）", "col": BLOODTEAL, "sprite": "e_ishar_t", "scale": 0.42, "tint": (1.2, 0.8, 0.85), "grains": "drip", "ground": "blood",
     "shapes": [("circle", 90 + i * 85, CY + 190 - abs(i - 2) * 25, 22, BLOODTEAL, "solid") for i in range(5)] +
               [("fan", CX, CY + 40, 190, math.pi / 2 - 0.5, 0.5, BLOODTEAL), ("fan", CX, CY + 40, 190, math.pi / 2 + 0.5, 0.5, BLOODTEAL),
                ("sprite", "e_tear", 0.5, 90, CY + 70), ("sprite", "e_tear", 0.5, PW - 90, CY + 70)],
     "lines": ["招式换形：三点落击改「泪落」——5 个小落点沿弧线依次落下；撕咬改 2 段交叉剪（X 形两扇）。过卡点召 2 个泪，泪在场就每 6 秒放共鸣直线。", "特效：红青双色（预警外缘红），红色体液颗粒滴落、落地留红斑。", "转场：体表裂纹亮一次，2 个泪从本体射出落地。"]},
    {"name": "三 · 回声（33–0）", "col": WHITETEAL, "sprite": "e_ishar_t", "scale": 0.42, "tint": (1.1, 1.15, 1.15), "aura": True, "grains": "orbit", "ground": "sound",
     "shapes": [("ring", CX, CY + 40, 150, 1.2, 0.6, WHITETEAL, 22, "scale"), ("ring", CX, CY + 40, 230, 2.25, 0.6, WHITETEAL, 30, "scale", 0.1),
                ("beam", CX, CY + 40, PL[0], PL[1], 10, WHITETEAL), ("beam", CX, CY + 40, T1[0], T1[1], 10, WHITETEAL), ("beam", CX, CY + 40, T2[0], T2[1], 10, WHITETEAL)],
     "lines": ["招式换形：三线扫射改分目标，三条线各锁队长和两名队友；大群之歌改 2 圈先后扩散、缺口错开 60°，弹改鳞片形。", "特效：白青配色；全场浮出同心声纹环（低亮度，随歌扩散）。", "转场：一圈不伤人的声波从本体扩到屏边（单次）。"]},
])

GREEN, GOLDGREEN, WHITEGREEN = (0.55, 1.0, 0.65), (0.9, 1.0, 0.4), (0.85, 1.0, 0.85)
SHEETS["izumik"] = ("伊祖米克，生态泉源（结局四）· 分幕对照", [
    {"name": "一 · 阐释（100–66）", "col": GREEN, "sprite": "e_izumik", "scale": 0.45, "grains": "rise", "ground": "roots",
     "shapes": [("circle", PL[0] + dx, PL[1] - abs(dx) * 0.2, 28, GREEN) for dx in (-120, -60, 0, 60, 120)] + [("ring", CX, CY + 40, 190, 0.9, 0.5, GREEN, 30)],
     "lines": ["潮汐坠落（朝队长的弧排落点）/ 解读旋涡（缺口环）/ 分享（扇形）；75% 强制一次震撼。", "特效：绿色颗粒上升；扎根根须。"]},
    {"name": "二 · 学习（66–33）", "col": GOLDGREEN, "sprite": "e_izumik", "scale": 0.45, "tint": (1.1, 1.1, 0.8), "grains": "stream", "ground": "roots",
     "shapes": [("spiral", CX, CY + 40, GOLDGREEN, 2), ("sprite", "e_offspring", 0.4, 60, CY + 120), ("sprite", "e_offspring", 0.4, PW - 60, CY + 110),
                ("sprite", "e_offspring", 0.4, 100, CY + 200), ("sprite", "e_offspring", 0.4, PW - 110, CY + 205)],
     "lines": ["招式换形：解读旋涡从缺口环改成 2 条慢转的螺旋弹臂（从臂间走）；子代每 12 秒从场边走向本体，吸收一只伤害 +5%（不回血）。", "特效：金绿配色；颗粒流从子代流进本体；身上亮点按吸收层数 1–4 圈点亮。", "转场：根须向四周猛长一次，子代从场边出现。"]},
    {"name": "三 · 分享（33–0）", "col": WHITEGREEN, "sprite": "e_izumik", "scale": 0.45, "aura": True, "grains": "fall", "ground": "fog",
     "shapes": [("circle", 110, CY + 170, 52, (1.0, 0.9, 0.5), "ring"), ("circle", PW - 110, CY + 170, 52, (1.0, 0.9, 0.5), "ring"),
                ("text", (150, 90), "全场蓄力：预告 2–4.5 秒 + 1.6 秒"), ("fan", CX, CY + 40, 200, math.pi / 2 - 0.9, 0.35, WHITEGREEN),
                ("fan", CX, CY + 40, 200, math.pi / 2, 0.35, WHITEGREEN), ("fan", CX, CY + 40, 200, math.pi / 2 + 0.9, 0.35, WHITEGREEN)],
     "lines": ["新招：分享·全场——灯柱光圈内完全不受伤；先预告（副标题 + 光圈渐亮 + 本体停步）再蓄力，最少 3.6 秒，期间不出别的招。扇形分享改三叶扇。", "特效：全场低亮度绿雾，只有灯柱光圈是清的（安全区一眼可见）；绿色颗粒从天上飘落。", "转场：本体开花一次（单次脉冲），灯柱光圈同步渐亮。"]},
])

ICE, FROST, ABYSS, REBORN = (0.55, 0.85, 1.0), (0.8, 0.95, 1.0), (0.3, 0.5, 0.95), (0.6, 0.8, 1.0)
SHEETS["knight_boss"] = ("最后的骑士（结局二）· 分幕对照", [
    {"name": "一 · 骑士（100–66）", "col": ICE, "sprite": "e_knight", "scale": 0.8, "grains": "rise",
     "shapes": [("beam", CX - 40, CY + 50, PL[0] + 60, PL[1] + 10, 30, ICE), ("circle", CX - 150, CY + 120, 70, ICE, "dark")],
     "lines": ["冲锋（直线）/ 长枪连刺（扇形）/ 寒冷（圆，受击触发）/ 冰线 + 追击。", "特效：枪尖冒白色冷气颗粒；寒冷留冰面。"]},
    {"name": "二 · 冰原（66–33）", "col": FROST, "sprite": "e_knight", "scale": 0.8, "tint": (1.05, 1.1, 1.2), "grains": "orbit", "ground": "frost",
     "shapes": [("beam", CX - 40, CY + 50, PL[0] + 60, PL[1] + 10, 30, FROST, "zig"), ("circle", CX - 150, CY + 120, 70, FROST, "dark", "hex"),
                ("sprite", "prop_ice_stake", 0.5, 90, CY + 150), ("sprite", "prop_ice_stake", 0.5, PW - 90, CY + 140), ("sprite", "prop_ice_stake", 0.5, CX + 150, CY + 40)],
     "lines": ["招式换形：冲锋路径画成锯齿冰棱带；寒冷圆改六角雪花纹；冰枪桩 3 根（引它撞桩）；寒冷 4 秒，挂寒冷时下一击 ×1.3（图标变色）。", "特效：白蓝更亮，盔甲结霜（颗粒绕身）；全场霜纹从桩向外扩散。", "转场：长枪插地，3 根冰枪桩破土，霜纹铺开。"]},
    {"name": "三 · 掷枪（33–0）", "col": ABYSS, "sprite": "e_knight", "scale": 0.8, "tint": (0.85, 0.95, 1.2), "grains": "drip", "ground": "abyss",
     "shapes": [("beam", CX + 30, CY + 20, PW - 50, CY + 200, 16, ABYSS), ("sprite", "prop_ice_stake", 0.5, PW - 60, CY + 205),
                ("beam", CX - 40, CY + 50, CX - 160, CY + 180, 28, ABYSS), ("beam", CX - 160, CY + 180, PL[0], PL[1], 28, ABYSS)],
     "lines": ["新招：长枪掷击——直线预警 1 秒，落地处立一根新冰枪桩（最多 4 根）；冲锋改 2 连折线（第二冲转角）。", "特效：深海蓝 + 冰白（「唯有海洋」）；冰面裂开露出深色海水纹；本体滴落冰水颗粒。", "转场：拔枪掷出第一根，落地立桩。"]},
    {"name": "重生 · 冲锋形态", "col": REBORN, "sprite": "e_knight_walk_charge", "scale": 0.75, "aura": True, "grains": "stream", "ground": "frost",
     "shapes": [("beam", 40, CY + 120, PW - 40, CY + 120, 26, REBORN), ("beam", PW - 40, CY + 150, 40, CY + 180, 26, REBORN), ("beam", 40, CY + 210, PW - 40, CY + 200, 26, REBORN),
                ("ring", CX, CY + 40, 150, -math.pi / 2, 0.6, REBORN)],
     "lines": ["原作冲锋形态：平举长枪慢走（移速 ×0.5），靠冲锋三连追人；长枪回旋（缺口环）；旧桩碎掉重立 3 根。", "特效：现有平举长枪帧条 + 身后残影拖尾。"]},
])

STEEL, FRACT = (0.7, 0.8, 0.95), (0.55, 0.65, 1.0)
SHEETS["path"] = ("塑路者（中期）· 分幕对照", [
    {"name": "一 · 探路（100–50）", "col": STEEL, "sprite": "e_path", "scale": 0.5, "grains": "rise",
     "shapes": [("beam", CX, CY + 50, PL[0] - 40, PL[1] + 20, 26, STEEL), ("circle", CX, CY + 60, 80, STEEL), ("fan", CX, CY + 40, 200, 0.4, 0.8, STEEL)],
     "lines": ["冲撞（直线）/ 震地（圆）/ 分形塑路（扇形）；每第 3 招附带召 1 个分形（原作）。", "特效：钢灰碎屑颗粒。"]},
    {"name": "二 · 订正（50–0）", "col": FRACT, "sprite": "e_path", "scale": 0.5, "tint": (0.9, 0.95, 1.25), "grains": "orbit", "ground": "fractal",
     "shapes": [("beam", CX, CY + 50, 90, CY + 190, 26, FRACT), ("beam", 90, CY + 190, PW - 80, CY + 210, 26, FRACT),
                ("circle", CX - 60, CY + 110, 34, FRACT, "solid", "tri"), ("circle", CX - 110, CY + 150, 34, FRACT, "solid", "tri"), ("circle", CX - 160, CY + 185, 34, FRACT, "solid", "tri"),
                ("ring", CX, CY + 40, 170, 1.0, 0.6, FRACT, 12, "blade")],
     "lines": ["招式换形：冲撞 2 连改直角折线；震地单圈改沿冲撞线 3 连落点；新招订正（刃弹缺口环）；受击召分形（上限 6）、猎核。", "特效：分形紫青配色，预警填三角分形纹；身边几何方块颗粒环绕；冲撞路径留几何裂纹。", "转场：本体碎成分形碎片再拼回 + 中期横幅「订正」。"]},
])

ORANGE, DARKGOLD = (1.0, 0.45, 0.2), (0.95, 0.7, 0.3)
SHEETS["iberia"] = ("圣徒伊比利亚（中期）· 分幕对照", [
    {"name": "一 · 圣徒（100–50）", "col": ORANGE, "sprite": "e_saint_dark", "scale": 0.7, "grains": "none",
     "shapes": [("beam", CX, CY + 20, PL[0], PL[1], 14, ORANGE), ("circle", T1[0], T1[1], 40, ORANGE), ("fan", CX, CY + 40, 200, math.pi / 2 + 0.6, 0.5, ORANGE)],
     "lines": ["手炮（直线）/ 轰击（圆）/ 散射（扇形）；弹药 1，装填可打断（5 秒破绽）。", "特效：无常驻颗粒。"]},
    {"name": "二 · 延生（50–0）", "col": DARKGOLD, "sprite": "e_saint_dark", "scale": 0.7, "tint": (1.1, 0.95, 0.75), "grains": "smoke", "ground": "scorch",
     "shapes": [("circle", PL[0] + dx, PL[1] + dy, 30, DARKGOLD, "solid", "tri") for dx, dy in ((0, -10), (-70, 20), (70, 20))] +
               [("ring", CX, CY + 40, 140, 2.0, 0.55, DARKGOLD, 18), ("fan", CX, CY + 40, 210, math.pi / 2 + 0.7, 0.45, DARKGOLD)],
     "lines": ["招式换形：轰击改三连曲射，落点呈三角；散射改 2 波错位；装填 2.2→1.4 秒，清膛（缺口环）每轮必出。", "特效：暗金配色，身上冒黑烟颗粒；弹坑留焦痕。", "转场：举炮朝天一发信号弹（金色光点升起后消失）。"]},
])

GOLD, WHITEGOLD = (1.0, 0.76, 0.3), (1.0, 0.9, 0.65)
SHEETS["carmen"] = ("圣徒卡门（中期）· 分幕对照", [
    {"name": "一 · 圣徒（100–50）", "col": GOLD, "sprite": "e_saint", "scale": 0.7, "grains": "none",
     "shapes": [("beam", 40, CY + 140, PW - 40, CY + 160, 10, GOLD), ("ring", CX, CY + 40, 200, 0.6, 0.5, GOLD, 29)],
     "lines": ["狙击（细直线）/ 炮身横扫（扇形）/ 环射（3 缺口环）/ 退避跳；弹药 3。"]},
    {"name": "二 · 守誓（50–0）", "col": WHITEGOLD, "sprite": "e_saint", "scale": 0.7, "tint": (1.15, 1.1, 0.95), "grains": "rise", "ground": "cross_cracks",
     "shapes": [("beam", 40, CY + 100, PL[0], PL[1], 10, WHITEGOLD), ("beam", PW - 40, CY + 100, PL[0], PL[1], 10, WHITEGOLD), ("beam", CX, CY + 30, PL[0], PL[1], 10, WHITEGOLD),
                ("ring", CX, CY + 40, 170, 0.6, 0.5, WHITEGOLD, 26), ("ring", CX, CY + 40, 230, 1.5, 0.5, WHITEGOLD, 32), ("circle", T1[0], T1[1], 36, WHITEGOLD)],
     "lines": ["招式换形：狙击三连改两侧交叉；环射改 2 波（0.8 秒后第二波缺口错开）；每次打空都进近战段，必出炮身砸击（圆）。", "特效：白金光尘；砸击留十字裂纹。", "转场：炮身拄地，一圈金色尘环。"]},
])

BTEAL, AGREEN, IBLUE = (0.25, 0.85, 0.9), (0.5, 0.95, 0.6), (0.65, 0.75, 1.0)
SHEETS["tide_pair"] = ("接潮组（主教 + 蔑死体 / 斥亡体，中期）· 分幕对照", [
    {"name": "一（各自为战）", "col": BTEAL, "sprite": "e_bishop", "scale": 0.7, "grains": "none",
     "shapes": [("sprite", "e_archon", 0.6, 110, CY + 40), ("sprite", "e_immortal", 0.6, PW - 110, CY + 40),
                ("circle", PL[0] - 50, PL[1] - 20, 30, BTEAL), ("circle", PL[0], PL[1], 30, BTEAL), ("circle", PL[0] + 50, PL[1] - 20, 30, BTEAL),
                ("beam", 110, CY + 30, CX, CY + 30, 8, BTEAL)],
     "lines": ["主教：潮汐柱（直线三圈）/ 交错潮环 / 统一（两体连线）；蔑死体：横扫 / 吐息 / 跃击；斥亡体：连斩 / 旋刃 / 迸发。"]},
    {"name": "二 · 统一（任一具过 50%）", "col": BTEAL, "sprite": "e_bishop", "scale": 0.7, "tint": (0.95, 1.1, 1.15), "grains": "pairflow", "ground": "tide",
     "shapes": [("sprite", "e_archon", 0.6, 110, CY + 40, (1.0, 1.15, 0.95)), ("sprite", "e_immortal", 0.6, PW - 110, CY + 40, (0.95, 1.0, 1.2)),
                ("beam", 110, CY + 30, PW - 110, CY + 30, 14, BTEAL), ("beam", 110, CY + 30, PL[0], PL[1], 14, AGREEN), ("beam", PW - 110, CY + 30, PL[0], PL[1], 14, IBLUE),
                ("ring", 110, CY + 40, 70, 0.5, 0.7, AGREEN, 10, "blade")],
     "lines": ["招式换形：统一改三角——两体连线 + 各自连向队长，往三角外斜走；潮环 2 波错位；蔑死体裂潮独立成招（刃环）、横扫 3 段；斥亡体常驻轻狂暴 + 残影。", "特效：两体的预警互带对方的颜色边（一个意志）；两体之间一条低亮度潮水带，水滴颗粒沿连线流动。", "转场：两体同时抬头，连线由暗渐亮建立。"]},
])


if __name__ == "__main__":
    for k, (t, acts) in SHEETS.items():
        sheet(k, t, acts)
