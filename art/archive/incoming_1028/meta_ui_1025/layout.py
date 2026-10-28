"""认知塑造·布局（自绘星座版，10-26 用户：「每条线一个自绘星座，形状对应线的含义，按 Ⅰ→Ⅴ 一笔连下来，只写线名，不用地球星座名」）。
- 每条线一个自绘星座：节点是星，按 Ⅰ→Ⅱ→… 一笔连下来；笔画可以经过不可点的点缀星（d）把形状勾圆，末阶之后可以再收一笔回到某颗星，
  把图形闭合（整条线点满时这一笔才亮）。少数星座带几笔很淡的辅助线 / 点缀星（extra / dots），只为认得出形状。
  形状：攻击性 = 箭、生存本能 = 心、生命感悟 = 心跳脉搏、自我保护 = 盾、领导欲 = 王冠、好奇心 = 眼睛、多程信息处理那条 = 闪电、
  收藏癖 = 宝石、交涉 = 天平、危机感 = 警示三角、未雨绸缪 = 侧闪残影。
- 星座旁只写线名（下附已塑造 / 总数）；星名、线名自动在右 / 左 / 下 / 上里选不压线、不重叠的方位。
- 写出 game/data/meta_roots.json，并出几何预览（标出星太近、连线擦星、标签重叠 / 压线 / 出界）。
运行：D:/Anaconda/python.exe -X utf8 -B art/archive/incoming_1028/meta_ui_1025/layout.py
"""
from pathlib import Path
import json
import math
from PIL import Image, ImageDraw, ImageFont

P = Path(__file__).resolve().parent
ROOT = P.parents[3]
D = json.loads((ROOT / 'game/data/meta_tree.json').read_text(encoding='utf-8'))
NODES = D['nodes']

# 星座形状（局部坐标，设计单位，y 向下）：stroke 一笔的顶点（'n' = 下一颗节点星，按 Ⅰ→… 依次取；'d' = 点缀星；
# ('back', k) = 收笔回到第 k 颗节点星）；extra = 很淡的辅助线；dots = 点缀星
S2 = math.sqrt(0.5)
SHAPES = {
    # 箭：箭杆从左下往右上，Ⅲ 是箭头根，Ⅳ 一侧倒钩 → Ⅴ 箭尖 → 另一侧倒钩 → 收回箭头根
    'atk': {'stroke': [('n', -85, 85), ('n', -42, 42), ('n', 0, 0), ('n', -34, -34), ('n', 60, -60), ('d', 34, 34), ('back', 2)]},
    # 心：Ⅰ 心尖 → 左侧 → 左瓣 → 中间凹口 → Ⅴ 右瓣 → 右侧 → 收回心尖
    'hp': {'stroke': [('n', 0, 72), ('n', -64, 2), ('n', -36, -48), ('n', 0, -20), ('n', 36, -48), ('d', 64, 2), ('back', 0)]},
    # 心跳脉搏：平 → 平 → Ⅲ 高峰 → 低谷 → 回平 → 往右延出去
    'reg': {'stroke': [('n', -112, 4), ('n', -58, 4), ('n', -26, -62), ('n', 8, 50), ('n', 48, 4), ('d', 110, 4)]},
    # 盾：左上 → 右上 → 右肩 → Ⅳ 盾尖 → 左肩 → 收回左上
    'def': {'stroke': [('n', -52, -52), ('n', 52, -52), ('n', 54, 14), ('n', 0, 72), ('d', -54, 14), ('back', 0)], 'dots': [(0, -6)]},
    # 王冠：左底 → 左峰 → 谷 → 中峰 → 谷 → Ⅳ 右峰 → 右底 → 收回左底
    'xp': {'stroke': [('n', -72, 36), ('n', -64, -36), ('d', -30, 4), ('n', 0, -58), ('d', 30, 4), ('n', 64, -36), ('d', 72, 36), ('back', 0)]},
    # 眼睛：左眼角 → 上眼睑 → 右眼角 → 下眼睑 → 收回左眼角；瞳孔一颗点缀星
    'pick': {'stroke': [('n', -88, 0), ('d', -46, -30), ('n', 0, -40), ('d', 46, -30), ('n', 88, 0), ('d', 46, 30), ('n', 0, 40),
                        ('d', -46, 30), ('back', 0)], 'dots': [(0, 0)]},
    # 闪电：右上 → 左中 → 右中 → 左下
    'disp': {'stroke': [('n', 48, -92), ('n', -28, -12), ('n', 34, 6), ('n', -48, 92)]},
    # 宝石：左腰 → 底尖 → 右腰 → 右上台面 → 左上台面 → 收回左腰；腰线一笔淡线
    'gold': {'stroke': [('n', -60, -12), ('n', 0, 60), ('n', 60, -12), ('d', 32, -46), ('d', -32, -46), ('back', 0)],
             'extra': [((-60, -12), (60, -12))]},
    # 天平：左端 → 支点 → 右端（横梁）；立柱、底座、两只秤盘是淡线
    'shop': {'stroke': [('n', -78, -22), ('n', 0, -36), ('n', 78, -22)],
             'extra': [((0, -36), (0, 56)), ((-32, 56), (32, 56)), ((-78, -22), (-98, 20)), ((-78, -22), (-58, 20)), ((-98, 20), (-58, 20)),
                       ((78, -22), (58, 20)), ((78, -22), (98, 20)), ((58, 20), (98, 20))]},
    # 警示三角：Ⅰ 顶 → Ⅱ 右下 → 左下 → 收回顶；中间一道「!」
    'sh': {'stroke': [('n', 0, -56), ('n', 62, 46), ('d', -62, 46), ('back', 0)], 'extra': [((0, -18), (0, 10))], 'dots': [(0, 26)]},
    # 残影（未雨绸缪，闪避，10-27）：一道侧闪的弧线 Ⅰ → Ⅱ → Ⅲ，下面两道淡弧是身后的残影
    'dodge': {'stroke': [('n', -60, 22), ('d', -30, -8), ('n', 0, -18), ('d', 30, -8), ('n', 60, 22)],
              'extra': [((-50, 42), (0, 12)), ((0, 12), (50, 42))], 'dots': [(-20, 50), (20, 50)]},
}
# 每个星座：中心（世界坐标）、缩放
PLACE = {
    'reg': ((235, 180), 1.0), 'def': ((590, 195), 1.0), 'sh': ((865, 165), 1.0), 'hp': ((1160, 200), 1.15),
    'atk': ((330, 455), 1.15), 'pick': ((730, 440), 1.1), 'gold': ((1120, 420), 1.15),
    'xp': ((300, 705), 1.15), 'shop': ((705, 690), 1.1), 'disp': ((1110, 690), 1.25),
    'dodge': ((945, 330), 1.0),
}
WORLD = (1388, 830)
CONST_SIDE = {'disp': 'r', 'gold': 'b'}   # 线名指定摆哪边（闪电下面贴着世界底边，上面又离宝石太近）
KEY = {k for k, v in NODES.items() if any(('rule' in e) or ('start_relic' in e) for e in v.get('effects', []))}
LINE_NAME = {'atk': '攻击性', 'hp': '生存本能', 'reg': '生命感悟', 'def': '自我保护', 'xp': '领导欲', 'pick': '好奇心', 'disp': '多程信息处理',
             'gold': '收藏癖', 'shop': '交涉', 'sh': '危机感', 'dodge': '未雨绸缪'}
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


