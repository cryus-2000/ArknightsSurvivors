"""认知塑造·布局（照抄原作版，10-25 用户：「或者干脆照抄原作吧，做一些小改版」；照原作有公司授权）。
底图：原作水月「认知塑造」节点树（PRTS 集成战略_3_认知塑造_节点树.png，2238×1338，下载在主仓库外 build/meta_ui/ref/is3_tree.png，不进 git）。
- ORIG：原作节点位置（原图像素）与是否大节点；EDGES：原作连线（可带弧线控制点、是否原作青色特殊路径）；ARROWS：原作蓝色三角。
- OURS：本作 39 个节点放在哪个原作位置——同名的放原作对应位置；多出来的阶顺着原作那条线延长（生命感悟Ⅲ–Ⅴ 沿物由心生那条青线、
  好奇心Ⅱ–Ⅳ 用中轴空出来的资源调配 / 交易行为 / 积累Ⅰ）；绝处逢生放原作「为了生存」大节点位。原作有而本作没有的节点只留连线经过，不画盘。
- 世界坐标 = 原图像素 × K（设计单位）。写出 game/data/meta_roots.json，并出几何预览（标出标签重叠）。
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
K = 0.62

# 原作节点（原图像素）：名 → (x, y, 大节点)
ORIG = {
    'start': (1118, 140, 0), 'xp1': (1118, 193, 0), 'loot': (1118, 330, 0), 'trade': (1118, 470, 0), 'res': (1118, 610, 0),
    'cur': (1118, 820, 0), 'acc1': (1118, 962, 0), 'shop1': (1118, 1102, 0),
    'def1': (998, 262, 0), 'def2': (838, 193, 0), 'atk3': (488, 193, 0), 'def3': (712, 300, 0), 'reg1': (510, 350, 0),
    'sh1': (375, 382, 0), 'reg2': (238, 425, 0), 'sh2': (105, 463, 0),
    'hp1': (1215, 292, 0), 'hp2': (1258, 193, 0), 'accT': (1397, 193, 0), 'acc2': (1748, 193, 0),
    'hp5': (1729, 358, 0), 'hp4': (1665, 512, 0), 'rat': (1562, 650, 1), 'gold1': (1281, 580, 0), 'gold2': (1418, 490, 0),
    'duck': (1862, 393, 0), 'judge': (1995, 423, 0), 'prac': (2128, 465, 1), 'fateR': (1786, 580, 0), 'rainL': (1664, 733, 0),
    'rainR': (2028, 712, 0), 'goldR': (1860, 936, 0), 'surv': (1755, 1027, 1), 'mgmt': (1503, 857, 0), 'disp1': (1318, 937, 0),
    'shop2': (1463, 1030, 0), 'gold3': (1355, 1070, 0), 'xp4': (1520, 1160, 0), 'tong': (1388, 1205, 1), 'regB': (1255, 1235, 0),
    'shop3': (980, 1230, 0), 'wan': (715, 1160, 1), 'hab': (880, 1070, 1), 'xp2': (920, 935, 0), 'xp3': (770, 1035, 0),
    'atk1': (948, 412, 0), 'atk2': (862, 520, 0), 'gan': (735, 690, 1), 'self': (617, 578, 0), 'hp3': (505, 668, 0),
    'fateL': (395, 744, 0), 'atk4': (650, 800, 0), 'def4': (565, 911, 0), 'atk5': (480, 1022, 0), 'def5': (375, 936, 0),
    'emo': (282, 830, 1), 'def6': (210, 713, 0), 'hp6': (147, 590, 0), 'wu': (278, 540, 1),
}
# 原作连线：(a, b, 弧线控制点或 None, 原作青色特殊路径)
EDGES = [
    ('start', 'xp1', None, 0), ('xp1', 'loot', None, 0), ('xp1', 'hp2', None, 0), ('hp2', 'accT', None, 0),
    ('loot', 'def1', (1040, 335), 0), ('loot', 'hp1', (1185, 335), 0), ('loot', 'trade', None, 0),
    ('def2', 'def1', (995, 193), 0), ('def2', 'atk3', None, 0), ('def3', 'def1', None, 0),
    ('atk3', 'reg1', None, 0), ('def3', 'reg1', None, 0), ('reg1', 'sh1', None, 0), ('sh1', 'reg2', None, 0), ('reg2', 'sh2', None, 0),
    ('trade', 'atk1', (1040, 400), 0), ('trade', 'res', None, 0), ('res', 'gold1', (1200, 610), 0), ('res', 'cur', None, 0),
    ('atk1', 'atk2', None, 0), ('atk2', 'gan', None, 0), ('gan', 'cur', (900, 830), 0), ('cur', 'rat', (1360, 830), 0),
    ('gold1', 'gold2', (1350, 520), 0), ('gold2', 'rat', None, 0), ('hp4', 'rat', (1630, 600), 0), ('hp5', 'hp4', (1715, 450), 0),
    ('acc2', 'hp5', None, 0), ('rat', 'rainL', None, 0), ('rainL', 'fateR', (1740, 680), 0), ('fateR', 'duck', (1840, 480), 0),
    ('duck', 'judge', None, 0), ('judge', 'prac', None, 0),
    ('prac', 'rainR', (2080, 600), 1), ('rainR', 'goldR', (1950, 860), 1), ('goldR', 'surv', None, 1),
    ('cur', 'acc1', None, 0), ('acc1', 'xp2', None, 0), ('disp1', 'mgmt', None, 0), ('disp1', 'gold3', None, 0),
    ('shop1', 'hab', (1000, 1100), 0), ('shop1', 'gold3', (1240, 1100), 0), ('gan', 'self', None, 0),
    ('gold3', 'shop2', None, 0), ('shop2', 'xp4', None, 0), ('xp4', 'tong', None, 0),
    ('tong', 'regB', None, 1), ('regB', 'shop3', (1120, 1250), 1), ('shop3', 'wan', (840, 1215), 1),
    ('xp2', 'hab', None, 0), ('xp3', 'hab', None, 0),
    ('self', 'hp3', None, 0), ('hp3', 'fateL', None, 0),
    ('gan', 'atk4', None, 0), ('atk4', 'def4', None, 0), ('def4', 'atk5', None, 0), ('atk5', 'def5', None, 0), ('def5', 'emo', None, 0),
    ('emo', 'def6', None, 0), ('def6', 'hp6', None, 0), ('hp6', 'wu', None, 1),
]
# 原作蓝色三角：(连线 a, b, 位置 0–1，指向 b)
ARROWS = [('atk3', 'reg1', 0.62), ('def3', 'reg1', 0.72), ('atk2', 'gan', 0.6), ('res', 'cur', 0.7), ('gold2', 'rat', 0.6),
          ('cur', 'rat', 0.82), ('gan', 'cur', 0.22)]
# 本作节点 → 原作位置
OURS = {
    'xp1': 'xp1', 'xp2': 'xp2', 'xp3': 'xp3', 'xp4': 'xp4',
    'disp1': 'disp1', 'disp2': 'self', 'disp3': 'loot', 'disp4': 'surv',
    'atk1': 'atk1', 'atk2': 'atk2', 'atk3': 'atk3', 'atk4': 'atk4', 'atk5': 'atk5',
    'def1': 'def1', 'def2': 'def2', 'def3': 'def3', 'def4': 'def4',
    'hp1': 'hp1', 'hp2': 'hp2', 'hp3': 'hp3', 'hp4': 'hp4', 'hp5': 'hp5',
    'sh1': 'sh1', 'sh2': 'sh2',
    'reg1': 'reg1', 'reg2': 'reg2', 'reg3': 'regB', 'reg4': 'hp6', 'reg5': 'def6',
    'gold1': 'gold1', 'gold2': 'gold2', 'gold3': 'gold3',
    'shop1': 'shop1', 'shop2': 'shop2', 'shop3': 'shop3',
    'pick1': 'cur', 'pick2': 'res', 'pick3': 'trade', 'pick4': 'acc1',
}
KEY = {k for k, v in NODES.items() if any(('rule' in e) or ('start_relic' in e) for e in v.get('effects', []))}


def bez2(a, c, b, n=24):
    return [((1 - t) ** 2 * a[0] + 2 * (1 - t) * t * c[0] + t * t * b[0], (1 - t) ** 2 * a[1] + 2 * (1 - t) * t * c[1] + t * t * b[1]) for t in [i / n for i in range(n + 1)]]


def build():
    pos = {n: (v[0] * K, v[1] * K) for n, v in ORIG.items()}
    edges = []
    for a, b, c, cy in EDGES:
        pa, pb = pos[a], pos[b]
        pts = bez2(pa, (c[0] * K, c[1] * K), pb) if c else [pa, pb]
        edges.append({'a': a, 'b': b, 'pts': [[round(x, 1), round(y, 1)] for x, y in pts], 'cyan': cy})
    arrows = []
    for a, b, t in ARROWS:
        e = next(e for e in edges if e['a'] == a and e['b'] == b)
        pts = e['pts']
        i = min(len(pts) - 2, int(t * (len(pts) - 1)))
        arrows.append({'p': pts[i], 'q': pts[i + 1]})
    assert set(OURS) == set(NODES), set(NODES) ^ set(OURS)
    return {'world': [round(2238 * K), round(1338 * K)], 'crown': [round(pos['start'][0], 1), round(pos['start'][1], 1)],
            'orig': {n: [round(p[0], 1), round(p[1], 1), ORIG[n][2]] for n, p in pos.items()},
            'ours': OURS, 'edges': edges, 'arrows': arrows}


FB = ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc', 13)
FS = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 11)


def effect_line(k):
    s = NODES[k]['desc'].split('。')[0]
    return s if len(s) <= 14 else s[:13] + '…'


def check(lay):
    items = []
    for k, o in lay['ours'].items():
        x, y, _ = lay['orig'][o]
        key = k in KEY
        r = 22 if key else 16
        rr = 30 if key else 17
        items.append(('disc', k, (x - rr, y - rr, x + rr, y + rr)))
        w = sum(FB.getlength(c) for c in NODES[k]['name'])
        top = y + r + (14 if key else 5)
        items.append(('lab', k, (x - w / 2 - 6, top, x + w / 2 + 6, top + 20)))
    ov = lambda a, b: a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]
    probs = []
    for i in range(len(items)):
        for j in range(i + 1, len(items)):
            if items[i][1] != items[j][1] and ov(items[i][2], items[j][2]):
                probs.append((items[i][0] + ':' + items[i][1], items[j][0] + ':' + items[j][1]))
    return items, probs


def main():
    lay = build()
    items, probs = check(lay)
    for a, b in probs:
        print('overlap', a, b)
    print('problems', len(probs))
    W, H = lay['world']
    im = Image.new('RGB', (W, H), (8, 14, 24))
    d = ImageDraw.Draw(im, 'RGBA')
    for e in lay['edges']:
        d.line([tuple(q) for q in e['pts']], fill=(40, 200, 200) if e['cyan'] else (190, 196, 204), width=3)
    for n, (x, y, big) in lay['orig'].items():
        if n not in lay['ours'].values():
            d.ellipse((x - 4, y - 4, x + 4, y + 4), outline=(120, 120, 120))
    bad = {a.split(':')[1] for a, _ in probs} | {b.split(':')[1] for _, b in probs}
    for kind, k, b in items:
        x, y, _ = lay['orig'][lay['ours'][k]]
        if kind == 'disc':
            r = 22 if k in KEY else 16
            d.ellipse((x - r, y - r, x + r, y + r), fill=(10, 14, 20), outline=(255, 90, 90) if k in bad else (236, 240, 244), width=2)
        else:
            d.text((b[0] + 6, b[1]), NODES[k]['name'], font=FB, fill=(255, 120, 120) if k in bad else (236, 240, 244))
            d.text((b[0] + 6, b[1] + 17), effect_line(k), font=FS, fill=(150, 164, 178))
    im.save(ROOT / 'build/meta_ui/layout_orig.png')
    out = {'_doc': '认知塑造布局（照抄原作版；art/incoming/meta_ui_1025/layout.py 生成，别手改）：orig 原作节点位置（设计单位）与是否大节点；'
                   'ours 本作节点 → 原作位置；edges 原作连线（已采样，cyan = 原作青色特殊路径）；arrows 原作蓝色三角（p → q 方向）',
           'scene': lay}
    (ROOT / 'game/data/meta_roots.json').write_text(json.dumps(out, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')


if __name__ == '__main__':
    main()
