# -*- coding: utf-8 -*-
"""萨米敌人 / Boss 像素帧条（11-20：PRTS Spine 渲染 → 像素化 → 直接进包，11-19 用户把干员的 B 方案扩到敌人和 Boss；docs/399）。

借 tools/spine_px.py 的整条流程（逐附件渲染 → 调色板 → 清理 → 描边），本脚本只管敌人这边的约定：
  1. 按下面 ENEMIES 表写 tools/spine_run_trial/cfg/sami_<id>{.src,,_px}.json（无腿：地线 = 待机首帧最低点，同令的召唤物）
  2. 调 spine_px.py 出大画布帧条（build/spine_px/sami_<id>/strips/）
  3. 按全部动作的并集包围盒裁成紧框（宽高偶数），写运行时帧条到 game/art/enemies/sami/：
     e_sami_<id>@2x.png（待机）、e_sami_<id>_<动作>@2x.png；Boss 另出 1 倍 e_sami_<id>[_<动作>].png（同 install_enemy_redraw.BOSS_1X：boss_intro 读 1 倍）
     wound = 1 帧（原作没有受击轨，取 Die 开头 0.1 秒的后仰姿势），同水月敌人
  4. 规格写 tools/spine_run_trial/cfg/sami_enemies_sprites.json：每个运行时键的 enemy_pixels 条目（anchor / frames / frame_size）
     + enemy_redraw 条目（frames / event_frames / sample_times / loop / duration），主题开关合入后并进 game/themes/sami/data/；现在游戏不读

    python tools/spine_px_enemy.py                 # 全部
    python tools/spine_px_enemy.py husk will       # 只做这几只
    python tools/spine_px_enemy.py husk --no-render  # 只重新裁框 / 写规格（大画布帧条已出）
"""
import argparse, json, os, subprocess, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as _GR
COMMON = _GR.common_root()
CFG = os.path.join(ROOT, "tools", "spine_run_trial", "cfg")
RAW = os.path.join(COMMON, "build", "prts_ref", "_raw")
DST = os.path.join(ROOT, "game", "art", "enemies", "sami")
SPEC_OUT = os.path.join(CFG, "sami_enemies_sprites.json")
CMP1X = os.path.join(COMMON, "build", "spine_px", "_sami_cmp", "1x")


def A(anim, n, dur, loop=True, at=None):
    """动作：Spine 轨名、帧数、轨长；loop 均分不含终点，非循环含终点；at = 单帧取样时刻"""
    if at is not None:
        return {"anim": anim, "n": 1, "times": [at], "loop": False, "dur": 0.12}
    return {"anim": anim, "n": n, "dur": dur, "loop": loop}


