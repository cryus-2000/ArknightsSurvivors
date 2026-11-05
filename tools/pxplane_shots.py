#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""转平面试验（docs/246 斯卡蒂、docs/254 星熊；fx/px_plane）的看图工具。--op 选干员（缺省 skadi）。本机 Windows，窗口在屏幕外、静音（godot_runner），一次只开 1 个 Godot（串行）。

  demo  图鉴演示模式（tests/elite_demo_shot.tscn）逐招连拍：三种画法（0 当前游戏 / 2 旧做法原样贴 / 1 转平面）× 精英档，
        同一招同一时刻对齐（同一演示、同一帧号），拼「三栏对比」：每招一张 + 2 倍局部；另拼三档并排（只转平面版）。
  rec   同种子同一局 8:00 起 20 秒，fx/px_plane = 0 / 1 各跑一遍（--realtime，30 帧原速）拼左关右开 mp4；同局收 TRACE 逐行比。
  trace 只比 TRACE（--fixed-fps 60 非实时）：fx/px_plane = 0 / 1 / 2 三局两两比。

用法（仓库根目录）：
    python tools/pxplane_shots.py demo --out "E:/ArknightsSurvivors/Claude outputs/px_plane_skadi_1105"
    python tools/pxplane_shots.py rec  --out ... --seed 11 --from 480 --secs 20
    python tools/pxplane_shots.py trace --seed 23 --maxt 300 --extra "--elite2 --sptest"
