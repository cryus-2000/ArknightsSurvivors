"""能天使音效第三轮候选（docs/113 §17，10-25 用户：「能天使的音效没有替换」）。
用户要换：从第六节已处理好的 CC0 单发（build/sfx_review_1024/gun/g*.ogg，来源 / 作者 / 许可见 build/sfx_candidates_1024/freesound/meta.json）
里挑三套，每套 3 条轮换（op_exusiai_atk / _b / _c，音高 ±8%，同帧多发由 OP_GAP 合并），并用同一套样本拼出技能音：
  s1 装填：金属「咔」+ 3 连点射；s2 蓄压：6 连渐快；s3 倾泻：18 连渐快 + 末发加重；big（弹匣倾泻落点）：9 连 + 一声重的。
全部由样本拼接（无合成），响度对齐现用 op_exusiai_atk，峰值软限幅 -1 dBFS。

运行：python game/tools/gen_sfx_review_exu3_1025.py            写试听包 build/sfx_review_1024/exu3/ 并追加第七节
      python game/tools/gen_sfx_review_exu3_1025.py --apply A  把 A 套写进 game/audio/sfx/（单声道 44.1 kHz 16 位 wav + .import）
先运行 gen_sfx_review_1024.py、gen_sfx_review_cc0_1024.py、gen_sfx_review_gun_1024.py。
"""
import os, re, sys, json, hashlib, random
import numpy as np
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_sfx_review_cc0_1024 as cc

SR = cc.SR
GUN = os.path.join(cc.REV, "gun")
OUT = os.path.join(cc.REV, "exu3")
SFXDIR = os.path.join(HERE, "..", "audio", "sfx")
META = os.path.join(cc.SRC, "meta.json")
# 套名 -> (说明, [三条单发], 技能用的主样本)
SETS = {
    "A": ("消音·干脆：威尔罗德 + 两条消音枪，3.2 / 2.3 / 2.6 kHz 重心，几乎只有机括声，连射最不累", ["g3", "g5", "g6"], "g5"),
    "B": ("冲锋枪·利落：游戏用射击音效 + 自动步枪「punchy」+ 消音单发，重心 1.6–3 kHz，有枪口爆音", ["g10", "g7", "g13"], "g10"),
    "C": ("科幻·冷：实验性科幻枪 + 消音带相位器尾音 + 消音枪，偏电子、有尾音", ["g11", "g8", "g2"], "g8"),
}
FILES = {"A": "op_exusiai_atk", "B": "op_exusiai_atk_b", "C": "op_exusiai_atk_c"}   # 一套里三条单发的游戏文件名（按 SETS 顺序）
RNG = np.random.default_rng(1025)


def rd(n):
    x, sr = sf.read(os.path.join(GUN, n + ".ogg"), dtype="float64")
    return x.mean(1) if x.ndim > 1 else x


def shift(x, p):
    return np.interp(np.arange(int(len(x) / p)) * p, np.arange(len(x)), x)


def limit(x, peak=-1.0):
    cap = 10 ** (peak / 20)
    return cap * np.tanh(x / cap) if np.abs(x).max() > cap else x


def stack(x, times, gains, pitches):
    """把样本 x 按 times（秒）依次叠出来"""
    mix = np.zeros(int((max(times) + len(x) / SR + 0.25) * SR))
    for t, g, p in zip(times, gains, pitches):
        y = shift(x, p) * g
        s = int(t * SR)
        mix[s:s + len(y)] += y
    return mix


def burst(x, n, t0_gap, t1_gap, g0=0.8, g1=0.8, last=0.0):
    """n 连发，间隔从 t0_gap 渐变到 t1_gap；last > 0 时末发加重（升 last dB、降调）"""
    times, t = [], 0.0
    for k in range(n):
        times.append(t)
        t += t0_gap + (t1_gap - t0_gap) * (k / max(1, n - 1))
    gains = [g0 + (g1 - g0) * k / max(1, n - 1) for k in range(n)]
    pitches = list(RNG.uniform(0.93, 1.07, n))
    if last > 0:
        gains[-1] *= 10 ** (last / 20)
        pitches[-1] = 0.82
    return stack(x, times, gains, pitches)


def click(sr=SR):
    """装填的金属「咔」：6 ms 窄带噪声 + 2.2 kHz 衰减正弦"""
    n = int(0.05 * sr)
    t = np.arange(n) / sr
    x = np.sin(2 * np.pi * 2200 * t) * np.exp(-t * 90) * 0.5 + RNG.normal(0, 1, n) * np.exp(-t * 400) * 0.35
    return x


def skills(main):
    """用主样本拼 s1 / s2 / s3 / big"""
    x = rd(main)
    ck = click()
    s1 = np.concatenate([ck, np.zeros(int(0.06 * SR))])
    b = burst(x, 3, 0.085, 0.085, 0.8, 0.8)
    s1 = np.concatenate([s1, b])
    s2 = burst(x, 6, 0.11, 0.06, 0.65, 0.95)
    s3 = burst(x, 18, 0.07, 0.04, 0.7, 1.0, last=3.0)
    big = np.concatenate([burst(x, 9, 0.06, 0.045, 0.7, 0.9), np.zeros(int(0.12 * SR))])
    heavy = shift(x, 0.78) * 1.4
    big = np.concatenate([big, heavy])
    return {"s1": s1, "s2": s2, "s3": s3, "big": big}


def norm(x):
    x = x / max(1e-9, np.abs(x).max()) * 0.9 if np.abs(x).max() > 0.95 else x
    return limit(x)


