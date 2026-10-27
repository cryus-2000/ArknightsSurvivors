"""「冲锋号令·γ型」发动音换成一下很轻很短的随响（10-28，用户「冲锋号令的音效有点烦，可以取消或者换成一下很轻的随响」）：
推进之王 S1 与德克萨斯 S2 都叫「冲锋号令·γ型」。现状：推进之王 op_siege_s1 是 0.91 秒的铜管号角式发动音（每 4.5 秒最多一次），
德克萨斯 op_texas_s2 借推进之王 S2「跃空锤」风声 ×1.15（0.32 秒）。轻随响：约 0.1 秒的低通噪声「噗」+ 一下很低的体（无音高、无长尾），
有效响度比普攻低约 6 dB；sfx.gd 的 cmd_cue = "soft" 时两个技能改播它们，"mute" 不播，"old"（缺省）不变。
文件：audio/sfx/op_siege_s1_soft.wav、op_texas_s2_soft.wav（16 位单声道 44.1 kHz）。
用法：python game/tools/gen_sfx_cmd_cue_1028.py       写进 game/audio/sfx/
"""
import os
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
SFX = os.path.normpath(os.path.join(HERE, "..", "audio", "sfx"))
rng = np.random.default_rng(1028)


def env(n, a, dec):
    t = np.arange(n) / SR
    return np.minimum(t / a, 1.0) * np.exp(-t / dec)


def lp(x, fc):
    return sosfilt(butter(2, fc, fs=SR, output="sos"), x)


def cue(f0, f1, body, tail):
    n = int(tail * SR)
    air = lp(rng.standard_normal(n), f1) * env(n, 0.004, 0.025)
    air = sosfilt(butter(2, f0, "high", fs=SR, output="sos"), air)
    t = np.arange(n) / SR
    thump = np.sin(2 * np.pi * np.cumsum(body * (1 - 0.35 * t / t[-1])) / SR) * env(n, 0.003, 0.03)
    x = 0.7 * air / (np.abs(air).max() + 1e-9) + 0.5 * thump
    x[-int(0.02 * SR):] *= np.linspace(1, 0, int(0.02 * SR))
    return x


def rms100(x):
    w = int(0.1 * SR)
    e = np.convolve(x * x, np.ones(w) / w, "valid") if len(x) > w else np.array([np.mean(x * x)])
    return 10 * np.log10(e.max() + 1e-12)


def save(name, x, tgt):
    x = x * 10 ** ((tgt - rms100(x)) / 20)
    wavfile.write(os.path.join(SFX, name + ".wav"), SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))
    print(name, "%.2f s rms100 %.1f peak %.1f" % (len(x) / SR, rms100(x), 20 * np.log10(np.abs(x).max())))


save("op_siege_s1_soft", cue(300, 1800, 95, 0.11), -21.0)    # 推进之王：更沉
save("op_texas_s2_soft", cue(500, 2600, 130, 0.09), -21.0)   # 德克萨斯：更干更轻