"""
import argparse, glob, os, shutil, subprocess, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
BUILD = os.path.join(ROOT, "build", "pxplane")
LOGS = os.path.join(BUILD, "logs")
OPS = {
    "skadi": {"name": "斯卡蒂", "modes": {3: "普攻", 0: "S1 迅捷打击·γ型", 1: "S2 跃浪击", 2: "S3 涌潮悲歌"}, "off": {0: 3, 1: 12, 2: 10}},
    # 星熊：S1 出手即判定（下劈 + 裂网）；S2 取地刺破土后 3 帧；S3 取起手后约 0.3 秒（青绿弧 + 第一记直线撕裂）
    "hoshiguma": {"name": "星熊", "modes": {3: "普攻 盾斧斩", 0: "S1 战意", 1: "S2 荆棘", 2: "S3 力之锯"}, "off": {0: 4, 1: 10, 2: 12}},
    # 安洁莉娜（docs/267）：S1 是接下来 3 发强化弹（落点帧按能量峰挑）；S2 起手后约 0.27 秒（环带收拢 + 第一道绸带）；S3 起手后约 0.8 秒（重力核心成形 + 第一块大碎石托起）。
    # 没有「旧做法」对照，② 栏同 ①
    "angelina": {"name": "安洁莉娜", "modes": {3: "普攻 重力弹", 0: "S1 秘杖·速充模式", 1: "S2 秘杖·微粒模式", 2: "S3 秘杖·反重力模式"}, "off": {1: 8, 2: 24},
                 "cols": [(0, "① 当前游戏原样"), (0, "②（安洁莉娜没有旧做法对照，同 ①）"), (1, "③ 转平面 + 统一像素 + 吃光 + Noita")]},
}
OP = "skadi"
MODE_NAME = OPS[OP]["modes"]
MODE_KEY = {3: "atk", 0: "s1", 1: "s2", 2: "s3"}
MODE_TIERS = {3: [0, 1, 2], 0: [0, 1, 2], 1: [1, 2], 2: [2]}
LATE = ["--bal=growth/late_shape=1"]   # 截图一律开后期形状（额外剑气要在三档图里看得到，docs/246 §9）
COLS = [(0, "① 当前游戏原样"), (2, "② pixelfx 原样直接贴（旧做法）"), (1, "③ 转平面 + 统一像素 + 吃光 + Noita")]
FONT = "C:/Windows/Fonts/msyh.ttc"
REUSE = False


def font(sz):
    return ImageFont.truetype(FONT, sz)


def shoot(px, tier, mode, start, every, n, w=1280, h=720, extra=(), suffix=""):
    tag = "e%d_m%d_px%d%s" % (tier, mode, px, suffix)
    fdir = os.path.join(BUILD, "demo", tag)
    if REUSE and len(glob.glob(os.path.join(fdir, "f_*.png"))) >= n:   # --reuse：只重拼图，不再开 Godot
        lg = os.path.join(LOGS, "demo_" + tag + ".log")
        out = open(lg, encoding="utf-8").read() if os.path.exists(lg) else ""
        return tag, sorted(glob.glob(os.path.join(fdir, "f_*.png"))), [], [l.split() for l in out.splitlines() if l.startswith("FXRLOG")]
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir)
    args = [GR.find_godot(), "--audio-driver", "Dummy", "--fixed-fps", "30", "--path", GAME, "res://tests/elite_demo_shot.tscn", "--",
            "--shot_op=" + OP, "--shot_stage=%d" % tier, "--shot_mode=%d" % mode, "--shot_dir=" + fdir.replace("\\", "/"),
            "--shot_start=%g" % start, "--shot_every=%d" % every, "--shot_n=%d" % n, "--shot_w=%d" % w, "--shot_h=%d" % h,
            "--bal=fx/px_plane=%d" % px, "--bal=fx/recipe_log=1"] + LATE + list(extra)
    out, err, to = GR.run_godot(args, 900)
    os.makedirs(LOGS, exist_ok=True)
    open(os.path.join(LOGS, "demo_" + tag + ".log"), "w", encoding="utf-8").write((out or "") + "\n" + (err or ""))
    errs = GR.script_errors(out, err)
    ev = [l.split() for l in (out or "").splitlines() if l.startswith("FXRLOG")]
    return tag, sorted(glob.glob(os.path.join(fdir, "f_*.png"))), errs, ev


def energy(frames, ref):
    """每帧与「当前游戏」同帧的差（特效差异能量）：找特效最显眼的帧"""
    e = []
    for f, r in zip(frames, ref):
        a = np.asarray(Image.open(f).convert("RGB"), dtype=np.int16)
        b = np.asarray(Image.open(r).convert("RGB"), dtype=np.int16)
        e.append(int((np.abs(a - b).sum(axis=2) > 60).sum()))
    return e


def label(im, text, sz=26):
    d = ImageDraw.Draw(im)
    f = font(sz)
    tw = d.textlength(text, font=f)
    d.rectangle((8, 8, 24 + tw, 16 + sz + 10), fill=(0, 0, 0))
    d.text((16, 10), text, fill=(255, 255, 255), font=f)
    return im


def demo(a):
    out = a.out
    os.makedirs(out, exist_ok=True)
    res = {}
    for mode in [int(x) for x in a.modes.split(",")]:
        for tier in MODE_TIERS[mode]:
            for px, _ in COLS:
                if (tier, mode, px) in res:
                    continue   # 同一画法只拍一次（安洁莉娜 ② 栏同 ①）
                tag, frames, errs, ev = shoot(px, tier, mode, a.start, a.every, a.n, extra=a.extra.split())
                print(tag, len(frames), "帧", errs[:2], flush=True)
                res[(tier, mode, px)] = frames
                if px == 1:
                    res[(tier, mode, "ev")] = ev
    font_b = font(30)
    for mode in [int(x) for x in a.modes.split(",")]:
        tiers_up = []
        for tier in MODE_TIERS[mode]:
            fr = {px: res[(tier, mode, px)] for px, _ in COLS}
            n = min(len(v) for v in fr.values())
            if n == 0:
                continue
            e = energy(fr[1][:n], fr[0][:n])
            k = int(np.argmax(e))
            # 技能招：按技能事件帧对齐（能量峰常落在普攻上）。S1 出手即判定；S2 起跳约 15 帧后落地；S3 取起手后约 0.3 秒（大水柱 + 第一记暗蓝旋斩）
            OFF = OPS[OP]["off"]
            if mode in OFF:
                evs = [int(x[3]) for x in res.get((tier, mode, "ev"), []) if len(x) > 3 and x[2] == "skill%d" % mode and x[3].isdigit()]
                f0 = int(a.start * 30)
                cand = [(fe + OFF[mode] - f0) // a.every for fe in evs if (fe + OFF[mode] - f0) // a.every >= 0]
                if cand and cand[0] < n:
                    k = cand[0]
            if a.force_k >= 0:
                k = min(a.force_k, n - 1)   # --force_k：指定帧（自动对齐挑不到那一招时）
            # 三栏：同一帧号（同一时刻、同一画面）
            ims = [Image.open(fr[px][k]).convert("RGB") for px, _ in COLS]
            W, H = ims[0].size
            sheet = Image.new("RGB", (W * 3 + 8, H + 56), (12, 12, 16))
            dd = ImageDraw.Draw(sheet)
            dd.text((12, 8), OPS[OP]["name"] + " %s · 精英 %d · 同一帧（演示第 %d 张）" % (MODE_NAME[mode], tier, k), fill=(230, 230, 230), font=font_b)
            for i, (im, (px, lab)) in enumerate(zip(ims, COLS)):
                sheet.paste(label(im.copy(), lab), (i * (W + 4), 56))
            base = "cmp_%s_e%d" % (MODE_KEY[mode], tier)
            sheet.save(os.path.join(out, base + ".png"))
            # 2 倍局部：以「转平面」帧里差异最大处为中心，取 320×180 放大到 640×360
            a1 = np.asarray(ims[2], dtype=np.int16)
            a0 = np.asarray(ims[0], dtype=np.int16)
            m = (np.abs(a1 - a0).sum(axis=2) > 60)
            ys, xs = np.nonzero(m)
            cx, cy = (int(np.median(xs)), int(np.median(ys))) if len(xs) else (W // 2, H // 2)
            cw, ch = 320, 180
            x0 = min(max(0, cx - cw // 2), W - cw)
            y0 = min(max(0, cy - ch // 2), H - ch)
            crop = Image.new("RGB", (cw * 2 * 3 + 8, ch * 2 + 56), (12, 12, 16))
            dd = ImageDraw.Draw(crop)
            dd.text((12, 8), "2 倍局部（最近邻放大） · %s · 精英 %d" % (MODE_NAME[mode], tier), fill=(230, 230, 230), font=font_b)
            for i, (im, (px, lab)) in enumerate(zip(ims, COLS)):
                c = im.crop((x0, y0, x0 + cw, y0 + ch)).resize((cw * 2, ch * 2), Image.NEAREST)
                crop.paste(label(c, lab, 20), (i * (cw * 2 + 4), 56))
            crop.save(os.path.join(out, base + "_x2.png"))
            # 三档并排：转平面版，命中峰前后 5 帧
            idx = [max(0, min(n - 1, k + d)) for d in (-2, -1, 0, 2, 5)]
            row = [Image.open(fr[1][j]).convert("RGB").crop((x0, y0, x0 + cw, y0 + ch)).resize((cw * 2, ch * 2), Image.NEAREST) for j in idx]   # 2 倍局部（最近邻）
            tiers_up.append((tier, row))
            print("三栏", base, "帧", k, flush=True)
        if tiers_up:
            rw, rh = tiers_up[0][1][0].size
            sheet = Image.new("RGB", (100 + rw * 5 + 16, 56 + (rh + 8) * len(tiers_up)), (12, 12, 16))
            dd = ImageDraw.Draw(sheet)
            dd.text((12, 8), "转平面版三档 · " + OPS[OP]["name"] + " %s（每行一档，命中前后 5 帧）" % MODE_NAME[mode], fill=(230, 230, 230), font=font_b)
            for r, (tier, row) in enumerate(tiers_up):
                y = 56 + r * (rh + 8)
                dd.text((16, y + rh // 2 - 18), "E%d" % tier, fill=(255, 255, 255), font=font(34))
                for j, im in enumerate(row):
                    sheet.paste(im.resize((rw, rh)), (100 + j * (rw + 4), y))
            sheet.save(os.path.join(out, "tiers_%s.png" % MODE_KEY[mode]))


def fps_cmp(a):
    """帧率统一前后：同一招（普攻 E2 / S1 E2）同一演示，fx/px_plane_fps = 12.8（各件小数帧率 + 平滑位移）vs 15（统一节拍），
    逐帧连拍（30 帧原速），左右并排 mp4 + 局部 2 倍"""
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    os.makedirs(a.out, exist_ok=True)
    for mode in (3, 0):
        dirs = []
        for fps in ("12.8", "15"):
            tag, frames, errs, ev = shoot(1, 2, mode, 2.0, 1, 150, extra=["--bal=fx/px_plane_fps=" + fps], suffix="_fps" + fps.replace(".", ""))
            print(tag, len(frames), errs[:2], flush=True)
            dirs.append(os.path.join(BUILD, "demo", tag))
        # 局部：以斯卡蒂附近（演示镜头中心）为准，取 480×270 放大 2 倍
        lab = os.path.join(BUILD, "_fps_labels.png")
        im = Image.new("RGBA", (1924, 540), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        f = font(26)
        for i, t in enumerate(["统一前：各件小数帧率（12.8 fps）+ 60 Hz 平滑位移", "统一后：全局 15 fps 节拍 + 位置按拍跳格"]):
            x = i * 964
            d.rectangle((x + 8, 8, x + 24 + int(d.textlength(t, font=f)), 50), fill=(0, 0, 0, 180))
            d.text((x + 16, 12), t, fill=(255, 255, 255, 255), font=f)
        im.save(lab)
        mp4 = os.path.join(a.out, "fps_before_after_%s.mp4" % MODE_KEY[mode])
        crop = "crop=480:270:400:225,scale=960:540:flags=neighbor"
        subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(dirs[0], "f_%04d.png"), "-framerate", "30", "-i", os.path.join(dirs[1], "f_%04d.png"),
                        "-i", lab, "-filter_complex", "[0:v]%s,pad=964:540:0:0:black[l];[1:v]%s[r];[l][r]hstack=inputs=2[h];[h][2:v]overlay=0:0[v]" % (crop, crop),
                        "-map", "[v]", "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", mp4], check=True)
        print("录像", mp4, flush=True)


def linkcmp(a, base):
    """连携技三栏（docs/254）：实战局里本干员当队员（--lead 另指队长），fx/px_plane = 1 / 0 / 2 各录一段（同种子、同参数，玩法逐行一致），
    从 1 那局的 PXPLOG（fx/recipe_log = 1）找连携事件（cover / combo）的游戏时间，换算成录像帧号，拼三栏 + 2 倍局部。"""
    t0, secs, st = a.t0, a.secs, 2
    dirs = {}
    for px in (1, 0, 2):
        tag = "link%d_s%d_%d" % (px, a.seed, t0)
        ex = base + ["--bal=fx/px_plane=%d" % px, "--bal=fx/recipe_log=1", "--realtime", "--rtfrom=%d" % t0, "--recframes=%d,%d" % (t0, secs * 30),
                     "--recstride=%d" % st, "--maxt=%d" % (t0 + secs + 1)]
        dirs[px] = os.path.join(BUILD, tag + "_frames")
        print(run(tag, ex, 30, dirs[px]), flush=True)
    log = open(os.path.join(LOGS, "link1_s%d_%d.log" % (a.seed, t0)), encoding="utf-8").read()
    evs = [l.split() for l in log.splitlines() if l.startswith("PXPLOG hsg cover") or l.startswith("PXPLOG hsg combo ") or l.startswith("FXRLOG angelina ang_link ")]
    print("连携事件", [(e[2], e[-1]) for e in evs], flush=True)
    if not evs:
        print("这段里没有连携技出手", flush=True)
        return False
    T = float(evs[0][-1])
    k = int(round((T - t0) * 30.0)) + (7 if evs[0][2] == "ang_link" else 8)   # 落定后约 0.25 秒（盾立定、冲击环扩开）；安洁莉娜取碎片绕圈收拢途中（出手后约 0.23 秒）
    k -= k % st
    fr = {px: os.path.join(dirs[px], "rec_%05d.png" % k) for px in (0, 2, 1)}
    if not all(os.path.exists(f) for f in fr.values()):
        print("缺帧", fr, flush=True)
        return False
    ims = [Image.open(fr[px]).convert("RGB") for px, _ in COLS]
    W, H = ims[0].size
    f30 = font(30)
    sheet = Image.new("RGB", (W * 3 + 8, H + 56), (12, 12, 16))
    dd = ImageDraw.Draw(sheet)
    dd.text((12, 8), OPS[OP]["name"] + " 连携技「%s」· 实战局同种子 %d · %.2f 秒" % ({"cover": "举盾", "ang_link": "引力环"}.get(evs[0][2], "举盾推挡"), a.seed, T), fill=(230, 230, 230), font=f30)
    for i, (im, (px, lab)) in enumerate(zip(ims, COLS)):
        sheet.paste(label(im.copy(), lab), (i * (W + 4), 56))
    os.makedirs(a.out, exist_ok=True)
    sheet.save(os.path.join(a.out, "cmp_link.png"))
    a1 = np.asarray(ims[2], dtype=np.int16)
    a0 = np.asarray(ims[0], dtype=np.int16)
    m = (np.abs(a1 - a0).sum(axis=2) > 60)
    ys, xs = np.nonzero(m)
    cx, cy = (int(np.median(xs)), int(np.median(ys))) if len(xs) else (W // 2, H // 2)
    cw, ch = 320, 180
    x0 = min(max(0, cx - cw // 2), W - cw)
    y0 = min(max(0, cy - ch // 2), H - ch)
    crop = Image.new("RGB", (cw * 2 * 3 + 8, ch * 2 + 56), (12, 12, 16))
    dd = ImageDraw.Draw(crop)
    dd.text((12, 8), "2 倍局部（最近邻放大） · 连携技", fill=(230, 230, 230), font=f30)
    for i, (im, (px, lab)) in enumerate(zip(ims, COLS)):
        crop.paste(label(im.crop((x0, y0, x0 + cw, y0 + ch)).resize((cw * 2, ch * 2), Image.NEAREST), lab, 20), (i * (cw * 2 + 4), 56))
    crop.save(os.path.join(a.out, "cmp_link_x2.png"))
    print("三栏 cmp_link 帧", k, flush=True)
    return diff("link0_s%d_%d" % (a.seed, t0), "link1_s%d_%d" % (a.seed, t0)) & diff("link0_s%d_%d" % (a.seed, t0), "link2_s%d_%d" % (a.seed, t0))


def branch(a):
    """分支招一行一招（转平面版，精二）：跃浪 / 回澜（跃浪路线 S2）、涌潮 / 怒涛第二圈（涌潮路线 S1）、怒涛终结大浪（涌潮路线 S3 结束）。
    按 PXPLOG 事件帧对齐，每行 6 帧（事件后 0–0.6 秒），斯卡蒂附近 2 倍局部"""
    os.makedirs(a.out, exist_ok=True)
    plan = [("wave", 1, 2.0, 120), ("surge", 0, 2.0, 120), ("surge", 2, 8.5, 90)]
    shots = {}
    for route, mode, start, n in plan:
        tag, frames, errs, ev = shoot(1, 2, mode, start, 2, n, extra=["--route=skadi:" + route], suffix="_" + route)
        log = open(os.path.join(LOGS, "demo_" + tag + ".log"), encoding="utf-8", errors="ignore").read()
        px = [l.split() for l in log.splitlines() if l.startswith("PXPLOG")]
        shots[(route, mode)] = (frames, px, int(start * 30))
        print(tag, len(frames), errs[:2], len(px), flush=True)

    def first(key, pred):
        frames, px, f0 = shots[key]
        for q in px:
            if pred(q) and (int(q[3]) - f0) // 2 >= 0:
                return frames, (int(q[3]) - f0) // 2
        return frames, None

    rows = [
        ("跃浪（S2 分支一）：一路碎浪往前推", ("wave", 1), lambda q: q[1] == "跃浪击", 2),
        ("回澜（S2 分支二）：海水倒卷回脚下，汇中心冲起水柱", ("wave", 1), lambda q: q[1] == "跃浪" and q[2] == "c", 0),
        ("涌潮（S1 分支一）：脚下涌出一圈矮水涌往外推", ("surge", 0), lambda q: q[1] == "涌潮" and q[5] == "-" and int(q[4]) < 160, 0),
        ("怒涛（S1 分支二）：0.4 秒后第二圈，更高 + 海绿", ("surge", 0), lambda q: q[1] == "涌潮" and q[5] == "skill" and int(q[4]) < 160, 0),
        ("怒涛（S1 分支二）：悲歌结束环身大碎浪", ("surge", 2), lambda q: q[1] == "涌潮" and int(q[4]) >= 160, 0),
    ]
    cw, ch = 560, 330
    sheet = Image.new("RGB", (cw * 6 + 8 * 5, 56 + (ch + 44) * len(rows)), (12, 12, 16))
    d = ImageDraw.Draw(sheet)
    d.text((12, 8), "斯卡蒂分支招（转平面版，精二，图鉴演示，1 倍；每行事件后约 0–0.6 秒）", fill=(230, 230, 230), font=font(28))
    for r, (lab, key, pred, off) in enumerate(rows):
        frames, k = first(key, pred)
        y = 56 + r * (ch + 44)
        d.text((12, y + 4), lab + ("" if k is not None else "（本局没触发）"), fill=(255, 255, 255), font=font(24))
        if k is None:
            continue
        for j in range(6):
            i = min(len(frames) - 1, k + off + j * 3)
            im = Image.open(frames[i]).convert("RGB")
            W, H = im.size
            c = im.crop((W // 2 - cw // 2 - 20, H // 2 - ch // 2 - 10, W // 2 + cw // 2 - 20, H // 2 + ch // 2 - 10)).resize((cw, ch), Image.NEAREST)   # 1 倍、大范围（2 倍局部会把大浪裁出框）
            sheet.paste(c, (j * (cw + 8), y + 40))
    sheet.save(os.path.join(a.out, "branches.png"))
    print("分支招", os.path.join(a.out, "branches.png"), flush=True)


def combo(a):
    """连携技「落潮横扫」三栏：局内（队长德克萨斯 + 斯卡蒂 + 推进之王，master 机器人会冲刺），同种子 fx/px_plane = 0 / 2 / 1 各一局，
    86 秒起连存 12 秒（30 帧原速），按转平面局的连携事件帧对齐三栏，另出 2 倍局部"""
    os.makedirs(a.out, exist_ok=True)
    t0, secs = 79, 6   # 实时步长下种子 3 约 82 秒触发一次落潮横扫（tools 里先不存帧探过）
    dirs = {}
    pxlog = []
    for px in (0, 2, 1):
        tag = "combo_px%d" % px
        fdir = os.path.join(BUILD, tag)
        # 「落潮横扫」是 E 连携（combo.gd，触发：队长冲刺结束），新版连携 link/v2 缺省开时不亮起，这里关掉 v2 拍它；
        # 队长德克萨斯 + 斯卡蒂 + 推进之王，master 机器人会冲刺；整局实时步长（快进步长不同会让冲刺时机分岔）
        ex = ["--seed=3", "--op=texas", "--squad=skadi,siege", "--bot=master", "--maxprog", "--bal=ult/test_fill_at=-1", "--bal=link/v2=0", "--bal=fx/px_plane=%d" % px,
              "--bal=fx/recipe_log=1", "--realtime", "--rtfrom=0", "--recframes=%d,%d" % (t0, secs * 60), "--maxt=%d" % (t0 + secs + 2)] + LATE
        r = run(tag, ex, 60, fdir)   # 60 帧步长：与非实时快跑同一步长，机器人冲刺时机一致（连携才会在同一时刻触发）
        print(r, flush=True)
        dirs[px] = fdir
        if px == 1:
            log = open(os.path.join(LOGS, tag + ".log"), encoding="utf-8", errors="ignore").read()
            pxlog = [l.split() for l in log.splitlines() if l.startswith("PXPLOG combo")]
    fr = {px: sorted(glob.glob(os.path.join(dirs[px], "rec_*.png"))) for px in dirs}
    n = min(len(v) for v in fr.values())
    if n == 0:
        print("没有帧")
        return
    # 连携帧：转平面局与「当前游戏」差异最大的那一帧（连携事件只有引擎帧号，录制起点的引擎帧号不可知）
    e = energy(fr[1][:n], fr[0][:n])
    k = int(np.argmax(e))
    print("连携事件", len(pxlog), "次；取第", k, "帧", flush=True)
    ims = [Image.open(fr[px][min(n - 1, k + 1)]).convert("RGB") for px, _ in COLS]
    W, H = ims[0].size
    fb = font(30)
    sheet = Image.new("RGB", (W * 3 + 8, H + 56), (12, 12, 16))
    dd = ImageDraw.Draw(sheet)
    dd.text((12, 8), "斯卡蒂连携技「落潮横扫」（局内 E 连携，队长冲刺落点；link/v2=0）· 同种子同一帧", fill=(230, 230, 230), font=fb)
    for i, (im, (px, lab)) in enumerate(zip(ims, COLS)):
        sheet.paste(label(im.copy(), lab), (i * (W + 4), 56))
    sheet.save(os.path.join(a.out, "cmp_combo.png"))
    a1 = np.asarray(ims[2], dtype=np.int16)
    a0 = np.asarray(ims[0], dtype=np.int16)
    ys, xs = np.nonzero(np.abs(a1 - a0).sum(axis=2) > 60)
    cx, cy = (int(np.median(xs)), int(np.median(ys))) if len(xs) else (W // 2, H // 2)
    cw, ch = 320, 180
    x0 = min(max(0, cx - cw // 2), W - cw)
    y0 = min(max(0, cy - ch // 2), H - ch)
    crop = Image.new("RGB", (cw * 2 * 3 + 8, ch * 2 + 56), (12, 12, 16))
    dd = ImageDraw.Draw(crop)
    dd.text((12, 8), "2 倍局部 · 连携技「落潮横扫」", fill=(230, 230, 230), font=fb)
    for i, (im, (px, lab)) in enumerate(zip(ims, COLS)):
        crop.paste(label(im.crop((x0, y0, x0 + cw, y0 + ch)).resize((cw * 2, ch * 2), Image.NEAREST), lab, 20), (i * (cw * 2 + 4), 56))
    crop.save(os.path.join(a.out, "cmp_combo_x2.png"))
    print("连携三栏", os.path.join(a.out, "cmp_combo.png"), flush=True)


def run(tag, extra, fps, fdir=None):
    os.makedirs(LOGS, exist_ok=True)
    args = [GR.find_godot(), "--path", GAME, "--audio-driver", "Dummy", "--resolution", "1280x720", "--fixed-fps", str(fps), "--",
            "--balance", "--nodeath", "--trace=1"] + extra
    if fdir:
        shutil.rmtree(fdir, ignore_errors=True)
        os.makedirs(fdir)
        args += ["--shotdir=" + fdir.replace(os.sep, "/")]
    out, err, to = GR.run_godot(args, 5400)
    open(os.path.join(LOGS, tag + ".log"), "w", encoding="utf-8").write((out or "") + "\n" + (err or ""))
    return tag, len([l for l in (out or "").splitlines() if l.startswith("TRACE")]), GR.script_errors(out, err)[:3], to


def traces(tag):
    p = os.path.join(LOGS, tag + ".log")
    return [l for l in open(p, encoding="utf-8").read().splitlines() if l.startswith("TRACE")] if os.path.exists(p) else []


def diff(a, b):
    ta, tb = traces(a), traces(b)
    n = sum(1 for x, y in zip(ta, tb) if x != y) + abs(len(ta) - len(tb))
    same = n == 0 and len(ta) > 0
    print("%s vs %s：TRACE %d / %d 行，%s" % (a, b, len(ta), len(tb), "逐行一致" if same else "有差异 %d 行" % n), flush=True)
    for i, (x, y) in enumerate(zip(ta, tb)):
        if x != y:
            print("  第 %d 行：\n   %s\n   %s" % (i + 1, x[:200], y[:200]))
            break
    return same


def main():
    global OP, MODE_NAME, BUILD, LOGS, REUSE, COLS
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["demo", "rec", "trace", "diff", "fps", "linkcmp", "branch", "combo"])
    ap.add_argument("--out", default=os.path.join(BUILD, "out"))
    ap.add_argument("--modes", default="3,0,1,2")
    ap.add_argument("--start", type=float, default=2.0)
    ap.add_argument("--every", type=int, default=2)
    ap.add_argument("--n", type=int, default=60)
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--squad", default="")
    ap.add_argument("--from", dest="t0", type=int, default=480)
    ap.add_argument("--secs", type=int, default=20)
    ap.add_argument("--maxt", type=int, default=300)
    ap.add_argument("--extra", default="")
    ap.add_argument("--pxs", default="0,1")
    ap.add_argument("--op", default="skadi", choices=sorted(OPS))
    ap.add_argument("--crf", type=int, default=20)
    ap.add_argument("--lead", default="", help="rec / trace：另找一名队长，--op 的干员当队员（拍连携技用）")
    ap.add_argument("--reuse", action="store_true")
    ap.add_argument("--force_k", type=int, default=-1)
    a = ap.parse_args()
    REUSE = a.reuse
    OP, MODE_NAME = a.op, OPS[a.op]["modes"]
    COLS = OPS[a.op].get("cols", COLS)
    if a.op != "skadi":
        BUILD = os.path.join(ROOT, "build", "pxplane_" + a.op)
        LOGS = os.path.join(BUILD, "logs")
    base = ["--seed=%d" % a.seed] + (["--op=" + a.lead, "--squad=" + a.op] if a.lead else ["--op=" + a.op]) + (["--squad=" + a.squad] if a.squad else []) + a.extra.split()
    if a.cmd == "demo":
        demo(a)
        return
    if a.cmd == "fps":
        fps_cmp(a)
        return
    if a.cmd == "branch":   # 斯卡蒂分支招（docs/246）
        branch(a)
        return
    if a.cmd == "combo":   # 斯卡蒂连携技「落潮横扫」三栏（docs/246）
        combo(a)
        return
    if a.cmd == "linkcmp":
        sys.exit(0 if linkcmp(a, base) else 1)
    tags = []
    if a.cmd == "rec":
        for px in (0, 1):   # 串行：本机同一时间只开 1 个 Godot
            tag = "rec%d_s%d_%d" % (px, a.seed, a.t0)
            ex = base + ["--bal=fx/px_plane=%d" % px, "--realtime", "--rtfrom=%d" % a.t0, "--recframes=%d,%d" % (a.t0, a.secs * 30), "--maxt=%d" % (a.t0 + a.secs + 1)]
            print(run(tag, ex, 30, os.path.join(BUILD, tag + "_frames")), flush=True)
            tags.append(tag)
        import imageio_ffmpeg
        ff = imageio_ffmpeg.get_ffmpeg_exe()
        d0, d1 = [os.path.join(BUILD, t + "_frames") for t in tags]
        n = min(len(glob.glob(os.path.join(d0, "rec_*.png"))), len(glob.glob(os.path.join(d1, "rec_*.png"))))
        lab = os.path.join(BUILD, "_rec_labels.png")
        im = Image.new("RGBA", (2560 + 4, 720), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        f = font(28)
        for i, t in enumerate(["关（当前游戏）", "开（fx/px_plane = 1 转平面）"]):
            x = i * 1284
            d.rectangle((x + 10, 660, x + 30 + int(d.textlength(t, font=f)), 705), fill=(0, 0, 0, 170))
            d.text((x + 20, 664), t, fill=(255, 255, 255, 255), font=f)
        im.save(lab)
        os.makedirs(a.out, exist_ok=True)
        mp4 = os.path.join(a.out, "late_%dm%02d_onoff.mp4" % (a.t0 // 60, a.t0 % 60))
        subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(d0, "rec_%05d.png"), "-framerate", "30", "-i", os.path.join(d1, "rec_%05d.png"),
                        "-i", lab, "-filter_complex", "[0:v]pad=1284:720:0:0:black[l];[l][1:v]hstack=inputs=2[h];[h][2:v]overlay=0:0[v]", "-map", "[v]", "-frames:v", str(n),
                        "-c:v", "libx264", "-crf", str(a.crf), "-pix_fmt", "yuv420p", mp4], check=True)
        print("录像", mp4, "%d 帧" % n, "%.1f MB" % (os.path.getsize(mp4) / 1048576))
    elif a.cmd == "trace":
        for px in [int(x) for x in a.pxs.split(",")]:
            tag = "trace%d_s%d" % (px, a.seed)
            print(run(tag, base + ["--bal=fx/px_plane=%d" % px, "--maxt=%d" % a.maxt], 60), flush=True)
            tags.append(tag)
    else:
        tags = [os.path.basename(f)[:-4] for f in sorted(glob.glob(os.path.join(LOGS, "trace*_s%d.log" % a.seed)))]
    ok = True
    for t in tags[1:]:
        ok &= diff(tags[0], t)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
