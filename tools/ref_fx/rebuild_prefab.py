# -*- coding: utf-8 -*-
"""原作特效 prefab 还原（内部参照，docs/242 §13）：从本机明日方舟客户端的 .ab 读 prefab（贴图、颜色、粒子参数、混合方式），
按层级回放，出关键帧拼图和 mp4，给 pixelfx 放开版画招式时对照形状、节奏和颜色。原作素材和输出都不进 git / 包。

用法：
  python tools/ref_fx/rebuild_prefab.py <干员> --list [--grep 关键字]     # 列出特效包里的 prefab
  python tools/ref_fx/rebuild_prefab.py <干员> <prefab>[,<prefab>...] [选项]
    --dur 2.0        时长（秒，缺省 2）
    --scale 1.0      画面缩放（像素 / 单位 = 200 × scale）
    --ground auto    地面投影：auto（树里有 rotation_z 节点）/ on / off
    --flip           朝左
    --path 2.5,0.5   拖尾 / 按距离发射的路径：向右飞 2.5 单位、用时 0.5 秒（弹道类 prefab 用；不给就不画拖尾和连线）
    --line 2.5       连线：从根节点向右 2.5 单位（LineRenderer 用）
    --stop 1.0       循环发射在第几秒停（缺省不停）
    --seed 1 --fps 30 --size 960x640 --keys 8 --slow 2
    --out 目录        缺省 <主仓库>/Claude outputs/<干员>_ref/
    --reindex        重建依赖包索引（客户端更新后）
干员 id 用本作的（skadi、skalter、specter_unchained …，表见 arkab.OPS）；也可以直接给 .ab 路径。
多个 prefab 用逗号隔开时同时从 0 秒起叠在同一位置（例：起手 + 刀光 + 命中）。
输出：<prefab>_ref.mp4（原速）、<prefab>_ref_slow2x.mp4、<prefab>_ref_keyframes.png（均匀 8 帧 + 时间）、<prefab>.json（层级 dump，查参数用）。
贴图先找 build/ark_ref/<干员>/（已导出的参照图），没有再从包里导到 build/ark_ref/<干员>/_tex/；网格存 build/ark_ref/<干员>/_mesh/。
近似和不支持的部分见 sim.py 文件头；子发射器、噪声、力场不模拟，读关键帧时以原作录像为准。
需要：UnityPy 1.25.x、lz4、numpy、Pillow、imageio-ffmpeg（本机系统 python 都有）。第一次运行会建依赖包索引（只读包头，约 6 分钟）。
原型：逻各斯会话 Claude outputs/logos_ref/scripts。
"""
import argparse, json, os, shutil, subprocess, sys, tempfile
import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import arkab as AB
import sim as SM

