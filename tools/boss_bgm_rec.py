# -*- coding: utf-8 -*-
"""结局二 / 三 / 四最终 Boss 配乐录像（10-28，docs/164 §7）：每只 Boss 30 秒原速（30 帧 / 秒）战斗，含一次 p1 → p2 切阶段，带声音。

画面：--autotest --bossacts=<Boss>（autotest._bossacts_step：Boss 在队长旁刷出、按自己的 AI 出招；骑士用 knight_boss2 直接二阶段形态，
一阶段半血卡点会入潮离场）。卡点间隔拉到 60 秒不触发，--actsp2=14 在登场 14 秒时把血放到 45%，music_director 在下一条小节线上叠入 p2，
录满 30 秒自动退出。--realtime 保证游戏钟与录像钟 1:1。
声音：测试局一律静音（Master 总线静音，不改），所以离线混音、不外放：
  - 配乐：--musiclog 打出切曲 / 切阶段的游戏时间（"MUSIC t=… final_knight p1 / p2"），按 sfx.gd 同一套规则混同一批 ogg
    （起播淡入 0.8 / 秒、p2 在请求后的下一条小节线前 BAR_AHEAD 秒以 STEM_IN 速度进、vol_target -4 dB）；
  - 音效：--sfxtrace 记下每次真正放出的音效（渲染帧号、名字、音量、音高），同 tools/exu_sync_rec.py。
用法：python tools/boss_bgm_rec.py [--out <目录>] [--only knight_boss2,ishar,izumik]
输出：主仓库 build/boss_bgm_1028/最终Boss配乐.mp4（三段拼接）。窗口经 godot_runner 放副屏 / 屏幕外，静音；ffmpeg 用 imageio_ffmpeg 自带的。
"""
import argparse, glob, json, os, re, shutil, subprocess, sys
import numpy as np
import soundfile as sf

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
import exu_sync_rec as EX

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MUS = os.path.join(ROOT, "game", "audio", "music")
SR, FPS = EX.SR, EX.FPS
REC_T0, SECS = 151.0, 30.0   # bossacts 第 20 帧把 g.t 设成 150，Boss 登场；从 151 秒录 30 秒
BAR_AHEAD, STEM_IN, VOL_DB, FADE_IN = 0.1, 10.0, -4.0, 0.8
BOSSES = [("knight_boss2", "结局二 · 最后的骑士《Último Caballo sumergido》"), ("ishar", "结局三 · 伊莎玛拉《The Swarm Theme》"),
          ("izumik", "结局四 · 伊祖米克《Tree of Evolution》")]


