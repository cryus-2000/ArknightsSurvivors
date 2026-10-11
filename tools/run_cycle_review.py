# -*- coding: utf-8 -*-
"""跑步帧条审查（docs/64 §9）：量化新干员 `_run` 循环并与已验收干员对照，出对照 GIF / MP4、总览图、实机录像。

用法：
    python tools/run_cycle_review.py                 # 量化 + 对照图（只读 art/incoming，不开 Godot）
    python tools/run_cycle_review.py --capture       # 另外开 Godot 录实机（--autotest 主控绕圈跑，副屏 / 屏幕外，静音）
    python tools/run_cycle_review.py --ops texas,hoshiguma --refs skadi,wisadel,saria

输出：主仓库 build/run_review/
    metrics.json / metrics.md       每条帧条的量化（@2x 为主，游戏读 @2x；像素统一折成 1x 像素）
    compare_<op>.gif / .mp4         新干员 + 3 个参考，@2x × 3 最近邻，manifest fps（10），青线 = 脚底，品红虚线 = 第 0 帧头顶
    compare_all.gif / .mp4          五人 + 参考同框
    contact_sheet.png               逐帧 + 洋葱皮叠影 + 相邻帧差异热区 + 腿部带
    ingame_<op>.gif / ingame_sheet.png   实机录像裁切（--capture）

指标口径（全部按 1x 像素报告；@2x 量出的值 / 2）：
    diff        相邻帧（循环 6 对）RGBA 不同的像素 / 两帧不透明并集，取平均；minpair = 最像的一对
    half        f(i) 与 f(i+3)（半个周期，左右腿应互换）的同一比例，取平均
    bob_top     各帧外框顶行的极差；bob_c = 各帧不透明像素重心 y 的极差（含头发武器，偏小）
    head_bob    头部带（外框顶往下 1/3）重心 y 的极差
    move        剪影实质变化：去掉 1px（@2x 2px）以内的描边抖动后，相邻两帧互不覆盖的像素 / 并集；move_half = f(i) 对 f(i+3)
    leg_move    同上，只看腿部带；leg_move_half = 半周期（左右腿应互换，越大越好）
    upper_move  同上，只看外框上 55%（头、躯干、武器、头发的二次运动）
    leg_xor     腿部带（脚底往上 10px@1x、脚中心 ±12px）剪影异或 / 并集，相邻帧平均
    feet_seq    每帧最低 3 行里分开的着地块数（2 = 两脚分开着地 / 跨步，1 = 并拢或过渡）；feet_alt = 相邻帧之间块数变化的次数
    crouch      跑步外框高 / 待机 f0 外框高（< 0.9 = 整套蹲着跑）
    stride      最低 3 行不透明像素的横向跨度，6 帧里的最大值与极差（迈步大小、着地点是否在变）
    foot_dx     最低行中心 x 的极差（脚底锚点漂移）
    lean        头部带重心相对髋部带（外框 55–75% 高）重心的倾角，度，正 = 向前（朝右）；武器会带偏，只作参考
"""
import argparse, json, math, os, subprocess, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
import godot_runner as gr  # noqa: E402

ART = os.path.join(ROOT, "art", "incoming")
OUT = os.path.join(gr.common_root(ROOT), "build", "run_review")
NEW = ["texas", "hoshiguma", "exusiai", "angelina", "skalter"]
REFS3 = ["skadi", "wisadel", "saria"]
REFS_ALL = ["skadi", "wisadel", "saria", "suzuran", "irene", "ulpianus", "siege", "kaltsit", "logos",
            "eyjafjalla", "specter_unchained", "lumen", "mizuki"]
NAMES = {"texas": "德克萨斯", "hoshiguma": "星熊", "exusiai": "能天使", "angelina": "安洁莉娜", "skalter": "浊心斯卡蒂",
         "skadi": "斯卡蒂", "wisadel": "维什戴尔", "saria": "塞雷娅", "suzuran": "铃兰", "irene": "艾丽妮",
         "ulpianus": "乌尔比安", "siege": "推进之王", "kaltsit": "凯尔希", "logos": "逻各斯", "eyjafjalla": "艾雅法拉",
         "specter_unchained": "归溟幽灵鲨", "lumen": "流明", "mizuki": "水月"}
