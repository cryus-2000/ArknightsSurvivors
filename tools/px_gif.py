# -*- coding: utf-8 -*-
"""pixelfx 放开版统一 GIF 自查图（协调人 11-04，用户要在录像前先看全员按新口径自查后的 GIF；docs/242 §14.26）。

每招一个 GIF：E0 / E1 / E2 三格并排，统一 3 倍（1x 美术像素 × 3，人物 / 怪 / 帧条同一倍率），速度按 V6_FRAMES 的 fps。
按实战摆（用户 11-04「特效要打在怪身上」）：干员站左边，3 只普通怪摆在攻击方向、射程以内，另放一颗敌弹 #33ceff 和一颗经验结晶看撞色；
  - 近战 / 自身类：帧条原点在干员脚底；
  - 落点 / 命中类（注册表 hit / bullet / debride / mark_zone / proj 键下）：原点在怪脚下；
  - 敌人身上附件（注册表 status 键下）：挂在怪头顶；
  - 弹体（proj_ 前缀）：从干员飞到怪（直线，0.3 秒），到了接注册表 bullet.hit 的命中帧条；
  - 命中那一刻怪闪白一帧、往后退几像素（只在 GIF 里画）。
叠层：地面层（名字含 floor / ground）→ 本体 → 前景层，每条先 _deco 后核心。
循环：帧条源码 meta.loop 为 true（按 tools/pixelfx_fx/targets_*.json 找源码），或注册表 aura / side / hook / sp_mote / mark_zone / status / hold 键下的，
  按无缝循环播（不停顿；等宽帧条按脚底对齐），也可 --loop 指定；其余一次性的播完停 0.5 秒再循环。
帧条：已导出进 game/art/fx/ 的 <前缀>* 和 proj_<x>_ul_*，全部收（不限注册表）；打包帧条按 game/data/px_frames.json 取帧和原点。
输出：<主仓库>/Claude outputs/pixelfx_gif/<干员>/<招>.gif，和总览 <干员>_index.png（每招 E2 格画面最满的一帧）。

用法：python tools/px_gif.py <干员> [--only 招,…] [--scale 3] [--prefix fx_x_ul_] [--land 招,…] [--loop 招,…] [--out 目录]
招 = 帧条名去掉前缀（缺省从注册表读）和 _e0 / _e1 / _e2、变体数字、_tm / _deco / _lo 后缀；弹体招名前加 proj:（文件名 proj_<招>.gif）。
"""
import argparse, glob, json, os, re, sys
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
FLIGHT = 0.3
FONT = "C:/Windows/Fonts/msyh.ttc"
LAND_KEYS = ("hit", "debride", "bullet", "mark_zone", "proj")
STATUS_KEYS = ("status",)
LOOP_KEYS = ("aura", "side", "hook", "sp_mote", "mark_zone", "status", "hold")


def v6_frames():
    src = open(os.path.join(ROOT, "game", "scripts", "art.gd"), encoding="utf-8").read()
    return {m.group(1): (int(m.group(2)), float(m.group(3))) for m in re.finditer(r'"([\w@]+)": \[(\d+), ([\d.]+)\]', src)}


def index():
    return json.load(open(os.path.join(ART, "index.json"), encoding="utf-8"))


def res_path(idx, name):
    p = idx.get(name)
    return os.path.join(ROOT, "game", p[len("res://"):].replace("/", os.sep)) if p else None


def src_loops():
    """帧条名 → 源码 meta.loop（导出目标 targets_*.json 的 fx 指向 tools/pixelfx_fx/<类>/<名>.js）"""
    out, cache = {}, {}
    for f in glob.glob(os.path.join(TOOLS, "pixelfx_fx", "targets_*.json")):
        for k, v in json.load(open(f, encoding="utf-8")).items():
            if k.startswith("_") or not isinstance(v, dict) or "fx" not in v:
                continue
            js = os.path.join(TOOLS, "pixelfx_fx", v["fx"] + ".js")
            if js not in cache:
                txt = open(js, encoding="utf-8").read() if os.path.exists(js) else ""
                m = re.search(r"export const meta\s*=\s*\{(.*?)\n\};", txt, re.S)
                cache[js] = bool(m and re.search(r"\bloop:\s*true", m.group(1))) or bool(re.search(r"export const meta\s*=\s*\{[^\n]*\bloop:\s*true", txt))
            out[k] = cache[js]
    return out


