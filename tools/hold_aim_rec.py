# -*- coding: utf-8 -*-
"""按住瞄准录像（10-31）：三段拼一条 mp4——键鼠按住左键瞄准、触屏拖动瞄准键、召唤类（凯尔希 Mon3tr）按住瞄准。
每段：前 3 秒不按（自动普攻）→ 按住瞄准 → 松手回到自动。原速 30 帧 / 秒（--realtime --fixed-fps 30），静音，窗口由 godot_runner 挪到屏幕外。
驱动脚本 tools/hold_aim_rec.gd（替玩家按住，画光标 / 指尖）。

用法：python tools/hold_aim_rec.py [--seed 1 --start 75]
输出：主仓库 build/hold_aim_1031/hold_aim.mp4
"""
import argparse, glob, os, shutil, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FPS = 30
SECS = 13.0
# [段名, 标题, 队长, 队友, 方式, 方向（度）, 每秒转角, 附加参数]
SEGS = [
    ("kb", "键鼠：按住左键朝光标", "exusiai", "skadi,saria", "kb", "180,270,0,90", 0.0, []),
    ("touch", "触屏：拖动瞄准键", "lappland", "skadi,saria", "touch", "180,0", 0.0, ["--touch"]),
    ("summon", "召唤：Mon3tr 扑向瞄准方向", "kaltsit", "skadi,saria", "kb", "180,0", 0.0, []),
]


def record(seg, a, out_dir, ff):
    tag, title, op, sq, mode, dirs, spin, extra = seg
    fdir = os.path.join(out_dir, "frames_" + tag)
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir, exist_ok=True)
    h0, h1 = a.start + 3.0, a.start + 10.0
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", str(FPS),
            "-s", os.path.join(ROOT, "tools", "hold_aim_rec.gd"), "--",
            "--balance", "--seed=%d" % a.seed, "--op=" + op, "--squad=" + sq, "--bot=expert", "--realtime", "--nodeath",
            "--rtfrom=%g" % max(0.0, a.start - 2.0), "--recframes=%g,%d" % (a.start, int(SECS * FPS)), "--shotdir=" + fdir,
            "--ha_mode=" + mode, "--ha_from=%g" % h0, "--ha_to=%g" % h1, "--ha_dirs=" + dirs, "--ha_spin=%g" % spin] + extra
    out, err, to = GR.run_godot(args, 1800)
    open(os.path.join(out_dir, "log_%s.txt" % tag), "w", encoding="utf-8").write(out + "\n----\n" + err)
    errs = GR.script_errors(out, err)
    n = len(glob.glob(os.path.join(fdir, "rec_*.png")))
    print(tag, "帧数", n, "脚本错误", errs[:3] if errs else 0, "超时" if to else "", flush=True)
    font = "fontfile='C\:/Windows/Fonts/msyh.ttc'"
    tf = []
    for i, txt in enumerate([title, "自动普攻（不按）", "按住瞄准"]):   # 中文走 UTF-8 文本文件，免得命令行编码出错
        p = os.path.join(out_dir, "label_%s_%d.txt" % (tag, i))
        open(p, "w", encoding="utf-8").write(txt)
        tf.append("textfile='%s'" % p.replace("\\", "/").replace(":", "\:"))
    vf = ("scale=1280:-2,"
          "drawtext=%s:%s:x=24:y=24:fontsize=34:fontcolor=white:box=1:boxcolor=black@0.55:boxborderw=10,"
          "drawtext=%s:%s:x=24:y=80:fontsize=28:fontcolor=white:box=1:boxcolor=black@0.55:boxborderw=8:enable='lt(t\,3)+gte(t\,10)',"
          "drawtext=%s:%s:x=24:y=80:fontsize=28:fontcolor=0xffc070:box=1:boxcolor=black@0.55:boxborderw=8:enable='between(t\,3\,10)'"
          ) % (font, tf[0], font, tf[1], font, tf[2])
    mp4 = os.path.join(out_dir, "seg_%s.mp4" % tag)
    subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(fdir, "rec_%05d.png"),
                    "-vf", vf, "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "24", "-an", mp4], check=True)
    return mp4


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(GR.common_root(), "build", "hold_aim_1031"))
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--start", type=float, default=75.0)
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    os.makedirs(a.out, exist_ok=True)
    GR.ensure_imported(os.path.join(ROOT, "game"))
    segs = [s for s in SEGS if not a.only or s[0] in a.only.split(",")]
    mp4s = [record(s, a, a.out, ff) for s in segs]
    lst = os.path.join(a.out, "list.txt")
    open(lst, "w", encoding="utf-8").write("".join("file '%s'\n" % p.replace("\\", "/") for p in mp4s))
    final = os.path.join(a.out, "hold_aim.mp4")
    subprocess.run([ff, "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", final], check=True)
    print("成片", final)


if __name__ == "__main__":
    main()
