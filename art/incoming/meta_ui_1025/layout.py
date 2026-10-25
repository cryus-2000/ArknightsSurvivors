"""认知塑造·布局（真实星座版，10-25 用户：星空版改成「真实的星座」）。
- 每条认知线配一个星数相近的真实星座，用它真实的星位形状和连线（赤经赤纬取常用星表近似值，投影成北上东左，即仰望时的样子），
  按比例缩放到合适大小；质变节点放在该星座最亮的那颗星上。星座旁写「线名 · 星座名」。
- 星座之间的整体布局不再照原作节点位置，以星图好看、不重叠为准（PLACE）。
- 每个星座里没用上的星（如狮子座 η、天琴座 ε）作为点缀星画成暗点（deco），不可点。
- 写出 game/data/meta_roots.json，并出几何预览（标出连线交叉、擦星、星太近、标签重叠 / 压线 / 出界）。
运行：D:/Anaconda/python.exe -X utf8 -B art/incoming/meta_ui_1025/layout.py
"""
from pathlib import Path
import json
import math
from PIL import Image, ImageDraw, ImageFont

P = Path(__file__).resolve().parent
ROOT = P.parents[2]
D = json.loads((ROOT / 'game/data/meta_tree.json').read_text(encoding='utf-8'))
NODES = D['nodes']


def ra(h, m):
    return (h + m / 60.0) * 15.0


# 星座：中文名、星表（拜耳名, 赤经°, 赤纬°, 星等）、连线（星表下标对）、节点顺序（Ⅰ→… 用星表哪颗）、点缀星（赤经°, 赤纬°）
CONS = {
    'atk': ('狮子座', [('ε Leo', ra(9, 45.9), 23.77, 2.98), ('μ Leo', ra(9, 52.8), 26.01, 3.88), ('ζ Leo', ra(10, 16.7), 23.42, 3.43),
                     ('γ Leo', ra(10, 20.0), 19.84, 2.01), ('α Leo 轩辕十四', ra(10, 8.4), 11.97, 1.35)],
            [(0, 1), (1, 2), (2, 3), (3, 4)], [0, 1, 2, 3, 4],
            [(ra(10, 7.3), 16.76)]),   # η（在轩辕十四和 γ 之间那条线上）
    'hp': ('天琴座', [('β Lyr', ra(18, 50.1), 33.36, 3.5), ('γ Lyr', ra(18, 59.0), 32.69, 3.24), ('δ2 Lyr', ra(18, 54.5), 36.9, 4.3),
                    ('ζ Lyr', ra(18, 44.8), 37.6, 4.36), ('α Lyr 织女星', ra(18, 36.9), 38.78, 0.03)],
           [(0, 1), (1, 2), (2, 3), (3, 4), (3, 0)], [0, 1, 2, 3, 4], [(ra(18, 44.3), 39.67)]),   # ε
    'reg': ('仙后座', [('β Cas', ra(0, 9.2), 59.15, 2.27), ('α Cas', ra(0, 40.5), 56.54, 2.24), ('γ Cas', ra(0, 56.7), 60.72, 2.15),
                     ('δ Cas', ra(1, 25.8), 60.24, 2.66), ('ε Cas', ra(1, 54.4), 63.67, 3.35)],
            [(0, 1), (1, 2), (2, 3), (3, 4)], [0, 1, 2, 3, 4], []),
    'def': ('南十字座', [('δ Cru', ra(12, 15.1), -58.75, 2.79), ('β Cru', ra(12, 47.7), -59.69, 1.25), ('γ Cru', ra(12, 31.2), -57.11, 1.64),
                      ('α Cru', ra(12, 26.6), -63.10, 0.76)],
            [(0, 1), (2, 3)], [0, 1, 2, 3], [(ra(12, 21.4), -60.40)]),   # ε
    'xp': ('乌鸦座', [('ε Crv', ra(12, 10.1), -22.62, 3.0), ('β Crv', ra(12, 34.4), -23.40, 2.65), ('δ Crv', ra(12, 29.9), -16.52, 2.95),
                    ('γ Crv', ra(12, 15.8), -17.54, 2.59)],
           [(0, 1), (1, 2), (2, 3), (3, 0)], [0, 1, 2, 3], [(ra(12, 8.4), -24.73)]),   # α
    'pick': ('海豚座', [('β Del', ra(20, 37.5), 14.60, 3.63), ('α Del', ra(20, 39.6), 15.91, 3.77), ('γ Del', ra(20, 46.7), 16.12, 3.9),
                      ('δ Del', ra(20, 43.5), 15.07, 4.43)],
             [(0, 1), (1, 2), (2, 3), (3, 0)], [0, 1, 2, 3], [(ra(20, 33.2), 11.30)]),   # ε
    'disp': ('飞马座', [('γ Peg', ra(0, 13.2), 15.18, 2.83), ('α Peg', ra(23, 4.8), 15.21, 2.49), ('β Peg', ra(23, 3.8), 28.08, 2.42),
                      ('α And', ra(0, 8.4), 29.09, 2.06)],
             [(0, 1), (1, 2), (2, 3), (3, 0)], [0, 1, 2, 3], []),
    'gold': ('天鹰座', [('γ Aql', ra(19, 46.3), 10.61, 2.72), ('α Aql 牛郎星', ra(19, 50.8), 8.87, 0.76), ('β Aql', ra(19, 55.3), 6.41, 3.71)],
             [(0, 1), (1, 2)], [0, 1, 2], []),
    'shop': ('猎户座', [('δ Ori', ra(5, 32.0), -0.30, 2.23), ('ε Ori', ra(5, 36.2), -1.20, 1.69), ('ζ Ori', ra(5, 40.8), -1.94, 1.77)],
             [(0, 1), (1, 2)], [0, 1, 2], []),   # 腰带三星
    'sh': ('双子座', [('β Gem 北河三', ra(7, 45.3), 28.03, 1.14), ('α Gem 北河二', ra(7, 34.6), 31.89, 1.58)],
           [(0, 1)], [0, 1], []),
}
# 每个星座：中心（世界坐标，设计单位）、最长边缩放到多长
PLACE = {
    'reg': ((235, 175), 230), 'def': ((585, 205), 150), 'sh': ((860, 160), 130), 'hp': ((1150, 210), 190),
    'atk': ((330, 445), 210), 'pick': ((735, 430), 150), 'gold': ((1110, 470), 170),
    'xp': ((300, 715), 150), 'shop': ((690, 690), 150), 'disp': ((1090, 700), 170),
}
WORLD = (1388, 830)
KEY = {k for k, v in NODES.items() if any(('rule' in e) or ('start_relic' in e) for e in v.get('effects', []))}
LINE_NAME = {'atk': '攻击性', 'hp': '生存本能', 'reg': '生命感悟', 'def': '自我保护', 'xp': '领导欲', 'pick': '好奇心', 'disp': '多程信息处理',
             'gold': '收藏癖', 'shop': '交涉', 'sh': '危机感'}


