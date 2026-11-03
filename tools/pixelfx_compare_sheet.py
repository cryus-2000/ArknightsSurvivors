# -*- coding: utf-8 -*-
"""新旧特效静态关键帧对照图（漏项 #28：每人先交一个代表招式的对照图过用户这一关，再铺其余招式）。

每对一行：左边旧版、右边新版，各取同样比例位置的几帧（缺省 4 帧：起手 / 命中 / 扩散 / 余韵），按原点对齐、整数放大，深海底色。
新版有 <名>_deco 时先画装饰再画核心（同游戏）；打包帧条（data/px_frames.json）按表取帧，等宽帧条按帧中心；@2x 按逻辑尺寸缩回。
旧 / 新各从一个 git 提交读（帧条、art.gd 的 V6_FRAMES、px_frames.json），缺省旧 = main、新 = 工作区。
用法：
  python tools/pixelfx_compare_sheet.py --pair fx_skadi_slash=fx_skadi_ul_slash --pair fx_skadi_ul_spin [--old-rev main] [--new-rev 工作区]
         [--frames 4] [--zoom 2] [--out "Claude outputs/xxx.png"]
  --pair 旧名=新名；只写一个名字 = 同名帧条新旧两版对照。
"""
import argparse, io, json, os, re, subprocess
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
BG = (6, 20, 42)
FG = (220, 232, 240)
DIM = (120, 140, 160)


def font(sz):
    for p in (os.path.join(ROOT, "game", "fonts", "ui.ttf"), os.path.join(ROOT, "game", "fonts", "ui_fallback.otf"), "C:/Windows/Fonts/msyh.ttc"):
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


class Src:
    """一个版本：rev = None 读工作区，否则 git show"""

    def __init__(self, rev):
        self.rev = rev
        art = self.read("game/scripts/art.gd")
        self.v6 = {m.group(1): (int(m.group(2)), float(m.group(3))) for m in re.finditer(r'"([A-Za-z0-9_]+)": \[(\d+), ([\d.]+)\]', art.decode("utf-8") if art else "")}
        pf = self.read("game/data/px_frames.json")
        self.pf = json.loads(pf.decode("utf-8")) if pf else {}

    def read(self, rel):
        if self.rev is None:
            p = os.path.join(ROOT, rel)
            return open(p, "rb").read() if os.path.exists(p) else None
        r = subprocess.run(["git", "-C", ROOT, "show", "%s:%s" % (self.rev, rel)], capture_output=True)
        return r.stdout if r.returncode == 0 else None

    def frames(self, name):
        """[(RGBA 帧, 原点 (x, y), 放大倍率 1/hires)]；没有这张图返回 None"""
        for hx, hi in (("@2x", 2.0), ("", 1.0)):
            b = self.read("game/art/fx/%s%s.png" % (name, hx))
            if b:
                break
        else:
            return None
        im = Image.open(io.BytesIO(b)).convert("RGBA")
        n = self.v6.get(name, (1, 10.0))[0]
        out = []
        if name in self.pf:
            for x, y, w, h, ax, ay in self.pf[name]:
                out.append((im.crop((x, y, x + max(w, 1), y + max(h, 1))) if w else Image.new("RGBA", (1, 1)), (ax, ay), 1.0 / hi))
        else:
            fw = im.width // n
            for i in range(n):
                out.append((im.crop((i * fw, 0, (i + 1) * fw, im.height)), (fw / 2.0, im.height / 2.0), 1.0 / hi))
        return out


def pick(n, k):
    """k 个关键帧：起手 / 命中 / 扩散 / 余韵按比例取"""
    fr = [0.08, 0.25, 0.5, 0.8] if k == 4 else [i / max(1, k - 1) * 0.9 for i in range(k)]
    return [min(n - 1, int(round(f * (n - 1)))) for f in fr]


def layers(src, name):
    core = src.frames(name)
    if core is None:
        return None
    deco = src.frames(name + "_deco")
    return [deco, core] if deco else [core]


