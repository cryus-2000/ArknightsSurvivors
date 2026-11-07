"""塞雷娅转平面帧条烘焙（docs/269）：只用 Python（PIL），图形定义在 tools/pxplane_saria_art.py。
输出 game/art/fx/pxp/pxp_sa_<键>.png（帧横排，1 像素 = 1 美术像素）+ .import（同 Godot 缺省纹理导入参数）+ game/data/pxp_saria.json。
用法：python tools/pxplane_bake_saria.py"""
import hashlib, json, os, sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pxplane_saria_art as A

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "game", "art", "fx", "pxp")
META = os.path.join(ROOT, "game", "data", "pxp_saria.json")
DIRS = [-90, -45, 0, 45, 90]
EMIT_LUM = 0.8
EMIT_MAX = 32

IMPORT_TMPL = """[remap]

importer="texture"
type="CompressedTexture2D"
path="res://.godot/imported/{name}-{md5}.ctex"
metadata={{
"vram_texture": false
}}

[deps]

source_file="res://art/fx/pxp/{name}"
dest_files=["res://.godot/imported/{name}-{md5}.ctex"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""


def strips():
    out = {}
    for R in A.BASH_R:
        for d in DIRS:
            for t in (0, 1):
                out["bash_r%d_e%d_up_d%d" % (R, t, d)] = (A.bash_up(R, t, d), False)
            out["bash_r%d_gd_d%d" % (R, d)] = (A.bash_gd(R, d), False)
            out["cbash_r%d_d%d" % (R, d)] = (A.cbash_up(R, d), False)
    for d in DIRS:
        out["hit_d%d" % d] = (A.hit_spikes(d), False)
        out["hitc_d%d" % d] = (A.hit_spikes(d, calc=True), False)
        out["hita_d%d" % d] = (A.hit_spikes(d, amber=True), False)
    for R in A.SUIT_R:
        out["suit_r%d_gd" % R] = (A.suit_gd(R), False)
    out["suit_up"] = (A.suit_up(), False)
    for nm, big in (("pilB", True), ("pilS", False)):
        for v in (0, 1, 2):
            rise, idle, brk = A.pillar_frames(big, v)
            out["%s%d_rise" % (nm, v)] = (rise, False)
            out["%s%d_idle" % (nm, v)] = (idle, True)
            out["%s%d_brk" % (nm, v)] = (brk, False)
    for v in (0, 1):
        grow, idle, brk = A.cluster_frames(v)
        out["cal%d_grow" % v] = (grow, False)
        out["cal%d_idle" % v] = (idle, True)
        out["cal%d_brk" % v] = (brk, False)
    out["s3cast_gd"] = (A.s3cast_gd(), False)
    out["s3cast_up"] = (A.s3cast_up(), False)
    out["field_gd"] = (A.field_gd(), True)
    out["orb"] = (A.orb_frames(), True)
    out["orbbrk"] = (A.orb_break(), False)
    out["chip"] = (A.chip_up(), False)
    for R in A.SHAT2_R:
        out["shat2_r%d_up" % R] = (A.ring_spikes_up(R, 10, 9, 71), False)
        out["shat2_r%d_gd" % R] = (A.ring_dust_gd(R, 73), False)
    out["markb_up"] = (A.ring_spikes_up(22, 6, 6, 75), False)
    out["markb_gd"] = (A.ring_dust_gd(22, 77), False)
    for t in (0, 1, 2):
        for v in (0, 1):
            out["qspk_e%d_v%d" % (t, v)] = (A.qspike(t, v), False)
    out["s1_gd"] = (A.s1_gd(), False)
    for t in (0, 1, 2):
        out["s1_e%d_up" % t] = (A.s1_up(t), False)
    out["syrhit"] = (A.syr_hit(), False)
    for t in (1, 2):
        out["s2_e%d_gd" % t] = (A.s2_gd(t), False)
    out["s2_up"] = (A.s2_up(), False)
    out["hot_aura"] = (A.hot_aura(), True)
    out["hot_tick"] = (A.hot_tick(), False)
    out["lk_b"] = (A.link_shell(False), False)
    out["lk_f"] = (A.link_shell(True), False)
    out["lk_ring_gd"] = (A.link_ring_gd(), False)
    for v in (0, 1, 2):
        out["lk_patch_v%d" % v] = (A.link_patch(v), False)
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


def uid_of(name):
    h = int(hashlib.sha1(("pxp_sa/" + name).encode()).hexdigest(), 16)
    al = "abcdefghijklmnopqrstuvwxyz0123456789"
    s = al[h % 26]
    h //= 26
    for _ in range(11):
        s += al[h % 36]
        h //= 36
    return s


def main():
    os.makedirs(ART, exist_ok=True)
    meta = {"_doc": "docs/269 塞雷娅转平面帧条：tools/pxplane_bake_saria.py 生成（图形 tools/pxplane_saria_art.py），键加前缀 sa_ 对应 art/fx/pxp/pxp_sa_<键>.png；n 帧数、fps、w / h 单帧尺寸（美术像素）、ox / oy 原点、loop、emit 每帧热芯 [x, y, 颜色]"}
    n = 0
    total = 0
    for k, (frames, loop) in strips().items():
        im, w, h, ox, oy, emit = render(frames)
        fn = "pxp_sa_%s.png" % k.replace("_d-", "_dm").lower()   # 文件名不许大写（asset_lint N1）；游戏 _tex 同样转小写
        p = os.path.join(ART, fn)
        im.save(p, optimize=True)
        total += os.path.getsize(p)
        md5 = hashlib.md5(("res://art/fx/pxp/" + fn).encode()).hexdigest()
        ip = p + ".import"
        if not os.path.exists(ip):   # 已有的 .import（Godot 导入过）不覆盖，保留 uid
            with open(ip, "w", encoding="utf-8", newline="\n") as f:
                f.write(IMPORT_TMPL.format(uid=uid_of(fn), name=fn, md5=md5))
        meta[k] = {"n": len(frames), "fps": 15, "w": w, "h": h, "ox": ox, "oy": oy, "loop": loop, "emit": emit}
        n += 1
    with open(META, "w", encoding="utf-8", newline="\n") as f:
        json.dump(meta, f, ensure_ascii=False, separators=(",", ":"))
    print("帧条 %d 张，共 %.1f KB → %s" % (n, total / 1024.0, ART))


if __name__ == "__main__":
    main()