def build():
    chs = chains()
    stars, shapes, consts = {}, {}, {}
    for pre, sh in SHAPES.items():
        ch = chs[pre]
        (cx, cy), k = PLACE[pre]
        f = lambda x, y: [round(cx + x * k, 1), round(cy + y * k, 1)]
        stroke = []
        ni = 0
        pts = []
        for e in sh['stroke']:
            if e[0] == 'n':
                stars[ch[ni]] = f(e[1], e[2])
                stroke.append(['n', ch[ni]])
                pts.append(stars[ch[ni]])
                ni += 1
            elif e[0] == 'd':
                stroke.append(['d'] + f(e[1], e[2]))
                pts.append(f(e[1], e[2]))
            else:
                stroke.append(['n', ch[e[1]]])
        assert ni == len(ch), (pre, ni, len(ch))
        extra = [f(*a) + f(*b) for a, b in sh.get('extra', [])]
        dots = [f(*d) for d in sh.get('dots', [])]
        for x0, y0, x1, y1 in extra:
            pts += [[x0, y0], [x1, y1]]
        shapes[pre] = {'stroke': stroke, 'extra': extra, 'dots': dots}
        consts[pre] = {'box': [min(p[0] for p in pts), min(p[1] for p in pts), max(p[0] for p in pts), max(p[1] for p in pts)]}
    lay = {'world': list(WORLD), 'crown': [WORLD[0] / 2, 60], 'stars': stars, 'shapes': shapes, 'consts': consts}
    place_labels(lay)
    return lay


def short(k):
    nm = NODES[k]['name']
    return nm[-1] if nm[-1] in 'ⅠⅡⅢⅣⅤⅥ' else nm