def render_cell(lays, i, zoom, box):
    """box = (左, 上, 右, 下) 相对原点的范围（逻辑像素）；按原点叠层"""
    w, h = int((box[2] - box[0]) * zoom), int((box[3] - box[1]) * zoom)
    cv = Image.new("RGBA", (w, h), BG + (255,))
    for lay in lays:
        f, (ax, ay), s = lay[min(i, len(lay) - 1)]
        k = s * zoom
        fz = f.resize((max(1, round(f.width * k)), max(1, round(f.height * k))), Image.NEAREST)
        cv.alpha_composite(fz, (int(round(-box[0] * zoom - ax * k)), int(round(-box[1] * zoom - ay * k))))
    return cv


def extent(lays, idx):
    x0 = y0 = 1e9
    x1 = y1 = -1e9
    for lay in lays:
        for i in idx:
            f, (ax, ay), s = lay[min(i, len(lay) - 1)]
            bb = f.getchannel("A").point(lambda a: 255 if a > 10 else 0).getbbox()
            if bb:
                x0, y0 = min(x0, (bb[0] - ax) * s), min(y0, (bb[1] - ay) * s)
                x1, y1 = max(x1, (bb[2] - ax) * s), max(y1, (bb[3] - ay) * s)
    return (x0, y0, x1, y1) if x1 > x0 else (-8, -8, 8, 8)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pair", action="append", required=True)
    ap.add_argument("--old-rev", default="main")
    ap.add_argument("--new-rev", default="")
    ap.add_argument("--frames", type=int, default=4)
    ap.add_argument("--zoom", type=int, default=2)
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "pixelfx_compare_sheet.png"))
    a = ap.parse_args()
    old, new = Src(a.old_rev), Src(a.new_rev or None)
    f_t, f_s = font(22), font(15)
    rows = []
    for pr in a.pair:
        on, nn = pr.split("=", 1) if "=" in pr else (pr, pr)
        lo, ln = layers(old, on), layers(new, nn)
        cells = []
        for lays, nm, tag in ((lo, on, "旧 " + (a.old_rev or "工作区")), (ln, nn, "新 " + (a.new_rev or "工作区"))):
            if lays is None:
                cells.append((tag, nm, [], None))
                continue
            idx = pick(len(lays[-1]), a.frames)
            cells.append((tag, nm, idx, lays))
        # 新旧同一行共用范围，大小一眼可比
        boxes = [extent(c[3], c[2]) for c in cells if c[3]]
        box = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes)) if boxes else (-8, -8, 8, 8)
        box = (box[0] - 6, box[1] - 6, box[2] + 6, box[3] + 6)
        rows.append((cells, box))
    pad, head = 12, 54
    cw = lambda box: int((box[2] - box[0]) * a.zoom)
    ch = lambda box: int((box[3] - box[1]) * a.zoom)
    W = max(pad + 2 * (a.frames * (cw(b) + pad)) + pad * 3 for _, b in rows)
    H = sum(head + ch(b) + pad * 2 for _, b in rows) + pad
    sheet = Image.new("RGBA", (W, H), BG + (255,))
    d = ImageDraw.Draw(sheet)
    y = pad
    for cells, box in rows:
        x = pad
        for tag, nm, idx, lays in cells:
            d.text((x, y), tag, font=f_t, fill=FG)
            d.text((x, y + 28), nm + ("" if lays else "（没有这张图）"), font=f_s, fill=DIM)
            for j, i in enumerate(idx):
                c = render_cell(lays, i, a.zoom, box)
                sheet.alpha_composite(c, (x + j * (cw(box) + pad), y + head))
                d.text((x + j * (cw(box) + pad) + 4, y + head + 4), "帧 %d/%d" % (i + 1, len(lays[-1])), font=f_s, fill=DIM)
            x += a.frames * (cw(box) + pad) + pad * 2
        y += head + ch(box) + pad * 2
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    sheet.convert("RGB").save(a.out)
    print(a.out, sheet.size)


if __name__ == "__main__":
    main()
