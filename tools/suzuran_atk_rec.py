# -*- coding: utf-8 -*-
"""铃兰普攻音效候选录像（11-16）：铃兰当队长、机器人打一段，原速原色 30 帧录 10 秒（游戏钟与录像钟 1:1）。
做法同 exu_sync_rec.py：测试局静音，--sfxtrace 记下每次真正放出的音效，离线按 game/audio/sfx/*.wav 混音后合进 mp4（只有音效、没有配乐）。
同一段画面只录一次，按候选把 op_suzuran_atk 换成 build/sfx_suzuran_1116/op_suzuran_atk_<x>.wav 各混一版，画面完全相同、只差普攻声。
候选由 game/tools/gen_sfx_suzuran_atk_1116.py 生成（先跑它）。

用法：python tools/suzuran_atk_rec.py [--start 20] [--secs 10] [--seed 3]
输出：主仓库 build/sfx_suzuran_1116/铃兰普攻_现版.mp4、铃兰普攻_A.mp4 / _B.mp4 / _C.mp4
"""
import argparse, glob, json, os, shutil, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
import exu_sync_rec as X

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FPS = X.FPS
NAME = "op_suzuran_atk"
LABELS = {"old": ("现版", "现版（程序合成）"), "a": ("A", "候选 A 符咒·短"), "b": ("B", "候选 B 符咒·长"), "c": ("C", "候选 C 符咒 + 小铃")}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(GR.common_root(), "build", "sfx_suzuran_1116"))
    ap.add_argument("--start", type=float, default=20.0)
    ap.add_argument("--secs", type=float, default=10.0)
    ap.add_argument("--seed", type=int, default=3)
    a = ap.parse_args()
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    GR.ensure_imported(os.path.join(ROOT, "game"))
    fdir = os.path.join(a.out, "frames")
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir, exist_ok=True)
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", str(FPS), "--",
            "--balance", "--seed=%d" % a.seed, "--op=suzuran", "--bot=expert", "--realtime", "--rtfrom=%g" % max(0.0, a.start - 2.0),
            "--recframes=%g,%d" % (a.start, int(a.secs * FPS)), "--shotdir=" + fdir, "--sfxtrace", "--sfxstat"]
    out, err, to = GR.run_godot(args, 1800)
    errs = GR.script_errors(out, err)
    tr = None
    for ln in out.splitlines():
        if ln.startswith("SFXTRACE "):
            tr = json.loads(ln[9:])
    n = len(glob.glob(os.path.join(fdir, "rec_*.png")))
    if errs or to or tr is None or n == 0:
        print("失败：", "超时" if to else ("；".join(errs[:3]) or "没有帧 / 没有 SFXTRACE"))
        return 1
    ev = [e for e in tr["trace"] if e[1] == NAME]
    print("普攻出手音 %d 声 / %.1f 秒；全部音效：%s" % (len(ev), n / FPS, sorted({e[1] for e in tr["trace"]})), flush=True)
    raw = os.path.join(a.out, "frames_raw")
    shutil.rmtree(raw, ignore_errors=True)
    shutil.copytree(fdir, raw)
    for key, (short, label) in LABELS.items():
        src = os.path.join(a.out, "op_suzuran_atk_%s.wav" % key)
        if not os.path.exists(src):
            print("缺候选", src)
            continue
        X.load_wav.__defaults__[0].clear()
        X.load_wav(NAME)   # 先占位再替换成候选
        import wave, numpy as np
        w = wave.open(src)
        x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768.0
        if w.getnchannels() > 1:
            x = x.reshape(-1, w.getnchannels()).mean(1)
        X.load_wav.__defaults__[0][NAME] = (x, w.getframerate())
        shutil.rmtree(fdir, ignore_errors=True)
        shutil.copytree(raw, fdir)
        X.label_frames(fdir, "铃兰普攻 · " + label)
        wav = os.path.join(fdir, "mix.wav")
        X.write_wav(wav, X.mix(tr["trace"], tr["frame0"], n))
        mp4 = os.path.join(a.out, "铃兰普攻_%s.mp4" % short)
        subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(fdir, "rec_%05d.png"), "-i", wav,
                        "-vf", "scale=1280:-2", "-c:v", "libx264", "-crf", "20", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-shortest", mp4], check=True)
        print("视频", mp4, os.path.getsize(mp4), flush=True)
    shutil.rmtree(fdir, ignore_errors=True)
    shutil.rmtree(raw, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
