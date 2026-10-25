"""认知塑造·布局（海底星空版，10-25 用户：「改成那种海底星空的排列，节点可以是星座」；在照抄原作版 38bf92203 上改）。
- 每条认知线是一个星座：节点是星，同一条线按 Ⅰ→Ⅱ→… 用星座连线连起来，星座旁写线名（像星图标注）。
- 整体位置关系沿用原作水月「认知塑造」节点树（PRTS 集成战略_3_认知塑造_节点树.png，2238×1338，在主仓库 build/meta_ui/ref/，不进 git）：
  同名节点尽量留在原作位置；原作里同一条线的节点散在全图各处，连成星座会横穿整张图，所以离群的几颗挪进本星座所在的区域（见 STARS 注释）。
- 坐标先按原图像素写，世界坐标 = 原图像素 × K（设计单位）。写出 game/data/meta_roots.json，并出几何预览（标出星座连线交叉、标签重叠）。
运行：D:/Anaconda/python.exe -X utf8 -B art/incoming/meta_ui_1025/layout.py
"""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

P = Path(__file__).resolve().parent
ROOT = P.parents[2]
D = json.loads((ROOT / 'game/data/meta_tree.json').read_text(encoding='utf-8'))
NODES = D['nodes']
K = 0.62

# 星的位置（原图像素）。注释 = 原作这一片是哪些节点；* = 离群的同名节点挪进本星座
STARS = {
    # 攻击性：原作中间那条左下斜线（攻击性Ⅰ / Ⅱ / 感性 / 攻击性Ⅳ / Ⅴ）；*Ⅲ 原在左上
    'atk1': (948, 412), 'atk2': (862, 520), 'atk3': (735, 690), 'atk4': (650, 800), 'atk5': (480, 1022),
    # 自我保护：上方一簇（自我保护Ⅰ–Ⅲ，Ⅳ 放到原作攻击性Ⅲ 旁边）；*Ⅳ 原在左下
    'def1': (998, 262), 'def2': (838, 193), 'def3': (712, 300), 'def4': (540, 205),
    # 生命感悟：原作左边那条线（生命感悟 / 危机感Ⅰ / 生命感悟 / 危机感Ⅱ）往下勾
    'reg1': (510, 350), 'reg2': (372, 392), 'reg3': (238, 425), 'reg4': (105, 470), 'reg5': (150, 610),
    # 危机感：左下（物由心生 / 命运认同 附近）；*原在左边那条线上
    'sh1': (300, 560), 'sh2': (400, 690),
    # 生存本能：右上（生存本能Ⅰ / Ⅱ / Ⅳ / Ⅴ）；*Ⅲ 原在左边
    'hp1': (1215, 292), 'hp2': (1258, 193), 'hp3': (1470, 255), 'hp4': (1665, 512), 'hp5': (1729, 358),
    # 收藏癖：右中（收藏癖Ⅰ / Ⅱ + 理性与判断）；*Ⅲ 原在下中
    'gold1': (1281, 580), 'gold2': (1418, 490), 'gold3': (1560, 655),
    # 好奇心：中轴（好奇心 / 资源调配 / 交易行为）
    'pick1': (1118, 820), 'pick2': (1118, 660), 'pick3': (1055, 525), 'pick4': (1118, 395),
    # 领导欲：左下（领导欲Ⅱ / Ⅲ / 万众一心）；*Ⅰ 原在顶上、*Ⅳ 原在右下
    'xp1': (1010, 870), 'xp2': (920, 950), 'xp3': (770, 1035), 'xp4': (715, 1175),
    # 交涉：下中（交涉Ⅰ 原位，Ⅱ / Ⅲ 往右下排开）
    'shop1': (1080, 1100), 'shop2': (1250, 1165), 'shop3': (1420, 1235),
    # 多程信息处理 → 绝处逢生：右下（多程信息处理 / 管理策略 / 收藏癖Ⅲ / 为了生存）；*自我审视、战利品意识 原在左中 / 顶上
    'disp1': (1318, 937), 'disp2': (1503, 857), 'disp3': (1660, 940), 'disp4': (1755, 1060),
}
# 星座线名的位置（原图像素，标签中心）；多程信息处理那条每颗星名字都不同，不写线名
CONST = {
    'atk': ('攻击性', (760, 470)), 'def': ('自我保护', (790, 125)), 'reg': ('生命感悟', (300, 330)), 'sh': ('危机感', (230, 690)),
    'hp': ('生存本能', (1490, 165)), 'gold': ('收藏癖', (1420, 610)), 'pick': ('好奇心', (1215, 650)),
    'xp': ('领导欲', (820, 1130)), 'shop': ('交涉', (1150, 1235)),
}
KEY = {k for k, v in NODES.items() if any(('rule' in e) or ('start_relic' in e) for e in v.get('effects', []))}


