"""网上 CC0 音效接入（docs/113 §7–§8）：从 <主仓库>/build/sfx_src/ 的原始下载截取片段，处理后写进 game/audio/sfx/。
原始文件不进 git；本脚本把「哪个文件、从第几秒截多长、怎么处理、响度对齐到多少」全写死，重跑结果一样。

来源（全部 CC0 1.0，可商用、不必署名；来源仍写进 docs/113 与 data/credits.json）：
  Freesound 645317 DarkShroom「M9_noisegate」、558210 insaind「gun I: SMG 1」、517058 Invisible_inks「scifi_sniper_rifle」、
  330293 humanoide9000「Sci-fi gun shot x6」、387240 nettimato「chain」、108265 klakmart「ChainsRattling」、
  448917 Kp69606「Chain Rattling」（Freesound 原文件要登录，下载的是公开的 HQ 试听 mp3，许可相同）
  Kenney「Impact Sounds」「RPG Sounds」（kenney.nl / opengameart.org）
需要 numpy + scipy + soundfile。运行：python game/tools/import_sfx_cc0.py（先写 build/sfx_stage/ 核对）→ 加 --apply 写进 game/audio/sfx/
"""
import os, subprocess, wave
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly, butter, sosfilt

HERE = os.path.dirname(os.path.abspath(__file__))
SFX = os.path.normpath(os.path.join(HERE, "..", "audio", "sfx"))
common = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=HERE, capture_output=True, text=True).stdout.strip()
ROOT = os.path.dirname(os.path.abspath(os.path.join(HERE, common)))
SRC = os.path.join(ROOT, "build", "sfx_src")
ALT_OUT = os.path.join(ROOT, "build", "sfx_candidates")   # 没接进游戏的备选，供试听
import sys
if "--apply" not in sys.argv:
    SFX = os.path.join(ROOT, "build", "sfx_stage")   # 缺省先写到暂存目录核对；加 --apply 才写进 game/audio/sfx（覆盖的都是 git 跟踪文件）
    os.makedirs(SFX, exist_ok=True)
SR = 44100

src = open(os.path.join(HERE, "gen_sfx_ops.py"), encoding="utf-8").read()
exec(src[:src.index("SAVED = []")])   # 合成工具函数（乌尔比安普攻的风声与砸地层沿用原合成）
rng = np.random.default_rng(1021)


def load(rel):
    x, sr = sf.read(os.path.join(SRC, rel))
    if x.ndim > 1:
        x = x.mean(axis=1)
    if sr != SR:
        x = resample_poly(x, SR, sr)
    return x


def cut(x, t0, dur, fade_in=0.002, fade_out=0.03):
    y = x[int(t0 * SR): int((t0 + dur) * SR)].copy()
    a, b = max(1, int(fade_in * SR)), max(1, int(fade_out * SR))
    y[:a] *= np.linspace(0, 1, a)
    y[-b:] *= np.linspace(1, 0, b)
    return y


def lowpass(x, fc, order=4):
    return sosfilt(butter(order, fc, fs=SR, output="sos"), x)


def repitch(x, ratio):
    """ratio < 1 降调（变长）：按整数比重采样"""
    up, down = int(round(1000 / ratio)), 1000
    return resample_poly(x, up, down)


def chain_tone(x, ratio=0.7, fc=2800):
    """锁链录音很亮（重心约 10 kHz）：降调 + 8 阶低通 + 补 800 Hz 以下的链身，撞击留在 1–3 kHz，不扎耳朵"""
    y = lowpass(repitch(x, ratio), fc, 8)
    return y + lowpass(y, 800, 4) * 1.5


def rms100(x):
    w = max(1, int(SR * 0.1))
    e = np.convolve(x * x, np.ones(w) / w, mode="valid") if len(x) > w else np.array([np.mean(x * x)])
    return 10 * np.log10(max(1e-12, e.max()))


def level(x, target_rms, peak_cap=-1.0):
    """响度对齐：最响 100 ms 的 RMS 拉到 target_rms（dBFS），峰值超过 peak_cap 时软限幅"""
    x = x * 10 ** ((target_rms - rms100(x)) / 20)
    cap = 10 ** (peak_cap / 20)
    if np.abs(x).max() > cap:
        x = np.tanh(x / cap) * cap
    return x


