# -*- coding: utf-8 -*-
"""怪物风格统一试点（协调人 11-04，用户睡前指令）：「旧 | 新」对照 GIF。只出图，不接入游戏。

    python tools/monster_fx/enemy_gif.py [bone,stone,floater,path] [--lib <pixelfx 库目录>]

每种怪一张 GIF：上排「旧」、下排「新」，四格 = 受击 / 攻击起手 / 命中（打到干员）/ 死亡碎裂（Boss 起手格放技能演出），各格自己循环。
- 「旧」按现有代码近似复刻（world.gd / vfx.gd / combat.gd：受击 = _wound 帧 + 白剪影 0.08 秒 + 暖白火星；死亡 = _death 帧条压到 0.3 秒、最后一帧碎成像素；
  命中 = 干员红闪 + 红圈 + 红火星）。不是游戏录像，只用来对比方向。
- 「新」用 tools/monster_fx/js/*.js（pixelfx）烘焙的帧条 + 本脚本的死亡碎裂烘焙（按怪自己的死亡帧像素做 Noita 式碎块：抛出、受重力、落地弹一下、躺平变暗）。
- 敌弹本体（proj_*）两边一样，只换命中 / 起手；危险色 #ff2667 只给预警，敌弹青 #33ceff 只给子弹本体。
- 统一 3 倍（1 游戏像素 × 3）；敌人帧条是 @2x，先缩回 1x。
输出：Claude outputs/monster_fx_pilot/<怪>.gif、帧条 PNG（build/mfx/strips/）、显存估算 build/mfx/vram.json。
"""
import argparse, json, math, os, random, subprocess, sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
JS = os.path.join(ROOT, "tools", "monster_fx", "js")
FONT = "C:/Windows/Fonts/msyh.ttc"
K = 3
FPS = 20
GROUND = (34, 48, 58)
DANGER = (255, 38, 103)
EBULLET = (51, 206, 255)
for _s in (sys.stdout, sys.stderr):
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8", errors="replace")

DEATH_FR = {"e_bone": 6, "e_stone": 6, "e_floater": 6, "e_path": 8}
ENEMIES = {
    # kind：melee 近战贴身 / lob 抛射 / shot 直射 / boss
    "bone": {"tex": "e_bone", "kind": "melee", "name": "骸骨（近战贴身，最常见）"},
    "stone": {"tex": "e_stone", "kind": "lob", "name": "石壳（抛射落点，有落点预警）", "proj": "proj_rock_shard@2x"},
    "floater": {"tex": "e_floater", "kind": "shot", "name": "浮游（直射神经弹）", "proj": "proj_floater_nerve"},
    "path": {"tex": "e_path", "kind": "boss", "name": "Boss「途」（刃环技能）"},
}
NERVE_DARK = ["#061a22", "#0a2f3c", "#114a5c", "#1a6b84", "#2a8fac"]   # 神经液残液：比敌弹青暗两阶（不用 #33ceff 本色）
DANGER_RAMP = ["#3a0b18", "#8a1838", "#ff2667", "#ff9ab3", "#fff0f4"]


def common_root():
    p = ROOT
    while ".claude" in p:
        p = os.path.dirname(p)
    return p


def index():
    return json.load(open(os.path.join(ROOT, "game", "art", "index.json"), encoding="utf-8"))


