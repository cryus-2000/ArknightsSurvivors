"""标题页左侧入口·B 方案去「PPT 感」（10-25 用户：「B 的基础上做，但现在是不是太 ppt 风格了」）。
判断：PPT 感来自 平滑半透明面板 + 竖条小标题 + 每项同样的圆环图标——幻灯片模板的语言，和像素场景脱节。
改法都回到项目已有的像素 UI 语言（docs/37 §8 / tide_ui.gd）：2 逻辑像素一格、四角像素阶梯切角、Bayer 抖动、5×7 像素字、16×16 双色像素图标。
  B1 像素磁贴列：成长两项是阶梯切角抖动块，档案两项小一号，试炼一行像素字；选中 = 青边深块 + 台阶青光。
  B2 声呐刻度：不用块，左边一根像素刻度尺把各项串起来（呼应集结出发的刻度盘）；选中 = 刻度上的青色指针 + 像素下划线扫过。
  B3 刻度 + 选中块：刻度尺串联，只有选中项是阶梯切角块。
分组不用小标题：靠编号（01–02 / 03–04 / 05）、字号与间距分主次。
运行：D:/Anaconda/python.exe -B art/incoming/title_jelly_1024/render_hierarchy_b.py → hierarchy/B1..B3.png、hierarchy/comparison_b.png
"""
from pathlib import Path
import importlib.util
import sys
from PIL import Image, ImageDraw

P = Path(__file__).resolve().parent
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('h', P / 'render_hierarchy.py')
h = importlib.util.module_from_spec(spec); spec.loader.exec_module(h)
u = h.u

