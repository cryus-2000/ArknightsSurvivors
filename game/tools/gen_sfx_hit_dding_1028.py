"""命中音去「叮」（10-28，用户定）：德克萨斯 / 流明 / 铃兰 / 艾丽妮的命中音里有单一音高的钟声 / 金属音层（bell / metal 约 1650–2600 Hz），
连打听成「叮叮叮」。每个保留各自质感，去掉纯音层，改成噪声 + 下滑短促体 + 少量带通，电平与原来相近或略低（最响 100 ms RMS −0.5 dB）。
  德克萨斯：刀刃「嗖 + 收势」——2–5 kHz 扫频噪声 + 短促下滑体（收势命中，非普通命中）
  流明：法术「噗 + 微光」——扫频噪声 + 细碎高频闪粒（噪声，无音高）+ 轻体
  铃兰：狐火「软爆 + 火苗」——带通噪声 + 噼啪 + 软体（去掉铃铛）
  艾丽妮：细剑「咔 + 闷」——高通短噪声 + 下滑体（去掉剑身金属音）
工具函数沿用 gen_sfx_ops.py（程序合成，numpy + scipy），16 位单声道 44.1 kHz。
用法：python game/tools/gen_sfx_hit_dding_1028.py             写对照 mp4 到 <主仓库>/build/hit_dding_1028/（不改游戏文件）
      python game/tools/gen_sfx_hit_dding_1028.py --apply     把 4 个新命中音写进 game/audio/sfx/（用户选定后再用）
"""
import os, sys, subprocess, wave
import numpy as np
from scipy.io import wavfile

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, "gen_sfx_ops.py"), encoding="utf-8").read()
exec(src[:src.index("SAVED = []")])    # SR、N、bp、lp、hp、env、tone、thud、sweep_noise、crackle、at、pad …
rng = np.random.default_rng(1028)
SFX = os.path.normpath(os.path.join(HERE, "..", "audio", "sfx"))
common = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=HERE, capture_output=True, text=True).stdout.strip()
ROOT = os.path.dirname(os.path.abspath(os.path.join(HERE, common)))
OUT = os.path.join(ROOT, "build", "hit_dding_1028")
FF = r"D:\Anaconda\Lib\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe"


def read(name):
    sr, x = wavfile.read(os.path.join(SFX, name + ".wav"))
    return x.astype(np.float64) / 32768.0


def rms100(x):
    w = max(1, int(SR * 0.1))
    e = np.convolve(x * x, np.ones(w) / w, mode="valid") if len(x) > w else np.array([np.mean(x * x)])
    return 10 * np.log10(max(1e-12, e.max()))


def peaky(x):
    """音高感：平滑频谱里最高峰比 ±1 个八度内中位数高多少 dB（纯音 > 20，噪声 < 12）"""
    n = max(len(x), 4096)
    X = np.abs(np.fft.rfft(np.pad(x, (0, n - len(x))) * np.hanning(n))) + 1e-9
    f = np.fft.rfftfreq(n, 1 / SR)
    k = 7
    S = np.convolve(X, np.ones(k) / k, "same")
    m = (f > 400) & (f < 8000)
    i = np.argmax(np.where(m, S, 0))
    near = (f > f[i] / 2) & (f < f[i] * 2)
    return float(f[i]), 20 * np.log10(S[i] / np.median(S[near]))


def fit(x, old, db=-0.5):
    """响度对齐到原文件最响 100 ms RMS + db，峰值不超过原峰值"""
    x = x * 10 ** ((rms100(old) + db - rms100(x)) / 20)
    cap = np.abs(old).max()
    if np.abs(x).max() > cap:
        x = np.tanh(x / cap) * cap
    return x.astype(np.float32)


def new_texas():
    n = 0.16
    air = sweep_noise(n, 1800, 5000, 0.55) * env(n, 0.002, 26)
    body = thud(0.1, 300, 110, 34)
    tick = hp(N(0.02), 3000) * env(0.02, 0.0004, 120)
    return pad(air * 0.8, body * 0.55, tick * 0.35)


def new_lumen():
    n = 0.22
    puff = sweep_noise(n, 900, 4200, 0.6) * env(n, 0.003, 20) * 0.6
    glint = hp(N(n), 4500) * env(n, 0.001, 38) * 0.22    # 细碎闪粒：噪声，没有音高
    body = thud(0.09, 240, 140, 40) * 0.4
    return pad(puff, glint, body)


def new_suzuran():
    n = 0.18
    soft = bp(N(n), 500, 2300) * env(n, 0.002, 24) * 0.6
    fire = crackle(n, 150, 2500, 7000, 20) * 0.3
    body = thud(0.1, 210, 110, 32) * 0.45
    return pad(soft, fire, body)


