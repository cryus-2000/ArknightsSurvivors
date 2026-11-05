"""安洁莉娜转平面帧条烘焙（docs/267）：只用 Python（PIL），图形定义在 tools/pxplane_ang_art.py。
输出 game/art/fx/pxp/pxp_an_<键>.png（帧横排，1 像素 = 1 美术像素）+ .import（同 Godot 缺省纹理导入参数）+ game/data/pxp_angelina.json。
用法：python tools/pxplane_bake_angelina.py"""
import hashlib, json, os, sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pxplane_ang_art as A

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "game", "art", "fx", "pxp")
META = os.path.join(ROOT, "game", "data", "pxp_angelina.json")
EMIT_LUM = 0.8
EMIT_MAX = 24
RIB_ROT = [0, 90, 180, 270]

IMPORT_TMPL = """[remap]

importer="texture"
type="CompressedTexture2D"
uid="uid://{uid}"
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
    """键 → (帧表, 是否循环)"""
    out = {}
    for t in range(3):
        out["orb_e%d" % t] = (A.orb(t), True)
        out["orb_s1_e%d" % t] = (A.orb(t, True), True)
        for z in range(3):
            for m in ("n", "s1"):
                up, gd = A.land(t, m, z)
                out["land_%s_e%d_z%d_up" % (m, t, z)] = (up, False)
                out["land_%s_e%d_z%d_gd" % (m, t, z)] = (gd, False)
    out["orb_sh_gd"] = (A.orb_shadow(), True)
    for z in range(3):
        out["well_z%d_gd" % z] = (A.well(z), False)
        out["echo_z%d_gd" % z] = (A.ring_in(37.5 * A.Z[z] * 0.8, 5, 6), False)
        out["band_z%d_gd" % z] = (A.band(z), True)
        out["bandop_z%d_gd" % z] = (A.band_open(z), False)
        out["lift_z%d_gd" % z] = (A.lift_edge(z), True)
        out["liftop_z%d_gd" % z] = (A.lift_edge(z, True), False)
        for t in (1, 2):
            for r in RIB_ROT:
                out["rib_e%d_z%d_r%d_gd" % (t, z, r)] = (A.ribbon(t, z, r), False)
    out["float_s_gd"] = (A.float_lines(4), True)
    out["float_l_gd"] = (A.float_lines(7), True)
    out["splash_gd"] = (A.ring_in(30.0 * 0.95, 4, 0), False)
    out["dense_in_gd"] = (A.ring_in(30.0, 5, 0, (4, 4, 3, 3, 2), 3), False)
    out["dense_pop_up"] = (A.dense_pop(30.0), False)
    out["lock_gd"] = (A.lock_mark(8), False)
    out["s1cast_up"] = (A.cast_star(), False)
    out["blades_up"] = (A.blades(), True)
    out["blades_cast_up"] = (A.blades(True), False)
    for v in range(3):
        out["rock_v%d_up" % v] = (A.rock(v), False)
    out["lk_shard_up"] = (A.link_shard(), True)
    up, gd = A.link_land()
    out["lk_land_up"] = (up, False)
    out["lk_land_gd"] = (gd, False)
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
    h = int(hashlib.sha1(("pxp_an/" + name).encode()).hexdigest(), 16)
    al = "abcdefghijklmnopqrstuvwxyz0123456789"
    s = al[h % 26]
    h //= 26
    for _ in range(11):
        s += al[h % 36]
        h //= 36
    return s


def main():
    os.makedirs(ART, exist_ok=True)
    meta = {"_doc": "docs/267 安洁莉娜转平面帧条：tools/pxplane_bake_angelina.py 生成（图形 tools/pxplane_ang_art.py），键加前缀 an_ 对应 art/fx/pxp/pxp_an_<键>.png；n 帧数、fps、w / h 单帧尺寸（美术像素）、ox / oy 原点、loop、emit 每帧热芯 [x, y, 颜色]"}
    n = 0
    total = 0
    for k, (frames, loop) in strips().items():
        im, w, h, ox, oy, emit = render(frames)
        fn = "pxp_an_%s.png" % k
        p = os.path.join(ART, fn)
        im.save(p, optimize=True)
        total += os.path.getsize(p)
        md5 = hashlib.md5(("res://art/fx/pxp/" + fn).encode()).hexdigest()
        ip = p + ".import"
        if not os.path.exists(ip):   # 已有的 .import（Godot 导入过）不覆盖，保留 uid
            with open(ip, "w", encoding="utf-8", newline=chr(10)) as f:
                f.write(IMPORT_TMPL.format(uid=uid_of(fn), name=fn, md5=md5))
        meta[k] = {"n": len(frames), "fps": 15, "w": w, "h": h, "ox": ox, "oy": oy, "loop": loop, "emit": emit}
        n += 1
    with open(META, "w", encoding="utf-8", newline=chr(10)) as f:
        json.dump(meta, f, ensure_ascii=False, separators=(",", ":"))
    print("帧条 %d 张，共 %.1f KB → %s" % (n, total / 1024.0, ART))


if __name__ == "__main__":
    main()