def load(idx, name):
    p = idx.get(name)
    if isinstance(p, dict):
        p = p.get("path")
    if not p:
        return None
    im = Image.open(p.replace("res://", os.path.join(ROOT, "game") + "/")).convert("RGBA")
    return im.resize((im.width // 2, im.height // 2), Image.NEAREST) if "@2x" in name else im


def frames(im, n):
    w = im.width // n
    return [im.crop((i * w, 0, (i + 1) * w, im.height)) for i in range(n)]


def ramp_of(im, n=5):
    """从精灵取材质色阶：不透明像素按亮度排序，取 n 个分位的平均色"""
    px = [p[:3] for p in im.get_flattened_data() if p[3] > 128]
    px.sort(key=lambda c: 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2])
    out = []
    for i in range(n):
        seg = px[int(len(px) * i / n): max(int(len(px) * (i + 1) / n), int(len(px) * i / n) + 1)]
        out.append("#%02x%02x%02x" % tuple(sum(c[j] for c in seg) // len(seg) for j in range(3)))
    return out


# ---------------------------------------------------------------- 新：pixelfx 烘焙
def unpremul(im):
    """反预乘（tools/pixelfx_export.py 同法，docs/242 §8）"""
    import numpy as np
    x = np.asarray(im).astype(np.float32)
    al = x[..., 3:4]
    x[..., :3] = np.where(al > 0, np.minimum(255, x[..., :3] * 255 / np.maximum(al, 1)), 0)
    return Image.fromarray(x.astype(np.uint8), "RGBA")


def render(lib, fx, opts, tag):
    out = os.path.join(ROOT, "build", "mfx", "strips", tag)
    os.makedirs(out, exist_ok=True)
    r = subprocess.run(["node", "tools/render.mjs", "monster/" + fx, "--sheet", "--opts", json.dumps(opts), "--out", out], cwd=lib, capture_output=True, text=True, encoding="utf-8")
    if r.returncode:
        sys.exit("render %s 失败：%s" % (fx, r.stderr[-400:]))
    d = os.path.join(out, "monster", fx)
    meta = json.load(open(os.path.join(d, fx + ".json"), encoding="utf-8"))
    sheet = Image.open(os.path.join(d, fx + ".png")).convert("RGBA")
    px = meta["meta"]["pixelfx"]
    fr = []
    for f in meta["frames"]:
        g = f["frame"]
        im = sheet.crop((g["x"], g["y"], g["x"] + g["w"], g["y"] + g["h"]))
        fr.append(unpremul(im))
    return {"frames": fr, "fps": px["fps"], "pivot": tuple(px["pivot"]), "size": tuple(px["frameSize"]), "name": tag}


def shatter(frame, seed, big=False, fps=FPS, dur=0.9):
    """死亡碎裂烘焙（Noita 式）：按怪自己的像素切成 2×2（Boss 3×3）碎块，从身体重心往外上方抛，受重力，落地（脚底线）弹一下、躺平、变暗消失；
    细碎的 1 px 块变成落尘。返回 (帧列表, 原点)。原点 = 精灵脚底中点。"""
    rng = random.Random(seed)
    w, h = frame.size
    bb = frame.getbbox() or (0, 0, w, h)
    floor = bb[3] - 1
    cx, cy = (bb[0] + bb[2]) / 2, (bb[1] + bb[3]) / 2
    cs = 3 if big else 2
    pix = frame.load()
    chunks = []
    for y0 in range(bb[1], bb[3], cs):
        for x0 in range(bb[0], bb[2], cs):
            cells = [(x, y, pix[x, y]) for y in range(y0, min(y0 + cs, h)) for x in range(x0, min(x0 + cs, w)) if pix[x, y][3] > 100]
            if not cells:
                continue
            dx, dy = x0 - cx, y0 - cy
            d = math.hypot(dx, dy) or 1
            sp = rng.uniform(25, 70) * (1.4 if big else 1)
            chunks.append({"cells": [(x - x0, y - y0, c) for x, y, c in cells], "x": x0, "y": y0, "vx": dx / d * sp + rng.uniform(-15, 15),
                           "vy": dy / d * sp * 0.6 - rng.uniform(30, 80), "dust": len(cells) <= 1 or rng.random() < 0.18, "life": rng.uniform(0.55, dur)})
    PAD = 40 if big else 22
    W, H = w + 2 * PAD, h + PAD
    out = []
    G = 260
    for i in range(int(dur * fps)):
        t = i / fps
        im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        p = im.load()
        for c in chunks:
            if t > c["life"]:
                continue
            if c["dust"]:   # 落尘：慢慢飘落、变暗
                x, y = c["x"] + c["vx"] * 0.3 * t, c["y"] + 18 * t + 40 * t * t
                k = 0.55
            else:
                vy = c["vy"]
                tl = max(0.0, (-vy + math.sqrt(max(0.0, vy * vy + 2 * G * (floor - c["y"])))) / G)   # 落地时刻
                if t < tl:
                    x, y = c["x"] + c["vx"] * t, c["y"] + vy * t + 0.5 * G * t * t
                    k = 1.0
                else:   # 弹一下后躺平
                    u = t - tl
                    v2 = -(vy + G * tl) * 0.25
                    hop = max(0.0, -(v2 * u + 0.5 * G * u * u))
                    x, y = c["x"] + c["vx"] * tl + c["vx"] * 0.3 * min(u, 0.2), floor - hop
                    k = max(0.25, 0.85 - 1.2 * u)
            fade = 1 - max(0.0, (t - c["life"] * 0.7) / (c["life"] * 0.3))
            for ox, oy, col in c["cells"]:
                X, Y = int(x + ox + PAD), int(min(y + oy, floor))
                if 0 <= X < W and 0 <= Y < H:
                    p[X, Y] = (int(col[0] * k), int(col[1] * k), int(col[2] * k), int(255 * max(0.0, fade)) if fade < 0.5 else 255)
        out.append(im)
    return {"frames": out, "fps": fps, "pivot": (int(cx) + PAD, floor), "name": "shatter"}


# ---------------------------------------------------------------- 播放
class Clip:
    def __init__(self, s, t0=0.0, at=(0, 0), hold=False):
        self.s, self.t0, self.at = s, t0, at

    def frame(self, t):
        u = t - self.t0
        if u < 0:
            return None
        k = int(u * self.s["fps"])
        return self.s["frames"][k] if k < len(self.s["frames"]) else None


def paste(cell, im, x, y, pivot=(0, 0)):
    if im is None:
        return
    im = im.resize((im.width * K, im.height * K), Image.NEAREST)
    cell.alpha_composite(im, (int(x - pivot[0] * K), int(y - pivot[1] * K)))


def white_of(im, a):
    w = Image.new("RGBA", im.size, (255, 255, 255, 0))
    w.putalpha(im.getchannel("A").point(lambda v: int(v * a)))
    return w


def tint(im, col, a):
    w = Image.new("RGBA", im.size, col + (0,))
    w.putalpha(im.getchannel("A").point(lambda v: int(v * a)))
    o = im.copy()
    o.alpha_composite(w)
    return o


def sparks(d, x, y, t, n, col, seed, sp=60, life=0.18, grav=0):
    r = random.Random(seed)
    for _ in range(n):
        a, v = r.uniform(0, 6.28), r.uniform(0.5, 1) * sp
        if t > life:
            continue
        px, py = x + math.cos(a) * v * t * K, y + (math.sin(a) * v * t + grav * t * t) * K
        d.rectangle((px, py, px + K - 1, py + K - 1), fill=col + (int(255 * (1 - t / life)),))


def hatch_circle(cell, cx, cy, r, t):   # 落点预警（telegraph_draw：斜线填充 + 脉动描边，两边一样）
    d = ImageDraw.Draw(cell)
    a = int(150 + 80 * math.sin(t * 18))
    d.ellipse((cx - r * K, cy - r * K * 0.6, cx + r * K, cy + r * K * 0.6), outline=DANGER + (a,), width=K)
    for i in range(-r, r, 3):
        x0 = cx + i * K
        d.line((x0, cy + r * K * 0.5, x0 + r * K * 0.5, cy - r * K * 0.2), fill=DANGER + (60,), width=1)


# ---------------------------------------------------------------- 主流程
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("which", nargs="?", default="bone,stone,floater,path")
    ap.add_argument("--lib", default=os.path.join(common_root(), ".claude", "worktrees", "sad-archimedes-f80199", "build", "pixelfx"))
    a = ap.parse_args()
    lib = a.lib
    os.makedirs(os.path.join(lib, "src", "fx", "monster"), exist_ok=True)
    import shutil
    for f in os.listdir(JS):
        shutil.copy2(os.path.join(JS, f), os.path.join(lib, "src", "fx", "monster", f))
    idx = index()
    out_dir = os.path.join(common_root(), "Claude outputs", "monster_fx_pilot")
    os.makedirs(out_dir, exist_ok=True)
    ft = ImageFont.truetype(FONT, 18)
    ftb = ImageFont.truetype(FONT, 30)
    hero = frames(load(idx, "op_skadi_idle@2x") or load(idx, "op_skadi_idle@1x"), 1)[0] if idx.get("op_skadi_idle@2x") else None
    if hero is not None and hero.width > hero.height:
        hero = hero.crop((0, 0, hero.height, hero.height))
    vram = {}
    for key in a.which.split(","):
        E = ENEMIES[key]
        tex, kind, big = E["tex"], E["kind"], E["kind"] == "boss"
        nd = DEATH_FR[tex]
        death = load(idx, tex + "_death@2x")
        fw = death.width // nd
        idle = frames(load(idx, tex + "@2x"), load(idx, tex + "@2x").width // fw)
        att = load(idx, tex + ("_skill@2x" if big else "_attack@2x"))
        att = frames(att, att.width // fw) if att else idle
        wound = load(idx, tex + "_wound@2x")
        wound = frames(wound, max(1, wound.width // fw))[0] if wound else idle[0]
        dfr = frames(death, nd)
        mat = ramp_of(idle[0])
        # 新帧条
        S = {}
        S["hit"] = render(lib, "mon-hit", {"palette": mat, "big": 1 if big else 0, "seed": 3}, key + "_hit")
        if kind == "melee":
            S["wind"] = render(lib, "mon-windup-claw", {"seed": 2}, key + "_wind")
            S["imp"] = render(lib, "mon-hit-claw", {"seed": 3}, key + "_imp")
        elif kind == "lob":
            S["wind"] = render(lib, "mon-windup-gather", {"palette": ramp_of(idle[0], 4), "mode": 0, "seed": 4}, key + "_wind")
            S["imp"] = render(lib, "mon-impact", {"palette": mat, "mode": 0, "seed": 5}, key + "_imp")
        elif kind == "shot":
            S["wind"] = render(lib, "mon-windup-gather", {"palette": ramp_of(idle[0], 4), "mode": 1, "seed": 4}, key + "_wind")
            S["imp"] = render(lib, "mon-impact", {"palette": NERVE_DARK, "mode": 1, "seed": 5}, key + "_imp")
        else:
            S["wind"] = render(lib, "mon-boss-quake", {"seed": 6}, key + "_quake")
            S["imp"] = render(lib, "mon-hit-claw", {"seed": 7}, key + "_imp")
        cut = max(1, int(nd * 0.4))   # 死亡帧条先播 40%，再从那一帧碎开
        S["die"] = shatter(dfr[cut], 11, big)
        for k2, s in S.items():
            w, h = s["frames"][0].size
            vram[tex + "_" + k2] = {"frames": len(s["frames"]), "frame": [w, h], "MB_full": round(len(s["frames"]) * w * h * 4 / 2 ** 20, 3)}
            sd = os.path.join(ROOT, "build", "mfx", "png")
            os.makedirs(sd, exist_ok=True)
            st = Image.new("RGBA", (w * len(s["frames"]), h))
            for i, f in enumerate(s["frames"]):
                st.alpha_composite(f, (i * w, 0))
            st.save(os.path.join(sd, "%s_%s.png" % (key, k2)))
        proj = load(idx, E["proj"]) if E.get("proj") else None
        if proj is not None and proj.width > proj.height * 1.5:
            proj = frames(proj, proj.width // proj.height)[0]
        # 版式
        ew, eh = fw * K, idle[0].height * K
        CW = int(max(ew * 1.9, 96 * K)) if not big else int(ew * 1.7)
        CH = eh + (150 if big else 90)
        HB, LB = 44, 70
        cols = ["受击", "技能演出" if big else "攻击起手", "命中（打到干员）", "死亡碎裂"]
        T = 1.6 if big else 1.2
        nfr = int(T * FPS)
        imgs = []
        for i in range(nfr):
            t = i / FPS
            sheet = Image.new("RGBA", (LB + 4 * CW, HB + 2 * CH), (10, 16, 28, 255))
            d0 = ImageDraw.Draw(sheet)
            for c, name in enumerate(cols):
                d0.text((LB + c * CW + 8, 8), name, font=ft, fill=(220, 228, 240))
            for r, lab in enumerate(("旧", "新")):
                d0.text((10, HB + r * CH + CH // 2 - 20), lab, font=ftb, fill=((150, 160, 175), (255, 214, 102))[r])
                for c in range(4):
                    cell = Image.new("RGBA", (CW, CH), GROUND + (255,))
                    d = ImageDraw.Draw(cell)
                    fx_, fy_ = int(CW * (0.42 if c != 2 else 0.62)), CH - (80 if big else 24)   # 怪脚底（Boss 留出裂网的位置）
                    piv = (fw // 2, idle[0].height - 2)
                    new = r == 1
                    if c == 0:   # 受击：0.1 秒挨一下
                        u = (t - 0.1) % 0.6
                        hitting = u < (0.08 if not big else 0.11)
                        body = wound if (hitting and not big) else idle[int(t * 6) % len(idle)]
                        paste(cell, body, fx_, fy_, piv)
                        if hitting:
                            paste(cell, white_of(body, 0.5 if big else 0.9), fx_, fy_, piv)
                        hx, hy = fx_ - ew * 0.1, fy_ - eh * 0.45
                        if new:
                            sh = S["hit"]
                            k3 = int(u * sh["fps"])
                            if k3 < len(sh["frames"]):
                                paste(cell, sh["frames"][k3], hx, hy, sh["pivot"])
                        else:
                            sparks(d, hx, hy, u, 6, (255, 242, 217), int(t / 0.6), 70)
                    elif c == 1:   # 起手 / Boss 技能
                        if big:
                            u = t % T
                            body = att[min(len(att) - 1, int(u * 5))]
                            if new:
                                q = S["wind"]
                                k3 = int(u * q["fps"])
                                if k3 < len(q["frames"]):
                                    paste(cell, q["frames"][k3], fx_, fy_ - 4, q["pivot"])
                            else:   # 旧：脚下预警圈（telegraph 描边脉动）→ 白闪
                                if u < 0.6:
                                    hatch_circle(cell, fx_, fy_ - 4, 46, u)
                                elif u < 0.65:
                                    d.ellipse((fx_ - 46 * K, fy_ - 4 - 28 * K, fx_ + 46 * K, fy_ - 4 + 28 * K), outline=(255, 255, 255, 255), width=K * 2)
                            paste(cell, body, fx_, fy_, piv)
                        else:
                            u = t % T
                            pre = u < 0.35
                            body = att[(int(u * 3) % 2) if pre else min(len(att) - 1, 2 + int((u - 0.35) * 10))]
                            paste(cell, body, fx_, fy_, piv)
                            if kind == "lob" and u < 0.8:
                                hatch_circle(cell, fx_ + ew * 0.9, fy_ - 4, 14, u)
                            if new and u < 0.4:
                                q = S["wind"]
                                k3 = int(u * q["fps"])
                                ax, ay = (fx_ + ew * 0.3, fy_ - eh * 0.35) if kind == "melee" else (fx_ + ew * 0.15, fy_ - eh * 0.55)
                                if k3 < len(q["frames"]):
                                    paste(cell, q["frames"][k3], ax, ay, q["pivot"])
                            if proj is not None and not pre and u < 0.8:   # 敌弹本体：两边一样
                                v = (u - 0.35) / 0.45
                                px_, py_ = fx_ + ew * 0.15 + v * ew * 0.75, fy_ - eh * 0.55 + (eh * 0.5 * v if kind == "shot" else -eh * 0.6 * math.sin(v * math.pi) + eh * 0.5 * v)
                                paste(cell, proj, px_, py_, (proj.width // 2, proj.height // 2))
                    elif c == 2:   # 命中：干员站右侧被打
                        u = t % T
                        hx_, hy_ = int(CW * 0.55), CH - 24
                        if hero is not None:
                            hb = hero if u > 0.2 else tint(hero, (255, 60, 70), 0.55)
                            paste(cell, hb, hx_, hy_, (hero.width // 2, hero.height - 2))
                        ix, iy = hx_, hy_ - (hero.height * K * 0.45 if hero is not None else 30)
                        if kind in ("lob", "shot"):
                            iy = hy_ - 4 if kind == "lob" else iy
                        if new:
                            q = S["imp"]
                            k3 = int(u * q["fps"])
                            if k3 < len(q["frames"]):
                                paste(cell, q["frames"][k3], ix, iy, q["pivot"])
                        else:
                            if u < 0.25:
                                rr = (6 + 40 * u) * K
                                d.ellipse((ix - rr, iy - rr, ix + rr, iy + rr), outline=(255, 77, 89, int(255 * (1 - u / 0.25))), width=K)
                            sparks(d, ix, iy, u, 8, (255, 77, 89), 5, 80, 0.22)
                    else:   # 死亡
                        u = t % T
                        if new:
                            dt_ = cut / 6.0
                            if u < dt_:
                                paste(cell, dfr[min(cut, int(u * 6))], fx_, fy_, piv)
                            else:
                                q = S["die"]
                                k3 = int((u - dt_) * q["fps"])
                                if k3 < len(q["frames"]):
                                    paste(cell, q["frames"][k3], fx_, fy_, q["pivot"])
                        else:   # 旧：帧条压到 0.3 秒，最后一帧碎成像素（无重力、四散淡出）
                            if u < 0.3:
                                paste(cell, dfr[min(nd - 1, int(u / 0.3 * nd))], fx_, fy_, piv)
                            elif u < 0.6:
                                last = dfr[nd - 1] if dfr[nd - 1].getbbox() else dfr[nd - 3]
                                v = u - 0.3
                                rnd = random.Random(7)
                                pp = last.load()
                                for yy in range(0, last.height, 2):
                                    for xx in range(0, last.width, 2):
                                        c4 = pp[xx, yy]
                                        if c4[3] < 100:
                                            continue
                                        aa = rnd.uniform(0, 6.28)
                                        X = fx_ + (xx - piv[0]) * K + math.cos(aa) * 60 * v * K
                                        Y = fy_ + (yy - piv[1]) * K + math.sin(aa) * 60 * v * K
                                        d.rectangle((X, Y, X + K - 1, Y + K - 1), fill=c4[:3] + (int(255 * (1 - v / 0.3)),))
                    sheet.alpha_composite(cell, (LB + c * CW, HB + r * CH))
            imgs.append(sheet.convert("RGB"))
        gif = os.path.join(out_dir, "%s.gif" % key)
        imgs[0].save(gif, save_all=True, append_images=imgs[1:], duration=int(1000 / FPS), loop=0, disposal=1)
        imgs[int(nfr * 0.3)].save(os.path.join(out_dir, "%s_frame.png" % key))
        print("%s %s → %s（%d 帧）" % (key, E["name"], gif, nfr))
    vp = os.path.join(ROOT, "build", "mfx", "vram.json")
    json.dump(vram, open(vp, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("显存估算 → %s；合计 %.2f MB（全档 RGBA、未打包）" % (vp, sum(v["MB_full"] for v in vram.values())))


if __name__ == "__main__":
    main()