FB = ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc', 13)
FC = ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc', 13)


def chains():
    child = {v['req']: k for k, v in NODES.items() if 'req' in v}
    out = {}
    for k, v in NODES.items():
        if 'req' not in v:
            ch = [k]
            while ch[-1] in child:
                ch.append(child[ch[-1]])
            out[k.rstrip('0123456789')] = ch
    return out


def project(pts, c0):
    """赤经赤纬 → 平面（度）：以星座中心为切点，东在左、北在上（仰望星空时的样子）"""
    ra0, de0 = c0
    out = []
    for a, d in pts:
        da = (a - ra0 + 540.0) % 360.0 - 180.0
        out.append((-da * math.cos(math.radians(de0)), -(d - de0)))
    return out


def build():
    chs = chains()
    stars, lines, deco, consts, mags = {}, [], [], {}, {}
    for pre, (cname, st, ln, order, dc) in CONS.items():
        ch = chs[pre]
        assert len(ch) == len(order), (pre, len(ch), len(order))
        ras = [s[1] for s in st]
        c0 = (math.degrees(math.atan2(sum(math.sin(math.radians(a)) for a in ras), sum(math.cos(math.radians(a)) for a in ras))) % 360.0,
              sum(s[2] for s in st) / len(st))
        xy = project([(s[1], s[2]) for s in st] + list(dc), c0)
        n = len(st)
        xs = [p[0] for p in xy[:n]]
        ys = [p[1] for p in xy[:n]]
        span = max(max(xs) - min(xs), max(ys) - min(ys))
        (cx, cy), size = PLACE[pre]
        k = size / span
        mx, my = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
        w = [(round(cx + (x - mx) * k, 1), round(cy + (y - my) * k, 1)) for x, y in xy]
        for i, si in enumerate(order):
            stars[ch[i]] = list(w[si])
            mags[ch[i]] = st[si][3]
        for i, nid in enumerate(ch):   # 质变节点必须在最亮的星上（飞马座四颗全是质变，不查）
            if nid in KEY and pre != 'disp':
                assert st[order[i]][3] == min(s[3] for s in st), (pre, nid)
        for a, b in ln:
            lines.append([ch[order.index(a)], ch[order.index(b)]])
        deco += [list(p) for p in w[n:]]
        consts[pre] = {'name': cname, 'box': [min(p[0] for p in w[:n]), min(p[1] for p in w[:n]), max(p[0] for p in w[:n]), max(p[1] for p in w[:n])]}
    lay = {'world': list(WORLD), 'crown': [WORLD[0] / 2, 60], 'stars': stars, 'mags': mags, 'lines': lines, 'deco': deco, 'consts': consts}
    place_labels(lay)
    return lay


