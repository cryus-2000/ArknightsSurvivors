# -*- coding: utf-8 -*-
"""小怪冲刺只靠身体预警（docs/139 §7.6）的后期对照：同 seed 同一局分别用 render/dash_tell_style 2 / 3 录一段，左右并排出 mp4，
再按两段画面的差异（同局同帧，只有冲刺预警不同）自动找小怪蓄力的位置，出一张近景序列图。

    python tools/probes/dash_body_tell_rec.py rec 2 [--dir D]      # 录 style 2（截图到 D/s2，缺省在 C 盘临时目录）
    python tools/probes/dash_body_tell_rec.py rec 3
    python tools/probes/dash_body_tell_rec.py video <输出.mp4> [--mb 25]
    python tools/probes/dash_body_tell_rec.py closeup <输出.png>

局：seed 13、熟练机器人、满编（水月 / 灰烬 / 维什戴尔 / 凯尔希）、--nodeath，7:00 起 120 秒；1920×1080、--fixed-fps 30 + --realtime（原速、原色），
窗口经 godot_runner 放副屏 / 屏幕外、静音。
"""
import argparse, os, subprocess, sys, tempfile
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as GR

T0, SECS, FPS = 420.0, 120, 30
SQUAD = ["mizuki", "siege", "wisadel", "kaltsit"]
DEF_DIR = os.path.join(tempfile.gettempdir(), "dash_body_tell_1104")


def rec(style, base, t0=T0, secs=SECS):
    d = os.path.join(base, "s%d" % style)
    os.makedirs(d, exist_ok=True)
    for f in os.listdir(d):
        os.remove(os.path.join(d, f))
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", str(FPS), "--resolution", "1920x1080", "--",
            "--balance", "--seed=13", "--op=" + SQUAD[0], "--squad=" + ",".join(SQUAD[1:]), "--bot=expert", "--nodeath",
            "--realtime", "--playclock", "--rtfrom=%g" % (t0 - 3.0), "--recframes=%g,%d" % (t0, secs * FPS),
            "--shotdir=" + d.replace(os.sep, "/"), "--bal=render/dash_tell_style=%d" % style]
    out, err, to = GR.run_godot(args, 7200)
    open(os.path.join(d, "stdout.txt"), "w", encoding="utf-8").write(out[-20000:] + "\n----\n" + err[-5000:])
    n = len([f for f in os.listdir(d) if f.startswith("rec_")])
    print("style %d 帧 %d %s %s" % (style, n, "超时" if to else "", GR.script_errors(out, err)[:2]))


def frames(base):
    a, b = os.path.join(base, "s2"), os.path.join(base, "s3")
    fa = sorted(f for f in os.listdir(a) if f.startswith("rec_"))
    fb = sorted(f for f in os.listdir(b) if f.startswith("rec_"))
    n = min(len(fa), len(fb))
    return [(os.path.join(a, fa[i]), os.path.join(b, fb[i])) for i in range(n)]


def video(base, dst, mb):
    import imageio_ffmpeg
    pairs = frames(base)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 22)
    except OSError:
        font = None
    W, H = 960, 540
    # 满屏噪点画面很难压：2 分钟 1928×540 双画面 x264 crf 33 仍 29.4 MiB、x265 crf 34 仍 25.9 MiB（11-04 实测）。
    # 改成先拼出无损中间文件，再 x264 两遍编码按体积卡到 mb × 0.94
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    mid = os.path.join(base, "_mid_lossless.mkv")
    p = subprocess.Popen([ff, "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (W * 2 + 8, H), "-r", str(FPS), "-i", "-",
                          "-c:v", "libx264", "-qp", "0", "-preset", "ultrafast", "-pix_fmt", "yuv444p", mid], stdin=subprocess.PIPE)
    for fa, fb in pairs:
        fr = Image.new("RGB", (W * 2 + 8, H), (10, 12, 18))
        fr.paste(Image.open(fa).convert("RGB").resize((W, H), Image.NEAREST), (0, 0))
        fr.paste(Image.open(fb).convert("RGB").resize((W, H), Image.NEAREST), (W + 8, 0))
        d = ImageDraw.Draw(fr)
        for x, s in ((8, "style 2 现状：威胁者短箭"), (W + 16, "style 3：只靠身体预警")):
            d.rectangle((x - 4, 4, x + 270, 34), fill=(0, 0, 0))
            d.text((x, 6), s, fill=(255, 230, 150), font=font)
        p.stdin.write(fr.tobytes())
    p.stdin.close()
    p.wait()
    kbps = int(mb * 0.94 * 8 * 1024 * 1024 / (len(pairs) / FPS) / 1000)
    log = os.path.join(base, "_x264pass")
    for ps in (1, 2):
        subprocess.run([ff, "-y", "-loglevel", "error", "-i", mid, "-c:v", "libx264", "-preset", "slow", "-b:v", "%dk" % kbps, "-pass", str(ps), "-passlogfile", log,
                        "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-an"] + (["-f", "mp4", "NUL" if os.name == "nt" else "/dev/null"] if ps == 1 else [dst]), check=True)
    os.remove(mid)
    print("两遍 %d kbps：%.1f MiB，%d 帧" % (kbps, os.path.getsize(dst) / 1048576.0, len(pairs)))