def write(path, x):
    x = np.clip(x, -1, 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    print("%-34s %.3f s  rms100 %.1f  peak %.1f" % (os.path.basename(path), len(x) / SR, rms100(x), 20 * np.log10(np.abs(x).max() + 1e-9)))


def game(name, x):
    write(os.path.join(SFX, name + ".wav"), x)


def alt(name, x):
    os.makedirs(ALT_OUT, exist_ok=True)
    write(os.path.join(ALT_OUT, name + ".wav"), x)


K_IMP = "kenney_impact/x/Audio/"
K_RPG = "kenney_rpg/x/OGG/"

# ---------------------------------------------------------------- 能天使（拉特兰制式枪）
# 普攻：M9 实录单发（已降噪的干声），去掉 120 Hz 以下的轰，响度按普攻口径（播放 -11 dB → 有效约 -26）
m9 = load("fs645317_darkshroom_m9/645317-hq.mp3")
m9 = hp(m9, 120, 2)
game("op_exusiai_atk", level(cut(m9, 0.0, 0.26, 0.0005, 0.04), -15.0))
# 命中：Kenney 轻金属撞击，短小，按每秒多次的命中口径压低
hit = load(K_IMP + "impactMetal_light_002.ogg")
game("op_exusiai_hit", level(cut(lowpass(hit, 4000, 6), 0.0, 0.12, 0.0005, 0.04), -21.0))
# 弹匣倾泻（big）：科幻狙击单发，冷的电子尾
sn = load("fs517058_invisibleinks_scifi_sniper/517058-hq.mp3")
game("op_exusiai_big", level(cut(sn, 0.50, 0.62, 0.001, 0.15), -14.0))
# 备选：冲锋枪单发 / 科幻枪声
smg = load("fs558210_insaind_smg/558210-hq.mp3")
alt("exusiai_atk_smg", level(cut(smg, 0.215, 0.13, 0.0005, 0.04), -15.0))
sg = load("fs330293_humanoide9000_scifi_gun/330293-hq.mp3")
alt("exusiai_atk_scifi", level(cut(sg, 1.965, 0.40, 0.001, 0.12), -15.0))

# ---------------------------------------------------------------- 乌尔比安（锚链）
# 录音频谱重心约 10 kHz：一律走 chain_tone（降调 + 陡低通 + 补链身），压掉刺耳的高频，留下粗链的重量
# 一技能（掷锚，锁链长长哗啦）：klakmart 两链互碰的一段连续哗啦
kl = load("fs108265_klakmart_chains/108265-hq.mp3")
s1 = chain_tone(cut(kl, 18.00, 0.55, 0.004, 0.12))
game("op_ulpianus_s1", level(s1, -15.0))
# 三技能（锚链急速收紧）：nettimato 链钩录音里连着的两下抽紧
nt = load("fs387240_nettimato_chain/387240-hq.mp3")
s3 = chain_tone(cut(nt, 8.76, 0.50, 0.002, 0.12), 0.75, 3200)
game("op_ulpianus_s3", level(s3, -16.0))
# 普攻（抡锚）：原合成的风声 + 砸地，锚链一抖换成 Kp69606 拖链录音
kp = load("fs448917_kp69606_chain_drag/448917-hq.mp3")
ch = chain_tone(cut(kp, 7.90, 0.20, 0.002, 0.06), 0.7, 2400)
atk = pad(sweep_noise(0.3, 900, 200, 0.55) * env(0.3, 0.04, 8) * 0.8, ch / (np.abs(ch).max() + 1e-9) * 0.35,
          at(thud(0.22, 110, 40, 16) * 0.8, 0.14), at(lp(N(0.2), 1800) * env(0.2, 0.001, 18) * 0.35, 0.14))
game("op_ulpianus_atk", level(hp(atk, 35, 1), -13.0))
# 备选：nettimato 单独一下重链（可替换锚落地前的链响）
alt("ulpianus_chain_hit", level(chain_tone(cut(nt, 3.64, 0.35, 0.002, 0.1)), -15.0))

# ---------------------------------------------------------------- 冷兵器
# 德克萨斯普攻（拔剑斩）：Kenney 刀划，短而干
kn = load(K_RPG + "knifeSlice.ogg")
game("op_texas_atk", level(cut(kn, 0.0, min(0.22, len(kn) / SR), 0.0005, 0.05), -17.0))
# 星熊命中（盾格挡「铛」）：Kenney 重金属撞击
mh = load(K_IMP + "impactMetal_heavy_001.ogg")
game("op_hoshiguma_hit", level(cut(lowpass(mh, 7000), 0.0, min(0.35, len(mh) / SR), 0.0005, 0.08), -16.0))
print("->", SFX)