def wr(path, x, wav=False):
    if wav:
        sf.write(path, x.astype(np.float32), SR, subtype="PCM_16")
    else:
        sf.write(path, x.astype(np.float32), SR, format="OGG", subtype="VORBIS")


def import_text(name):
    """手写 .import（和同目录其它 wav 一致；uid 由 Godot 首次导入时认，这里给稳定随机 uid）"""
    h = hashlib.md5(("res://audio/sfx/%s.wav" % name).encode()).hexdigest()
    ref = open(os.path.join(SFXDIR, "op_exusiai_hit.wav.import"), encoding="utf-8").read()
    uid = "uid://" + "".join(random.Random(name).choice("abcdefghijklmnopqrstuvwxyz0123456789") for _ in range(13))
    t = re.sub(r'uid="[^"]*"', 'uid="%s"' % uid, ref)
    t = re.sub(r"op_exusiai_hit\.wav-[0-9a-f]{32}", "%s.wav-%s" % (name, h), t)
    return t.replace("op_exusiai_hit", name)


def apply(key):
    sing = SETS[key][1]
    names = ["op_exusiai_atk", "op_exusiai_atk_b", "op_exusiai_atk_c"]
    for n, g in zip(names, sing):
        write_game(n, rd(g))
    sk = skills(SETS[key][2])
    for k, nm in (("s1", "op_exusiai_s1"), ("s2", "op_exusiai_s2"), ("s3", "op_exusiai_s3"), ("big", "op_exusiai_big")):
        write_game(nm, norm(sk[k]))
    print("已写入", key)


def write_game(name, x):
    p = os.path.join(SFXDIR, name + ".wav")
    wr(p, x, wav=True)
    ip = p + ".import"
    if not os.path.exists(ip):
        open(ip, "w", encoding="utf-8", newline="\n").write(import_text(name))


def main():
    if "--apply" in sys.argv:
        apply(sys.argv[sys.argv.index("--apply") + 1])
        return
    os.makedirs(OUT, exist_ok=True)
    meta = json.load(open(META, encoding="utf-8"))
    ids = {"g3": 701224, "g5": 381569, "g6": 380185, "g10": 720118, "g7": 855654, "g13": 100465, "g11": 445347, "g8": 855656, "g2": 819269}
    now = rd("now")
    wr(os.path.join(OUT, "now_rot.ogg"), norm(burst(now, 12, 0.1, 0.1, 0.8, 0.8)))
    def aud(p):
        return '<audio controls preload="none" src="%s"></audio>' % p
    h = ["<!--exu3-->", "<h1>七、能天使第三轮：三套轮换枪声 + 技能连射（docs/113 §17）</h1>",
         "<p><small>用户 10-25「能天使的音效没有替换」→ 换。每套 3 条单发轮换（音高 ±8%），技能音由同一套样本拼出：s1 装填 +3 连点射，s2 6 连渐快，s3 18 连渐快 + 末发加重，big 9 连 + 一声重的。"
         "同一帧多发由 OP_GAP 0.045 s 合并。现用版 = M9 单发 + 技能借艾丽妮 / 维什戴尔。</small></p>",
         "<table><tr><th>套</th><th>单发 ×3</th><th>12 连射（轮换）</th><th>技能 s1 / s2 / s3 / big</th><th>来源 / 许可</th></tr>",
         "<tr><td>现用</td><td>%s</td><td>%s</td><td><small>借艾丽妮 / 维什戴尔，未换</small></td><td><small>DarkShroom M9 · CC0</small></td></tr>" % (aud("../sfx_review_1024/gun/now.ogg").replace("../sfx_review_1024/", ""), aud("exu3/now_rot.ogg"))]
    for key, (note, sing, main_s) in SETS.items():
        xs = [rd(g) for g in sing]
        for i, x in enumerate(xs):
            wr(os.path.join(OUT, "%s_%d.ogg" % (key, i + 1)), x)
        times = [k * 0.1 for k in range(12)]
        mix = np.zeros(int((12 * 0.1 + 0.4) * SR))
        for k, t in enumerate(times):
            y = shift(xs[k % 3], RNG.uniform(0.92, 1.08)) * 0.8
            mix[int(t * SR):int(t * SR) + len(y)] += y
        wr(os.path.join(OUT, "%s_rot.ogg" % key), norm(mix))
        sk = skills(main_s)
        for k, v in sk.items():
            wr(os.path.join(OUT, "%s_%s.ogg" % (key, k)), norm(v))
        src = "<br>".join('%s <a href="%s" style="color:#9cd">%s</a> · %s · %s' % (g, meta[str(ids[g])]["url"], meta[str(ids[g])]["title"][:34], meta[str(ids[g])]["user"], meta[str(ids[g])]["license"]) for g in sing)
        h.append("<tr><td><b>%s</b><br><small>%s</small></td><td>%s</td><td>%s</td><td>%s</td><td><small>%s</small></td></tr>" % (
            key, note, "".join(aud("exu3/%s_%d.ogg" % (key, i + 1)) for i in range(3)), aud("exu3/%s_rot.ogg" % key),
            "".join("<div><small>%s</small> %s</div>" % (k, aud("exu3/%s_%s.ogg" % (key, k))) for k in ("s1", "s2", "s3", "big")), src))
    h.append("</table><!--/exu3-->")
    p = os.path.join(cc.REV, "index.html")
    t = open(p, encoding="utf-8").read()
    t = re.sub(r"<!--exu3-->.*?<!--/exu3-->", "", t, flags=re.S)
    open(p, "w", encoding="utf-8").write(t + "\n".join(h))
    print("done", OUT)


if __name__ == "__main__":
    main()
