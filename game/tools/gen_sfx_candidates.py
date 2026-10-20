"""音效盘点（docs/110）的替换候选：枪击 / 锁链等先合成到 build/sfx_candidates/，用户试听选定后再改进 gen_sfx_ops.py 正式替换。
合成函数直接取 gen_sfx_ops.py 的工具段（同一套程序合成，不用任何外部音频），不会改动 audio/sfx/ 里的现有文件。

运行：python game/tools/gen_sfx_candidates.py      输出：<主仓库>/build/sfx_candidates/<名字>.wav + 现用文件的对照副本
"""
import os, shutil, subprocess
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, "gen_sfx_ops.py"), encoding="utf-8").read()
exec(src[:src.index("SAVED = []")])   # 只取工具函数（T / N / bp / lp / hp / env / tone / bell / metal / thud / verb / at / pad / sat …）
rng = np.random.default_rng(1021)

try:
    common = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=HERE, capture_output=True, text=True).stdout.strip()
    ROOT = os.path.dirname(os.path.abspath(os.path.join(HERE, common)))
except OSError:
    ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "build", "sfx_candidates")
os.makedirs(OUT, exist_ok=True)
SFX = os.path.join(HERE, "..", "audio", "sfx")


def out(name, x, gain=0.85):
    import wave
    x = hp(x, 35, 1)
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    nz = np.where(np.abs(x) > 0.004)[0]
    if len(nz):
        x = x[:min(len(x), nz[-1] + int(0.03 * SR))]
    fade = min(len(x), 600)
    x[-fade:] *= np.linspace(1, 0, fade)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    print(name, round(len(x) / SR, 3))


def keep(name):
    """现用文件复制一份到候选目录，名字加 _now，方便对照试听"""
    shutil.copy(os.path.join(SFX, name + ".wav"), os.path.join(OUT, name + "_now.wav"))


# ---------------------------------------------------------------- 能天使枪击（现用：维什戴尔炮声 ×1.9，低频「咚」没有枪口爆音）
# A 清脆：枪口爆裂（宽带噪声 4 ms 起落）+ 短促膛压（180→90 Hz 40 ms）+ 机件「咔」+ 极短尾音
keep("op_wisadel_atk")
crack = hp(N(0.03), 2500) * env(0.03, 0.0002, 160)
body = thud(0.07, 190, 90, 45)
click = metal(0.04, 3100, 70, bright=0.4) * 0.25
tail = lp(N(0.12), 2200) * env(0.12, 0.002, 30) * 0.3
out("exusiai_atk_A", pad(crack * 0.9, body * 0.7, at(click, 0.012), tail), 0.75)
# B 厚一点：多一层 1.2 kHz 的枪声主体，尾音长 40 ms（连发时更像冲锋枪）
mid = bp(N(0.06), 700, 1800) * env(0.06, 0.0005, 55)
out("exusiai_atk_B", pad(crack * 0.8, body * 0.8, mid * 0.6, at(click, 0.015), lp(N(0.16), 1800) * env(0.16, 0.002, 22) * 0.35), 0.78)
# 命中（现用：艾丽妮命中 ×1.3，每秒 6–11 次）：更短更轻的「噗」，高频少
keep("op_irene_hit")
out("exusiai_hit_A", pad(bp(N(0.04), 900, 3500) * env(0.04, 0.0005, 90) * 0.7, thud(0.05, 260, 140, 60) * 0.5), 0.5)

# ---------------------------------------------------------------- 乌尔比安锁链（现用：1.5–3.4 kHz 金属小撞击，最敏感的频段，刺耳）
# A 粗链：撞击降到 520–1300 Hz、泛音压暗、整体 3.2 kHz 低通，加链节拖地的低噪声
keep("op_ulpianus_s1")
keep("op_ulpianus_atk")


def heavy_chain(sec, n=10, f0=520, f1=1300, decay=26.0):
    x = np.zeros(int(sec * SR))
    for k in range(n):
        t0 = (k / n) * sec + rng.uniform(0, sec / n * 0.8)
        h = metal(0.12, rng.uniform(f0, f1), decay, bright=0.32) * rng.uniform(0.45, 1.0)
        st = int(min(t0, sec - 0.12) * SR)
        x[st:st + len(h)] += h[:len(x) - st]
    return lp(x, 3200)


s = pad(heavy_chain(0.55, 12) * 0.55, sweep_noise(0.5, 500, 1400, 0.5) * swell(0.5, 0.4) * 0.45,
        lp(N(0.55), 600) * swell(0.55, 0.5) * 0.25)
out("ulpianus_s1_A", verb(s, 0.35, 0.2), 0.75)
# B 更沉：撞击 380–900 Hz，少几节，铁链拉直时一声低「铮」
s = pad(heavy_chain(0.55, 8, 380, 900, 22) * 0.6, sweep_noise(0.5, 400, 1100, 0.5) * swell(0.5, 0.4) * 0.4,
        at(metal(0.4, 140, 6, bright=0.45) * 0.3, 0.38))
out("ulpianus_s1_B", verb(s, 0.35, 0.2), 0.75)
# 普攻里的链抖也换粗链（原 4 节 1.5–2.4 kHz）
s = pad(sweep_noise(0.3, 900, 200, 0.55) * env(0.3, 0.04, 8) * 0.8, heavy_chain(0.2, 4, 520, 1100) * 0.3,
        at(thud(0.22, 110, 40, 16) * 0.8, 0.14), at(lp(N(0.2), 1800) * env(0.2, 0.001, 18) * 0.35, 0.14))
out("ulpianus_atk_A", s, 0.7)
print("->", OUT)
