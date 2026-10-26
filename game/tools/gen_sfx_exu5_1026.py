"""能天使音效第五轮：原作枪械音效候选的试听包（docs/113 §19，10-26 用户：「用原作游戏里能天使本来的射击音效」）。

素材：明日方舟 CN 客户端 2.7.81（热更新 26-10-22-14-02-11-51447808）audio/sound_beta_2/player/p_atk_*.ab 的 AudioClip，
用 ArknightsStudioCLI 导出成 wav，放在主仓库 build/ak_src/out_atk/（内部参照，不进 git、不进包，用户 10-15 已确认公司授权下载作参照）。
映射（哪条是能天使）：热更新里没有干员战斗预制体，骨骼文件只有 OnAttack / OnStart 事件、没有音效名，所以**还没确认**；这里按「武器类型」给三套候选：
  P = pistolup_n / pistolup_d / pistol_n（带装填音变体 pistolup_sreload / dreload，对得上她技能的装填 / 连射）
  Q = handgun_n / handgun_s / handgun_h
  R = silncrgun_n / silncrgun_d / silncrgun_h（短促的科幻消音枪，各 0.2 s）
处理：取第一声枪响（起音前 3 ms 起、0.30 s，尾部 60 ms 淡出，保留自然尾音），80 Hz 高通，rms100 对齐 -9.5 dBFS（同 §18 的响度）；
技能 / 弹匣倾泻用同一套样本按 §17 的办法重拼（s1 = 装填 + 3 连点射），命中沿用 §18 的金属叮。不做任何合成。
运行：python game/tools/gen_sfx_exu5_1026.py            写试听包 build/exu_orig_review/（before = 现用版；P / Q / R；每套 combat 6 秒实战混音 + 技能 + 单发）
      python game/tools/gen_sfx_exu5_1026.py --apply P   写进 game/audio/sfx/（只在用户选定后用；切片来自官方资源，是否提交进 git 要用户先定）
"""
import glob, importlib.util, os, subprocess, sys
import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt, resample_poly

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("exu4", os.path.join(HERE, "gen_sfx_exu4_1026.py"))
E4 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(E4)
SR = E4.SR
common = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=HERE, capture_output=True, text=True).stdout.strip()
ROOT = os.path.dirname(os.path.abspath(os.path.join(HERE, common)))
SRC = os.path.join(ROOT, "build", "ak_src", "out_atk")
OUT = os.path.join(ROOT, "build", "exu_orig_review")
SETS = {"P": ["pistolup_n", "pistolup_d", "pistol_n"], "Q": ["handgun_n", "handgun_s", "handgun_h"], "R": ["silncrgun_n", "silncrgun_d", "silncrgun_h"]}
RELOAD = {"P": "pistolup_sreload"}


def load(name):
    fs = glob.glob(os.path.join(SRC, "**", "p_atk_%s.wav" % name), recursive=True)
    if not fs:
        raise SystemExit("缺 %s（先导出 build/ak_src/out_atk）" % name)
    x, sr = sf.read(fs[0], dtype="float64")
    if x.ndim > 1:
        x = x.mean(1)
    if sr != SR:
        from math import gcd
        g = gcd(SR, sr)
        x = resample_poly(x, SR // g, sr // g)
    return x


def shot(name, length=0.30):
    x = load(name)
    x = sosfilt(butter(2, 80, btype="high", fs=SR, output="sos"), x)
    fr = int(0.002 * SR)
    n = len(x) // fr
    e = np.sqrt((x[:n * fr].reshape(n, fr) ** 2).mean(1))
    i = int(np.argmax(e > e.max() * 0.3))
    a = max(0, i * fr - int(0.003 * SR))
    y = x[a:a + int(length * SR)].copy()
    fo = int(0.06 * SR)
    y[-fo:] *= np.linspace(1, 0, fo)
    return y


def build(key):
    names = SETS[key]
    atk = [E4.to_rms(shot(n), -9.5) for n in names]
    main = shot(names[1])
    hit = E4.build("after")["hit"]
    ck = E4.click()
    if key in RELOAD:
        rl = load(RELOAD[key])[:int(0.5 * SR)]
        ck = E4.to_rms(rl, -14.0)
    s1 = np.concatenate([ck, np.zeros(int(0.06 * SR)), E4.burst(main, 3, 0.85, 0.85, 0.075, 0.075)])
    s2 = E4.burst(main, 6, 0.7, 1.0, 0.1, 0.055)
    s3 = E4.burst(main, 18, 0.75, 1.0, 0.065, 0.038, last=3.0)
    big = np.concatenate([E4.burst(main, 9, 0.75, 0.95, 0.055, 0.042), np.zeros(int(0.12 * SR)), E4.shift(main, 0.78) * 1.4])
    return {"atk": atk[0], "atk_b": atk[1], "atk_c": atk[2], "hit": hit,
            "s1": E4.to_rms(s1, -10.0), "s2": E4.to_rms(s2, -9.0), "s3": E4.to_rms(s3, -8.0), "big": E4.to_rms(big, -9.5)}


def main():
    if "--apply" in sys.argv:
        key = sys.argv[sys.argv.index("--apply") + 1]
        S = build(key)
        for k, v in S.items():
            sf.write(os.path.join(E4.SFX, "op_exusiai_%s.wav" % k), v.astype(np.float32), SR, subtype="PCM_16")
        print("已写入", key)
        return
    os.makedirs(OUT, exist_ok=True)
    sets = {"before": {k: E4.rd_wav("op_exusiai_" + k) for k in ("atk", "atk_b", "atk_c", "hit", "s1", "s2", "s3", "big")}}   # before = 工作区现用文件（§18）
    for k in SETS:
        sets[k] = build(k)
    for tag, S in sets.items():
        E4.wr(os.path.join(OUT, tag + "_combat.ogg"), E4.demo(S, tag))
        E4.wr(os.path.join(OUT, tag + "_skills.ogg"), E4.skills_demo(S))
        for k in ("atk", "atk_b", "atk_c", "hit"):
            E4.wr(os.path.join(OUT, "%s_%s.ogg" % (tag, k)), S[k])
        print(tag, {k: round(E4.rms100(v), 1) for k, v in S.items()})


if __name__ == "__main__":
    main()