# 本作 id → 原作素材键（tools/prts_spine.py ENEMY 表）、尺度（Spine → @2x 像素，按 docs/399 §2 体型档定）、画布、动作
# keep：设定色（瞳色等）补进调色板，量化时不被并掉（docs/87 §4.3；利刃青眼 / 游荡者品红眼取自原作 Head 贴图）
# 帧数照水月同档：普通 4 / 4 / 6 / 6 / 1，精英 6 / 6 / 8 / 8 / 1，Boss 6 / 6 / 8 / 8 + 招式 8
ENEMIES = {
    "husk": {"src": "sami_shell", "name": "染污躯壳", "tier": "normal", "scale": 0.141, "canvas": 192,
             "acts": {"idle": A("Idle", 4, 1.0), "move": A("Move", 4, 2.0), "rush": A("Run", 4, 0.6667),
                      "attack": A("Attack", 6, 1.1667, False), "death": A("Die", 6, 1.0, False), "wound": A("Die", 1, 0, at=0.1)}},
    "drone": {"src": "sami_drone", "name": "坍缩构造体", "tier": "normal", "scale": 0.197, "canvas": 192, "post": "post_drone",
              "acts": {"idle": A("Idle", 1, 0, at=0.0), "move": A("Move", 1, 0, at=0.0), "attack": A("Attack", 1, 0, at=0.0),
                       "death": A("Die", 6, 0.5, False), "wound": A("Die", 1, 0, at=0.05)}},
    "caster": {"src": "sami_caster", "name": "歪曲施法者", "tier": "normal", "scale": 0.151, "canvas": 192,
               "acts": {"idle": A("Idle", 4, 2.0), "move": A("Move", 4, 2.0), "rush": A("Run", 4, 0.6667),
                        "attack": A("Attack", 6, 1.6667, False), "death": A("Die", 6, 1.0, False), "wound": A("Die", 1, 0, at=0.1)}},
    "icebug": {"src": "snslime_a", "name": "冰爆源石虫·α", "tier": "normal", "scale": 0.166, "canvas": 192,
               "acts": {"idle": A("Idle", 4, 1.0), "move": A("Move", 4, 1.0), "attack": A("Attack", 6, 2.5, False),
                        "death": A("Die", 6, 1.0, False), "wound": A("Die", 1, 0, at=0.1)}},
    "breaker": {"src": "snow_icebreaker", "name": "雪怪小队破冰者", "tier": "high", "scale": 0.183, "canvas": 256,
                "acts": {"idle": A("Idle", 4, 2.0), "move": A("Move", 4, 1.2), "attack": A("Attack", 8, 3.0, False),
                         "death": A("Die", 6, 1.0, False), "wound": A("Die", 1, 0, at=0.1)}},
    "warrior": {"src": "sami_warrior", "name": "木裂战士", "tier": "elite", "scale": 0.161, "canvas": 256,
                "acts": {"idle": A("Idle", 6, 1.6667), "move": A("Move", 6, 0.8), "attack": A("Attack_A", 8, 1.0, False),
                         "attack_b": A("Attack_B", 8, 1.0, False), "death": A("Die", 8, 0.6667, False), "wound": A("Die", 1, 0, at=0.08)}},
    "vinebox": {"src": "sami_vinebox", "name": "巨壳藤蔓", "tier": "rare", "scale": 0.193, "canvas": 192,
                "acts": {"disguised": A("Idle", 4, 2.0), "reveal": A("Start", 6, 1.1, False), "idle": A("Move", 1, 0, at=0.0),
                         "move": A("Move", 6, 1.3333), "attack": A("Attack", 6, 1.0, False), "death": A("Die", 6, 1.0, False),
                         "wound": A("Die", 1, 0, at=0.1)}},
    "blade": {"src": "sami_blade", "name": "“邪魔的利刃”", "tier": "boss", "scale": 0.194, "canvas": 256, "keep": ["#a9eddc", "#62b7a6"],
              "eyes_from": ["wanderer", {"#ff2a6e": "#a9eddc", "#f02a75": "#62b7a6"}],
              "acts": {"idle": A("Idle", 6, 2.0), "move": A("Move", 6, 1.3333), "attack": A("Attack", 8, 2.1667, False),
                       "combat": A("Combat", 8, 1.8333, False), "death": A("Die", 8, 1.0, False), "wound": A("Die", 1, 0, at=0.1)}},
    "wanderer": {"src": "sami_blade2", "name": "“邪魔的利刃”，游荡者", "tier": "boss", "scale": 0.194, "canvas": 256, "keep": ["#ff2a6e", "#f02a75"],
                 "acts": {"idle": A("Idle", 6, 2.0), "move": A("Move", 6, 1.3333), "attack": A("Attack", 8, 2.1667, False),
                          "combat": A("Combat", 8, 1.8333, False), "death": A("Die", 8, 1.0, False), "wound": A("Die", 1, 0, at=0.1)}},
    "will": {"src": "sami_will", "name": "“萨米的意志”", "tier": "boss", "scale": 0.135, "canvas": 448, "colors": 96,
             "acts": {"idle": A("Idle", 6, 4.0), "attack": A("Attack", 8, 3.0, False),
                      "surge_begin": A("Skill_01_Begin", 8, 3.0, False), "surge_loop": A("Skill_01_Loop", 6, 2.0),
                      "surge_end": A("Skill_01_End", 4, 0.6667, False), "sigh": A("Skill_02", 8, 2.6667, False),
                      "death": A("Die", 8, 1.1, False), "wound": A("Die", 1, 0, at=0.1)}},
}


