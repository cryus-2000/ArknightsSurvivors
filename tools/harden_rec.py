# -*- coding: utf-8 -*-
"""最后一幕硬化对照录像（11-16，B站玩家「高伤害秒了偏执泡影还得硬扛一段出招」）：--autotest --hardendemo=<Boss>，
Boss 直接摆到最后一幕开头，登场 3 秒一发打到剩 3%，录到倒下后 4 秒。原速 30 帧（--realtime），音效按 --sfxtrace 离线混音（同 exu_sync_rec），
测试局照样静音。改前 = 同一份代码 --bal=boss/last_hold_max=0 --bal=boss/last_auto_kill=0（旧行为：护盾撑满这一幕最短时长、剩 3% 要补刀）
+ 旧血量倍率；普通 = 不打那一发，队长照常打。

用法：python tools/harden_rec.py [--boss paranoia] [--only burst_old,burst_new,normal_old,normal_new] [--oldhp 1.45] [--out <目录>]
输出：主仓库 build/harden_1116/<Boss>_<场景>.mp4
"""
import argparse, glob, json, os, shutil, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
import exu_sync_rec as EX

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FPS = EX.FPS


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(GR.common_root(), "build", "harden_1116"))
    ap.add_argument("--boss", default="paranoia")
    ap.add_argument("--only", default="burst_old,burst_new,normal_old,normal_new")
    ap.add_argument("--oldhp", default="1.45")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--op", default="mizuki")
    a = ap.parse_args()
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    os.makedirs(a.out, exist_ok=True)
    GR.ensure_imported(os.path.join(ROOT, "game"))
    for key in a.only.split(","):
        label = {"burst_old": "高伤害秒杀 · 改前：硬化撑满 25 秒、还要补刀", "burst_new": "高伤害秒杀 · 改后：护盾 3 秒后直接击破",
                 "normal_old": "普通构筑 · 改前", "normal_new": "普通构筑 · 改后（偏执泡影生命上调）"}[key]
        fdir = os.path.join(a.out, "frames_%s_%s" % (a.boss, key))
        shutil.rmtree(fdir, ignore_errors=True)
        os.makedirs(fdir, exist_ok=True)
        args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", str(FPS), "--",
                "--autotest", "--seed=%d" % a.seed, "--op=" + a.op, "--hardendemo=" + a.boss + ("" if key.startswith("burst") else ",-1"), "--realtime", "--nobossintro",
                "--recframes=150,%d" % (80 * FPS), "--shotdir=" + fdir, "--sfxtrace"]
        if key.endswith("old"):
            args += ["--bal=boss/last_hold_max=0", "--bal=boss/last_auto_kill=0", "--bal=boss/hp_x_paranoia=" + a.oldhp]
        out, err, to = GR.run_godot(args, 1800)
        errs = GR.script_errors(out, err)
        tr = None
        for ln in out.splitlines():
            if ln.startswith("SFXTRACE "):
                tr = json.loads(ln[9:])
            elif ln.startswith("HARDENDEMO"):
                print(key, ln, flush=True)
        n = len(glob.glob(os.path.join(fdir, "rec_*.png")))
        if errs or to or n == 0:
            print(key, "失败：", "超时" if to else ("；".join(errs[:3]) or "没有帧"))
            continue
        EX.label_frames(fdir, label)
        wav = os.path.join(fdir, "mix.wav")
        EX.write_wav(wav, EX.mix(tr["trace"], tr["frame0"], n) if tr else EX.np.zeros(int(n / FPS * EX.SR)))
        mp4 = os.path.join(a.out, "%s_%s.mp4" % (a.boss, key))
        subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(fdir, "rec_%05d.png"), "-i", wav,
                        "-vf", "scale=1280:-2", "-c:v", "libx264", "-crf", "21", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-shortest", mp4], check=True)
        print(key, "帧", n, "秒", round(n / FPS, 1), "视频", mp4, os.path.getsize(mp4), flush=True)
        shutil.rmtree(fdir, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
