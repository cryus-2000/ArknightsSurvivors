# -*- coding: utf-8 -*-
"""pixelfx 放开版统一 GIF 自查图（协调人 11-04，用户要在录像前先看全员按新口径自查后的 GIF；docs/242 §14.26）。

每招一个 GIF：E0 / E1 / E2 三格并排，统一 3 倍（1x 美术像素 × 3），速度与游戏一致（V6_FRAMES 的 fps）。
每格：游戏地面色底、干员待机首帧、2–3 只普通怪（e_runner 首帧）、一颗敌弹 #33ceff、一颗经验结晶（gem_small），方便看大小和撞色。
叠层：地面层（名字含 floor / ground 的帧条）→ 本体（干员 / 怪 / 弹 / 结晶）→ 前景层；每条帧条先画 _deco（装饰）再画核心。
一次性特效播完停 0.5 秒再循环；名字含 aura / loop / hold / orbit / shell 的按循环播（无缝）。
帧条读 game/art/fx/<名>.png，打包帧条按 game/data/px_frames.json 取帧和原点，等宽帧条按帧中心；原点放在干员脚底。
输出：<主仓库>/Claude outputs/pixelfx_gif/<干员>/<招>.gif，和总览 <干员>_index.png（每招 E2 中段一帧）。

用法：python tools/px_gif.py <干员> [--only 招,…] [--scale 3] [--out 目录]
招 = 帧条名去掉前缀（缺省从注册表读，--prefix 可改）和 _e0 / _e1 / _e2、变体数字、_tm / _deco / _lo 后缀。
落点类招（注册表里 hit / status / bullet / debride / mark_zone / proj 键下的帧条，或 --land 指定）原点放在第一只怪脚下，格子里标「实际出现在落点」。
"""
import argparse, json, os, re, sys
from PIL import Image, ImageDraw, ImageFont

for _s in (sys.stdout, sys.stderr):
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8", errors="replace")
TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
import godot_runner as GR

ART = os.path.join(ROOT, "game", "art")
GROUND = (32, 50, 60)                 # 游戏地面主色（实战截图取样）
BULLET = (0x33, 0xCE, 0xFF)
FPS_OUT = 30
HOLD = 0.5
LOOP_KEYS = ("aura", "loop", "hold", "orbit", "shell")
FONT = "C:/Windows/Fonts/msyh.ttc"


def v6_frames():
    src = open(os.path.join(ROOT, "game", "scripts", "art.gd"), encoding="utf-8").read()
    return {m.group(1): (int(m.group(2)), float(m.group(3))) for m in re.finditer(r'"([\w@]+)": \[(\d+), ([\d.]+)\]', src)}


def index():
    return json.load(open(os.path.join(ART, "index.json"), encoding="utf-8"))


def res_path(idx, name):
    p = idx.get(name)
    return os.path.join(ROOT, "game", p[len("res://"):].replace("/", os.sep)) if p else None