ROOT = AB.ROOT
FONT = "C:/Windows/Fonts/msyh.ttc"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("op")
    ap.add_argument("prefabs", nargs="?", default="")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--grep", default="")
    ap.add_argument("--dur", type=float, default=2.0)
    ap.add_argument("--scale", type=float, default=1.0)
    ap.add_argument("--ground", default="auto", choices=["auto", "on", "off"])
    ap.add_argument("--flip", action="store_true")
    ap.add_argument("--path", default="")
    ap.add_argument("--line", type=float, default=0.0)
    ap.add_argument("--stop", type=float, default=None)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--size", default="960x640")
    ap.add_argument("--keys", type=int, default=8)
    ap.add_argument("--slow", type=float, default=2.0)
    ap.add_argument("--out", default="")
    ap.add_argument("--reindex", action="store_true")
    a = ap.parse_args()

    env, abp = AB.load_env(a.op, a.reindex)
    if a.list or not a.prefabs:
        names = [n for n in AB.list_prefabs(env) if a.grep.lower() in n.lower()]
        print("%s（%s）：%d 个 prefab" % (a.op, abp, len(names)))
        for n in names:
            print("  " + n)
        return
    want = [x for x in a.prefabs.split(",") if x]
    dump = AB.dump_prefabs(env, want)
    miss = [w for w in want if w not in dump]
    if miss:
        sys.exit("包里没有这些 prefab：%s（先 --list --grep 查名字）" % "、".join(miss))
    op = a.op if a.op in AB.OPS else os.path.splitext(os.path.basename(abp))[0]
    ref = os.path.join(ROOT, "build", "ark_ref", op)
    texd, meshd = os.path.join(ref, "_tex"), os.path.join(ref, "_mesh")
    out = a.out or os.path.join(ROOT, "Claude outputs", "%s_ref" % op)
    os.makedirs(out, exist_ok=True)
    AB.export_meshes(env, want, meshd)
    used = set()
    for r in dump.values():
        AB.textures_in(r, used)
    SM.cfg.TEX_DIRS = [ref, texd]
    have = {t for t in used if SM.tex(t) is not None}
    SM._tex.clear()
    n_tex = AB.export_textures(env, used - have, texd)

    W, H = (int(x) for x in a.size.split("x"))
    SM.cfg.W, SM.cfg.H, SM.cfg.S, SM.cfg.FPS, SM.cfg.MESH = W, H, 200.0 * a.scale, a.fps, meshd
    SM.cfg.END = max(a.dur, 0.5)
    anchor = np.array([W * (0.62 if a.flip else 0.38) if (a.path or a.line) else W * 0.5, H * 0.62])
    path = line = None
    if a.path:
        dist, secs = (float(x) for x in a.path.split(","))
        sgn = -1 if a.flip else 1
        path = (0.0, secs, lambda t, d=dist, s=secs: anchor + np.array([sgn * d * SM.cfg.S * min(1.0, max(0.0, t / s)), 0.0]))
    if a.line:
        line = (anchor, anchor + np.array([(-1 if a.flip else 1) * a.line * SM.cfg.S, 0.0]))
    ground = None if a.ground == "auto" else a.ground == "on"
    insts = [SM.Inst(dump[w], w, 0.0, anchor, stop=a.stop, flip=-1 if a.flip else 1, ground=ground, path=path, line=line, seed=a.seed + i) for i, w in enumerate(want)]
    nps = sum(sum(isinstance(it, SM.PSim) for it in I.items) for I in insts)

    tag = "+".join(want) if len(want) < 4 else want[0] + "_etc"
    tag = "".join(ch if ch.isalnum() or ch in "_-+#" else "_" for ch in tag)
    fnt = ImageFont.truetype(FONT, 16) if os.path.exists(FONT) else ImageFont.load_default()
    nf = int(round(a.dur * a.fps))
    tmp = tempfile.mkdtemp(prefix="refx_")
    frames = []
    try:
        for i in range(nf):
            t = i / a.fps
            base = Image.new("RGB", (W, H), SM.cfg.BG)
            d = ImageDraw.Draw(base)
            step = int(SM.cfg.S * 0.5)
            for x in range(int(anchor[0]) % step, W, step):
                d.line([(x, 0), (x, H)], fill=(60, 66, 77))
            for y in range(int(anchor[1]) % step, H, step):
                d.line([(0, y), (W, y)], fill=(60, 66, 77))
            d.ellipse([anchor[0] - 3, anchor[1] - 3, anchor[0] + 3, anchor[1] + 3], outline=(200, 200, 200))
            cv = SM.Canvas(base)
            for I in insts:
                I.draw(cv, t)
            im = cv.image()
            ImageDraw.Draw(im).text((8, 6), "%s  %s  t=%.2fs（原作参照还原，近似）" % (op, tag, t), fill=(220, 220, 220), font=fnt)
            im.save(os.path.join(tmp, "f%04d.png" % i))
            frames.append(im)
        ff = __import__("imageio_ffmpeg").get_ffmpeg_exe()
        base_mp4 = os.path.join(out, tag + "_ref.mp4")
        for mp4, vf in ((base_mp4, "pad=ceil(iw/2)*2:ceil(ih/2)*2"), (os.path.join(out, "%s_ref_slow%gx.mp4" % (tag, a.slow)), "setpts=%g*PTS,pad=ceil(iw/2)*2:ceil(ih/2)*2" % a.slow)):
            subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", str(a.fps), "-i", os.path.join(tmp, "f%04d.png"), "-vf", vf,
                            "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", "-r", str(a.fps), mp4], check=True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    k = max(1, min(a.keys, nf))
    pick = [frames[int(round(j * (nf - 1) / max(1, k - 1)))] for j in range(k)]
    cols = 4 if k > 4 else k
    rows = (k + cols - 1) // cols
    tw, th = W // 2, H // 2
    sheet = Image.new("RGB", (tw * cols, th * rows), (20, 22, 26))
    for j, im in enumerate(pick):
        sheet.paste(im.resize((tw, th), Image.LANCZOS), ((j % cols) * tw, (j // cols) * th))
    sheet.save(os.path.join(out, tag + "_ref_keyframes.png"))
    for w in want:
        json.dump(dump[w], open(os.path.join(out, "%s.json" % "".join(ch if ch.isalnum() or ch in "_-#" else "_" for ch in w)), "w", encoding="utf-8"), ensure_ascii=False, indent=1, default=str)
    lost = set().union(*(I.missing for I in insts))
    print("%s：%d 帧（%.1f 秒）、粒子系统 %d 个、新导出贴图 %d 张%s → %s" % (tag, nf, a.dur, nps, n_tex, "、缺贴图 " + "、".join(sorted(lost)) if lost else "", out))


if __name__ == "__main__":
    main()