def music_mix(track, t_start, t_p2, n):
    """从游戏时间 REC_T0 起 n 个采样的配乐（立体声）：track 在 t_start 从头起播，p2 在 t_p2 请求（None = 不切）"""
    meta = json.load(open(os.path.join(MUS, "suno_layers.json"), encoding="utf-8"))[track]
    from scipy.signal import resample_poly
    lay = []
    for f in meta["files"]:
        x, sr = sf.read(os.path.join(MUS, f + ".ogg"), dtype="float32", always_2d=True)
        lay.append(resample_poly(x, 441, 320, axis=0) if sr == 32000 else x)
    t = REC_T0 + np.arange(n) / SR                 # 游戏时间
    pos = t - t_start                               # 曲内位置
    i = np.clip((pos * SR).astype(int), 0, None) % len(lay[0])
    g_trk = np.clip(pos * FADE_IN, 0.0, 1.0) * (pos >= 0)
    g2 = np.zeros(n)
    if t_p2 is not None:
        bar = 4 * 60.0 / meta["bpm"]
        # sfx._lay_tick：拍号按 (pos − 首拍偏移 + BAR_AHEAD) 算，越过下一条小节线时开层，之后以 STEM_IN 每秒爬到 1
        p_req = t_p2 - t_start
        on_at = np.ceil((p_req - meta["offset"] + BAR_AHEAD) / bar) * bar + meta["offset"] - BAR_AHEAD
        g2 = np.clip((pos - on_at) * STEM_IN, 0.0, 1.0)
    y = lay[0][i] * g_trk[:, None] + lay[1][i] * (g_trk * g2)[:, None]
    return y * 10 ** (VOL_DB / 20.0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(GR.common_root(), "build", "boss_bgm_1028"))
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    only = [k for k in a.only.split(",") if k]
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    os.makedirs(a.out, exist_ok=True)
    GR.ensure_imported(os.path.join(ROOT, "game"))
    parts = []
    for boss, label in BOSSES:
        if only and boss not in only:
            continue
        fdir = os.path.join(a.out, "frames_" + boss)
        shutil.rmtree(fdir, ignore_errors=True)
        os.makedirs(fdir)
        nf = int(SECS * FPS)
        args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", str(FPS), "--",
                "--autotest", "--seed=1", "--op=mizuki", "--bossacts=" + boss, "--realtime", "--bal=boss/acts_demo_len=60", "--actsp2=14",
                "--recframes=%g,%d" % (REC_T0, nf), "--shotdir=" + fdir.replace(os.sep, "/"), "--sfxtrace", "--musiclog"]
        out, err, to = GR.run_godot(args, 900)
        open(os.path.join(a.out, boss + ".log"), "w", encoding="utf-8").write(out + "\n----\n" + err)
        errs = GR.script_errors(out, err)
        tr, t_start, t_p2, track = None, None, None, ""
        for ln in out.splitlines():
            if ln.startswith("SFXTRACE "):
                tr = json.loads(ln[9:])
            m = re.match(r"MUSIC t=([\d.]+) (final\w*) (p[12])", ln)
            if m:
                track = m.group(2)
                if m.group(3) == "p1" and t_start is None:
                    t_start = float(m.group(1))
                if m.group(3) == "p2" and t_p2 is None:
                    t_p2 = float(m.group(1))
        n = len(glob.glob(os.path.join(fdir, "rec_*.png")))
        print("%s：%d 帧，配乐 %s 起 %.1f 秒、p2 %s；%s" % (boss, n, track, t_start or -1, "%.1f 秒" % t_p2 if t_p2 else "没切",
              "超时" if to else ("；".join(errs[:3]) or "无脚本错误")), flush=True)
        if to or tr is None or n < nf or t_start is None:
            print("  失败：没有完整帧 / SFXTRACE / 配乐日志")
            continue
        EX.label_frames(fdir, label + ("    %.0f 秒处切二阶段（p2 叠入）" % (t_p2 - REC_T0) if t_p2 else ""))
        ns = int(n / FPS * SR)
        y = music_mix(track, t_start, t_p2, ns)
        s = EX.mix(tr["trace"], tr["frame0"], n)[:ns]
        y[: len(s)] += s[:, None]
        pk = np.abs(y).max()
        if pk > 0.94:   # Master 硬限幅 -0.5 dB 的近似：整段等比例压
            y *= 0.94 / pk
        wav = os.path.join(fdir, "mix.wav")
        sf.write(wav, y.astype(np.float32), SR, subtype="PCM_16")
        mp4 = os.path.join(a.out, "seg_%s.mp4" % boss)
        subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(fdir, "rec_%05d.png"), "-i", wav,
                        "-vf", "scale=1280:-2", "-c:v", "libx264", "-crf", "28", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-shortest", mp4], check=True)
        parts.append(mp4)
        shutil.rmtree(fdir, ignore_errors=True)
    if parts:
        lst = os.path.join(a.out, "list.txt")
        open(lst, "w", encoding="utf-8").write("".join("file '%s'\n" % p.replace("\\", "/") for p in parts))
        final = os.path.join(a.out, "最终Boss配乐.mp4")
        subprocess.run([ff, "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", final], check=True)
        os.remove(lst)
        print("视频", final, "%.1f MB" % (os.path.getsize(final) / 1e6))
    return 0


if __name__ == "__main__":
    sys.exit(main())