def chains():
    child = {v['req']: k for k, v in NODES.items() if 'req' in v}
    out = []
    for k, v in NODES.items():
        if 'req' not in v:
            ch = [k]
            while ch[-1] in child:
                ch.append(child[ch[-1]])
            out.append(ch)
    return out


def build():
    assert set(STARS) == set(NODES), set(NODES) ^ set(STARS)
    stars = {k: [round(x * K, 1), round(y * K, 1)] for k, (x, y) in STARS.items()}
    consts = {p: {'name': n, 'at': [round(x * K, 1), round(y * K, 1)]} for p, (n, (x, y)) in CONST.items()}
    return {'world': [round(2238 * K), round(1338 * K)], 'crown': [round(1118 * K, 1), round(140 * K, 1)], 'stars': stars, 'consts': consts}


FB = ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc', 12)
FC = ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc', 14)


def short(k):
    """星旁的字：带罗马数字的线只写数字（线名在星座旁），多程信息处理那条写全名"""
    nm = NODES[k]['name']
    return nm[-1] if nm[-1] in 'ⅠⅡⅢⅣⅤⅥ' else nm


def segs(lay):
    out = []
    for ch in chains():
        for a, b in zip(ch, ch[1:]):
            out.append((a, b, lay['stars'][a], lay['stars'][b]))
    return out


def cross(p1, p2, p3, p4):
    def o(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    return o(p1, p2, p3) * o(p1, p2, p4) < 0 and o(p3, p4, p1) * o(p3, p4, p2) < 0


def seg_pt(a, b, p):
    ax, ay = a
    bx, by = b
    px, py = p
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return ((ax + t * dx - px) ** 2 + (ay + t * dy - py) ** 2) ** 0.5


def check(lay):
    probs = []
    ss = segs(lay)
    for i in range(len(ss)):
        for j in range(i + 1, len(ss)):
            if len({ss[i][0], ss[i][1], ss[j][0], ss[j][1]}) == 4 and cross(ss[i][2], ss[i][3], ss[j][2], ss[j][3]):
                probs.append(('cross', ss[i][:2], ss[j][:2]))
    for a, b, pa, pb in ss:   # 连线贴着别的星擦过
        for k, p in lay['stars'].items():
            if k not in (a, b) and seg_pt(pa, pb, p) < 20:
                probs.append(('graze', (a, b), k))
    boxes = []
    for k, (x, y) in lay['stars'].items():
        r = 18 if k in KEY else 12
        boxes.append(('star', k, (x - r, y - r, x + r, y + r)))
        w = FB.getlength(short(k))
        boxes.append(('lab', k, (x + r + 2, y - 8, x + r + 6 + w, y + 8)))
    for p, c in lay['consts'].items():
        w = FC.getlength(c['name']) + 8
        x, y = c['at']
        boxes.append(('const', p, (x - w / 2, y - 10, x + w / 2, y + 10)))
    ov = lambda a, b: a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]
    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            if boxes[i][1] != boxes[j][1] and ov(boxes[i][2], boxes[j][2]):
                probs.append(('overlap', boxes[i][:2], boxes[j][:2]))
    for kind, name, b in boxes:   # 线名压在星座连线上
        if kind == 'const':
            cx, cy = (b[0] + b[2]) / 2, (b[1] + b[3]) / 2
            for a, c, pa, pb in ss:
                if seg_pt(pa, pb, (cx, cy)) < 12:
                    probs.append(('const-on-line', name, (a, c)))
    return boxes, probs


def main():
    lay = build()
    boxes, probs = check(lay)
    for pr in probs:
        print(*pr)
    print('problems', len(probs))
    W, H = lay['world']
    im = Image.new('RGB', (W, H), (6, 12, 26))
    d = ImageDraw.Draw(im, 'RGBA')
    for a, b, pa, pb in segs(lay):
        d.line([tuple(pa), tuple(pb)], fill=(150, 190, 230, 160), width=1)
    for kind, k, b in boxes:
        if kind == 'star':
            x, y = lay['stars'][k]
            r = 6 if k in KEY else 3
            d.ellipse((x - r, y - r, x + r, y + r), fill=(240, 246, 255))
        elif kind == 'lab':
            d.text((b[0], b[1]), short(k), font=FB, fill=(170, 186, 204))
        else:
            d.text((b[0] + 4, b[1]), lay['consts'][k]['name'], font=FC, fill=(255, 210, 90))
    im.save(ROOT / 'build/meta_ui/layout_stars.png')
    out = {'_doc': '认知塑造布局（海底星空版；art/incoming/meta_ui_1025/layout.py 生成，别手改）：stars 每个节点（星）的世界坐标（设计单位）；'
                   'consts 星座线名与标注位置（按链前缀）；同一条线按 Ⅰ→Ⅱ→… 连成星座',
           'scene': lay}
    (ROOT / 'game/data/meta_roots.json').write_text(json.dumps(out, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')


if __name__ == '__main__':
    main()
