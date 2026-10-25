"""认知塑造·根系布局（10-25 用户：按原作水月「认知塑造」节点树 + 深蓝之树树根意象，弧线内收、不对称）。
结构：树干从顶栏下垂到树冠 → 分出几条主根（不挂节点）→ 每条线从主根的不同位置分叉成一条细根，节点按弧长在 [t0, t1] 等分。
所有曲线都是三次贝塞尔（世界坐标 = 设计单位）。写出 game/data/meta_roots.json（游戏读），并出一张几何预览（标出重叠）。
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

# 方向一「深蓝之树」：一屏 1280×720。左短右长（左下留给详情卡），调度是中间主根
SCENE = {
    'world': [1280, 720],
    'crown': [556, 170],
    'keep': [[0, 0, 1280, 64], [0, 420, 350, 720], [960, 64, 1280, 116], [0, 698, 1280, 720]],
    # 主根：[P0, P1, P2, P3, 起点宽, 末端宽]
    'mains': {
        'L': [[552, 176], [470, 190], [300, 186], [176, 240], 9, 4],     # 探索
        'C': [[556, 182], [556, 222], [556, 258], [558, 288], 10, 7],    # 成长（领导欲半路分出，调度接着往下）
        'R1': [[562, 178], [628, 196], [724, 240], [772, 316], 9, 4],    # 战斗
        'R2': [[566, 172], [700, 140], [900, 150], [1012, 230], 10, 4],  # 生存
    },
    # 线：[主根, 分叉处 t, P1, P2, P3, 节点 t0, t1, 标签方向]（P0 = 主根上 t 处；t1 < 1 时根尖越过末节再长一小段；标签 b 下 / r 右 / l 左 / z 左右交错）
    # 每条线大致守一条约 100 宽的竖向「车道」（交涉 165 · 收藏癖 285 · 好奇心 395 · 领导欲 495 · 调度 600 · 危机感 700 · 攻击性 800 · 生存本能 905 ·
    # 自我保护 1035 · 生命感悟 1170），名字一律放下方就不会互相压；弧度靠主根的拱和根尖往里收
    'roots': {
        'shop': ['L', 1.00, [150, 280], [146, 340], [190, 384], 0.05, 0.92],
        'gold': ['L', 0.66, [276, 240], [262, 310], [300, 390], 0.22, 0.92],
        'pick': ['L', 0.30, [430, 240], [378, 330], [412, 470], 0.18, 0.93],
        'xp':   ['C', 0.40, [496, 270], [470, 420], [500, 620], 0.24, 0.94],
        'disp': ['C', 1.00, [570, 370], [628, 470], [606, 646], 0.13, 0.88],
        'sh':   ['R1', 0.42, [690, 250], [706, 300], [690, 352], 0.36, 0.95],
        'atk':  ['R1', 1.00, [832, 392], [850, 540], [780, 668], 0.04, 0.90],
        'hp':   ['R2', 0.40, [884, 204], [966, 384], [884, 640], 0.14, 0.92],
        'def':  ['R2', 0.68, [1032, 214], [1106, 330], [1030, 492], 0.16, 0.92],
        'reg':  ['R2', 1.00, [1150, 262], [1262, 440], [1150, 668], 0.22, 0.92],
    },
}


ORIG_K = 1.5


def scaled(lay, k):
    sc = lambda q: [round(q[0] * k, 1), round(q[1] * k, 1)]
    out = {'world': [int(lay['world'][0] * k), int(lay['world'][1] * k)], 'crown': sc(lay['crown']), 'keep': [],
           'mains': {m: [sc(v[0]), sc(v[1]), sc(v[2]), sc(v[3]), v[4] * k, v[5] * k] for m, v in lay['mains'].items()},
           'roots': {r: [v[0], v[1], sc(v[2]), sc(v[3]), sc(v[4])] + v[5:] for r, v in lay['roots'].items()}}
    return out


ORIG = scaled(SCENE, ORIG_K)


def effect_line(k):
    """节点下的一行效果：desc 第一句；质变节点只留第一句（规则名在详情卡）"""
    s = NODES[k]['desc'].split('。')[0]
    return s if len(s) <= 16 else s[:15] + '…'   # 同游戏 _effect_line


def bez(c, t):
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = c
    u = 1 - t
    return (u * u * u * x0 + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * x3,
            u * u * u * y0 + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y3)


def samples(c, n=200):
    pts = [bez(c, i / n) for i in range(n + 1)]
    acc = [0.0]
    for i in range(1, len(pts)):
        acc.append(acc[-1] + math.dist(pts[i - 1], pts[i]))
    return pts, acc


def at_len(pts, acc, s):
    for i in range(1, len(acc)):
        if acc[i] >= s:
            f = (s - acc[i - 1]) / max(1e-6, acc[i] - acc[i - 1])
            return (pts[i - 1][0] + (pts[i][0] - pts[i - 1][0]) * f, pts[i - 1][1] + (pts[i][1] - pts[i - 1][1]) * f)
    return pts[-1]


def curve_of(lay, p):
    spec = lay['roots'][p]
    main = lay['mains'][spec[0]]
    p0 = bez(main[:4], spec[1])
    return [list(p0), spec[2], spec[3], spec[4]], spec[5], spec[6]


def place(lay):
    out = {}
    for p in lay['roots']:
        c, t0, t1 = curve_of(lay, p)
        ids = CHAINS[p]
        pts, acc = samples(c)
        L = acc[-1]
        n = len(ids)
        for j, k in enumerate(ids):
            f = t0 + (t1 - t0) * (j / (n - 1) if n > 1 else 1.0)
            out[k] = at_len(pts, acc, f * L)
            sd = lay['roots'][p][7] if len(lay['roots'][p]) > 7 else 'b'
            SIDE[k] = ('r' if j % 2 == 0 else 'l') if sd == 'z' else sd   # z：左右交错（偶数节右、奇数节左）
    return out


FB = ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc', 13)


def rad(k):
    """节点占地半径（同游戏：普通盘 8 格 = 16，质变盘 11 格 = 22 + 放射条纹到 34）"""
    return 30 if k in KEY else 17


FS = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 11)
FULL = False   # 方向二：名称 + 一行效果


SIDE = {}   # 节点 id → 标签方向（place 时按线填）


def label_box(k, x, y):
    r = 22 if k in KEY else 16
    off = 16 if k in KEY else 6          # 同游戏 _draw_labels：名字在盘下方 r + off；侧放时离盘边 off + 6
    name = NODES[k]['name']
    w = sum(FB.getlength(ch) for ch in name)
    h = 18
    if FULL:
        w = max(w, sum(FS.getlength(ch) for ch in effect_line(k)))
        h = 36
    side = SIDE.get(k, 'b')
    if side == 'r':
        x0 = x + r + off + 6
        return (x0, y - h / 2, x0 + w + 4, y + h / 2)
    if side == 'l':
        x1 = x - r - off - 6
        return (x1 - w - 4, y - h / 2, x1, y + h / 2)
    return (x - w / 2 - 2, y + r + off, x + w / 2 + 2, y + r + off + h)


def check(lay, pos):
    probs = []
    items = []
    for k, (x, y) in pos.items():
        r = rad(k)
        items.append(('disc', k, (x - r, y - r, x + r, y + r)))
        items.append(('lab', k, label_box(k, x, y)))
    def ov(a, b):
        return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]
    for i in range(len(items)):
        for j in range(i + 1, len(items)):
            if items[i][1] != items[j][1] and ov(items[i][2], items[j][2]):
                probs.append((items[i][0] + ':' + items[i][1], items[j][0] + ':' + items[j][1]))
    for kind, k, b in items:
        for z in lay['keep']:
            if ov(b, z):
                probs.append((kind + ':' + k, 'keep' + str(z)))
        if b[0] < 0 or b[2] > lay['world'][0] or b[3] > lay['world'][1]:
            probs.append((kind + ':' + k, 'out'))
    return probs, items


def preview(lay, pos, items, probs, path):
    W, H = lay['world']
    im = Image.new('RGB', (W, H), (8, 20, 34))
    d = ImageDraw.Draw(im, 'RGBA')
    for z in lay['keep']:
        d.rectangle(z, fill=(255, 255, 255, 18), outline=(255, 255, 255, 40))
    cx, cy = lay['crown']
    d.polygon([(cx - 26, 0), (cx + 26, 0), (cx + 10, cy), (cx - 10, cy)], fill=(30, 60, 90))
    for m in lay['mains'].values():
        pts, _ = samples(m[:4])
        for i, q in enumerate(pts):
            w = m[4] + (m[5] - m[4]) * i / len(pts)
            d.ellipse((q[0] - w / 2, q[1] - w / 2, q[0] + w / 2, q[1] + w / 2), fill=(70, 110, 140))
    for p in lay['roots']:
        c, _, _ = curve_of(lay, p)
        pts, _ = samples(c)
        d.line(pts, fill=(120, 170, 200), width=3)
    bad = {a.split(':')[1] for a, _ in probs} | {b.split(':')[1] for _, b in probs if ':' in b}
    for kind, k, b in items:
        x, y = pos[k]
        if kind == 'disc':
            r = rad(k)
            d.ellipse((x - r, y - r, x + r, y + r), fill=(10, 14, 20), outline=(255, 90, 90) if k in bad else (230, 236, 240), width=2)
        else:
            d.rectangle(b, outline=(255, 90, 90, 200) if k in bad else (120, 140, 160, 100))
            d.text((b[0] + 2, b[1]), NODES[k]['name'], font=FB, fill=(230, 236, 240))
    im.save(path)


def main():
    global FULL
    FULL = True
    pos2 = place(ORIG)
    probs2, items2 = check(ORIG, pos2)
    for a, b in probs2:
        print('orig overlap', a, b)
    print('orig problems', len(probs2))
    preview(ORIG, pos2, items2, probs2, ROOT / 'build/meta_ui/layout_orig.png')
    FULL = False
    pos = place(SCENE)
    probs, items = check(SCENE, pos)
    for a, b in probs:
        print('overlap', a, b)
    print('problems', len(probs))
    preview(SCENE, pos, items, probs, ROOT / 'build/meta_ui/layout_scene.png')
    out = {'_doc': '认知塑造根系布局（art/incoming/meta_ui_1025/layout.py 生成，别手改）：mains 主根 [P0..P3, 起点宽, 末端宽]；'
                   'roots 每条线 [主根, 分叉处 t, P1, P2, P3, 节点 t0, t1]，P0 取主根上 t 处，节点按弧长在 [t0, t1] 等分',
           'scene': SCENE, 'orig': ORIG}
    (ROOT / 'game/data/meta_roots.json').write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding='utf-8')


if __name__ == '__main__':
    main()