BG = (38, 52, 66, 255)
FPS = 10


def strip_path(op, hi=True):
    base = "player_run" if op == "mizuki" else "op_%s_run" % op
    return os.path.join(ART, base + ("@2x" if hi else "") + ".png")


def load(op, hi=True):
    im = Image.open(strip_path(op, hi)).convert("RGBA")
    s = im.height
    n = im.width // s
    return [np.array(im.crop((i * s, 0, (i + 1) * s, s))) for i in range(n)]


# ---------------------------------------------------------------- 量化

def _dilate(m, r):
    o = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            o |= np.roll(np.roll(m, dy, 0), dx, 1)
    return o


def _move(a, b, r=2):
    """剪影「实质变化」：去掉 r 像素以内的描边抖动后，A、B 互不覆盖的像素 / 并集（@2x 取 r = 2，即 1x 的 1px）"""
    u = (a | b).sum()
    return ((a & ~_dilate(b, r)).sum() + (b & ~_dilate(a, r)).sum()) / max(1, u)


def _runs(row):
    """一行里不透明段的个数（段间至少 1 个透明像素）"""
    r = np.concatenate([[0], row.astype(np.int8), [0]])
    return int(np.sum(np.diff(r) == 1))


def metrics(op):
    fr = load(op, True)
    k = 2.0   # @2x → 1x 像素
    n = len(fr)
    s = fr[0].shape[0]
    masks = [f[..., 3] > 0 for f in fr]
    out = {"op": op, "frames": n}

    def pair_ratio(a, b, ma, mb):
        u = ma | mb
        d = np.any(a != b, axis=-1) & u
        return d.sum() / max(1, u.sum())

    pairs = [pair_ratio(fr[i], fr[(i + 1) % n], masks[i], masks[(i + 1) % n]) for i in range(n)]
    out["diff"] = float(np.mean(pairs))
    out["minpair"] = float(np.min(pairs))
    out["pairs"] = [round(float(p), 3) for p in pairs]
    out["sil_xor"] = float(np.mean([(masks[i] ^ masks[(i + 1) % n]).sum() / max(1, (masks[i] | masks[(i + 1) % n]).sum()) for i in range(n)]))
    h = n // 2
    out["half"] = float(np.mean([pair_ratio(fr[i], fr[(i + h) % n], masks[i], masks[(i + h) % n]) for i in range(n)]))

    tops, bots, cys, heads, hips, lean, foot_c, spans, span_l, span_r, legsep = [], [], [], [], [], [], [], [], [], [], []
    for m in masks:
        ys, xs = np.nonzero(m)
        top, bot = ys.min(), ys.max()
        tops.append(top / k)
        bots.append(bot / k)
        cys.append(ys.mean() / k)
        hgt = bot - top + 1
        hb = m[top: top + hgt // 3]
        hy, hx = np.nonzero(hb)
        heads.append(((hy.mean() + top) / k, hx.mean() / k))
        lo, hi_ = top + int(hgt * 0.55), top + int(hgt * 0.75)
        py, px = np.nonzero(m[lo:hi_])
        hips.append(((py.mean() + lo) / k, px.mean() / k))
        dy = hips[-1][0] - heads[-1][0]
        dx = heads[-1][1] - hips[-1][1]
        lean.append(math.degrees(math.atan2(dx, dy)))
        xs_b = np.nonzero(m[bot])[0]
        foot_c.append(xs_b.mean() / k)
        low = np.nonzero(m[bot - 5: bot + 1].any(axis=0))[0]   # 最低 3 行（@2x 6 行）
        spans.append((low.max() - low.min() + 1) / k)
        span_l.append(low.min() / k)
        span_r.append(low.max() / k)
        # 腿部带：脚底往上 20 行 @2x（10px@1x），横向取脚中心 ±24（±12@1x）
        fc = int(round(xs_b.mean()))
        band = m[bot - 19: bot + 1, max(0, fc - 24): min(s, fc + 25)]
        legsep.append(_runs(m[bot - 5: bot + 1].any(axis=0)))   # 最低 3 行（1x）里分开的着地块数：两脚分开 = 2，并拢 / 过渡 = 1
    out["bob_top"] = float(max(tops) - min(tops))
    out["bob_c"] = float(max(cys) - min(cys))
    out["head_bob"] = float(max(h[0] for h in heads) - min(h[0] for h in heads))
    out["tops"] = [round(t, 1) for t in tops]
    out["height"] = float(np.mean([b - t + 1 / k for t, b in zip(tops, bots)]))
    out["foot_dx"] = float(max(foot_c) - min(foot_c))
    out["stride_max"] = float(max(spans))
    out["stride_rng"] = float(max(spans) - min(spans))
    out["contact_l_rng"] = float(max(span_l) - min(span_l))
    out["contact_r_rng"] = float(max(span_r) - min(span_r))
    out["lean"] = float(np.mean(lean))
    out["lean_rng"] = float(max(lean) - min(lean))
    out["feet_seq"] = "".join(str(v) for v in legsep)
    out["feet_alt"] = int(sum(1 for i in range(n) if legsep[i] != legsep[(i + 1) % n]))   # 着地块数在相邻帧之间变化的次数（有交替 ≥ 2）
    idle = Image.open(strip_path(op).replace("_run@2x", "_idle@2x")).convert("RGBA") if op != "mizuki" else Image.open(os.path.join(ART, "player_idle@2x.png")).convert("RGBA")
    im0 = np.array(idle.crop((0, 0, idle.height, idle.height)))[..., 3] > 0
    iy = np.nonzero(im0)[0]
    out["idle_h"] = float((iy.max() - iy.min() + 1) / k)
    # 腿部带剪影异或（固定窗口：所有帧共用脚底行与第 0 帧脚中心）
    bot0 = max(int(b * k) for b in bots)
    fc0 = int(round(np.mean(foot_c) * k))
    lb = [m[bot0 - 19: bot0 + 1, max(0, fc0 - 24): fc0 + 25] for m in masks]
    out["leg_xor"] = float(np.mean([(lb[i] ^ lb[(i + 1) % n]).sum() / max(1, (lb[i] | lb[(i + 1) % n]).sum()) for i in range(n)]))
    out["move"] = float(np.mean([_move(masks[i], masks[(i + 1) % n]) for i in range(n)]))
    out["move_half"] = float(np.mean([_move(masks[i], masks[(i + h) % n]) for i in range(n)]))
    out["leg_move"] = float(np.mean([_move(lb[i], lb[(i + 1) % n]) for i in range(n)]))
    out["leg_move_half"] = float(np.mean([_move(lb[i], lb[(i + h) % n]) for i in range(n)]))
    topb = min(int(t * k) for t in tops)
    mid = topb + int((bot0 - topb) * 0.55)
    ub = [m[:mid] for m in masks]
    out["upper_move"] = float(np.mean([_move(ub[i], ub[(i + 1) % n]) for i in range(n)]))
    out["leg_px"] = float(np.mean([x.sum() for x in lb]) / (k * k))
    out["crouch"] = out["height"] / out["idle_h"]
    return out


# ---------------------------------------------------------------- 画图

def _font(sz):
    for p in [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


def _panel(op, i, scale, label=True, guides=True):
    fr = load(op, True)
    f = Image.fromarray(fr[i % len(fr)])
    s = f.width
    pad_top = 22 if label else 0
    can = Image.new("RGBA", (s * scale, s * scale + pad_top), BG)
    big = f.resize((s * scale, s * scale), Image.NEAREST)
    can.alpha_composite(big, (0, pad_top))
    d = ImageDraw.Draw(can)
    if guides:
        m0 = fr[0][..., 3] > 0
        top0 = np.nonzero(m0)[0].min()
        y = pad_top + top0 * scale
        for x in range(0, s * scale, 8):
            d.line([(x, y), (x + 3, y)], fill=(255, 80, 200, 255))
        yf = pad_top + 93 * scale - 1
        d.line([(0, yf), (s * scale, yf)], fill=(0, 230, 230, 255))
        xa = 48 * scale
        d.line([(xa, yf - 6), (xa, yf + 1)], fill=(0, 230, 230, 255))
    if label:
        d.text((4, 2), "%s %s  f%d" % (NAMES.get(op, op), op, i % len(fr)), fill=(235, 240, 245, 255), font=_font(14))
    return can


def _row(ops, i, scale):
    ps = [_panel(o, i, scale) for o in ops]
    w = sum(p.width for p in ps) + 4 * (len(ps) - 1)
    can = Image.new("RGBA", (w, ps[0].height), (20, 24, 30, 255))
    x = 0
    for p in ps:
        can.alpha_composite(p, (x, 0))
        x += p.width + 4
    return can


def _grid(rows, i, scale):
    rs = [_row(r, i, scale) for r in rows]
    w = max(r.width for r in rs)
    can = Image.new("RGBA", (w, sum(r.height for r in rs) + 4 * (len(rs) - 1)), (20, 24, 30, 255))
    y = 0
    for r in rs:
        can.alpha_composite(r, (0, y))
        y += r.height + 4
    return can


def save_anim(frames, name, fps=FPS, loops_mp4=6):
    gif = os.path.join(OUT, name + ".gif")
    pal = [f.convert("RGB").quantize(colors=255, method=Image.MEDIANCUT, dither=Image.NONE) for f in frames]
    pal[0].save(gif, save_all=True, append_images=pal[1:], duration=int(1000 / fps), loop=0, disposal=1)
    ff = _ffmpeg()
    if ff:
        tmp = os.path.join(OUT, "_mp4_" + name)
        os.makedirs(tmp, exist_ok=True)
        k = 0
        for _ in range(loops_mp4):
            for f in frames:
                g = f.convert("RGB")
                if g.width % 2 or g.height % 2:
                    g = g.crop((0, 0, g.width - g.width % 2, g.height - g.height % 2))
                g.save(os.path.join(tmp, "%05d.png" % k))
                k += 1
        subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", str(fps), "-i", os.path.join(tmp, "%05d.png"),
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16", "-movflags", "+faststart",
                        os.path.join(OUT, name + ".mp4")], check=False)
        for fn in os.listdir(tmp):
            os.remove(os.path.join(tmp, fn))
        os.rmdir(tmp)
    return gif