def times(a):
    if "times" in a:
        return a["times"]
    n, d = a["n"], a["dur"]
    if n == 1:
        return [0.0]
    return [round(d * k / (n if a["loop"] else n - 1), 4) for k in range(n)] if a["loop"] else [round(min(d * k / (n - 1), d - 0.001), 4) for k in range(n)]


# 处理方式候选（11-20 用户：先给躯壳 / 意志各出几种，选定再批量）：A = 现行（ENEMIES 表），其余在 A 上覆盖
VARIANTS = {
    "A": {"_doc": "现行：64 色（意志 96）+ 外描边（#0a1418，混 55%）"},
    "B": {"outline": None, "lift": 0.8, "_doc": "无外描边 + 提亮暗部（明度 v^0.8）：更接近原作的亮度，只留原作线稿"},
    "C": {"colors": 24, "outline": {"color": "#0a1418", "mix": 1.0}, "_doc": "少色平涂：24 色（暗面并块）+ 纯色硬外描边，更像手绘像素"},
    # 11-20 用户嫌 A 太黑太淡、B / C 发灰、高光白和蓝都没了：在原图（贴图页）上先调再量化
    "D": {"tex": {"lift": 0.8, "sat": 1.25, "hi_pct": 0.03, "hi_colors": 12, "contrast": 1.18}, "outline": None, "own_outline": 0.45,
          "_doc": "原图提亮 v^0.8 + 饱和 ×1.25 → 最亮 3% 单列 12 色 → 主色按色相拉开明度 ×1.18 → 描边 = 本色压暗 45%"},
}
SUFFIX = ""   # --variant 时 = "_v<名>"，帧条与规格写到候选目录，不进 game/


