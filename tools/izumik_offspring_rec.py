# -*- coding: utf-8 -*-
"""伊祖米克开场子代（小水母）新旧对照录像（用户 10-30「一开始的水母可以多一点，队友能全部清完」）。

同 tools/boss_bgm_rec.py：--autotest --bossacts=izumik，Boss 在队长旁刷出，从登场后 1 秒起录 30 秒（学习期 20 秒 + 一幕开头），
30 帧 / 秒原速，带声音（配乐按 --musiclog 离线混、音效按 --sfxtrace 离线混；测试局本身静音、窗口经 godot_runner 放副屏 / 屏幕外）。
改前 = --bal 覆盖回 10-30 前的值（学习期每 4 秒 2 只、一幕每批 4–6 只、血量 ×1），改后 = 当前缺省（乙档；--tier=a 用甲档）。
用法：python tools/izumik_offspring_rec.py [--tier=a|b]   输出：主仓库 build/izumik_offspring_1030/开场子代_改前vs改后.mp4
"""
import argparse, glob, json, os, re, shutil, subprocess, sys
import numpy as np
import soundfile as sf

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
import exu_sync_rec as EX
import boss_bgm_rec as BB

ROOT = BB.ROOT
FPS, SR = EX.FPS, EX.SR
OLD = ["boss/izumik_learn_n=2", "boss/izumik_learn_cd=4", "boss/izumik_off_hp=1", "boss/izumik_batch_min=4", "boss/izumik_batch_max=6", "boss/izumik_learn_spd=45", "boss/izumik_absorb_need=5"]
TIER_A = ["boss/izumik_learn_n=3", "boss/izumik_learn_cd=3", "boss/izumik_off_hp=2.5", "boss/izumik_learn_spd=60", "boss/izumik_batch_min=6", "boss/izumik_batch_max=8", "boss/izumik_absorb_need=5"]


def seg(out, tag, bals, label, ff):
    fdir = os.path.join(out, "frames_" + tag)
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir)
    nf = int(BB.SECS * FPS)
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", str(FPS), "--",
            "--autotest", "--seed=1", "--op=mizuki", "--bossacts=izumik", "--realtime", "--bal=boss/acts_demo_len=60",
            "--recframes=%g,%d" % (BB.REC_T0, nf), "--shotdir=" + fdir.replace(os.sep, "/"), "--sfxtrace", "--musiclog"] + ["--bal=" + b for b in bals]
    o, e, to = GR.run_godot(args, 900)
    open(os.path.join(out, tag + ".log"), "w", encoding="utf-8").write(o + "\n----\n" + e)
    tr, t_start, track = None, None, ""
    for ln in o.splitlines():
        if ln.startswith("SFXTRACE "):
            tr = json.loads(ln[9:])
        m = re.match(r"MUSIC t=([\d.]+) (final\w*) (p[12])", ln)
        if m and m.group(3) == "p1" and t_start is None:
            track, t_start = m.group(2), float(m.group(1))
    n = len(glob.glob(os.path.join(fdir, "rec_*.png")))
    errs = GR.script_errors(o, e)
    print(tag, n, "帧", "超时" if to else ("；".join(errs[:3]) or "无脚本错误"), flush=True)
    if to or tr is None or n < nf:
        raise SystemExit("录制失败，见 " + os.path.join(out, tag + ".log"))
    EX.label_frames(fdir, label)
    ns = int(n / FPS * SR)
    y = BB.music_mix(track, t_start, None, ns) if t_start is not None else np.zeros((ns, 2))
    s = EX.mix(tr["trace"], tr["frame0"], n)[:ns]
    y[: len(s)] += s[:, None]
    pk = np.abs(y).max()
    if pk > 0.94:
        y *= 0.94 / pk
    wav = os.path.join(fdir, "mix.wav")
    sf.write(wav, y.astype(np.float32), SR, subtype="PCM_16")
    mp4 = os.path.join(out, "seg_%s.mp4" % tag)
    subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(fdir, "rec_%05d.png"), "-i", wav,
                    "-vf", "scale=1280:-2", "-c:v", "libx264", "-crf", "28", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-shortest", mp4], check=True)
    shutil.rmtree(fdir, ignore_errors=True)
    return mp4


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tier", default="b", choices=["a", "b"])   # b = 缺省（乙档，10-31 定）
    ap.add_argument("--out", default=os.path.join(GR.common_root(), "build", "izumik_offspring_1030"))
    a = ap.parse_args()
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    os.makedirs(a.out, exist_ok=True)
    GR.ensure_imported(os.path.join(ROOT, "game"))
    new_label = "改后：学习期每 2.5 秒 4 只、一幕每批 7–9 只、子代血量 ×3.5、移速 70、吸收 3 只强化一层" if a.tier == "b" else "改后（甲档）：学习期每 3 秒 3 只、一幕每批 6–8 只、子代血量 ×2.5、移速 60"
    parts = [seg(a.out, "old", OLD, "改前：学习期每 4 秒 2 只、一幕每批 4–6 只、子代血量 ×1、移速 45", ff),
             seg(a.out, "new_" + a.tier, [] if a.tier == "b" else TIER_A, new_label, ff)]
    lst = os.path.join(a.out, "list.txt")
    open(lst, "w", encoding="utf-8").write("".join("file '%s'\n" % p.replace("\\", "/") for p in parts))
    final = os.path.join(a.out, "开场子代_改前vs改后%s.mp4" % ("" if a.tier == "b" else "_甲档"))
    subprocess.run([ff, "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", final], check=True)
    os.remove(lst)
    for p in parts:
        os.remove(p)
    print("视频", final, "%.1f MB" % (os.path.getsize(final) / 1e6))
    return 0


if __name__ == "__main__":
    sys.exit(main())