def new_irene():
    n = 0.12
    click = hp(N(0.03), 2500) * env(0.03, 0.0003, 110) * 0.8
    body = thud(0.09, 320, 120, 38) * 0.6
    stab = bp(N(n), 900, 3200) * env(n, 0.001, 45) * 0.35    # 刺入的短促噪声，代替原来的剑身金属音
    return pad(click, body, stab)


OPS = {   # 名字 → (新合成, 原文件, 攻击间隔 s, 命中比攻击晚 s, 普攻文件)
    "texas": (new_texas, "op_texas_hit", 1.05, 0.12, "op_texas_atk"),
    "lumen": (new_lumen, "op_lumen_hit", 0.5, 0.10, "op_lumen_atk"),
    "suzuran": (new_suzuran, "op_suzuran_hit", 1.0, 0.12, "op_suzuran_atk"),
    "irene": (new_irene, "op_irene_hit", 0.8, 0.04, "op_irene_atk"),
}
CN = {"texas": "德克萨斯", "lumen": "流明", "suzuran": "铃兰", "irene": "艾丽妮"}
VOL = {"atk": -11.0, "hit": -10.0}      # sfx.gd OP_VOL；德克萨斯命中另有 OP_DB −3，流明普攻 / 命中调用处有微调，这里取缺省
OP_DB = {"texas": -3.0}


def put(buf, clip, t, db):
    i = int(t * SR)
    x = clip * 10 ** (db / 20)
    if i + len(x) > len(buf):
        buf = np.pad(buf, (0, i + len(x) - len(buf)))
    buf[i:i + len(x)] += x
    return buf


def seq(atk, hit, cd, delay, db_hit):
    buf = np.zeros(int(SR * (0.3 + 8 * cd + 0.5)), np.float32)
    t = 0.3
    for k in range(8):
        buf = put(buf, atk, t, VOL["atk"])
        buf = put(buf, hit, t + delay, db_hit)
        t += cd
    pk = np.abs(buf).max()
    return buf / pk * 0.89 if pk > 0.89 else buf


def clip_wav(path, x):
    wavfile.write(path, SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))


def main():
    os.makedirs(OUT, exist_ok=True)
    news = {}
    print("%-8s %-22s %-22s %s" % ("干员", "原：峰值频率 / 音高感 dB", "新：峰值频率 / 音高感 dB", "原 → 新 RMS100 / 峰值 dBFS"))
    for k, (fn, oldname, cd, delay, atkname) in OPS.items():
        old = read(oldname)
        new = fit(fn(), old)
        news[k] = new
        fo, po = peaky(old); fn_, pn = peaky(new)
        print("%-8s %6.0f Hz / %5.1f dB     %6.0f Hz / %5.1f dB     %.1f → %.1f / %.1f → %.1f" % (
            CN[k], fo, po, fn_, pn, rms100(old), rms100(new), 20 * np.log10(np.abs(old).max()), 20 * np.log10(np.abs(new).max())))
    if "--apply" in sys.argv:
        for k, x in news.items():
            with wave.open(os.path.join(SFX, OPS[k][1] + ".wav"), "wb") as w:
                w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
                w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
            print("写入", OPS[k][1])
        return
    from PIL import Image, ImageDraw, ImageFont
    font = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 44)
    small = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 28)
    parts = []
    i = 0
    for k, (fn, oldname, cd, delay, atkname) in OPS.items():
        atk = read(atkname)
        old = read(oldname)
        for tag, hit in (("旧命中音（叮）", old), ("新命中音（去音高）", news[k])):
            db = VOL["hit"] + OP_DB.get(k, 0.0)
            audio = seq(atk, hit, cd, delay, db)
            img = Image.new("RGB", (960, 540), (14, 22, 32))
            d = ImageDraw.Draw(img)
            d.text((50, 190), "%s · %s" % (CN[k], tag), font=font, fill=(235, 240, 245))
            d.text((50, 280), "本人普攻节奏连打 8 下（攻击间隔 %.2f 秒）" % cd, font=small, fill=(160, 180, 200))
            png, wav, mp4 = (os.path.join(OUT, "seg%d.%s" % (i, e)) for e in ("png", "wav", "mp4"))
            img.save(png); clip_wav(wav, audio)
            subprocess.run([FF, "-loglevel", "error", "-y", "-loop", "1", "-i", png, "-i", wav, "-shortest", "-c:v", "libx264", "-tune", "stillimage",
                            "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", mp4], check=True)
            parts.append(mp4)
            i += 1
    lst = os.path.join(OUT, "list.txt")
    open(lst, "w", encoding="utf-8").write("".join("file '%s'\n" % p.replace("\\", "/") for p in parts))
    final = os.path.join(OUT, "命中音去叮_对照.mp4")
    subprocess.run([FF, "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", final], check=True)
    for f in os.listdir(OUT):
        if f.startswith("seg") or f == "list.txt":
            os.remove(os.path.join(OUT, f))
    print(final, os.path.getsize(final))


main()