class Strip:
    """一条帧条：frames[i] = (RGBA 图, 原点 x, 原点 y)，坐标是 1x 美术像素"""
    def __init__(self, name, idx, v6, packed):
        self.name = name
        p = res_path(idx, name)
        self.ok = bool(p and os.path.exists(p))
        self.frames = []
        if not self.ok:
            return
        im = Image.open(p).convert("RGBA")
        if "@2x" in os.path.basename(p):
            im = im.resize((im.width // 2, im.height // 2), Image.NEAREST)
        n, self.fps = v6.get(name, (1, 10.0))
        if name in packed:
            for x, y, w, h, ox, oy in packed[name]:
                self.frames.append((im.crop((x, y, x + w, y + h)) if w > 0 and h > 0 else None, ox, oy))
        else:
            fw = im.width // max(1, n)
            for i in range(max(1, n)):
                self.frames.append((im.crop((i * fw, 0, (i + 1) * fw, im.height)), fw // 2, im.height // 2))
        self.loop = any(k in name for k in LOOP_KEYS)

    def dur(self):
        return len(self.frames) / max(1.0, self.fps)

    def at(self, t):
        if not self.frames:
            return None
        k = int(t * self.fps)
        if self.loop:
            k %= len(self.frames)
        elif k >= len(self.frames):
            return None
        return self.frames[k]


def first_frame(idx, name, square=True):
    p = res_path(idx, name)
    if not p:
        return None
    im = Image.open(p).convert("RGBA")
    if "@2x" in os.path.basename(p):
        im = im.resize((im.width // 2, im.height // 2), Image.NEAREST)
    if not square:
        return im
    if im.width % im.height == 0:
        return im.crop((0, 0, im.height, im.height))
    a = im.getchannel("A")   # 等宽不整除时按第一段空列切
    started = False
    for x in range(im.width):
        col = any(a.getpixel((x, y)) for y in range(im.height))
        if col:
            started = True
        elif started:
            return im.crop((0, 0, x, im.height))
    return im


LAND_KEYS = ("hit", "debride", "status", "bullet", "mark_zone", "proj")   # 注册表里这些键下的帧条在敌人 / 落点处播


def reg_info(op):
    """从注册表 data/px_ul.json 读：帧条前缀（fx_<x>_ul_，归溟幽灵鲨 id 是 specter_unchained、前缀是 fx_specter_ul_）和落点类帧条基名"""
    p = os.path.join(ROOT, "game", "data", "px_ul.json")
    reg = json.load(open(p, encoding="utf-8")).get(op, {}) if os.path.exists(p) else {}
    bases, land = [], set()

    def walk(n, under_land):
        if isinstance(n, dict):
            for k, v in n.items():
                walk(v, under_land or k in LAND_KEYS)
        elif isinstance(n, list):
            for v in n:
                walk(v, under_land)
        elif isinstance(n, str) and "_ul_" in n and n.startswith(("fx_", "proj_")):
            bases.append(n)
            if under_land:
                land.add(n)
    walk(reg, False)
    pres = sorted({b[:b.index("_ul_") + 4] for b in bases}, key=lambda x: -sum(1 for b in bases if b.startswith(x)))
    return (pres[0] if pres else "fx_%s_ul_" % op), land


def moves(op, idx, pre=None):
    """招 → {精英档: 帧条名}；E2 优先取 <招>_e2，没有就取不带档位的 <招>"""
    pre = pre or "fx_%s_ul_" % op
    out = {}
    for k in idx:
        if not k.startswith(pre) or "@" in k:
            continue
        rest = k[len(pre):]
        if re.search(r"(_deco|_lo|_tm)$", rest) or "_tm_" in rest or "_deco_" in rest:
            continue
        m = re.match(r"^(.*)_e([012])(\d*)$", rest)
        if m:
            if m.group(3):
                continue   # 种子变体（_e22 …）不另算
            out.setdefault(m.group(1), {})[int(m.group(2))] = k
        else:
            out.setdefault(rest, {}).setdefault(2, k)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("op")
    ap.add_argument("--only", default="")
    ap.add_argument("--scale", type=int, default=3)
    ap.add_argument("--out", default="")
    ap.add_argument("--prefix", default="", help="帧条前缀（缺省从注册表自动读，例 fx_specter_ul_）")
    ap.add_argument("--land", default="", help="逗号分隔的招名：按落点（敌人处）放；缺省按注册表里 hit / status / bullet / debride 等键自动认")
    a = ap.parse_args()
    K = a.scale
    idx, v6 = index(), v6_frames()
    pk_path = os.path.join(ROOT, "game", "data", "px_frames.json")
    packed = json.load(open(pk_path, encoding="utf-8")) if os.path.exists(pk_path) else {}
    out_dir = a.out or os.path.join(GR.common_root(), "Claude outputs", "pixelfx_gif", a.op)
    os.makedirs(out_dir, exist_ok=True)
    pre, land_b = reg_info(a.op)
    pre = a.prefix or pre
    mv = moves(a.op, idx, pre)
    land_mv = set(filter(None, a.land.split(","))) | {m for m, d in mv.items() if any(n in land_b or any(n.startswith(b) for b in land_b) for n in d.values())}
    print("帧条前缀 %s；落点类招 %s" % (pre, "、".join(sorted(land_mv)) or "无"))
    only = set(filter(None, a.only.split(",")))
    if only:
        mv = {k: v for k, v in mv.items() if k in only}
    if not mv:
        sys.exit("没有找到 %s* 帧条（先导出并跑 tools/asset_index.py；前缀不对用 --prefix）" % pre)
    body = first_frame(idx, "op_%s_idle@2x" % a.op) or first_frame(idx, "op_%s_idle@1x" % a.op)
    foe = first_frame(idx, "e_runner@2x")
    gem = first_frame(idx, "gem_small", square=False)
    ft = ImageFont.truetype(FONT, 16) if os.path.exists(FONT) else ImageFont.load_default()
    thumbs = []
    for name in sorted(mv):
        cells = []
        for el in (0, 1, 2):
            base = mv[name].get(el) or mv[name].get(2)
            core = Strip(base, idx, v6, packed) if base else None
            deco = Strip(base + "_deco", idx, v6, packed) if base else None
            cells.append((el, base, core, deco if deco and deco.ok else None, mv[name].get(el) is not None))
        ext = 40   # 按帧条最大外沿定格子
        for el, base, core, deco, own in cells:
            for s in (core, deco):
                if s and s.ok:
                    for im, ox, oy in s.frames:
                        if im is not None:
                            ext = max(ext, ox, oy, im.width - ox, im.height - oy)
        R = min(int(ext * K) + 30, 420)
        CW, CH = 2 * R, 2 * R + 26
        fx_ = CW // 2 - int(R * 0.25)   # 干员脚底（帧条原点）
        fy_ = CH // 2 + 30
        is_land = name in land_mv
        lx, ly = (int(fx_ + 0.62 * R), int(fy_ - 0.18 * R)) if is_land else (fx_, fy_)   # 落点类：原点放在第一只怪脚下
        loop = any(c[2] and c[2].ok and c[2].loop for c in cells)
        T = max(max((c[2].dur() if c[2] and c[2].ok else 0.0), (c[3].dur() if c[3] else 0.0)) for c in cells)
        total = T if loop else T + HOLD
        nfr = max(1, int(round(total * FPS_OUT)))
        imgs = []
        for i in range(nfr):
            t = i / FPS_OUT
            row = Image.new("RGB", (CW * 3, CH), GROUND)
            for ci, (el, base, core, deco, own) in enumerate(cells):
                cell = Image.new("RGBA", (CW, CH), GROUND + (255,))
                d = ImageDraw.Draw(cell)

                def put(s, front):
                    if not (s and s.ok):
                        return
                    if (("floor" in s.name or "ground" in s.name) == front):
                        return
                    f = s.at(t)
                    if f and f[0] is not None:
                        im = f[0].resize((f[0].width * K, f[0].height * K), Image.NEAREST)
                        cell.alpha_composite(im, (lx - f[1] * K, ly - f[2] * K))
                for s in (deco, core):
                    put(s, False)   # 地面层
                if body:
                    b = body.resize((body.width * K, body.height * K), Image.NEAREST)   # 人物 / 怪和帧条一样按 1x 美术像素 × K（游戏里都 × PX）
                    cell.alpha_composite(b, (fx_ - b.width // 2, fy_ - b.height + 4))
                if foe:
                    fe = foe.resize((foe.width * K, foe.height * K), Image.NEAREST)
                    for j, (dx, dy) in enumerate(((0.62, -0.18), (0.78, 0.12), (0.52, 0.32))):
                        cell.alpha_composite(fe, (int(fx_ + dx * R) - fe.width // 2, int(fy_ + dy * R) - fe.height))
                br = int(3 * K)
                bx, by = int(fx_ + 0.42 * R), int(fy_ - 0.42 * R)
                d.ellipse((bx - br, by - br, bx + br, by + br), fill=BULLET + (255,))
                if gem:
                    g2 = gem.resize((gem.width * K, gem.height * K), Image.NEAREST)
                    cell.alpha_composite(g2, (int(fx_ - 0.35 * R), int(fy_ + 0.25 * R)))
                for s in (deco, core):
                    put(s, True)   # 前景层
                d.text((6, 4), "E%d%s%s" % (el, "" if own else "（同 E2）", "　实际出现在落点（敌人处）" if is_land else ""), font=ft, fill=(230, 236, 245, 255))
                row.paste(cell.convert("RGB"), (ci * CW, 0))
            imgs.append(row)
        gif = os.path.join(out_dir, "%s.gif" % name)
        imgs[0].save(gif, save_all=True, append_images=imgs[1:], duration=int(1000 / FPS_OUT), loop=0, optimize=False, disposal=1)
        def busy(im):   # 总览取 E2 格里画面最满的一帧（不取固定时刻，免得落在收尾）
            c = im.crop((2 * CW, 30, 3 * CW, CH)).convert("RGB")
            return sum(1 for px in c.getdata() if abs(px[0] - GROUND[0]) + abs(px[1] - GROUND[1]) + abs(px[2] - GROUND[2]) > 40)
        mid = max(imgs[: max(1, int(len(imgs) * 0.8))][::2], key=busy)
        thumbs.append((name, mid.crop((2 * CW, 0, 3 * CW, CH))))
        print("%s：%d 帧（%.2f 秒%s）→ %s" % (name, nfr, total, "，循环" if loop else "", gif))
    tw = 260
    cols = 4
    rows_n = (len(thumbs) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw, rows_n * (tw + 24)), (6, 12, 24))
    d = ImageDraw.Draw(sheet)
    for i, (name, im) in enumerate(thumbs):
        x, y = (i % cols) * tw, (i // cols) * (tw + 24)
        sheet.paste(im.resize((tw, int(im.height * tw / im.width))).crop((0, 0, tw, tw)), (x, y + 24))
        d.text((x + 6, y + 2), "%s（E2）" % name, font=ft, fill=(220, 230, 240))
    p = os.path.join(out_dir, "%s_index.png" % a.op)
    sheet.save(p)
    print("总览 " + p)


if __name__ == "__main__":
    main()
