"""认知塑造·根系布局（几何版，10-25 用户定方向一「深蓝之树」并要求「稍微有一点几何规律，原作也是」）。
规则：
- 同阶节点在同一条水平线上（阶距一致）：Ⅰ–Ⅴ 落在 ROWS；
- 每条线一条竖向车道，同组车道等距；
- 根的走向只用直线段 + 45° / 90° 转折，转角都倒成同一半径的圆角；分叉一律 45° 斜下再转竖直，最外侧那条用 90° 圆角收边；
- 根尖越过末节往下一小段，再用四分之一圆弧往中线收（内收）；
- 左右主根高度错开、左短右长（左下留给详情卡），整体仍是有机的根系。
写出 game/data/meta_roots.json（折线已加密，游戏直接画），并出几何预览（标出重叠）。
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
ORDER = ["disp1", "shop1", "gold1", "pick1", "xp1", "sh1", "atk1", "hp1", "def1", "reg1"]   # 同 meta_tree_ui ROOT_ORDER


def chain(first):
    out = [first]
    while True:
        nxt = [k for k, v in NODES.items() if v.get('req') == out[-1]]
        if not nxt:
            return out
        out.append(nxt[0])


CHAINS = {c.rstrip('0123456789'): chain(c) for c in ORDER}
KEY = {k for k, v in NODES.items() if any(('rule' in e) or ('start_relic' in e) for e in v.get('effects', []))}

WORLD = [1280, 720]
CROWN = (590, 140)
ROWS = [226, 316, 406, 496, 586]          # Ⅰ–Ⅴ（阶距 90）
CORNER = 12.0                             # 圆角半径
DROP = 30.0                               # 分叉 45° 斜下的高度
TAIL = 22.0                               # 根尖越过末节的直段
CURL = 14.0                               # 根尖内收圆弧半径
# 组：主根所在的水平线（左右错开）与各线车道（组内等距）
# jog = (在第几阶之后, 横移量)：同组几条根在同一阶一起 45° 横移一次，仍互相平行等距
GROUPS = {
    'L': {'bus': 178, 'lanes': [('pick', 395), ('gold', 280), ('shop', 165)], 'side': -1, 'jog': {'gold': (0, -30), 'shop': (0, -30)}},   # 探索
    'C': {'bus': None, 'lanes': [('disp', 590), ('xp', 485)], 'side': 0, 'jog': {}},                     # 成长：调度是正下方的主根，领导欲从左主根分出
    'R1': {'bus': 166, 'lanes': [('sh', 700), ('atk', 805)], 'side': 1, 'jog': {'atk': (1, 30)}},       # 战斗
    'R2': {'bus': 166, 'lanes': [('hp', 910), ('def', 1015), ('reg', 1120)], 'side': 1, 'jog': {'hp': (1, 30), 'def': (1, 30), 'reg': (1, 30)}},   # 生存
}
GROUP_IX = {'L': 0, 'C': 1, 'R1': 2, 'R2': 3}   # 同 meta_tree_ui GROUPS：探索 / 成长 / 战斗 / 生存
KEEP = [[0, 0, 1280, 64], [0, 452, 352, 720], [960, 64, 1280, 116], [0, 698, 1280, 720]]


def densify(pts, step=3.0):
    out = [pts[0]]
    for i in range(1, len(pts)):
        a, b = pts[i - 1], pts[i]
        n = max(1, int(math.dist(a, b) / step))
        for k in range(1, n + 1):
            out.append((a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n))
    return out


def rounded(poly, r=CORNER, step=3.0):
    """折线倒圆角并加密：每个内角用半径 r 的圆弧替换（两边不够长时缩小半径）"""
    out = [poly[0]]
    for i in range(1, len(poly) - 1):
        a, b, c = poly[i - 1], poly[i], poly[i + 1]
        v1 = (a[0] - b[0], a[1] - b[1])
        v2 = (c[0] - b[0], c[1] - b[1])
        l1, l2 = math.hypot(*v1), math.hypot(*v2)
        if l1 < 1e-6 or l2 < 1e-6:
            continue
        u1 = (v1[0] / l1, v1[1] / l1)
        u2 = (v2[0] / l2, v2[1] / l2)
        ang = math.acos(max(-1.0, min(1.0, u1[0] * u2[0] + u1[1] * u2[1])))
        if ang > math.pi - 1e-3 or ang < 1e-3:
            out.append(b)
            continue
        t = min(r / math.tan(ang / 2.0), l1 * 0.45, l2 * 0.45)
        rr = t * math.tan(ang / 2.0)
        p1 = (b[0] + u1[0] * t, b[1] + u1[1] * t)
        p2 = (b[0] + u2[0] * t, b[1] + u2[1] * t)
        bis = (u1[0] + u2[0], u1[1] + u2[1])
        bl = math.hypot(*bis)
        bis = (bis[0] / bl, bis[1] / bl)
        cd = rr / math.sin(ang / 2.0)
        cc = (b[0] + bis[0] * cd, b[1] + bis[1] * cd)
        a1 = math.atan2(p1[1] - cc[1], p1[0] - cc[0])
        a2 = math.atan2(p2[1] - cc[1], p2[0] - cc[0])
        da = (a2 - a1 + math.pi) % (2 * math.pi) - math.pi
        n = max(2, int(abs(da) * rr / step))
        for k in range(n + 1):
            aa = a1 + da * k / n
            out.append((cc[0] + rr * math.cos(aa), cc[1] + rr * math.sin(aa)))
    out.append(poly[-1])
    return densify(out, step)


def curl(x, y, side):
    """根尖：往下 TAIL 再往中线收一个四分之一圆弧（side = 所在侧，-1 左 / 1 右 / 0 中线往左）"""
    sx = -side if side != 0 else -1
    pts = [(x, y + TAIL)]
    for k in range(1, 9):
        a = math.pi / 2 * k / 8
        pts.append((x + sx * CURL * (1 - math.cos(a)), y + TAIL + CURL * math.sin(a)))
    return pts


def build():
    cx, cy = CROWN
    lb = GROUPS['L']['bus']
    rb = GROUPS['R1']['bus']
    l_end = GROUPS['L']['lanes'][-1][1]
    r_end = GROUPS['R2']['lanes'][-1][1]
    mains = {
        'L': {'pts': [(cx - 4, cy), (cx - 4 - (lb - cy), lb), (l_end + DROP, lb)], 'w': [9, 5]},
        'R': {'pts': [(cx + 4, cy), (cx + 4 + (rb - cy), rb), (r_end - DROP, rb)], 'w': [10, 5]},
        'C': {'pts': [(cx, cy), (cx, cy + 46)], 'w': [10, 8]},
    }
    roots = {}
    for g, spec in GROUPS.items():
        side = spec['side']
        for p, lx in spec['lanes']:
            n = len(CHAINS[p])
            last_y = ROWS[n - 1]
            if p == 'disp':
                path = [(cx, cy + 46), (cx, last_y)]
            elif p == 'xp':
                path = [(lx + DROP, lb), (lx, lb + DROP), (lx, last_y)]
            elif g == 'L' and lx == l_end:
                path = [(l_end + DROP, lb), (lx, lb), (lx, last_y)]
            elif g == 'R2' and lx == r_end:
                path = [(r_end - DROP, rb), (lx, rb), (lx, last_y)]
            else:
                sgn = 1 if side > 0 else -1
                path = [(lx - sgn * DROP, spec['bus']), (lx, spec['bus'] + DROP), (lx, last_y)]
            jg = spec['jog'].get(p)
            if jg and jg[0] < n - 1:   # 第 jg[0] 阶与下一阶之间 45° 横移 jg[1]
                k0, dx = jg
                ym = (ROWS[k0] + ROWS[k0 + 1]) / 2.0
                path = path[:-1] + [(lx, ym - abs(dx) / 2.0), (lx + dx, ym + abs(dx) / 2.0), (lx + dx, last_y)]
            ex = path[-1][0]
            pts = rounded(path + curl(ex, last_y, -1 if p == 'xp' else side))
            nis = []
            for k in range(n):
                x_k = lx + (jg[1] if jg and k > jg[0] else 0)
                target = (x_k, ROWS[k])
                j = min(range(len(pts)), key=lambda q: math.dist(pts[q], target))
                pts[j] = target
                nis.append(j)
            roots[p] = {'pts': [[round(a, 1), round(b, 1)] for a, b in pts], 'ni': nis, 'main': 'C' if p == 'disp' else ('L' if g in ('L', 'C') else 'R')}
    mains_out = {m: {'pts': [[round(a, 1), round(b, 1)] for a, b in rounded(v['pts'])], 'w': v['w']} for m, v in mains.items()}
    # 组名小标：在该组第一条车道上方、主根线上面一点
    glabels = []
    for g, spec in GROUPS.items():
        xs = [lx for _, lx in spec['lanes']]
        by = spec['bus'] if spec['bus'] else cy + 30
        glabels.append([GROUP_IX[g], round(sum(xs) / len(xs)), by - 16])
    return {'world': WORLD, 'crown': list(CROWN), 'rows': ROWS, 'keep': KEEP, 'mains': mains_out, 'roots': roots, 'glabels': glabels}


FB = ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc', 13)


def label_box(k, x, y):
    r = 22 if k in KEY else 16
    off = 16 if k in KEY else 6
    w = sum(FB.getlength(ch) for ch in NODES[k]['name'])
    return (x - w / 2 - 6, y + r + off - 2, x + w / 2 + 6, y + r + off + 18)


def check(lay):
    pos = {}
    for p, r in lay['roots'].items():
        for k, j in zip(CHAINS[p], r['ni']):
            pos[k] = r['pts'][j]
    items = []
    for k, (x, y) in pos.items():
        rr = 30 if k in KEY else 17
        items.append(('disc', k, (x - rr, y - rr, x + rr, y + rr)))
        items.append(('lab', k, label_box(k, x, y)))
    ov = lambda a, b: a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]
    probs = []
    for i in range(len(items)):
        for j in range(i + 1, len(items)):
            if items[i][1] != items[j][1] and ov(items[i][2], items[j][2]):
                probs.append((items[i][0] + ':' + items[i][1], items[j][0] + ':' + items[j][1]))
    for kind, k, b in items:
        for z in lay['keep']:
            if ov(b, z):
                probs.append((kind + ':' + k, 'keep' + str(z)))
    return pos, items, probs


def preview(lay, pos, items, probs, path):
    W, H = lay['world']
    im = Image.new('RGB', (W, H), (8, 20, 34))
    d = ImageDraw.Draw(im, 'RGBA')
    for z in lay['keep']:
        d.rectangle(z, fill=(255, 255, 255, 18))
    for y in lay['rows']:
        d.line([(0, y), (W, y)], fill=(255, 255, 255, 18))
    for m in lay['mains'].values():
        d.line([tuple(q) for q in m['pts']], fill=(80, 120, 150), width=6)
    for r in lay['roots'].values():
        d.line([tuple(q) for q in r['pts']], fill=(120, 170, 200), width=3)
    bad = {a.split(':')[1] for a, _ in probs} | {b.split(':')[1] for _, b in probs if ':' in b}
    for kind, k, b in items:
        x, y = pos[k]
        if kind == 'disc':
            r = 22 if k in KEY else 16
            d.ellipse((x - r, y - r, x + r, y + r), fill=(10, 14, 20), outline=(255, 90, 90) if k in bad else (230, 236, 240), width=2)
        else:
            d.text((b[0] + 6, b[1] + 2), NODES[k]['name'], font=FB, fill=(255, 120, 120) if k in bad else (230, 236, 240))
    im.save(path)


def main():
    lay = build()
    pos, items, probs = check(lay)
    for a, b in probs:
        print('overlap', a, b)
    print('problems', len(probs))
    preview(lay, pos, items, probs, ROOT / 'build/meta_ui/layout_grid.png')
    out = {'_doc': '认知塑造根系布局（art/incoming/meta_ui_1025/layout.py 生成，别手改）：几何版——同阶同一水平线（rows）、每条线一条竖向车道、'
                   '直线段 + 45° / 90° 转折 + 统一圆角；mains 主根折线（已加密）+ 起止宽度；roots 每条线的折线（含根尖内收弧）与各节点在折线里的下标 ni',
           'scene': lay}
    (ROOT / 'game/data/meta_roots.json').write_text(json.dumps(out, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')


if __name__ == '__main__':
    main()