PX = 2                     # 1 像素格 = 2 逻辑像素（docs/37 §8 桌面）
GW, GH = 1280 // PX, 720 // PX
NAVY = [(18, 40, 68), (11, 26, 48), (6, 14, 30)]
CY = (96, 224, 232); CY_DIM = (70, 140, 160); EDGE = (44, 98, 124)
TXT = (228, 236, 244); TXT2 = (138, 160, 182); DIMC = (96, 112, 126)
BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
GLYPHS = {
    "A": "0E 11 11 1F 11 11 11", "C": "0E 11 10 10 10 11 0E", "D": "1E 11 11 11 11 11 1E", "E": "1F 10 10 1E 10 10 1F",
    "G": "0E 11 10 17 11 11 0F", "H": "11 11 11 1F 11 11 11", "I": "0E 04 04 04 04 04 0E", "L": "10 10 10 10 10 10 1F",
    "M": "11 1B 15 15 11 11 11", "N": "11 11 19 15 13 11 11", "O": "0E 11 11 11 11 11 0E", "R": "1E 11 11 1E 14 12 11",
    "S": "0F 10 10 0E 01 01 1E", "T": "1F 04 04 04 04 04 04", "U": "11 11 11 11 11 11 0E", "V": "11 11 11 11 11 0A 04",
    "W": "11 11 11 15 15 15 0A", "0": "0E 11 13 15 19 11 0E", "1": "04 0C 04 04 04 04 0E", "2": "0E 11 01 02 04 08 1F",
    "3": "1F 02 04 02 01 11 0E", "4": "02 06 0A 12 1F 02 02", "5": "1F 10 1E 01 01 11 0E", "/": "01 01 02 04 08 10 10",
}
ICONS = {
    "hunt": ["................", "................", "................", ".11111111111111.", ".1.22........1..", ".1.22.1.1.1..1..",
             ".1.22........1..", ".1.22.11111111..", ".1.22........1..", ".1.22.......1...", ".1.22........1..", ".11111111111111.",
             "................", "................", "................", "................"],
    "tree": [".......22.......", "......2222......", ".......22.......", ".......11.......", "..22...11...22..", "..221..11..122..",
             "....11.11.11....", "......1111......", ".......11.......", "...22..11..22...", "...221.11.122...", ".....111111.....",
             ".......11.......", ".......11.......", ".....111111.....", "................"],
    "gallery": ["................", "................", "................", ".11111111111111.", ".1.....11.....1.", ".1.222.11.222.1.",
                ".1.....11.....1.", ".1.222.11.222.1.", ".1.....11.....1.", ".1.222.11.222.1.", ".1.....11.....1.", ".1.....11.....1.",
                ".11111111111111.", "................", "................", "................"],
    "medal": ["...22......22...", "....22....22....", ".....22..22.....", "......2222......", ".....111111.....", "....11....11....",
              "...11..22..11...", "...1..2222..1...", "...1..2222..1...", "...11..22..11...", "....11....11....", ".....111111.....",
              "................", "................", "................", "................"],
    "boss": [".......11.......", ".......11.......", "......1111......", "....11.11.11....", "...1...11...1...", "...1........1...",
             "..1..........1..", "11111..22..11111", "11111..22..11111", "..1..........1..", "...1........1...", "...1...11...1...",
             "....11.11.11....", "......1111......", ".......11.......", ".......11......."],
}
REGION_G = (h.REGION[0] // PX, h.REGION[1] // PX, h.REGION[2] // PX, h.REGION[3] // PX)


class Grid:
    """像素层（640×360，1 格 = 2 逻辑像素）"""
    def __init__(self):
        self.im = Image.new('RGBA', (GW, GH), (0, 0, 0, 0))
        self.px = self.im.load()

    def put(self, x, y, col, a=255):
        if 0 <= x < GW and 0 <= y < GH:
            self.px[x, y] = (col[0], col[1], col[2], a)

    def text(self, x, y, s, col, k=1, track=1):
        for ch in s:
            if ch == ' ':
                x += 4 * k
                continue
            rows = GLYPHS[ch].split()
            for r, hx in enumerate(rows):
                v = int(hx, 16)
                for c in range(5):
                    if v & (1 << (4 - c)):
                        for dy in range(k):
                            for dx in range(k):
                                self.put(x + c * k + dx, y + r * k + dy, col)
            x += (5 + track) * k
        return x

    def icon(self, x, y, kind, c1, c2):
        for r, row in enumerate(ICONS[kind]):
            for c, ch in enumerate(row):
                if ch == '1':
                    self.put(x + c, y + r, c1)
                elif ch == '2':
                    self.put(x + c, y + r, c2)

    def block(self, x, y, w, hgt, n, fill=True, edge=None, tick=None, alpha=232):
        """四角 n 级像素阶梯切角块：fill = Bayer 抖动藏青（上浅下深），edge = 1 格阶梯描边色，tick = 左上角一小段亮青"""
        def inside(cx, cy):
            for (ex, ey) in ((cx, cy), (w - 1 - cx, cy), (cx, hgt - 1 - cy), (w - 1 - cx, hgt - 1 - cy)):
                if ex + ey < n:
                    return False
            return 0 <= cx < w and 0 <= cy < hgt
        for cy in range(hgt):
            for cx in range(w):
                if not inside(cx, cy):
                    continue
                border = not (inside(cx - 1, cy) and inside(cx + 1, cy) and inside(cx, cy - 1) and inside(cx, cy + 1))
                if edge and border:
                    self.put(x + cx, y + cy, edge)
                elif fill:
                    t = cy / max(1, hgt - 1) * 2.0 + cx / max(1, w) * 0.25
                    i = min(1, int(t))
                    f = t - i
                    col = NAVY[i + 1] if f * 16 > BAYER[(cy % 4) * 4 + cx % 4] else NAVY[i]
                    self.put(x + cx, y + cy, col, alpha)
        if tick:
            for k in range(6):
                self.put(x + n + k, y, tick)
            for k in range(3):
                self.put(x, y + n + k, tick)

    def halo(self, x, y, w, hgt, n, col):
        """选中块外一圈台阶式淡青光（两圈，逐圈变淡）"""
        for ring, a in ((1, 90), (2, 40)):
            xs, ys, ws, hs, nn = x - ring, y - ring, w + 2 * ring, hgt + 2 * ring, n + ring
            for cy in range(hs):
                for cx in range(ws):
                    on_edge = cx in (0, ws - 1) or cy in (0, hs - 1)
                    cut = min(cx + cy, ws - 1 - cx + cy, cx + hs - 1 - cy, ws - 1 - cx + hs - 1 - cy)
                    if (on_edge and cut >= nn) or cut == nn:
                        self.put(xs + cx, ys + cy, col, a)

    def to_layer(self):
        return self.im.resize((1280, 720), Image.Resampling.NEAREST)


def cn(lay, x, y, s, size, col):
    u.text(lay, x, y, s, size, '#%02x%02x%02x' % col if isinstance(col, tuple) else col, 'bold')


def cnw(s, size):
    return h.tw(s, size)


# 条目：(编号, 中文, 英文, 图标, 主次, 标签, 灰显)
ITEMS = [('01', '寻访', 'HEADHUNT', 'hunt', 0, '', False), ('02', '认知塑造', 'COGNITION', 'tree', 0, '', False),
         ('03', '图鉴', 'ARCHIVE', 'gallery', 1, '', False), ('04', '蚀刻章', 'MEDALS', 'medal', 1, '未开放', True),
         ('05', '试炼', 'TRIAL', 'boss', 2, '测试版', False)]


def ys_for(tier_h, gap):
    """按主次给每项的格坐标 y（主 26 格高、次 19 格高、试炼 10 格高；组间多空 gap 格）"""
    out = []
    y = 90
    last = 0
    for it in ITEMS:
        if it[4] != last:
            y += gap
            last = it[4]
        out.append(y)
        y += tier_h[it[4]]
    return out


def plan_b1(g, lay):
    ys = ys_for({0: 29, 1: 22, 2: 12}, 6)
    for i, (idx, c, en, ic, tier, tag, dim) in enumerate(ITEMS):
        y = ys[i]
        x = 52
        sel = i == 0
        if tier == 0:
            w, hh, n = 160, 26, 3
            if sel:
                g.halo(x, y, w, hh, n, CY)
            g.block(x, y, w, hh, n, True, CY if sel else EDGE, None if sel else CY)
            g.text(x + 6, y + 4, idx, CY if sel else CY_DIM)
            g.icon(x + 6, y + 13 - 3, ic, TXT if sel else TXT2, CY)
            cn(lay, (x + 28) * PX, (y + 4) * PX, c, 24, (255, 255, 255) if sel else (219, 229, 234))
            g.text(x + 28 + int(cnw(c, 24) / PX) + 5, y + 11, en, CY if sel else TXT2)   # 英文跟在中文右边、底边对齐
            if sel:
                g.text(x + w - 12, y + 10, '/', CY)
        elif tier == 1:
            w, hh, n = 128, 19, 2
            g.block(x, y, w, hh, n, True, EDGE, None, 200)
            g.text(x + 5, y + 6, idx, DIMC if dim else CY_DIM)
            g.icon(x + 18, y + 2, ic, DIMC if dim else TXT2, CY_DIM)
            cn(lay, (x + 38) * PX, (y + 3) * PX, c, 19, (122, 142, 156) if dim else (205, 217, 224))
            if tag:
                cn(lay, (x + 38) * PX + cnw(c, 19) + 8, (y + 6) * PX, tag, 10, (130, 150, 164))
        else:
            g.text(x + 2, y + 2, idx, DIMC)
            g.text(x + 18, y + 2, en, TXT2)
            cn(lay, (x + 52) * PX, y * PX + 1, c, 13, (160, 176, 186))
            cn(lay, (x + 52) * PX + cnw(c, 13) + 6, y * PX + 4, tag, 9, (110, 128, 140))


def ruler(g, y0, y1, marks):
    """左边像素刻度尺：每 3 格一个短刻度，marks 处长刻度"""
    x = 50
    for y in range(y0, y1):
        if y % 3 == 0:
            g.put(x, y, EDGE)
        if y % 6 == 0:
            g.put(x - 1, y, EDGE)
    for (y, long) in marks:
        for k in range(4 if long else 2):
            g.put(x - k, y, CY_DIM if long else EDGE)


def pointer(g, y, col):
    """刻度上的选中指针：朝右的像素三角"""
    for r in range(4):
        for c in range(r + 1):
            g.put(44 + c, y - r, col)
            g.put(44 + c, y + r, col)


def row_plain(g, lay, i, y, sel, show_block=False):
    idx, c, en, ic, tier, tag, dim = ITEMS[i]
    x = 56
    size = {0: 25, 1: 19, 2: 13}[tier]
    if tier == 2:
        g.text(x, y + 2, idx, DIMC)
        g.text(x + 14, y + 2, en, TXT2)
        cn(lay, (x + 48) * PX, y * PX + 1, c, 13, (160, 176, 186))
        cn(lay, (x + 48) * PX + cnw(c, 13) + 6, y * PX + 4, tag, 9, (110, 128, 140))
        return
    hh = 26 if tier == 0 else 19
    if show_block and sel:
        g.halo(x - 2, y - 2, 164, hh + 2, 3, CY)
        g.block(x - 2, y - 2, 164, hh + 2, 3, True, CY)
    g.text(x, y + (3 if tier == 0 else 6), idx, CY if sel else (DIMC if dim else CY_DIM))
    iy = y + (hh - 16) // 2
    g.icon(x + 14, iy, ic, TXT if sel else (DIMC if dim else TXT2), CY if sel else CY_DIM)
    tx = x + 36
    col = (255, 255, 255) if sel else ((122, 142, 156) if dim else ((219, 229, 234) if tier == 0 else (196, 209, 217)))
    cn(lay, tx * PX, (y + (2 if tier == 0 else 3)) * PX, c, size, col)
    if tier == 0:
        g.text(tx + int(cnw(c, size) / PX) + 5, y + 9, en, CY if sel else TXT2)   # 英文跟在中文右边、底边对齐
    if tag:
        cn(lay, tx * PX + cnw(c, size) + 8, (y + 6) * PX, tag, 10, (130, 150, 164))
    if sel and not show_block:
        for k in range(int(cnw(c, size) / PX) + 18):
            g.put(tx + k, y + hh, CY)


def plan_b2(g, lay, block=False):
    ys = ys_for({0: 30, 1: 22, 2: 12}, 7)
    ruler(g, ys[0] - 4, ys[-1] + 12, [(ys[0] + 13, True), (ys[1] + 13, True), (ys[2] + 9, False), (ys[3] + 9, False), (ys[4] + 5, False)])
    for i, y in enumerate(ys):
        row_plain(g, lay, i, y, i == 0, block)
    pointer(g, ys[0] + 13, CY)


PLANS = [
    ('B1', '像素磁贴列', lambda g, l: plan_b1(g, l), ['成长两项：阶梯切角抖动块（docs/37 §8 的磁贴语言）', '档案两项小一号块，试炼只剩一行像素字', '选中 = 青边深块 + 台阶青光']),
    ('B2', '声呐刻度', lambda g, l: plan_b2(g, l, False), ['左边一根像素刻度尺串起各项，呼应集结出发的刻度盘', '不用面板；靠编号、字号、间距分主次', '选中 = 刻度上的青色指针 + 像素下划线']),
    ('B3', '刻度 + 选中块', lambda g, l: plan_b2(g, l, True), ['刻度尺串联，未选中项不加底', '只有选中项是阶梯切角青边块', '主次同 B2']),
]


def main():
    out = P / 'hierarchy'
    base = h.clean_base()
    full = {'B': Image.open(out / 'B.png').convert('RGB')}
    for key, name, fn, _ in PLANS:
        u.CURRENT = key
        g = Grid()
        lay = u.layer()
        fn(g, lay)
        im = Image.alpha_composite(base, g.to_layer())
        im = Image.alpha_composite(im, lay.resize((1280, 720), Image.Resampling.LANCZOS)).convert('RGB')
        im.save(out / f'{key}.png')
        full[key] = im
    names = [('B', '原 B · 分组小标题（平滑面板）', ['竖条小标题 + 半透明面板 + 统一圆环 → 幻灯片感'])] + [(k, f'{k} · {n}', notes) for k, n, _, notes in PLANS]
    cw, ch, zw, zh = 640, 360, 640, 560
    b = Image.new('RGB', (cw * 4 + 30, 50 + ch + 10 + zh + 120), '#0b151d'); d = ImageDraw.Draw(b)
    f = u.font(7.5, 'bold'); fn_ = u.font(5.3, 'regular')
    for i, (k, title, notes) in enumerate(names):
        x = i * (cw + 10)
        d.text((x + 8, 12), title, font=f, fill='#e9f0f3')
        b.paste(full[k].resize((cw, ch), Image.Resampling.LANCZOS), (x, 50))
        b.paste(full[k].crop((80, 150, 480, 500)).resize((zw, zh), Image.Resampling.NEAREST), (x, 50 + ch + 10))
        ny = 50 + ch + 10 + zh + 12
        for n in notes:
            d.text((x + 8, ny), '· ' + n, font=fn_, fill='#b9ccd6'); ny += 26
    b.save(out / 'comparison_b.png')
    print(b.size)


if __name__ == '__main__':
    main()