def closeup(base, dst):
    """两段差异最集中的若干处（小怪蓄力：style 2 有短箭、style 3 有身体动作），各取蓄力前后 8 帧近景，上 style 2、下 style 3"""
    pairs = frames(base)
    hits = []
    for i in range(0, len(pairs), 3):
        a = np.asarray(Image.open(pairs[i][0]).convert("RGB")).astype(np.int16)
        b = np.asarray(Image.open(pairs[i][1]).convert("RGB")).astype(np.int16)
        # 两局 GPU 粒子落点每次不同，全图差异找不到；只找「style 2 有洋红短箭、style 3 同位置没有」的像素（Boss / 精英的线两边都有，抵消掉）
        mag = lambda c: (c[:, :, 0] > 170) & (c[:, :, 1] < 120) & (c[:, :, 2] > 80) & (c[:, :, 2] < 230)
        m = mag(a) & ~mag(b)
        m[:90] = False   # 顶部 HUD
        m[-160:] = False   # 底部 HUD
        ys, xs = np.nonzero(m)
        if 25 < xs.size < 900 and np.ptp(xs) < 140 and np.ptp(ys) < 140:   # 一处集中、短箭量级 = 一只蓄力中的小怪（更大的是 Boss 混战里的洋红特效）
            hits.append((xs.size, i, int(np.median(xs)), int(np.median(ys))))
    hits.sort(key=lambda h: abs(h[0] - 300))   # 越接近一根短箭的像素量越靠前
    pick, used = [], []
    for h in hits:
        if all(abs(h[1] - u) > 45 for u in used):
            pick.append(h)
            used.append(h[1])
        if len(pick) == 3:
            break
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 16)
    except OSError:
        font = None
    CW, CH, Z, K = 360, 240, 2, 8
    rows = []
    for _, i, cx, cy in pick:
        x0, y0 = max(0, cx - CW // 2), max(0, cy - CH // 2)
        idx = [min(len(pairs) - 1, max(0, i - 12 + 3 * k)) for k in range(K)]
        for s in (0, 1):
            row = Image.new("RGB", (K * (CW * Z + 4), CH * Z + 22), (10, 12, 18))
            dr = ImageDraw.Draw(row)
            dr.text((4, 2), ("style 2" if s == 0 else "style 3") + "  帧 %d 起每 3 帧（0.1 秒）" % idx[0], fill=(255, 230, 150), font=font)
            for k, j in enumerate(idx):
                im = Image.open(pairs[j][s]).convert("RGB").crop((x0, y0, x0 + CW, y0 + CH)).resize((CW * Z, CH * Z), Image.NEAREST)
                row.paste(im, (k * (CW * Z + 4), 22))
            rows.append(row)
    if not rows:
        print("没找到集中的差异")
        return
    W = rows[0].width
    out = Image.new("RGB", (W, sum(r.height + 6 for r in rows)), (0, 0, 0))
    y = 0
    for r in rows:
        out.paste(r, (0, y))
        y += r.height + 6
    out.save(dst, optimize=True)
    print(dst, [(i, cx, cy) for _, i, cx, cy in pick])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd")
    ap.add_argument("arg", nargs="?")
    ap.add_argument("--dir", default=DEF_DIR)
    ap.add_argument("--mb", type=float, default=25.0)
    ap.add_argument("--t0", type=float, default=T0)   # 近景用：另录一段早期干净画面（如 --t0 150 --secs 30 --dir <另一个目录>）
    ap.add_argument("--secs", type=int, default=SECS)
    a = ap.parse_args()
    if a.cmd == "rec":
        rec(int(a.arg), a.dir, a.t0, a.secs)
    elif a.cmd == "video":
        video(a.dir, a.arg, a.mb)
    elif a.cmd == "closeup":
        closeup(a.dir, a.arg)


if __name__ == "__main__":
    main()
