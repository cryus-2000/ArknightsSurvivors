"""能天使音效对拍（10-28，用户「攻击和音效有点对不上」）：枪声改成出弹那一帧每一轮射击一声（seg_exusiai._exu_volley），
所以技能发动时那段「预混好的连射录音」不能再响——s1 / s2 / s3 原来是 3 / 6 / 18 连射的拼接音，一播就是 0.8–1.4 秒，而实际射击持续 6 发 / 8 秒 / 10 秒，
间隔（0.35 / 0.2 / 4 连 × 0.06）和录音里写死的间隔（0.055–0.1 秒）对不上；弹匣倾泻（big）是 9 连 + 一声重的，实际是一轮 8 发扇形同时出膛。
改成：
  s1 / s2 / s3：短促的机械「咔」发动提示（0.2–0.3 秒，噪声 + 低频体，无枪声无音高），s1 装填两下、s2 拉栓一下带低体、s3 三下渐升 + 低频涌起（过热）
  big：只留原来最后那一声重击 + 两声错开 12 / 25 ms 的轻弹（扇形同时出膛）
枪声 atk / atk_b / atk_c 与命中 hit 不动。16 位单声道 44.1 kHz；「改前」固定读 1b64c476f 里的文件，重跑不受已写入文件影响。
用法：python game/tools/gen_sfx_exu_sync_1028.py            写到 <主仓库>/build/exu_sync_1028/（不改游戏文件）
      python game/tools/gen_sfx_exu_sync_1028.py --apply    写进 game/audio/sfx/（op_exusiai_s1 / s2 / s3 / big）
"""
import importlib.util, os, sys, subprocess
import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("exu4", os.path.join(HERE, "gen_sfx_exu4_1026.py"))
E4 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(E4)
SR = E4.SR
BASE = "1b64c476f"
rng = np.random.default_rng(1028)
common = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=HERE, capture_output=True, text=True).stdout.strip()
ROOT = os.path.dirname(os.path.abspath(os.path.join(HERE, common)))
OUT = os.path.join(ROOT, "build", "exu_sync_1028")


def bp(x, lo, hi):
    return sosfilt(butter(2, [lo, hi], "bandpass", fs=SR, output="sos"), x)


def env(n, atk, dec):
    t = np.arange(n) / SR
    return np.minimum(t / atk, 1.0) * np.exp(-t / dec)


def chk(f_lo=1200, f_hi=4200, body=170, g=1.0):
    """机械「咔」：1–4 kHz 带通噪声 12 ms + 短促低频体（无音高感）"""
    n = int(0.05 * SR)
    t = np.arange(n) / SR
    click = bp(rng.standard_normal(n), f_lo, f_hi) * env(n, 0.0008, 0.011)
    thump = np.sin(2 * np.pi * np.cumsum(body * (1 - 0.4 * t / t[-1])) / SR) * env(n, 0.001, 0.02)
    return g * (0.8 * click / (np.abs(click).max() + 1e-9) + 0.5 * thump)


def at(buf, clip, t):
    i = int(t * SR)
    if i + len(clip) > len(buf):
        buf = np.pad(buf, (0, i + len(clip) - len(buf)))
    buf[i:i + len(clip)] += clip
    return buf


def cue_s1():     # 装填：咔—咔
    b = np.zeros(int(0.24 * SR))
    b = at(b, chk(1500, 4200, 190, 0.9), 0.0)
    b = at(b, chk(1100, 3600, 150, 1.0), 0.085)
    return b


def cue_s2():     # 拉栓：一声带低体的「咔」+ 余下一点滑动的沙声
    b = np.zeros(int(0.30 * SR))
    b = at(b, chk(1000, 3800, 130, 1.1), 0.0)
    n = int(0.14 * SR)
    slide = bp(rng.standard_normal(n), 900, 2600) * env(n, 0.02, 0.05) * 0.25
    return at(b, slide, 0.05)


def cue_s3():     # 过载：三下渐升的「咔」+ 低频涌起
    b = np.zeros(int(0.34 * SR))
    for k, (t, lo, hi) in enumerate(((0.0, 1100, 3500), (0.07, 1400, 4000), (0.14, 1800, 4800))):
        b = at(b, chk(lo, hi, 140 + 25 * k, 0.85 + 0.12 * k), t)
    n = int(0.26 * SR)
    tt = np.arange(n) / SR
    sub = np.sin(2 * np.pi * np.cumsum(70 + 90 * tt / tt[-1]) / SR) * np.sin(np.pi * tt / tt[-1]) ** 2 * 0.45
    return at(b, sub, 0.06)


def new_big():
    old = E4.rd_wav("op_exusiai_big", BASE)
    heavy = old[int(1.04 * SR):].copy()          # 原来最后那一声重击
    heavy[-int(0.03 * SR):] *= np.linspace(1, 0, int(0.03 * SR))
    light = E4.rd_wav("op_exusiai_atk_b", BASE)
    b = np.zeros(len(heavy) + int(0.04 * SR))
    b = at(b, E4.shift(light, 0.92)[:int(0.2 * SR)] * 0.55, 0.0)
    b = at(b, E4.shift(light, 1.04)[:int(0.2 * SR)] * 0.45, 0.012)
    b = at(b, E4.shift(light, 0.97)[:int(0.2 * SR)] * 0.5, 0.025)
    b = at(b, heavy, 0.03)
    return b


def main():
    S = {"s1": E4.to_rms(cue_s1(), -12.0), "s2": E4.to_rms(cue_s2(), -12.0), "s3": E4.to_rms(cue_s3(), -11.0)}
    S["big"] = E4.to_rms(new_big(), -9.5)
    dest = os.path.normpath(os.path.join(HERE, "..", "audio", "sfx")) if "--apply" in sys.argv else OUT
    os.makedirs(dest, exist_ok=True)
    for k, v in S.items():
        name = ("op_exusiai_%s.wav" % k) if "--apply" in sys.argv else ("%s_new.wav" % k)
        sf.write(os.path.join(dest, name), v.astype(np.float32), SR, subtype="PCM_16")
        old = E4.rd_wav("op_exusiai_" + k, BASE)
        print("%-4s 改前 %.2f s rms100 %.1f → 新 %.2f s rms100 %.1f" % (k, len(old) / SR, E4.rms100(old), len(v) / SR, E4.rms100(v)))
    print("->", dest)


main()