class Strip:
    """一条帧条：frames[i] = (RGBA 图, 原点 x, 原点 y)，坐标是 1x 美术像素"""
    def __init__(self, name, idx, v6, packed, loop=False):
        self.name, self.loop = name, loop
        p = res_path(idx, name)
        self.ok = bool(p and os.path.exists(p))
        self.frames, self.fps = [], 10.0
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
            for i in range(max(1, n)):   # 等宽帧条：循环类（身上常驻）按脚底对齐，其余按帧中心（同游戏 fx_frame）
                self.frames.append((im.crop((i * fw, 0, (i + 1) * fw, im.height)), fw // 2, im.height if loop else im.height // 2))

    def dur(self):
        return len(self.frames) / max(1.0, self.fps)

    def at(self, t):
        if not self.frames or t < 0:
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
        if any(a.getpixel((x, y)) for y in range(im.height)):
            started = True
        elif started:
            return im.crop((0, 0, x, im.height))
    return im


def reg_info(op):
    """从注册表 data/px_ul.json 读：帧条前缀、落点类 / 附件类 / 循环类帧条基名、弹体命中帧条"""
    p = os.path.join(ROOT, "game", "data", "px_ul.json")
    reg = json.load(open(p, encoding="utf-8")).get(op, {}) if os.path.exists(p) else {}
    bases, land, status, loop = [], set(), set(), set()

    def walk(n, keys):
        if isinstance(n, dict):
            for k, v in n.items():
                walk(v, keys + (k,))
        elif isinstance(n, list):
            for v in n:
                walk(v, keys)
        elif isinstance(n, str) and "_ul_" in n and n.startswith(("fx_", "proj_")):
            bases.append(n)
            if any(k in LAND_KEYS for k in keys):
                land.add(n)
            if any(k in STATUS_KEYS for k in keys):
                status.add(n)
            if any(k in LOOP_KEYS for k in keys):
                loop.add(n)
    walk(reg, ())
    fxb = [b for b in bases if b.startswith("fx_")]
    pres = sorted({b[:b.index("_ul_") + 4] for b in fxb}, key=lambda x: -sum(1 for b in fxb if b.startswith(x)))
    bl = reg.get("bullet")
    bh = bl.get("hit") if isinstance(bl, dict) else None
    return (pres[0] if pres else "fx_%s_ul_" % op), land, status, loop, (bh.get("base") if isinstance(bh, dict) else None)


def shape_centers(op, reg_shapes):
    """注册表 shapes 登记的帧条 → 判定段的 center（self / leader / target / front …，取自干员 JSON 的圆形 / 锥形段；总组长 11-04：
    乌尔比安锚击 / 撼地、歌蕾蒂娅落点类原来一律画在干员脚底）"""
    p = os.path.join(ROOT, "game", "data", "characters", op + ".json")
    cen = {}

    def walk(n):
        if isinstance(n, dict):
            if n.get("shape") in ("circle", "cone") and n.get("src"):
                cen.setdefault(str(n.get("px_key", n["src"])), str(n.get("center", "self")))
            for v in n.values():
                walk(v)
        elif isinstance(n, list):
            for v in n:
                walk(v)
    if os.path.exists(p):
        walk(json.load(open(p, encoding="utf-8")))
    out = {}
    for k, e in (reg_shapes or {}).items():
        c = cen.get(k)
        if c is None or not isinstance(e, dict):
            continue
        for kk, v in e.items():   # base / alt / alt_base …：所有帧条名都按这一段的 center 摆
            for b in (v if isinstance(v, list) else [v]):
                if isinstance(b, str) and b.startswith("fx_"):
                    out[b] = c
    return out


def seg_land(op, pre):
    """seg_*.gd 里 _<id>_ul_fx(…) 调用放的帧条：命中写在 seg 里的落点类（逻各斯，组长 B 11-04）"""
    import glob
    out = set()
    for f in glob.glob(os.path.join(ROOT, "game", "scripts", "characters", "blocks", "seg_*.gd")):
        for line in open(f, encoding="utf-8"):
            if not re.search(r"_ul_fx\(", line):
                continue
            for lit in re.findall(r'"([^"]+)"', line):
                if lit.startswith(pre):
                    out.add(lit)
                elif re.fullmatch(r"[a-z0-9_]+", lit) and ("_%s_" % op in line or op in os.path.basename(f)):
                    out.add(pre + lit)
    return out


def pick(d, el):
    """和 vfx.px_ul_tex 同一查找顺序（基名 = E2）：精二 _e2 → 基名 → _e1 → _e0；精一 / 精零 本档 → 更低档 → 基名；
    单档帧条（例 fx_siege_ul_crush_e1）取不到时退回现有任一档（总组长 11-04：原来取 base 得 None 就崩）"""
    order = [2, 1, 0] if el >= 2 else list(range(el, -1, -1)) + [2]
    for e in order:
        if d.get(e):
            return d[e]
    return next(iter(d.values()))


def moves(idx, pres):
    """招 → {精英档: 帧条名}；E2 优先取 <招>_e2，没有就取不带档位的 <招>；弹体招名前加 proj:"""
    out = {}
    for k in idx:
        pre = next((p for p in pres if k.startswith(p)), None)
        if pre is None or "@" in k:
            continue
        rest = k[len(pre):]
        if re.search(r"(_deco|_lo|_tm)$", rest) or "_tm_" in rest or "_deco_" in rest:
            continue
        tag = "proj:" if pre.startswith("proj_") else ""
        m = re.match(r"^(.*)_e([012])(\d*)$", rest)
        if m:
            if m.group(3):
                continue   # 种子变体（_e22 …）不另算
            out.setdefault(tag + m.group(1), {})[int(m.group(2))] = k
        else:
            out.setdefault(tag + rest, {}).setdefault(2, k)
    return out


def tint_white(im, k):
    w = Image.new("RGBA", im.size, (255, 255, 255, 0))
    w.putalpha(im.getchannel("A").point(lambda v: int(v * k)))
    out = im.copy()
    out.alpha_composite(w)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("op")
    ap.add_argument("--only", default="")
    ap.add_argument("--scale", type=int, default=3)
    ap.add_argument("--out", default="")
    ap.add_argument("--prefix", default="", help="帧条前缀（缺省从注册表自动读，例 fx_specter_ul_）")
    ap.add_argument("--land", default="", help="逗号分隔的招名：按落点（敌人处）放")
    ap.add_argument("--loop", default="", help="逗号分隔的招名：按无缝循环播")
    a = ap.parse_args()
    K = a.scale
    idx, v6, sl = index(), v6_frames(), src_loops()
    pk_path = os.path.join(ROOT, "game", "data", "px_frames.json")
    packed = json.load(open(pk_path, encoding="utf-8")) if os.path.exists(pk_path) else {}
    out_dir = a.out or os.path.join(GR.common_root(), "Claude outputs", "pixelfx_gif", a.op)
    os.makedirs(out_dir, exist_ok=True)
    pre, land_b, status_b, loop_b, bullet_hit = reg_info(a.op)
    pre = a.prefix or pre
    pres = [pre, "proj_" + pre[3:] if pre.startswith("fx_") else "proj_%s_ul_" % a.op]
    mv = moves(idx, pres)
    only = set(filter(None, a.only.split(",")))
    if only:
        mv = {k: v for k, v in mv.items() if k in only}
    if not mv:
        sys.exit("没有找到 %s* / %s* 帧条（先导出并跑 tools/asset_index.py；前缀不对用 --prefix）" % tuple(pres))
    hit_of = lambda d, S: any(n in S or any(n.startswith(b) for b in S) for n in d.values())
    regj = json.load(open(os.path.join(ROOT, "game", "data", "px_ul.json"), encoding="utf-8")).get(a.op, {})
    cen = shape_centers(a.op, regj.get("shapes"))
    land_b = set(land_b) | {b for b, c in cen.items() if c == "target"} | seg_land(a.op, pre)
    front_b = {b for b, c in cen.items() if c == "front"}
    self_b = {b for b, c in cen.items() if c in ("self", "leader")}
    land_mv = set(filter(None, a.land.split(","))) | {m for m, d in mv.items() if hit_of(d, land_b) and not hit_of(d, self_b)}
    front_mv = {m for m, d in mv.items() if hit_of(d, front_b)} - land_mv   # center: front = 砸在身前（朝敌人）
    status_mv = {m for m, d in mv.items() if hit_of(d, status_b)}
    loop_mv = set(filter(None, a.loop.split(","))) | {m for m, d in mv.items() if hit_of(d, loop_b) or any(sl.get(n, False) for n in d.values())}
    print("帧条前缀 %s；落点类 %s；附件类 %s；循环类 %s" % (pre, "、".join(sorted(land_mv)) or "无", "、".join(sorted(status_mv)) or "无", "、".join(sorted(loop_mv)) or "无"))
    body = first_frame(idx, "op_%s_idle@2x" % a.op) or first_frame(idx, "op_%s_idle@1x" % a.op)
    foe = first_frame(idx, "e_runner@2x")
    gem = first_frame(idx, "gem_small", square=False)
    ft = ImageFont.truetype(FONT, 16) if os.path.exists(FONT) else ImageFont.load_default()
    hit_strip = None
    if bullet_hit:
        hit_strip = {}
        for el in (0, 1, 2):
            nm = bullet_hit + "_e%d" % el
            nm = nm if idx.get(nm) else bullet_hit
            hit_strip[el] = (Strip(nm, idx, v6, packed), Strip(nm + "_deco", idx, v6, packed))
    thumbs = []
    for name in sorted(mv):
        is_proj, is_land, is_status, is_loop = name.startswith("proj:"), name in land_mv, name in status_mv, name in loop_mv
        is_front = name in front_mv
        is_muzzle = "muzzle" in name   # 枪口类：帧条朝右（aim 朝向），摆在干员枪口（身前、约半身高），不画在脚底 / 背后（总组长 11-04：能天使）
        cells = []
        for el in (0, 1, 2):
            base = pick(mv[name], el)
            core = Strip(base, idx, v6, packed, is_loop)
            deco = Strip(base + "_deco", idx, v6, packed, is_loop)
            cells.append((el, core, deco if deco.ok else None, mv[name].get(el) is not None))
        ext = 30
        for el, core, deco, own in cells:
            for s in (core, deco):
                if s and s.ok:
                    for im, ox, oy in s.frames:
                        if im is not None:
                            ext = max(ext, ox, oy, im.width - ox, im.height - oy)
        R = min(int(ext * K) + 40, 420)
        CW = int(2.4 * R)
        LH = max(56, CW // 6)   # 顶部档位标题带：大号「E0 / E1 / E2」，三格缩到手机宽也看得清（总组长 11-04）
        CH = 2 * R + 30 + LH
        ftb = ImageFont.truetype(FONT, LH - 10) if os.path.exists(FONT) else ft
        ox_, oy_ = int(CW * 0.2), (CH + LH) // 2 + 40   # 干员脚底
        reach = int(min(max(ext * K * 0.8, 130), CW - ox_ - 60))
        foes = [(ox_ + reach, oy_), (ox_ + reach + 34, oy_ - 46), (ox_ + reach + 14, oy_ + 48)]
        # 命中时刻：近战 = 帧条外沿第一次够到怪的那一帧；落点 / 附件 = 0；弹体 = 飞到的时刻
        ti = 0.0
        if is_proj:
            ti = FLIGHT
        elif not (is_land or is_status):
            s = cells[2][1]
            ti = 0.08
            if s.ok:
                for i, (im, fx0, fy0) in enumerate(s.frames):
                    if im is not None and (im.width - fx0) * K >= reach * 0.85:
                        ti = i / s.fps
                        break
        T = max(max(c[1].dur() if c[1].ok else 0.0, c[2].dur() if c[2] else 0.0) for c in cells)
        if is_proj:
            T = FLIGHT + max((hit_strip[c[0]][0].dur() if hit_strip and hit_strip[c[0]][0].ok else 0.25) for c in cells)
        total = max(T, 1.0) if is_loop else T + HOLD
        nfr = max(1, int(round(total * FPS_OUT)))
        imgs = []
        for i in range(nfr):
            t = i / FPS_OUT
            row = Image.new("RGB", (CW * 3, CH), GROUND)
            for ci, (el, core, deco, own) in enumerate(cells):
                cell = Image.new("RGBA", (CW, CH), GROUND + (255,))
                d = ImageDraw.Draw(cell)
                kb = 0.0 if t < ti or is_loop else 8.0 * max(0.0, 1.0 - (t - ti) / 0.25)   # 受击后退
                flash = (not is_loop) and ti <= t < ti + 1.0 / FPS_OUT + 1e-6
                ex, ey = foes[0][0] + int(kb), foes[0][1]
                fh = foe.height * K if foe else 60

                def put(s, front, tt, ax, ay):
                    if not (s and s.ok) or (("floor" in s.name or "ground" in s.name) != (not front)):
                        return
                    f = s.at(tt)
                    if f and f[0] is not None:
                        im = f[0].resize((f[0].width * K, f[0].height * K), Image.NEAREST)
                        cell.alpha_composite(im, (ax - f[1] * K, ay - f[2] * K))

                def layer(front):
                    if is_proj:
                        if t < FLIGHT:
                            k = t / FLIGHT
                            ax, ay = int(ox_ + (ex - ox_) * k), int(oy_ - 40 + (ey - fh // 2 - (oy_ - 40)) * k)
                            for s in (deco, core):
                                put(s, front, t, ax, ay)
                        elif hit_strip:
                            hc, hd = hit_strip[el]
                            for s in (hd, hc):
                                put(s, front, t - FLIGHT, ex, ey - fh // 2)
                        return
                    ax, ay = (ex, ey - fh - 6) if is_status else (ex, ey) if is_land else (ox_ + int(reach * 0.6), oy_) if is_front else (ox_ + 9 * K, oy_ - int((body.height if body else 32) * K * 0.5)) if is_muzzle else (ox_, oy_)
                    for s in (deco, core):
                        put(s, front, t, ax, ay)
                layer(False)   # 地面层
                if body:
                    b = body.resize((body.width * K, body.height * K), Image.NEAREST)
                    cell.alpha_composite(b, (ox_ - b.width // 2, oy_ - b.height + 4))
                if foe:
                    fe = foe.resize((foe.width * K, foe.height * K), Image.NEAREST).transpose(Image.FLIP_LEFT_RIGHT)   # 怪面朝干员
                    for fx0, fy0 in foes:
                        im = tint_white(fe, 0.85) if flash else fe
                        cell.alpha_composite(im, (fx0 + int(kb) - fe.width // 2, fy0 - fe.height))
                br = int(3 * K)
                bx, by = int(ox_ + reach * 0.55), int(oy_ - 0.5 * R)
                d.ellipse((bx - br, by - br, bx + br, by + br), fill=BULLET + (255,))
                if gem:
                    g2 = gem.resize((gem.width * K, gem.height * K), Image.NEAREST)
                    cell.alpha_composite(g2, (int(ox_ + reach * 0.45), int(oy_ + 0.42 * R)))
                layer(True)   # 前景层
                tag = "　落点（敌人处）" if is_land else "　身前" if is_front else "　敌人头顶" if is_status else "　弹体" if is_proj else ""
                d.rectangle((0, 0, CW, LH), fill=(10, 16, 28, 255))
                d.text((10, 2), "E%d" % el, font=ftb, fill=((150, 160, 175), (120, 200, 255), (255, 214, 102))[el] + (255,))
                d.text((10 + int(LH * 1.5), LH // 2 - 9), "%s%s%s" % ("" if own else "（同 E2）", tag.strip("　"), "　循环" if is_loop else ""), font=ft, fill=(200, 210, 225, 255))
                row.paste(cell.convert("RGB"), (ci * CW, 0))
            imgs.append(row)
        fn = name.replace("proj:", "proj_")
        gif = os.path.join(out_dir, "%s.gif" % fn)
        imgs[0].save(gif, save_all=True, append_images=imgs[1:], duration=int(1000 / FPS_OUT), loop=0, optimize=False, disposal=1)

        def busy(im):   # 总览取 E2 格里画面最满的一帧
            c = im.crop((2 * CW, LH, 3 * CW, CH)).convert("RGB").resize((CW // 4, (CH - LH) // 4))
            return sum(1 for px in c.getdata() if abs(px[0] - GROUND[0]) + abs(px[1] - GROUND[1]) + abs(px[2] - GROUND[2]) > 40)
        mid = max(imgs[: max(1, int(len(imgs) * 0.8))][::2], key=busy)
        thumbs.append((fn, mid.crop((2 * CW, LH, 3 * CW, CH))))
        print("%s：%d 帧（%.2f 秒%s）→ %s" % (fn, nfr, total, "，循环" if is_loop else "", gif))
    tw, cols = 300, 3
    rows_n = (len(thumbs) + cols - 1) // cols
    th = max(int(tw * im.height / im.width) for _, im in thumbs)
    sheet = Image.new("RGB", (cols * tw, rows_n * (th + 24)), (6, 12, 24))
    d = ImageDraw.Draw(sheet)
    for i, (name, im) in enumerate(thumbs):
        x, y = (i % cols) * tw, (i // cols) * (th + 24)
        sheet.paste(im.resize((tw, int(im.height * tw / im.width))), (x, y + 24))
        d.text((x + 6, y + 2), "%s（E2）" % name, font=ft, fill=(220, 230, 240))
    p = os.path.join(out_dir, "%s_index.png" % a.op)
    sheet.save(p)
    print("总览 " + p)


if __name__ == "__main__":
    main()
