"""标题 Logo「方舟幸存者」生成器（像素风，与旧「水月」Logo 同一套画法）。

用法：python tools/make_logo.py [输出路径] [--theme=deep_sea]
在 1× 画布（260×65）上画，最后 ×2 最近邻放大成 520×130，写到 art/incoming/logo.png。

画法：
- 「方舟」大字：竖向渐变（浅青 → 青 → 深青），1px 深色描边 + 左上 1px 高光；
  水线以下的部分沉在水里（深蓝、逐行左右错位），水线是一排浅青虚线。
- 「幸存者」小字：同色渐变，下方一条细线 + 末端菱形。
- 徽记：四枚菱形排成 3+1 阵型（三枚青色围着一枚金色 = 三名干员护着博士），放在「舟」的右上角。
- THEMES 里按地图换主色；以后加地图只需加一组颜色。
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "game" / "fonts" / "ui.ttf"

THEMES = {
    "deep_sea": {
        "top": (226, 252, 252), "mid": (96, 226, 226), "low": (48, 168, 200),
        "sub_top": (20, 88, 150), "sub_low": (14, 58, 118),
        "line": (190, 248, 250), "outline": (12, 26, 40), "gold": (250, 206, 120), "dot": (170, 240, 250),
    },
}

W, H = 260, 65
WATER = 52        # 水线（1× 坐标）


def lerp(a, b, k):
    return tuple(int(round(a[i] + (b[i] - a[i]) * k)) for i in range(3))


def text_mask(txt, size, pos):
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).text(pos, txt, font=ImageFont.truetype(str(FONT), size), fill=255)
    return m.point(lambda v: 255 if v >= 128 else 0)


def paint(img, mask, th, y0, y1, water):
    """按 mask 上色：y0..y1 竖向渐变；water=True 时水线以下沉入水中。"""
    px = img.load()
    mk = mask.load()
    for y in range(H):
        for x in range(W):
            if not mk[x, y]:
                continue
            if water and y > WATER:
                k = (y - WATER) / max(1, H - WATER)
                c = lerp(th["sub_top"], th["sub_low"], k)
            else:
                k = min(1.0, max(0.0, (y - y0) / max(1, y1 - y0)))
                c = lerp(th["top"], th["mid"], k * 2) if k < 0.5 else lerp(th["mid"], th["low"], (k - 0.5) * 2)
            px[x, y] = c + (255,)


def ripple(img, mask):
    """水线以下逐行左右错位 ±1，像水里的倒影。"""
    src = img.copy()
    sp, mp = src.load(), mask.load()
    px = img.load()
    for y in range(WATER + 1, H):
        dx = (1, 0, -1, 0)[(y - WATER) % 4]
        for x in range(W):
            if mp[x, y]:
                px[x, y] = (0, 0, 0, 0)
        for x in range(W):
            if mp[x, y] and 0 <= x + dx < W:
                px[x + dx, y] = sp[x, y]


def outline_and_highlight(img, th):
    src = img.copy()
    sp = src.load()
    px = img.load()
    for y in range(H):
        for x in range(W):
            if sp[x, y][3]:
                # 左上邻是空 → 1px 高光
                if (x > 0 and not sp[x - 1, y][3]) or (y > 0 and not sp[x, y - 1][3]):
                    if y <= WATER:
                        px[x, y] = lerp(sp[x, y][:3], (255, 255, 255), 0.45) + (255,)
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and sp[nx, ny][3]:
                    px[x, y] = th["outline"] + (255,)
                    break


def diamond(d, cx, cy, r, col, edge):
    d.polygon([(cx, cy - r - 1), (cx + r + 1, cy), (cx, cy + r + 1), (cx - r - 1, cy)], fill=edge)
    d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=col)


def build(theme="deep_sea"):
    th = THEMES[theme]
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    # 「方舟」：大字，底部压过水线
    big = text_mask("方舟", 60, (7, -14))
    paint(img, big, th, 6, WATER, True)
    ripple(img, big)
    # 「幸存者」：小字，放在右侧中部
    small = text_mask("幸存者", 26, (140, 10))
    paint(img, small, th, 18, 40, False)
    outline_and_highlight(img, th)
    d = ImageDraw.Draw(img)
    # 水线：一排浅青虚线（只横过大字）
    for x in range(2, 136, 1):
        if (x // 6) % 3 != 2:
            img.putpixel((x, WATER), th["line"] + (255,))
    # 小字下方细线 + 末端菱形
    d.line([(140, 47), (232, 47)], fill=th["mid"] + (255,), width=1)
    diamond(d, 236, 47, 2, th["line"] + (255,), th["outline"] + (255,))
    # 徽记：3+1 菱形阵（舟的右上）
    ex, ey = 128, 12
    for dx, dy in ((0, -7), (-8, 3), (8, 3)):
        diamond(d, ex + dx, ey + dy, 3, th["mid"] + (255,), th["outline"] + (255,))
    diamond(d, ex, ey, 2, th["gold"] + (255,), th["outline"] + (255,))
    # 零星水光点
    for (x, y) in ((44, 30), (140, 24), (28, 60), (122, 63), (206, 58), (214, 26)):
        img.putpixel((x, y), th["dot"] + (255,))
    return img.resize((W * 2, H * 2), Image.NEAREST)


if __name__ == "__main__":
    out = ROOT / "art" / "incoming" / "logo.png"
    theme = "deep_sea"
    for a in sys.argv[1:]:
        if a.startswith("--theme="):
            theme = a[8:]
        else:
            out = Path(a)
    build(theme).save(out)
    print("wrote", out)