def _ffmpeg():
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        import shutil
        return shutil.which("ffmpeg")


def contact_sheet(ops, path):
    sc = 2
    rows = []
    f14 = _font(14)
    for op in ops:
        fr = load(op, True)
        s = fr[0].shape[0] * sc
        n = len(fr)
        cells = []
        for i in range(n):
            cells.append(_panel(op, i, sc, label=False))
        # 洋葱皮：6 帧剪影叠加，越多帧覆盖越亮；只有 1 帧覆盖（= 动了的地方）标橙
        cnt = sum((f[..., 3] > 0).astype(np.int32) for f in fr)
        on = np.zeros(fr[0].shape, np.uint8)
        on[..., 3] = 255
        on[..., :3] = BG[:3]
        v = (cnt * 255 // n).astype(np.uint8)
        on[cnt > 0, 0] = v[cnt > 0]
        on[cnt > 0, 1] = v[cnt > 0]
        on[cnt > 0, 2] = v[cnt > 0]
        part = (cnt > 0) & (cnt < n)
        on[part] = (255, 150, 40, 255)
        cells.append(Image.fromarray(on).resize((s, s), Image.NEAREST))
        # 变化热区：像素在 6 帧里取到的不同值个数（1 = 不动）
        stack = np.stack([f.reshape(-1, 4).view(np.uint32).reshape(f.shape[:2]) for f in fr])
        uniq = np.array([[len(set(stack[:, y, x])) for x in range(stack.shape[2])] for y in range(stack.shape[1])])
        hm = np.zeros(fr[0].shape, np.uint8)
        hm[..., 3] = 255
        hm[..., :3] = (20, 24, 30)
        anyop = cnt > 0
        hm[anyop] = (70, 80, 95, 255)
        for t, c in [(2, (60, 120, 220)), (3, (60, 200, 200)), (4, (240, 220, 60)), (5, (255, 120, 40)), (6, (255, 40, 90))]:
            hm[uniq >= t] = (*c, 255)
        cells.append(Image.fromarray(hm).resize((s, s), Image.NEAREST))
        w = sum(c.width for c in cells) + 4 * len(cells) + 150
        row = Image.new("RGBA", (w, s), (20, 24, 30, 255))
        ImageDraw.Draw(row).text((6, 6), "%s\n%s" % (NAMES.get(op, op), op), fill=(235, 240, 245, 255), font=f14)
        x = 150
        for c in cells:
            row.alpha_composite(c, (x, 0))
            x += c.width + 4
        rows.append(row)
    hdr = Image.new("RGBA", (rows[0].width, 26), (20, 24, 30, 255))
    ImageDraw.Draw(hdr).text((150, 4), "f0 … f5（@2x×2；青线 = 脚底 92，品红虚线 = f0 头顶）   |   叠影：橙 = 只在部分帧出现（动了的地方）   |   热区：像素在 6 帧里换过几种值（蓝 2 → 红 6）",
                             fill=(200, 210, 220, 255), font=f14)
    W = max(r.width for r in rows)
    sheet = Image.new("RGBA", (W, hdr.height + sum(r.height + 6 for r in rows)), (20, 24, 30, 255))
    sheet.alpha_composite(hdr, (0, 0))
    y = hdr.height
    for r in rows:
        sheet.alpha_composite(r, (0, y))
        y += r.height + 6
    sheet.convert("RGB").save(path)


# ---------------------------------------------------------------- 实机录像

CAP_RES = (1280, 720)


def capture(ops, nframes=120, t0=1.0):
    import concurrent.futures as cf
    game = os.path.join(ROOT, "game")
    gr.ensure_imported(game)
    godot = gr.find_godot()

    def run(op):
        d = os.path.join(OUT, "_ingame_raw", op)
        os.makedirs(d, exist_ok=True)
        for fn in os.listdir(d):
            os.remove(os.path.join(d, fn))
        # --autotest（非 --balance）：主控移动 = Vector2.from_angle(t * 0.4)，即慢慢绕大圈跑（game.gd _physics 移动输入）
        args = [godot, "--path", game, "--audio-driver", "Dummy", "--fixed-fps", "30", "--resolution", "%dx%d" % CAP_RES,
                "--", "--autotest", "--seed=1", "--op=" + op, "--shotdir=" + d.replace(os.sep, "/"),
                "--recframes=%.2f,%d" % (t0, nframes)]
        o, e, to = gr.run_godot(args, 240)
        errs = gr.script_errors(o, e)
        return op, len([f for f in os.listdir(d) if f.startswith("rec_")]), errs, to

    with cf.ThreadPoolExecutor(4) as ex:
        for op, n, errs, to in ex.map(run, ops):
            print("实机 %-18s %d 帧%s%s" % (op, n, "（超时）" if to else "", ("  脚本错误：" + errs[0]) if errs else ""), flush=True)


def ingame_outputs(ops, crop=(200, 170), scale=2, step=1):
    tiles = {}
    for op in ops:
        d = os.path.join(OUT, "_ingame_raw", op)
        if not os.path.isdir(d):
            continue
        fs = sorted(f for f in os.listdir(d) if f.startswith("rec_"))
        if not fs:
            continue
        frames = []
        for fn in fs[::step]:
            im = Image.open(os.path.join(d, fn)).convert("RGBA")
            cx, cy = im.width // 2, im.height // 2
            c = im.crop((cx - crop[0] // 2, cy - crop[1] // 2 - 10, cx + crop[0] // 2, cy + crop[1] // 2 - 10))
            c = c.resize((c.width * scale, c.height * scale), Image.NEAREST)
            ImageDraw.Draw(c).text((4, 2), "%s 实机 %s" % (NAMES.get(op, op), fn[4:9]), fill=(255, 255, 255, 255), font=_font(13))
            frames.append(c)
        save_anim(frames, "ingame_" + op, fps=30 // step, loops_mp4=1)
        tiles[op] = frames
    if tiles:
        # 同框：每人取同一时刻，拼成一行，生成一段合并 GIF
        n = min(len(v) for v in tiles.values())
        allf = []
        keys = list(tiles)
        cols = 4
        for i in range(n):
            w, h = tiles[keys[0]][0].size
            rows_n = (len(keys) + cols - 1) // cols
            can = Image.new("RGBA", (w * cols + 4 * (cols - 1), h * rows_n + 4 * (rows_n - 1)), (20, 24, 30, 255))
            for j, k in enumerate(keys):
                can.alpha_composite(tiles[k][i], ((w + 4) * (j % cols), (h + 4) * (j // cols)))
            allf.append(can)
        save_anim(allf, "ingame_all", fps=30 // step, loops_mp4=1)
        allf[min(30, n - 1)].convert("RGB").save(os.path.join(OUT, "ingame_sheet.png"))


# ---------------------------------------------------------------- 主程序

COLS = [("move", "整体剪影变化", "%.3f"), ("leg_move", "腿部变化", "%.3f"), ("leg_move_half", "腿部半周期差", "%.3f"),
        ("upper_move", "上半身变化", "%.3f"), ("head_bob", "头部起伏px", "%.1f"), ("bob_top", "头顶起伏px", "%.1f"),
        ("stride_max", "最大步幅px", "%.1f"), ("contact_l_rng", "后脚着地点变化px", "%.1f"), ("contact_r_rng", "前脚着地点变化px", "%.1f"),
        ("foot_dx", "脚底中心漂移px", "%.1f"), ("lean", "前倾°(近似)", "%+.0f"), ("crouch", "跑/站高比", "%.2f"),
        ("diff", "逐像素相邻差", "%.2f")]


def table(rows):
    head = "| 干员 | " + " | ".join(c[1] for c in COLS) + " |"
    sep = "|---|" + "---|" * len(COLS)
    lines = [head, sep]
    for r in rows:
        lines.append("| %s | " % NAMES.get(r["op"], r["op"]) + " | ".join(c[2] % r[c[0]] for c in COLS) + " |")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ops", default=",".join(NEW))
    ap.add_argument("--refs", default=",".join(REFS3))
    ap.add_argument("--capture", action="store_true")
    ap.add_argument("--ingame-only", action="store_true")
    a = ap.parse_args()
    ops = a.ops.split(",")
    refs = a.refs.split(",")
    os.makedirs(OUT, exist_ok=True)

    if not a.ingame_only:
        allrefs = [r for r in REFS_ALL if os.path.exists(strip_path(r))]
        res = {op: metrics(op) for op in ops + [r for r in allrefs if r not in ops]}
        with open(os.path.join(OUT, "metrics.json"), "w", encoding="utf-8") as fh:
            json.dump(res, fh, ensure_ascii=False, indent=1)
        refrows = [res[r] for r in allrefs]
        med = {c[0]: float(np.median([r[c[0]] for r in refrows])) for c in COLS}
        med["op"] = "参考中位数"
        NAMES["参考中位数"] = "**已验收 %d 人中位数**" % len(refrows)
        md = "## 新干员\n\n" + table([res[o] for o in ops] + [med]) + "\n\n## 已验收参考\n\n" + table(refrows) + "\n"
        with open(os.path.join(OUT, "metrics.md"), "w", encoding="utf-8") as fh:
            fh.write(md)
        print(md)

        for op in ops:
            save_anim([_row([op] + refs, i, 3) for i in range(6)], "compare_" + op)
        save_anim([_grid([ops, refs + ["mizuki"]], i, 2) for i in range(6)], "compare_all")
        contact_sheet(ops + refs + ["mizuki"], os.path.join(OUT, "contact_sheet.png"))

    if a.capture:
        capture(ops + refs)
    ingame_outputs(ops + refs)
    print("输出：" + OUT)


if __name__ == "__main__":
    main()
