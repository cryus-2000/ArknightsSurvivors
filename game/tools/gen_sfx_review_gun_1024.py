"""能天使枪声第二轮候选（docs/113 §16，10-24 用户：「枪声再找找」）：Freesound CC0 单发枪声录音。
每条自动找第一声枪响（起音前 3 ms 起、取 0.14 s，尾部 40 ms 淡出，枪声要短、连发不糊），100 Hz 高通 + 7 kHz 低通，
100 ms RMS 对齐现用 op_exusiai_atk；每条另做「8 连发」试听（间隔 0.11 s，音高 ±9% 随机，约等于过载连射 9 次 / 秒），测听着累不累。

先运行 gen_sfx_review_1024.py、gen_sfx_review_cc0_1024.py，再运行本脚本；结果追加到试听页第六节。
"""
import os, re, sys, html
import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_sfx_review_cc0_1024 as cc

SR = cc.SR
OUT = os.path.join(cc.REV, "gun")
os.makedirs(OUT, exist_ok=True)
LEN = 0.14
# (名字, Freesound id, 起点提示 s（找枪响的起始搜索位置）, 说明)
GUNS = [
    ("g1", 865993, 0.0, "mp5_fire：MP5 冲锋枪单发，利落"),
    ("g2", 819269, 0.0, "Gunshot with silencer：消音枪，闷而短"),
    ("g3", 701224, 0.0, "Welrod suppressed pistol：威尔罗德消音手枪，几乎只有机括声"),
    ("g4", 827945, 0.0, "Springfield 1911 (Suppressed)：消音 1911"),
    ("g5", 381569, 0.0, "Silenced Gunshot 3：消音枪声"),
    ("g6", 380185, 0.0, "Silenced Gunshot 2：消音枪声，更短"),
    ("g7", 855654, 0.0, "自动步枪单发，「punchy」，偏冲"),
    ("g8", 855656, 0.0, "消音手枪 + 类似相位器的金属尾音（偏科幻），取 0.2 s"),
    ("g9", 160590, 0.0, "Assault Rifle (Single Burst)：步枪单点射"),
    ("g10", 720118, 0.0, "Player_Shoot1：游戏用射击音效"),
    ("g11", 445347, 0.0, "FX - SHOT - Experimental gun 01：实验性科幻枪"),
    ("g12", 257364, 0.0, "Silenced Submachine gun：消音冲锋枪，取第一发"),
    ("g13", 100465, 0.0, "Silenced shot：消音枪单发"),
    ("g14", 645316, 0.0, "snub nose .357（DarkShroom，和现用同作者）：左轮，偏重"),
]


def find_onset(x):
    fr = int(0.002 * SR)
    n = len(x) // fr
    e = np.sqrt((x[:n * fr].reshape(n, fr) ** 2).mean(1))
    i = int(np.argmax(e > e.max() * 0.35))
    return max(0, i * fr - int(0.003 * SR))


def proc(x, tgt, length):
    x = sosfilt(butter(2, 100, btype="high", fs=SR, output="sos"), x)
    x = sosfilt(butter(4, 7000, fs=SR, output="sos"), x)
    fi, fo = int(0.002 * SR), int(0.04 * SR)
    x[:fi] *= np.linspace(0, 1, fi)
    x[-fo:] *= np.linspace(1, 0, fo)
    x = x * 10 ** ((tgt - cc.rms100(x)) / 20)
    cap = 10 ** (-1 / 20)
    if np.abs(x).max() > cap:
        x = cap * np.tanh(x / cap)
    return x


def burst(x, n=8, gap=0.11, seed=3):
    r = np.random.default_rng(seed)
    mix = np.zeros(int((n * gap + 0.4) * SR))
    for k in range(n):
        p = r.uniform(0.91, 1.09)
        y = np.interp(np.arange(int(len(x) / p)) * p, np.arange(len(x)), x) * 10 ** (-4 / 20)
        st = int(k * gap * SR)
        mix[st:st + len(y)] += y
    return mix / max(1.0, np.abs(mix).max() / 0.9)


def wr(path, x):
    sf.write(path, x.astype(np.float32), SR, format="OGG", subtype="VORBIS")


def main():
    import wave
    with wave.open(os.path.join(cc.SFX, "op_exusiai_atk.wav")) as w:
        old = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float64) / 32768.0
    tgt = cc.rms100(old)
    wr(os.path.join(OUT, "now.ogg"), old)
    wr(os.path.join(OUT, "now_burst.ogg"), burst(old))
    rows = []
    for name, sid, t0, note in GUNS:
        m = cc.fetch(sid)
        raw = cc.load(sid)
        ln = 0.2 if name == "g8" else LEN
        a = find_onset(raw[int(t0 * SR):]) + int(t0 * SR)
        x = proc(raw[a:a + int(ln * SR)].copy(), tgt, ln)
        wr(os.path.join(OUT, name + ".ogg"), x)
        wr(os.path.join(OUT, name + "_burst.ogg"), burst(x))
        st = cc.stats(x)
        rows.append((name, sid, a / SR, note, m, st))
        print(name, sid, m["user"], m["license"], "onset %.2fs %.2fs pk%.1f rms%.1f cen%.0f hf%.0f%%" % (a / SR, st[0], st[1], st[2], st[3], st[4] * 100))
    def aud(p):
        return '<audio controls preload="none" src="%s"></audio>' % p
    h = ["<!--gun-->", "<h1>六、能天使枪声第二轮：CC0 单发录音（docs/113 §16）</h1>",
         "<p><small>每条是 Freesound 上 CC0 的枪声，自动找到第一声枪响，取 0.14 s，100 Hz 高通 + 7 kHz 低通，响度对齐现用文件。「8 连发」是 0.11 s 间隔 + ±9% 音高随机，看连射累不累。</small></p>",
         "<table><tr><th>候选</th><th>单发</th><th>8 连发</th><th>来源 / 作者 / 许可</th><th>说明</th></tr>",
         "<tr><td>现用版</td><td>%s</td><td>%s</td><td><small>op_exusiai_atk（DarkShroom M9，CC0）</small></td><td></td></tr>" % (aud("gun/now.ogg"), aud("gun/now_burst.ogg"))]
    for name, sid, a, note, m, st in rows:
        h.append('<tr><td>%s</td><td>%s</td><td>%s</td><td><small><a href="%s" style="color:#9cd">%s</a><br>%s · %s</small></td><td><small>%s<br>起音 %.2f s；%.2fs / RMS %.1f / 重心 %.0f Hz / 4 kHz 以上 %.0f%%</small></td></tr>'
                 % (name, aud("gun/%s.ogg" % name), aud("gun/%s_burst.ogg" % name), m["url"], html.escape(m["title"][:60]), m["user"], m["license"], html.escape(note), a, st[0], st[2], st[3], st[4] * 100))
    h.append("</table><!--/gun-->")
    p = os.path.join(cc.REV, "index.html")
    t = open(p, encoding="utf-8").read()
    t = re.sub(r"<!--gun-->.*?<!--/gun-->", "", t, flags=re.S)
    open(p, "w", encoding="utf-8").write(t + chr(10).join(h))


if __name__ == "__main__":
    main()
