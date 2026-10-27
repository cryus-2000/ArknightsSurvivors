# -*- coding: utf-8 -*-
"""「冲锋号令·γ型」发动音对照录像（10-28）：同 seed 录三遍（每遍两段各 10 秒：推进之王 S1、德克萨斯 S2，各自作队友、--onlyskill 充对应技能），--cmdcue=old / soft / mute，各 20 秒原速（30 帧 / 秒）配「真正放出的」音效
（测试局静音，录屏时 --sfxtrace 记下每次放出的音效，离线混音，同 tools/exu_sync_rec.py）。编队：德克萨斯（队长）+ 推进之王 + 能天使，--maxprog 解锁全部技能。
用法：python tools/cmd_cue_rec.py [--sptest] [--start 60]   输出：主仓库 build/cmd_cue_1028/冲锋号令音效对照.mp4（旧 → 轻随响 → 无声）
"""
import argparse, glob, json, os, re, shutil, subprocess, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
import exu_sync_rec as R

ROOT = R.ROOT
FPS = R.FPS
VARS = [("old", "旧：冲锋号令原音"), ("soft", "轻随响（约 0.1 秒，比普攻轻约 6 dB，1.5 秒内只响一次）"), ("mute", "无声")]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(GR.common_root(), "build", "cmd_cue_1028"))
    ap.add_argument("--start", type=float, default=60.0)
    ap.add_argument("--secs", type=float, default=10.0)
    ap.add_argument("--seed", type=int, default=3)
    
    a = ap.parse_args()
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    os.makedirs(a.out, exist_ok=True)
    GR.ensure_imported(os.path.join(ROOT, "game"))
    parts = []
    SEGS = [("siege", "--op=texas --squad=siege,exusiai --onlyskill=0", "推进之王 S1「冲锋号令·γ型」"),
            ("texas", "--op=siege --squad=texas,exusiai --onlyskill=1 --prog=2", "德克萨斯 S2「冲锋号令·γ型」")]
    for key, label in VARS:
        for sk, sargs, slabel in SEGS:
            tag = key + "_" + sk
            fdir = os.path.join(a.out, "frames_" + tag)
            shutil.rmtree(fdir, ignore_errors=True)
            os.makedirs(fdir, exist_ok=True)
            args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", str(FPS), "--",
                    "--balance", "--seed=%d" % a.seed, "--bot=expert", "--realtime", "--rtfrom=%g" % max(0.0, a.start - 2.0),
                    "--recframes=%g,%d" % (a.start, int(a.secs * FPS)), "--shotdir=" + fdir, "--sfxtrace", "--sfxstat", "--sptest", "--cmdcue=" + key] + sargs.split()
            out, err, to = GR.run_godot(args, 1800)
            errs = GR.script_errors(out, err)
            tr, req = None, {}
            for ln in out.splitlines():
                if ln.startswith("SFXTRACE "):
                    tr = json.loads(ln[9:])
                elif ln.startswith("SFXREQ "):
                    req = json.loads(ln[7:])
            n = len(glob.glob(os.path.join(fdir, "rec_*.png")))
            if errs or to or tr is None or n == 0:
                print(tag, "失败：", "超时" if to else ("；".join(errs[:3]) or "没有帧 / 没有 SFXTRACE"))
                return 1
            cues = [(round((e[0] - tr["frame0"]) / FPS, 2), e[1]) for e in tr["trace"] if e[1] in ("op_siege_s1", "op_siege_s1_soft", "op_texas_s2", "op_texas_s2_soft")]
            print("%-12s 冲锋号令发动音 %d 次：%s；请求 %s" % (tag, len(cues), " ".join("%.1fs:%s" % c for c in cues), {k: v[:2] for k, v in req.items() if "siege_s1" in k or "texas_s2" in k}), flush=True)
            R.label_frames(fdir, label + " · " + slabel)
            wav = os.path.join(fdir, "mix.wav")
            R.write_wav(wav, R.mix(tr["trace"], tr["frame0"], n))
            mp4 = os.path.join(a.out, "seg_%s.mp4" % tag)
            subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(fdir, "rec_%05d.png"), "-i", wav,
                            "-vf", "scale=1280:-2", "-c:v", "libx264", "-crf", "22", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-shortest", mp4], check=True)
            parts.append(mp4)
            shutil.rmtree(fdir, ignore_errors=True)
    lst = os.path.join(a.out, "list.txt")
    open(lst, "w", encoding="utf-8").write("".join("file '%s'\n" % p.replace("\\", "/") for p in parts))
    final = os.path.join(a.out, "冲锋号令音效对照.mp4")
    subprocess.run([ff, "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", final], check=True)
    os.remove(lst)
    print("视频", final, os.path.getsize(final))
    return 0


if __name__ == "__main__":
    sys.exit(main())
