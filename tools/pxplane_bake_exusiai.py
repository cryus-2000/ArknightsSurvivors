"""能天使转平面帧条烘焙（docs/262）：只用 Python（PIL），图形定义在 tools/pxplane_exu_art.py。
输出 game/art/fx/pxp/pxp_ex_<键>.png（帧横排，1 像素 = 1 美术像素）+ .import（同 Godot 缺省纹理导入参数）+ game/data/pxp_exusiai.json。
用法：python tools/pxplane_bake_exusiai.py"""
import hashlib, json, os, sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pxplane_exu_art as A

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "game", "art", "fx", "pxp")
META = os.path.join(ROOT, "game", "data", "pxp_exusiai.json")
DIRS = [-90, -45, 0, 45, 90]
# 模式 → 出现的精英档（技能按精英化解锁：S2 精一、S3 精二、倾泻 = 精一天赋）
TIERS = {"n": [0, 1, 2], "s1": [0, 1, 2], "s2": [1, 2], "s3": [2], "g": [1, 2]}
EMIT_LUM = 0.8
EMIT_MAX = 24

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
    out = {}
    for m, ts in TIERS.items():
        for t in ts:
            for d in DIRS:
                for v in (0, 1):   # 连射时两种枪口火交替（十字 / 斜星）
                    out["mz_%s_e%d_v%d_d%d" % (m, t, v, d)] = (A.muzzle(m, t, d, v), False)
                out["hit_%s_e%d_d%d" % (m, t, d)] = (A.hit(m, t, d), False)
    for d in DIRS:
        out["hit_x_d%d" % d] = (A.hit("x", 0, d), False)
        out["hit_full_d%d" % d] = (A.hit("full", 1, d), False)
    out["smoke_up"] = (A.smoke(), False)
    out["ring_s1_gd"] = (A.ring_gd("s1", 26), False)
    out["ring_s3_gd"] = (A.ring_gd("s3", 36), False)
    out["ring_splash_gd"] = (A.ring_gd("n", 30), False)
    out["ring_frag_gd"] = (A.ring_gd("g", 28, "frag"), False)
    out["mark_gd"] = (A.ring_gd("g", 11, "mark"), False)
    out["halo_up"] = (A.halo("halo"), True)
    out["halo_fire_up"] = (A.halo("fire"), False)
    out["halo_s3_up"] = (A.halo("s3"), True)
    out["bless_up"] = (A.halo("bless"), False)
    out["steam_up"] = (A.steam(), False)
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
    h = int(hashlib.sha1(("pxp_ex/" + name).encode()).hexdigest(), 16)
    al = "abcdefghijklmnopqrstuvwxyz0123456789"
    s = al[h % 26]
    h //= 26
    for _ in range(11):
        s += al[h % 36]
        h //= 36
    return s


def main():
    os.makedirs(ART, exist_ok=True)
    meta = {"_doc": "docs/262 能天使转平面帧条：tools/pxplane_bake_exusiai.py 生成（图形 tools/pxplane_exu_art.py），键加前缀 ex_ 对应 art/fx/pxp/pxp_ex_<键>.png；n 帧数、fps、w / h 单帧尺寸（美术像素）、ox / oy 原点、loop、emit 每帧热芯 [x, y, 颜色]"}
    n = 0
    total = 0
    for k, (frames, loop) in strips().items():
        im, w, h, ox, oy, emit = render(frames)
        fn = "pxp_ex_%s.png" % k.replace("_d-", "_dm")
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