def segs(lay):
    """所有要画的线段（一笔的每一段 + 辅助线），世界坐标"""
    S = lay['stars']
    out = []
    for pre, sh in lay['shapes'].items():
        pts = [S[e[1]] if e[0] == 'n' else e[1:] for e in sh['stroke']]
        out += [(pre, pts[i], pts[i + 1]) for i in range(len(pts) - 1)]
        out += [(pre, e[:2], e[2:]) for e in sh['extra']]
    return out


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
    w = FC.getlength(LINE_NAME[p]) + 8
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    if side == 'b':
        return (cx - w / 2, y1 + 26, cx + w / 2, y1 + 58)
    if side == 't':
        return (cx - w / 2, y0 - 62, cx + w / 2, y0 - 30)
    if side == 'r':
        return (x1 + 34, cy - 16, x1 + 34 + w, cy + 16)
    return (x0 - 34 - w, cy - 16, x0 - 34, cy + 16)


def hits(lay, b, placed):
    n = 0
    for _, a, c in segs(lay):
        n += 3 * seg_rect(a, c, b)
    for k, (x, y) in lay['stars'].items():
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
        best = CONST_SIDE.get(p) or min('btrl', key=lambda sd: (hits(lay, const_box(lay, p, sd), placed), 'btrl'.index(sd)))
        bx = const_box(lay, p, best)
        placed.append(bx)
        lay['consts'][p]['at'] = [round((bx[0] + bx[2]) / 2, 1), round(bx[1] + 10, 1)]
        lay['consts'][p]['name'] = LINE_NAME[p]
    for k in lay['stars']:
        best = min('rlbt', key=lambda sd: (hits(lay, star_box(lay, k, sd), placed), 'rlbt'.index(sd)))
        lay['lside'][k] = best
        placed.append(star_box(lay, k, best))


def check(lay):
    probs = []
    S = lay['stars']
    for _, a, b in segs(lay):
        for k, p in S.items():
            if p not in (a, b) and seg_pt(a, b, p) < 20:
                probs.append(('graze', a, b, k))
    ks = list(S)
    for i in range(len(ks)):
        for j in range(i + 1, len(ks)):
            if math.dist(S[ks[i]], S[ks[j]]) < 44:
                probs.append(('close', ks[i], ks[j], round(math.dist(S[ks[i]], S[ks[j]]))))
    boxes = []
    for k, (x, y) in S.items():
        r = 18 if k in KEY else 12
        boxes.append(('star', k, (x - r, y - r, x + r, y + r)))
        boxes.append(('lab', k, star_box(lay, k, lay['lside'][k])))
    for p, c in lay['consts'].items():
        w = FC.getlength(c['name']) + 8
        x, y = c['at']
        boxes.append(('const', p, (x - w / 2, y - 10, x + w / 2, y + 22)))
    ov = lambda a, b: a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]
    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            if boxes[i][1] != boxes[j][1] and ov(boxes[i][2], boxes[j][2]):
                probs.append(('overlap', boxes[i][:2], boxes[j][:2]))
    for kind, name, b in boxes:
        if kind != 'star':
            for _, a, c in segs(lay):
                if seg_rect(a, c, b):
                    probs.append(('text-on-line', (kind, name), _))
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
    for pre, sh in lay['shapes'].items():
        for e in sh['extra']:
            d.line([tuple(e[:2]), tuple(e[2:])], fill=(150, 190, 230, 70), width=1)
        for x, y in sh['dots'] + [e[1:] for e in sh['stroke'] if e[0] == 'd']:
            d.ellipse((x - 1.5, y - 1.5, x + 1.5, y + 1.5), fill=(120, 140, 170))
        pts = [tuple(S[e[1]]) if e[0] == 'n' else tuple(e[1:]) for e in sh['stroke']]
        d.line(pts, fill=(150, 190, 230, 170), width=1)
    for kind, k, b in boxes:
        if kind == 'star':
            x, y = S[k]
            r = 6 if k in KEY else 3
            d.ellipse((x - r, y - r, x + r, y + r), fill=(240, 246, 255))
        elif kind == 'lab':
            d.text((b[0], b[1]), short(k), font=FB, fill=(170, 186, 204))
        else:
            d.text((b[0] + 4, b[1]), lay['consts'][k]['name'], font=FC, fill=(255, 210, 90))
    im.save(ROOT / 'build/meta_ui/layout_drawn.png')
    out = {'_doc': '认知塑造布局（自绘星座版；art/archive/incoming_1028/meta_ui_1025/layout.py 生成，别手改）：stars 每个节点（星）的世界坐标（设计单位）；'
                   'shapes 每条线的星座：stroke 一笔的顶点（["n", 节点 id] 或 ["d", x, y] 点缀星），extra 淡辅助线 [x0, y0, x1, y1]，dots 点缀星；'
                   'consts 线名标注位置；lside 星名摆在星的哪一边',
           'scene': lay}
    (ROOT / 'game/data/meta_roots.json').write_text(json.dumps(out, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')


if __name__ == '__main__':
    main()