def star_box(lay, k, side):
    """星名 + 消耗的框（和 meta_tree_ui.gd _draw_labels 的摆法一致）"""
    x, y = lay['stars'][k]
    r = 22 if k in KEY else 16
    w = FB.getlength(short(k)) + 34
    if side == 'r':
        return (x + r + 6, y - 9, x + r + 6 + w, y + 9)
    if side == 'l':
        return (x - r - 6 - w, y - 9, x - r - 6, y + 9)
    if side == 'b':
        return (x - w / 2, y + r + 4, x + w / 2, y + r + 22)
    return (x - w / 2, y - r - 22, x + w / 2, y - r - 4)


def const_box(lay, p, side):
    x0, y0, x1, y1 = lay['consts'][p]['box']
    w = FC.getlength(label(p)) + 8
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    if side == 'b':
        return (cx - w / 2, y1 + 26, cx + w / 2, y1 + 58)
    if side == 't':
        return (cx - w / 2, y0 - 62, cx + w / 2, y0 - 30)
    if side == 'r':
        return (x1 + 34, cy - 16, x1 + 34 + w, cy + 16)
    return (x0 - 34 - w, cy - 16, x0 - 34, cy + 16)


def hits(lay, b, placed):
    S = lay['stars']
    n = 0
    for a, c in lay['lines']:
        n += 3 * seg_rect(S[a], S[c], b)
    for k, (x, y) in S.items():
        r = 22 if k in KEY else 16
        n += 4 * (b[0] < x + r and x - r < b[2] and b[1] < y + r and y - r < b[3])
    for q in placed:
        n += 4 * (b[0] < q[2] and q[0] < b[2] and b[1] < q[3] and q[1] < b[3])
    n += 6 * (b[0] < 4 or b[2] > WORLD[0] - 4 or b[1] < 4 or b[3] > WORLD[1] - 4)
    return n


def place_labels(lay):
    placed = []
    lay['lside'] = {}
    for p in lay['consts']:
        best = min('btrl', key=lambda sd: (hits(lay, const_box(lay, p, sd), placed), 'btrl'.index(sd)))
        bx = const_box(lay, p, best)
        placed.append(bx)
        lay['consts'][p]['at'] = [round((bx[0] + bx[2]) / 2, 1), round(bx[1] + 10, 1)]
        lay['consts'][p]['label'] = label(p)
    for k in lay['stars']:
        best = min('rlbt', key=lambda sd: (hits(lay, star_box(lay, k, sd), placed), 'rlbt'.index(sd)))
        lay['lside'][k] = best
        placed.append(star_box(lay, k, best))




def short(k):
    nm = NODES[k]['name']
    return nm[-1] if nm[-1] in 'ⅠⅡⅢⅣⅤⅥ' else nm


def label(pre):
    return LINE_NAME[pre] + ' · ' + CONS[pre][0]


