"""认知塑造树样图第二轮 B2 / D2（docs/125 §8.7，10-22 用户：几何要「不规则」、流动要「无规则」，参考莱茵生命实验室图纸感）。

图谱与左栏沿用 meta_tree_mock.py 的 B / D，只换背景层：不规则多边形碎片（3–8 边 / 切角板块，40–300 px，1 px 青白描边 + 5–10% 填充，
少量带内部细线、刻度与小数字标注），每片独立慢漂 + 自旋（0.5–3 px/s、±2°/s），速度按两组慢正弦相乘起伏 → 偶有停顿与加速；
另撒零散十字准星 / 比例尺小标注随最近的碎片走。靠近选中节点时提亮。
用法：python -X utf8 tools/probes/meta_tree_mock2.py
输出：主仓库 build/ak_mock/meta_tree_{B2,D2}.png、meta_tree_{B2,D2}_flow.gif（流速 ×6）/ _flow.png、总览 meta_tree_sheet2.jpg
"""
import math
import os
import random
import sys
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meta_tree_mock as mt  # noqa: E402

W, H = mt.W, mt.H
SX, SY = mt.POS[mt.SEL]


class Frag:
    def __init__(self, rnd, i):
        self.size = math.exp(rnd.uniform(math.log(40), math.log(300)))   # 40–300 px 对数均匀：小片多、大片少但看得到
        self.x, self.y = rnd.uniform(-100, W + 100), rnd.uniform(-100, H + 100)
        kind = rnd.random()
        r = self.size / 2
        if kind < 0.3:   # 切角板块：矩形随机切掉 1–2 个角
            w, h = r * rnd.uniform(0.8, 1.4), r * rnd.uniform(0.35, 0.9)
            c1, c2 = r * rnd.uniform(0.1, 0.35), r * rnd.uniform(0.0, 0.3)
            self.pts = [(-w + c1, -h), (w, -h), (w, h - c2), (w - c2, h), (-w, h), (-w, -h + c1)]
        else:            # 不规则多边形：3–8 边，角度与半径都抖
            n = rnd.randint(3, 8)
            angs = sorted(rnd.uniform(0, 2 * math.pi) for _ in range(n))
            self.pts = [(math.cos(a) * r * rnd.uniform(0.6, 1.0), math.sin(a) * r * rnd.uniform(0.6, 1.0)) for a in angs]
        self.rot = rnd.uniform(0, 360)
        self.spin = rnd.uniform(-2, 2)                       # °/s
        self.dir = rnd.uniform(0, 2 * math.pi)
        self.v = rnd.uniform(0.5, 3.0)                       # px/s
        self.w1, self.w2 = rnd.uniform(0.05, 0.18), rnd.uniform(0.11, 0.31)
        self.p1, self.p2 = rnd.uniform(0, 6.3), rnd.uniform(0, 6.3)
        self.turn = rnd.uniform(-0.03, 0.03)                 # 方向慢慢偏转（rad/s）
        self.fill = rnd.uniform(0.05, 0.10)
        self.line = rnd.uniform(0.22, 0.42)
        self.inner = rnd.random() < 0.35                     # 内部细线
        self.label = ("%s-%02d" % (rnd.choice("RLKTM"), rnd.randint(1, 99)), "%.2f" % rnd.uniform(0, 9)) if rnd.random() < 0.3 else None
        self.ticks = rnd.random() < 0.25

    def gain(self, t):
        """速度倍率：两组慢正弦相乘再截断 → 0（停顿）到 ~1.8（加速）之间起伏"""
        g = 0.75 + 1.1 * math.sin(self.w1 * t + self.p1) * math.sin(self.w2 * t + self.p2) + 0.25 * math.sin(self.w2 * 2.3 * t)
        return max(0.0, g)

    def at(self, t, dt=0.25):
        """数值积分到 t 秒：位置、角度"""
        x, y, a, d = self.x, self.y, self.rot, self.dir
        s = 0.0
        while s < t:
            h = min(dt, t - s)
            g = self.gain(s)
            x += math.cos(d) * self.v * g * h
            y += math.sin(d) * self.v * g * h
            a += self.spin * (0.4 + 0.6 * g) * h
            d += self.turn * h
            s += h
        return x, y, a


rnd = random.Random(20261022)
FRAGS = [Frag(rnd, i) for i in range(34)]
MARKS = [(rnd.uniform(380, W - 20), rnd.uniform(70, 650), rnd.choice(["cross", "scale", "bracket"]), rnd.uniform(-0.6, 0.6), rnd.uniform(-0.6, 0.6))
         for _ in range(16)]
FONT_S = mt.font(10)


