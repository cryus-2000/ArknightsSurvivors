"""铃兰转平面帧条烘焙（docs/271）：只用 Python（PIL），图形定义在 tools/pxplane_suzuran_art.py。
输出 game/art/fx/pxp/pxp_sz_<键>.png（帧横排，1 像素 = 1 美术像素）+ game/data/pxp_suzuran.json。
.import 不写（GCP / 本机 Godot --import 时按规范生成 uid，见 e70548cbf）。
用法：python tools/pxplane_bake_suzuran.py"""
import json, os, sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pxplane_suzuran_art as A

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "game", "art", "fx", "pxp")
META = os.path.join(ROOT, "game", "data", "pxp_suzuran.json")
DIRS = [-90, -45, 0, 45, 90]
EMIT_LUM = 0.8
EMIT_MAX = 32


def strips():
    out = {}
    out["hit_up"] = (A.hit_up(), False)
    out["hit_gd"] = (A.ring_gd(12, 4), False)
    out["fl_s"] = (A.flame_frames(4, 3), True)
    out["fl_m"] = (A.flame_frames(7, 3, pale=True, seed=2), True)
    out["fl_l"] = (A.flame_frames(11, 5, pale=True, seed=4), True)
    out["gather"] = (A.gather(), True)
    for d in DIRS:
        out["bigfox_d%d" % d] = ([A.bigfox(d, f) for f in range(4)], True)
    out["tails"] = (A.tails_frames(), True)
    out["tails_flare"] = (A.tails_frames(True), False)
    out["s1sig_gd"] = ([A.sigil_gd(24, f, 12) for f in range(12)], False)
    out["s1col_up"] = (A.column_up(), False)
    out["stamp_gd"] = ([A.stamp_gd(f) for f in range(6)], False)
    out["seal_gd"] = ([A.seal_gd(f) for f in range(8)], True)
    out["brand_gd"] = ([A.brand_gd(f) for f in range(6)], True)
    for R in A.S2_R:
        tr = (8, R)
        out["s2_r%d_gd" % R] = (A.big_ring_gd(R, 9, travel=tr, seed=R), False)
        out["s2_r%d_b" % R] = (A.ring_tongues(R, int(R * 0.32), 9, 9, R, half="b", travel=tr), False)
        out["s2_r%d_f" % R] = (A.ring_tongues(R, int(R * 0.32), 9, 9, R, half="f", travel=tr), False)
    for R in A.S3_R:
        n = 12
        out["s3_r%d_gd" % R] = ([A.sweep_gd(R, f, n) for f in range(n)], False)
        out["s3_r%d_b" % R] = ([A.sweep(R, f, n, "b") for f in range(n)], False)
        out["s3_r%d_f" % R] = ([A.sweep(R, f, n, "f") for f in range(n)], False)
    out["drop_up"] = (A.drop_frames(), False)
    out["drop_gd"] = (A.drop_gd(), False)
    out["heal_up"] = (A.heal_up(), False)
    out["heal_gd"] = (A.heal_gd(), False)
    for R in A.PRAY_R:
        out["pray_r%d_gd" % R] = (A.big_ring_gd(R, 6, seed=R + 1), False)
        out["pray_r%d_b" % R] = (A.ring_tongues(R, 8, 6, 6, R + 1, half="b"), False)
        out["pray_r%d_f" % R] = (A.ring_tongues(R, 8, 6, 6, R + 1, half="f"), False)
    for R in A.HB_R:
        tr = (R * 0.45, R)
        out["hb_r%d_gd" % R] = (A.big_ring_gd(R, 7, travel=tr, seed=R + 2), False)
        out["hb_r%d_b" % R] = (A.ring_tongues(R, int(R * 0.3), 7, 8, R + 2, half="b", travel=tr), False)
        out["hb_r%d_f" % R] = (A.ring_tongues(R, int(R * 0.3), 7, 8, R + 2, half="f", travel=tr), False)
    out["att_gd"] = (A.att_tick_gd(), False)
    out["splash_gd"] = (A.splash_frames(), False)
    out["tuft"] = (A.tuft_frames(), False)
    return out


def lum(c):
    r, g, b, _ = A.hx(c)
    return (0.3 * r + 0.59 * g + 0.11 * b) / 255.0


def render(frames):
    """[Buf] → (PIL 帧条, w, h, ox, oy, emit)"""
    xs = [x for f in frames for (x, y) in f.p] or [0]
    ys = [y for f in frames for (x, y) in f.p] or [0]
    x0, x1, y0, y1 = min(xs) - 1, max(xs) + 1, min(ys) - 1, max(ys) + 1
    w, h = x1 - x0 + 1, y1 - y0 + 1
    im = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    px = im.load()
    emit = []
    for i, f in enumerate(frames):
        em = []
        for (x, y), c in sorted(f.p.items()):
            px[i * w + x - x0, y - y0] = A.hx(c)
            if lum(c) >= EMIT_LUM:
                em.append([x - x0, y - y0, c.lstrip("#")])
        if len(em) > EMIT_MAX:
            em = em[:: max(1, len(em) // EMIT_MAX)][:EMIT_MAX]
        emit.append(em)
    return im, w, h, -x0, -y0, emit


def main():
    os.makedirs(ART, exist_ok=True)
    meta = {"_doc": "docs/271 铃兰转平面帧条：tools/pxplane_bake_suzuran.py 生成（图形 tools/pxplane_suzuran_art.py），键加前缀 sz_ 对应 art/fx/pxp/pxp_sz_<键>.png；n 帧数、fps、w / h 单帧尺寸（美术像素）、ox / oy 原点、loop、emit 每帧热芯 [x, y, 颜色]"}
    n = 0
    total = 0
    for k, (frames, loop) in strips().items():
        im, w, h, ox, oy, emit = render(frames)
        fn = "pxp_sz_%s.png" % k.replace("_d-", "_dm").lower()
        p = os.path.join(ART, fn)
        im.save(p, optimize=True)
        total += os.path.getsize(p)
        meta[k] = {"n": len(frames), "fps": 15, "w": w, "h": h, "ox": ox, "oy": oy, "loop": loop, "emit": emit}
        n += 1
    with open(META, "w", encoding="utf-8", newline="\n") as f:
        json.dump(meta, f, ensure_ascii=False, separators=(",", ":"))
    print("帧条 %d 张，共 %.1f KB → %s" % (n, total / 1024.0, ART))


if __name__ == "__main__":
    main()