def cross(p1, p2, p3, p4):
    def o(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    return o(p1, p2, p3) * o(p1, p2, p4) < 0 and o(p3, p4, p1) * o(p3, p4, p2) < 0


def seg_pt(a, b, p):
    dx, dy = b[0] - a[0], b[1] - a[1]
    t = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy)))
    return math.hypot(a[0] + t * dx - p[0], a[1] + t * dy - p[1])


def seg_rect(a, b, r):
    for i in range(21):
        t = i / 20
        x, y = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
        if r[0] < x < r[2] and r[1] < y < r[3]:
            return True
    return False


def check(lay):
    probs = []
    S = lay['stars']
    ln = lay['lines']
    for i in range(len(ln)):
        for j in range(i + 1, len(ln)):
            a, b = ln[i]
            c, d = ln[j]
            if len({a, b, c, d}) == 4 and a.rstrip('0123456789') != c.rstrip('0123456789') and cross(S[a], S[b], S[c], S[d]):
                probs.append(('cross', ln[i], ln[j]))   # 南十字本身的交叉不算
    for a, b in ln:
        for k, p in S.items():
            if k not in (a, b) and seg_pt(S[a], S[b], p) < 20:
                probs.append(('graze', (a, b), k))
    ks = list(S)
    for i in range(len(ks)):
        for j in range(i + 1, len(ks)):
            if math.dist(S[ks[i]], S[ks[j]]) < 40:
                probs.append(('close', ks[i], ks[j], round(math.dist(S[ks[i]], S[ks[j]]))))
    boxes = []
    for k, (x, y) in S.items():
        r = 18 if k in KEY else 12
        boxes.append(('star', k, (x - r, y - r, x + r, y + r)))
        boxes.append(('lab', k, star_box(lay, k, lay['lside'][k])))
    for p, c in lay['consts'].items():
        w = FC.getlength(label(p)) + 8
        x, y = c['at']
        boxes.append(('const', p, (x - w / 2, y - 10, x + w / 2, y + 22)))
    ov = lambda a, b: a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]
    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            if boxes[i][1] != boxes[j][1] and ov(boxes[i][2], boxes[j][2]):
                probs.append(('overlap', boxes[i][:2], boxes[j][:2]))
    for kind, name, b in boxes:
        if kind != 'star':
            for a, c in ln:
                if seg_rect(S[a], S[c], b):
                    probs.append(('text-on-line', (kind, name), (a, c)))
        if b[0] < 4 or b[2] > WORLD[0] - 4 or b[1] < 4 or b[3] > WORLD[1] - 4:
            probs.append(('out', kind, name))
    return boxes, probs


def main():
    lay = build()
    boxes, probs = check(lay)
    for pr in probs:
        print(*pr)
    print('problems', len(probs))
    W, H = WORLD
    im = Image.new('RGB', (W, H), (6, 12, 26))
    d = ImageDraw.Draw(im, 'RGBA')
    S = lay['stars']
    for x, y in lay['deco']:
        d.ellipse((x - 1.5, y - 1.5, x + 1.5, y + 1.5), fill=(120, 140, 170))
    for a, b in lay['lines']:
        d.line([tuple(S[a]), tuple(S[b])], fill=(150, 190, 230, 160), width=1)
    for kind, k, b in boxes:
        if kind == 'star':
            x, y = S[k]
            r = 6 if k in KEY else 3
            d.ellipse((x - r, y - r, x + r, y + r), fill=(240, 246, 255))
        elif kind == 'lab':
            d.text((b[0], b[1]), short(k), font=FB, fill=(170, 186, 204))
        else:
            d.text((b[0] + 4, b[1]), label(k), font=FC, fill=(255, 210, 90))
    im.save(ROOT / 'build/meta_ui/layout_real.png')
    out = {'_doc': '认知塑造布局（真实星座版；art/incoming/meta_ui_1025/layout.py 生成，别手改）：stars 每个节点（星）的世界坐标（设计单位）、'
                   'mags 对应真实星的星等；lines 星座连线（真实星座的连线，节点 id 对）；deco 星座里没用上的点缀星；consts 每条线配的星座名与标注位置',
           'scene': lay}
    (ROOT / 'game/data/meta_roots.json').write_text(json.dumps(out, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')


if __name__ == '__main__':
    main()