def frag_layer(t, line_col, fill_col, boost=1.0):
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    for f in FRAGS:
        x, y, a = f.at(t)
        near = max(0.0, 1 - math.hypot(x - SX, y - SY) / 260)
        k = 1 + 0.9 * near * boost
        ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
        pts = [(round(x + px * ca - py * sa), round(y + px * sa + py * ca)) for px, py in f.pts]
        if len(pts) < 3:
            continue
        d.polygon(pts, fill=fill_col + (int(255 * min(0.2, f.fill * k)),))
        la = int(255 * min(0.7, f.line * k))
        d.line(pts + [pts[0]], fill=line_col + (la,), width=1)
        if f.inner:   # 内部细线：一条对角线 + 平行短线
            p0, p1 = pts[0], pts[len(pts) // 2]
            d.line([p0, p1], fill=line_col + (la // 2,), width=1)
            mx, my = (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2
            for o in (-6, 6):
                d.line([(mx + o * sa - 8 * ca, my - o * ca - 8 * sa), (mx + o * sa + 8 * ca, my - o * ca + 8 * sa)], fill=line_col + (la // 2,))
        if f.ticks:   # 沿第一条边的刻度
            (ax, ay), (bx, by) = pts[0], pts[1]
            L = math.hypot(bx - ax, by - ay) or 1
            nx, ny = -(by - ay) / L, (bx - ax) / L
            for j in range(1, int(L // 8)):
                u = j * 8 / L
                tl = 5 if j % 5 == 0 else 2
                px_, py_ = ax + (bx - ax) * u, ay + (by - ay) * u
                d.line([(px_, py_), (px_ + nx * tl, py_ + ny * tl)], fill=line_col + (la,))
        if f.label:
            lx, ly = pts[0]
            d.line([(lx, ly), (lx + 14, ly - 10), (lx + 52, ly - 10)], fill=line_col + (la,))
            d.text((lx + 16, ly - 22), f.label[0], font=FONT_S, fill=line_col + (min(255, la + 30),))
            d.text((lx + 56, ly - 15), f.label[1], font=FONT_S, fill=line_col + (la,))
    for mx, my, kind, vx, vy in MARKS:   # 零散小标注：各自极慢漂移
        x, y = mx + vx * t, my + vy * t
        c = line_col + (90,)
        if kind == "cross":
            d.line([(x - 5, y), (x + 5, y)], fill=c)
            d.line([(x, y - 5), (x, y + 5)], fill=c)
        elif kind == "scale":
            d.line([(x, y), (x + 40, y)], fill=c)
            for j in range(5):
                d.line([(x + j * 10, y), (x + j * 10, y - (4 if j % 2 == 0 else 2))], fill=c)
            d.text((x + 44, y - 7), "0.1", font=FONT_S, fill=c)
        else:
            d.line([(x, y + 8), (x, y), (x + 8, y)], fill=c)
            d.line([(x + 30, y + 22), (x + 30, y + 30), (x + 22, y + 30)], fill=c)
    return lay


BASE = {"B2": (19, 23, 30), "D2": (34, 52, 74)}
LINE = {"B2": (190, 236, 250), "D2": (214, 240, 255)}
FILL = {"B2": (120, 210, 240), "D2": (170, 220, 245)}


def bg_frag(v, t):
    img = Image.new("RGBA", (W, H), BASE[v] + (255,))
    img.alpha_composite(frag_layer(t, LINE[v], FILL[v]))
    return img


_orig_bg, _orig_left = mt.bg_for, mt.left_panel
mt.bg_for = lambda v, t: bg_frag(v, t) if v in BASE else _orig_bg(v, t)
mt.left_panel = lambda img, cfg, v: _orig_left(img, cfg, v[0])
mt.V["B2"] = dict(mt.V["B"], name="B2 斜切 · 不规则碎片", desc="寻访同款斜切 · 暗场 · 不规则多边形 / 切角板块碎片各自漂移自旋 + 刻度与小标注")
mt.V["D2"] = dict(mt.V["D"], name="D2 石板蓝 · 不规则碎片", desc="中明度石板蓝 · 同一套碎片系统，碎片描边更亮")


def main():
    out = mt.OUT
    shots = []
    for v in ("B2", "D2"):
        im = mt.render(v, 6.0)
        im.save(os.path.join(out, "meta_tree_%s.png" % v))
        shots.append(im)
        crop = (mt.GX0, mt.GY0, mt.GX1, mt.GY1)
        frames = [mt.render(v, 6.0 + i * 0.25 * 6, chrome=False).crop(crop).resize(((crop[2] - crop[0]) // 2, (crop[3] - crop[1]) // 2), Image.LANCZOS)
                  for i in range(48)]
        frames[0].save(os.path.join(out, "meta_tree_%s_flow.gif" % v), save_all=True, append_images=frames[1:], duration=125, loop=0)
        pick = [0, 16, 32]   # 0 / 24 / 48 秒（真实时间）
        fw, fh = frames[0].size
        strip = Image.new("RGB", (fw * 3 + 20, fh + 30), (10, 12, 16))
        d = ImageDraw.Draw(strip)
        for i, j in enumerate(pick):
            strip.paste(frames[j], (i * (fw + 10), 30))
            mt.text(d, (i * (fw + 10) + 6, 6), "t = %d 秒" % (j * 1.5), 15, (220, 226, 234))
        strip.save(os.path.join(out, "meta_tree_%s_flow.png" % v))
        print(v, "ok", flush=True)
    sw, sh = 640, 360
    sheet = Image.new("RGB", (sw * 2 + 30, sh + 66), (12, 14, 18))
    d = ImageDraw.Draw(sheet)
    for i, (v, im) in enumerate(zip(("B2", "D2"), shots)):
        x = 10 + i * (sw + 10)
        mt.text(d, (x, 10), mt.V[v]["name"], 18, (240, 242, 246), bold=True)
        mt.text(d, (x, 34), mt.V[v]["desc"], 12, (150, 160, 172))
        sheet.paste(im.resize((sw, sh), Image.LANCZOS), (x, 56))
    sheet.save(os.path.join(out, "meta_tree_sheet2.jpg"), quality=90)
    print("out", out)


if __name__ == "__main__":
    main()