def prep_tex(k, e, base):
    """候选 D：贴图页先调色，再自己做调色板。返回 (改过的 atlas 路径, 调色板 png)。产物写 build/spine_px/<k>/tex/（F 盘联接）"""
    import colorsys, shutil
    t = e["tex"]
    od = os.path.join(COMMON, "build", "spine_px", k, "tex")
    os.makedirs(od, exist_ok=True)
    atlas = base + ".atlas"
    shutil.copyfile(atlas, os.path.join(od, os.path.basename(atlas)))
    pages = [ln.strip() for ln in open(atlas, encoding="utf-8") if ln.strip().lower().endswith(".png")]
    allpx = []
    for pg in pages:
        im = Image.open(os.path.join(os.path.dirname(atlas), pg)).convert("RGBA")
        px = im.load()
        cache = {}
        for y in range(im.height):
            for x in range(im.width):
                c = px[x, y]
                if not c[3]:
                    continue
                q = cache.get(c[:3])
                if q is None:
                    h, sat, v = colorsys.rgb_to_hsv(c[0] / 255, c[1] / 255, c[2] / 255)
                    r, g, b = colorsys.hsv_to_rgb(h, min(1.0, sat * t["sat"]), v ** t["lift"])
                    q = cache[c[:3]] = (round(r * 255), round(g * 255), round(b * 255))
                px[x, y] = q + (c[3],)
                if c[3] >= 230:
                    allpx.append(q)
        im.save(os.path.join(od, pg))
    lum = lambda c: 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]
    allpx.sort(key=lum)
    cut = int(len(allpx) * (1 - t["hi_pct"]))
    main, hi = allpx[:cut], allpx[cut:]

    def mc(cols, n):
        im = Image.new("RGB", (len(cols), 1))
        im.putdata(cols)
        p = im.quantize(colors=n, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).getpalette()[:n * 3]
        return [tuple(p[i * 3:i * 3 + 3]) for i in range(len(p) // 3)]
    pal = mc(main, e.get("colors", 64))
    # 局部对比：主色按色相分 12 组（灰另成一组），组内明度离组均值 ×contrast——防中间调糊成一片
    groups = {}
    for c in pal:
        h, sat, v = colorsys.rgb_to_hsv(*(x / 255 for x in c))
        groups.setdefault(-1 if sat < 0.12 else int(h * 12) % 12, []).append((c, h, sat, v))
    out = []
    for g in groups.values():
        m = sum(x[3] for x in g) / len(g)
        for c, h, sat, v in g:
            r, gg, b = colorsys.hsv_to_rgb(h, sat, max(0.0, min(1.0, m + (v - m) * t["contrast"])))
            out.append((round(r * 255), round(gg * 255), round(b * 255)))
    out += mc(hi, t["hi_colors"])   # 高光单列，不参与上面的并色和拉伸
    out = list(dict.fromkeys(out))
    pp = os.path.join(od, "palette_D.png")
    o = Image.new("RGBA", (len(out), 1))
    o.putdata([c + (255,) for c in out])
    o.save(pp)
    print("%s 调色板 %d 色（高光 %d 色，阈值亮度 %.0f）" % (k, len(out), t["hi_colors"], lum(hi[0])), flush=True)
    return os.path.join(od, os.path.basename(atlas)).replace("\\", "/"), pp.replace("\\", "/")


def own_outline(im, k):
    """外圈像素 = 本色 ×(1-k)，不吸回调色板（同 spine_px.outline 的判定：与透明四邻接、一像素细件不压）"""
    W, H = im.size
    p = im.load()
    tr = lambda x, y: not (0 <= x < W and 0 <= y < H) or p[x, y][3] == 0
    ch = []
    for y in range(H):
        for x in range(W):
            c = p[x, y]
            if c[3] == 0 or not (tr(x - 1, y) or tr(x + 1, y) or tr(x, y - 1) or tr(x, y + 1)):
                continue
            if (tr(x - 1, y) and tr(x + 1, y)) or (tr(x, y - 1) and tr(x, y + 1)):
                continue
            ch.append((x, y, tuple(round(v * (1 - k)) for v in c[:3]) + (c[3],)))
    for x, y, c in ch:
        p[x, y] = c


def write_cfg(eid, e):
    k = "sami_" + eid + SUFFIX
    raw = os.path.join(RAW, e["src"])
    meta = json.load(open(os.path.join(raw, "meta.json"), encoding="utf-8"))
    base = os.path.join(raw, os.path.basename(meta["file"])).replace("\\", "/")
    atlas, pal = base + ".atlas", None
    if e.get("tex"):
        atlas, pal = prep_tex(k, e, base)
    json.dump({"skel": base + ".skel", "atlas": atlas}, open(os.path.join(CFG, k + ".src.json"), "w", encoding="utf-8"))
    rig = {"id": k, "src": k + ".src.json", "name": e["name"], "pack": {"scale": e["scale"], "root": [64, 120], "palette_png": ""},
           "skipAdditive": not e.get("additive"), "_doc": "萨米敌人「%s」（%s）：无腿，地线 = 待机首帧最低点（tools/spine_px_enemy.py 生成）" % (e["name"], e["src"])}
    json.dump(rig, open(os.path.join(CFG, k + ".json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    acts = {}
    for name, a in e["acts"].items():
        t = times(a)
        acts[name] = {"sample": {"anim": a["anim"], "times": t}, "durations": durs(a, t)}
    px = {"id": k, "rig": k + ".json", "tex_prefix": "e_" + k, "scale": e["scale"], "canvas": e["canvas"], "dens": [2, 1],
          "colors": e.get("colors", 64), "palette_alpha": 230, "palette_protect": False,
          "outline": e["outline"] if "outline" in e else {"color": "#0a1418", "mix": 0.55}, "actions": acts, "keep_colors": e.get("keep", []),
          **({"palette_prebuilt": pal} if pal else {}),
          "_doc": "tools/spine_px_enemy.py 生成，别手改；改 ENEMIES 表再跑"}
    json.dump(px, open(os.path.join(CFG, k + "_px.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)


def durs(a, t):
    if a["n"] == 1:
        return [a["dur"]]
    if a["loop"]:
        step = a["dur"] / a["n"]
        return [round(step, 4)] * a["n"]
    return [round(t[i + 1] - t[i], 4) for i in range(len(t) - 1)] + [round(max(a["dur"] - t[-1], 0.06), 4)]


def events(src, anim):
    info = os.path.join(COMMON, "build", "prts_ref", src, src + "_info.json")
    d = json.load(open(info, encoding="utf-8"))
    return [ev["t"] for ev in d["anims"].get(anim, {}).get("events", []) if ev.get("name") == "OnAttack"]


def borrow_eyes(e, other, im):
    """利刃与游荡者同一骨骼同一动画：游荡者的品红眼量化后留得住（利刃的青眼并进了灰白），
    按游荡者同帧眼睛像素的位置把利刃这几格换成原作青色（Head 贴图取色）"""
    src = Image.open(os.path.join(DST, other)).convert("RGBA")
    m = {tuple(int(c[i:i + 2], 16) for i in (1, 3, 5)): tuple(int(v[i:i + 2], 16) for i in (1, 3, 5)) for c, v in e["eyes_from"][1].items()}
    if src.size != im.size:
        raise SystemExit("借眼帧条尺寸不同：%s %s %s" % (other, src.size, im.size))
    n = 0
    sp, ip = src.load(), im.load()
    for y in range(im.height):
        for x in range(im.width):
            p = sp[x, y]
            if p[3] and p[:3] in m and ip[x, y][3]:
                ip[x, y] = m[p[:3]] + (255,)
                n += 1
    return n


def post_drone(outs, w, h):
    """坍缩构造体：原作 Spine 本体只有墨色剪影 + 两端蓝灯，图鉴里的「黑核 + 白色光晕 + 横竖光芒」是游戏里另挂的特效，
    这里按图鉴头像手补进帧条（本体中心）；原作 Die 轨是整体渐隐，二值透明后整段消失，死亡帧改为：光核爆亮 → 本体按点溶解、光核收缩"""
    import math
    K, W, L, P = (11, 8, 32), (244, 240, 255), (201, 184, 242), (233, 163, 184)

    def core(im, cx, cy, d, r=1.0):
        """d = 密度（2 = @2x，1 = @1x），r = 大小倍数（死亡时收缩）"""
        px = im.load()
        R = 8 * d // 2
        for dy in range(-R, R + 1):
            for dx in range(-R, R + 1):
                x, y = cx + dx, cy + dy
                if not (0 <= x < im.width and 0 <= y < im.height):
                    continue
                q = math.hypot(dx, dy) / (d / 2) / max(r, 0.01)   # 以 @2x 像素计
                adx, ady = abs(dx) / (d / 2) / max(r, 0.01), abs(dy) / (d / 2) / max(r, 0.01)
                c = None
                if q <= 1.2:
                    c = K
                elif q <= 2.7:
                    c = W
                elif q <= 3.7:
                    c = L
                elif dy == 0 and adx <= 8:
                    c = W if adx <= 5 else L
                elif dx == 0 and ady <= 6:
                    c = W if ady <= 4.5 else P
                if c and (r > 0.15 or q <= 2.7):
                    px[x, y] = c + (255,)

    def center(f):
        px = f.load()
        pts = [(x, y) for y in range(f.height) for x in range(f.width) if px[x, y][3] and px[x, y][2] < 120]   # 墨色本体（不算两端蓝灯）
        xs, ys = sorted(p[0] for p in pts), sorted(p[1] for p in pts)
        return xs[len(xs) // 2], ys[len(ys) // 2]

    for name, (o2, o1) in outs.items():
        for strip, d in ((o2, 2), (o1, 1)):
            fw = w // (2 // d)
            n = strip.width // fw
            if name == "death":
                base = outs["idle"][0 if d == 2 else 1].crop((0, 0, fw, strip.height))
                cx, cy = center(base)
                for i in range(n):
                    f = base.copy()
                    fp = f.load()
                    keep = 1.0 - i / (n - 1)
                    for y in range(f.height):
                        for x in range(f.width):
                            if fp[x, y][3] and ((x * 73856093 ^ y * 19349663) % 1000) / 1000.0 >= keep:
                                fp[x, y] = (0, 0, 0, 0)
                    core(f, cx, cy, d, [1.35, 1.0, 0.75, 0.5, 0.3, 0.1][min(i, 5)])
                    strip.paste(f, (fw * i, 0))
            else:
                for i in range(n):
                    f = strip.crop((fw * i, 0, fw * (i + 1), strip.height))
                    cx, cy = center(f)
                    core(f, cx, cy, d)
                    strip.paste(f, (fw * i, 0))


def finish(eid, e):
    """大画布帧条 → 紧框运行时帧条 + 规格"""
    k = "sami_" + eid + SUFFIX
    sd = os.path.join(COMMON, "build", "spine_px", k, "strips")
    size = e["canvas"]
    pad = (size - 128) // 2
    ox, oy = 64 + pad, 120 + pad
    strips = {}
    for name in e["acts"]:
        im = Image.open(os.path.join(sd, "e_%s_%s@2x.png" % (k, name))).convert("RGBA")
        n = im.width // size
        strips[name] = [im.crop((size * i, 0, size * (i + 1), size)) for i in range(n)]
    bb = [f.getbbox() for fr in strips.values() for f in fr if f.getbbox()]
    x0 = min(b[0] for b in bb) - 2
    y0 = min(b[1] for b in bb) - 2
    x1 = max(b[2] for b in bb) + 2
    y1 = max(max(b[3] for b in bb), oy + 4) + 2
    x0, y0 = max(0, x0 - x0 % 2), max(0, y0 - y0 % 2)
    x1, y1 = min(size, x1 + x1 % 2), min(size, y1 + y1 % 2)
    clip = [name for name, fr in strips.items() for f in fr if f.getbbox() and (f.getbbox()[0] <= 0 or f.getbbox()[1] <= 0 or f.getbbox()[2] >= size or f.getbbox()[3] >= size)]
    w, h = x1 - x0, y1 - y0
    os.makedirs(DST, exist_ok=True)
    boss = e["tier"] == "boss"
    spec = {}
    outs = {}
    for name, fr in strips.items():
        o2 = Image.new("RGBA", (w * len(fr), h))
        for i, f in enumerate(fr):
            o2.paste(f.crop((x0, y0, x1, y1)), (w * i, 0))
        im1 = Image.open(os.path.join(sd, "e_%s_%s@1x.png" % (k, name))).convert("RGBA")
        s1 = size // 2
        o1 = Image.new("RGBA", (w // 2 * len(fr), h // 2))
        for i in range(len(fr)):
            o1.paste(im1.crop((s1 * i + x0 // 2, y0 // 2, s1 * i + x1 // 2, y1 // 2)), (w // 2 * i, 0))
        outs[name] = (o2, o1)
    if e.get("post"):
        globals()[e["post"]](outs, w, h)
    if e.get("lift"):
        import colorsys
        for o2, o1 in outs.values():
            for im in (o2, o1):
                px = im.load()
                for y in range(im.height):
                    for x in range(im.width):
                        r, g, b, al = px[x, y]
                        if al:
                            hh, ss, vv = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
                            r2, g2, b2 = colorsys.hsv_to_rgb(hh, ss, vv ** e["lift"])
                            px[x, y] = (round(r2 * 255), round(g2 * 255), round(b2 * 255), al)
    if e.get("own_outline"):
        for o2, o1 in outs.values():
            for im in (o2, o1):
                own_outline(im, e["own_outline"])
    os.makedirs(CMP1X, exist_ok=True)
    for name, fr in strips.items():
        key = "e_" + k if name == "idle" else "e_%s_%s" % (k, name)
        out, o1 = outs[name]
        if e.get("eyes_from"):
            borrow_eyes(e, key.replace("e_" + k, "e_sami_" + e["eyes_from"][0]) + "@2x.png", out)
            borrow_eyes(e, key.replace("e_" + k, "e_sami_" + e["eyes_from"][0]) + ".png", o1)
        out.save(os.path.join(DST, key + "@2x.png"))
        # 1 倍只给 Boss 进包（同 install_enemy_redraw.BOSS_1X）；其余写 build/ 只供对照图
        o1.save(os.path.join(DST if boss else CMP1X, key + ".png"))
        a = e["acts"][name]
        t = times(a)
        ev = []
        for et in events(e["src"], a["anim"]):
            idx = next((i for i, tt in enumerate(t) if tt >= et - 1e-3), len(t) - 1)
            ev.append(idx)
        spec[key] = {"pixels": {"anchor": [round((ox - x0) / w, 4), round((oy - y0) / h, 4)], "scale": 1.0, "preserve_palette": True,
                                "frames": len(fr), "frame_size": [w, h]},
                     "redraw": {"frames": len(fr), "event_frames": sorted(set(ev)), "release_frame": None, "sample_times": t,
                                "loop": a["loop"], "duration": a["dur"] if a["n"] > 1 else 0.12},
                     "src_anim": a["anim"]}
    body = strips["idle"][0].getbbox()
    print("%s %s 框 %dx%d 待机 %dx%d（顶到脚 %d）%s" % (eid, e["name"], w, h, body[2] - body[0], body[3] - body[1], oy - body[1],
                                                 " 贴边：" + ",".join(sorted(set(clip))) if clip else ""), flush=True)
    return spec, {"id": eid, "name": e["name"], "src": e["src"], "tier": e["tier"], "frame_size_2x": [w, h],
                  "idle_body_2x": [body[2] - body[0], body[3] - body[1]], "top_to_foot_2x": oy - body[1], "clipped": sorted(set(clip))}


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("ids", nargs="*")
    ap.add_argument("--no-render", action="store_true")
    ap.add_argument("--variant", help="处理方式候选（VARIANTS 键）：帧条写到 --out，不进 game/、不改规格文件")
    ap.add_argument("--out", help="候选输出目录")
    a = ap.parse_args()
    global SUFFIX, DST, CMP1X
    if a.variant:
        SUFFIX = "_v" + a.variant
        DST = CMP1X = os.path.join(a.out, a.variant)
        os.makedirs(DST, exist_ok=True)
    ids = a.ids or list(ENEMIES)
    ids.sort(key=lambda i: 1 if ENEMIES[i].get("eyes_from") else 0)   # 借眼的排在被借的后面
    old = json.load(open(SPEC_OUT, encoding="utf-8")) if os.path.exists(SPEC_OUT) else {}
    old.setdefault("_doc", "萨米敌人 / Boss 帧条规格（tools/spine_px_enemy.py 生成，docs/399）：每个运行时键 pixels = enemy_pixels.json 条目、"
                           "redraw = enemy_redraw.json 条目；主题开关合入后并进 game/themes/sami/data/。现在游戏不读这个文件。")
    old.setdefault("sprites", {})
    old.setdefault("enemies", {})
    for eid in ids:
        e = dict(ENEMIES[eid])
        if a.variant:
            e.update({kk: vv for kk, vv in VARIANTS[a.variant].items() if not kk.startswith("_")})
        if not a.no_render:
            write_cfg(eid, e)
            r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "spine_px.py"), "sami_" + eid + SUFFIX], capture_output=True, text=True, encoding="utf-8", errors="replace")
            if r.returncode != 0:
                print(eid, "失败", r.stdout[-1500:], r.stderr[-1500:])
                continue
        spec, info = finish(eid, e)
        if a.variant:
            json.dump({"spec": spec, "info": info}, open(os.path.join(DST, eid + "_spec.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
            continue
        for kk in [x for x in old["sprites"] if x == "e_sami_" + eid or x.startswith("e_sami_%s_" % eid)]:
            del old["sprites"][kk]
        old["sprites"].update(spec)
        old["enemies"][eid] = info
    json.dump(old, open(SPEC_OUT, "w", encoding="utf-8", newline="\n"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
