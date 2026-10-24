"""音效改版候选（docs/113 §13，10-24 用户：「锁链和能天使的射击也得更改，冲锋的音效也得更改」）。
合成到 <主仓库>/build/sfx_review_1024/：每个音效「改前（现用文件）/ 改后（候选）」两个 ogg + 局内节奏混音 + 对照页 index.html。
工具函数取 gen_sfx_ops.py 的工具段（程序合成，不用任何外部音频）；不改 audio/sfx/，用户点头后再 --apply 写入正式文件。

运行：python game/tools/gen_sfx_review_1024.py              只生成试听包（build/sfx_review_1024/）
      python game/tools/gen_sfx_review_1024.py --apply      把候选写进 game/audio/sfx/（wav，引擎导入走 QOA）
"""
import os, sys, subprocess, wave, shutil
import numpy as np
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, "gen_sfx_ops.py"), encoding="utf-8").read()
exec(src[:src.index("SAVED = []")])   # T / N / bp / lp / hp / env / swell / tone / sweep_noise / metal / thud / crackle / verb / at / pad / sat
SFX = os.path.join(HERE, "..", "audio", "sfx")

try:
    common = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=HERE, capture_output=True, text=True).stdout.strip()
    ROOT = os.path.dirname(os.path.abspath(os.path.join(HERE, common)))
except OSError:
    ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "build", "sfx_review_1024")


def read_wav(name):
    with wave.open(os.path.join(SFX, name + ".wav")) as w:
        return np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float64) / 32768.0


def finish(x, peak_db):
    """去直流 / 低切、裁尾、淡出，峰值定到 peak_db（dBFS）"""
    x = hp(x, 40, 1)
    x = x / (np.max(np.abs(x)) + 1e-9) * 10 ** (peak_db / 20)
    nz = np.where(np.abs(x) > 0.004)[0]
    if len(nz):
        x = x[:min(len(x), nz[-1] + int(0.02 * SR))]
    f = min(len(x), 500)
    x[-f:] *= np.linspace(1, 0, f)
    return x


def rms100(x):
    n = int(0.1 * SR)
    if len(x) < n:
        return 20 * np.log10(np.sqrt(np.sum(x ** 2) / n) + 1e-9)
    c = np.cumsum(np.r_[0, x ** 2])
    return 10 * np.log10(np.max(c[n:] - c[:-n]) / n + 1e-12)


def centroid(x):
    s = np.abs(np.fft.rfft(x)) ** 2
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return float((s * f).sum() / (s.sum() + 1e-12))


def hf_share(x, fc=4000):
    s = np.abs(np.fft.rfft(x)) ** 2
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return float(s[f >= fc].sum() / (s.sum() + 1e-12))


def resample(x, ratio):
    """变速变调（同 AudioStreamPlayer.pitch_scale）"""
    n = int(len(x) / ratio)
    return np.interp(np.arange(n) * ratio, np.arange(len(x)), x)


def place(mix, x, t, db=0.0, pitch=1.0):
    if pitch != 1.0:
        x = resample(x, pitch)
    x = x * 10 ** (db / 20)
    st = int(t * SR)
    if st + len(x) > len(mix):
        mix = np.pad(mix, (0, st + len(x) - len(mix)))
    mix[st:st + len(x)] += x
    return mix


# ---------------------------------------------------------------- 金属链节
def clink(f, decay=48.0, amp=1.0, heavy=0.0):
    """一节链撞击：2 ms 噪声起音 + 三个非谐泛音的短环响（20–30 ms）+ 重链再加一层低频「咚」。整体 5.5 kHz 低通，别刺耳"""
    tick = hp(N(0.004), 2200) * env(0.004, 0.0002, 380) * 0.5
    ring = metal(0.1, f, decay, partials=(1.0, 2.76, 5.40), bright=0.42)
    low = thud(0.04, 380, 200, 90) * heavy
    return lp(pad(tick, ring, low), 5500, 2) * amp


def clinks(sec, times, f_lo, f_hi, a_lo, a_hi, heavy=0.0, decay=48.0):
    x = np.zeros(int(sec * SR))
    for k, t0 in enumerate(times):
        a = a_lo + (a_hi - a_lo) * k / max(1, len(times) - 1)
        c = clink(rng.uniform(f_lo, f_hi), decay * rng.uniform(0.8, 1.25), a * rng.uniform(0.75, 1.0), heavy)
        st = int(t0 * SR)
        if st >= len(x):
            continue
        x[st:st + len(c)] += c[:len(x) - st]
    return x


# ---------------------------------------------------------------- 锁链：出钩 / 收拉 / 抡锚
def chain_throw():
    """出钩（乌尔比安 S1 掷锚、歌蕾蒂娅钩索出手）：链节从盘里越抖越快地放出去，末尾钩头「铛」一声咬住"""
    t, ts, dt = 0.0, [], 0.075
    while t < 0.44:
        ts.append(t)
        t += dt
        dt *= 0.84
    links = clinks(0.6, ts, 1100, 2400, 0.4, 1.0, heavy=0.2)
    air = sweep_noise(0.42, 350, 1900, 0.7) * swell(0.42, 0.45) * 0.3
    clank = pad(metal(0.35, 540, 11, partials=(1.0, 2.76, 5.40, 8.93), bright=0.5) * 0.9, thud(0.06, 190, 80, 45) * 0.6,
                hp(N(0.006), 2000) * env(0.006, 0.0002, 250) * 0.5)
    x = pad(links, air, at(lp(clank, 6000), 0.45))
    return finish(verb(x, 0.25, 0.12), -2.0)


def chain_reel():
    """收拉（钩住后把人 / 自己拽回来）：链节一格一格过链轮的棘轮声，越拉越紧，吱的摩擦低鸣，最后绷直一声「铮」"""
    ts, t = [], 0.02
    for k in range(15):
        ts.append(t)
        t += 0.05 - 0.02 * k / 14
    links = clinks(0.78, ts, 850, 1700, 0.5, 1.0, heavy=0.3, decay=60.0)
    creak = lp(tone(0.55, 150, 230, "saw"), 700) * (0.6 + 0.4 * np.sin(2 * np.pi * 23 * T(0.55))) * swell(0.55, 0.85) * 0.22
    drag = lp(N(0.55), 1200) * swell(0.55, 0.8) * 0.16
    twang = pad(metal(0.4, 250, 8.5, partials=(1.0, 2.0, 3.01, 4.2), bright=0.55) * 0.55, hp(N(0.005), 1800) * env(0.005, 0.0002, 300) * 0.4)
    x = pad(links, at(creak, 0.02, 0.78), at(drag, 0.02, 0.78), at(lp(twang, 4500), 0.55))
    return finish(verb(x, 0.2, 0.1), -2.0)


def chain_swing():
    """抡锚（乌尔比安普攻）：锚头甩出的风切 + 稀疏几节沉链 + 末尾砸地一下"""
    air = sweep_noise(0.2, 800, 260, 0.6) * swell(0.2, 0.5) * 0.4
    links = clinks(0.3, [0.0, 0.05, 0.095, 0.135, 0.17], 800, 1500, 0.6, 1.0, heavy=0.4, decay=55.0)
    slam = pad(thud(0.22, 130, 52, 17) * 0.95, lp(metal(0.2, 430, 14, partials=(1.0, 2.76, 5.40), bright=0.4), 4000) * 0.35,
               lp(N(0.12), 1500) * env(0.12, 0.001, 35) * 0.3)
    x = pad(air, links, at(slam, 0.18))
    return finish(x, -2.2)


# ---------------------------------------------------------------- 冲锋三段：起步爆发 / 呼啸 / 撞击
def charge_launch():
    """起步爆发：脚下蹬地的低频「嘭」+ 锚链绷直的一声脆响 + 一口气爆出去的气流（0.2 s）"""
    sub = thud(0.18, 125, 42, 24) * 1.0
    burst = lp(N(0.2), 3200) * env(0.2, 0.002, 17) * 0.5
    snap = pad(metal(0.15, 860, 30, partials=(1.0, 2.76, 5.40), bright=0.42) * 0.55, hp(N(0.004), 2200) * env(0.004, 0.0002, 380) * 0.5)
    chirp = sweep_noise(0.14, 450, 2600, 0.55) * env(0.14, 0.003, 14) * 0.35
    return finish(pad(sub, burst, snap, chirp), -1.5)


def charge_rush():
    """呼啸：整段在加速（位移按 k²），风声与锚链拖响一路往上顶，到最响处戛然而止，接撞击（0.3 s）"""
    n = 0.3
    t = T(n) / n
    wind = sweep_noise(n, 500, 3300, 0.6) * (t ** 2.2)
    body = lp(N(n), 650) * (t ** 1.6) * 0.5
    ts, tt, dt = [], 0.0, 0.04
    while tt < n - 0.03:
        ts.append(tt)
        tt += dt
        dt = max(0.014, dt * 0.88)
    links = clinks(n, ts, 900, 1800, 0.25, 0.9, heavy=0.15, decay=60.0) * 0.9
    x = pad(wind * 0.9, body, links)
    x[-int(0.006 * SR):] *= np.linspace(1, 0.5, int(0.006 * SR))
    return finish(x, -2.0)


def charge_impact():
    """撞击：落点的低频「轰」+ 锚头砸地的金属闷响 + 碎石水花的碎响（0.55 s，音量比起步 / 呼啸高 2–3 dB）"""
    boom = tone(0.5, 88, 30) * env(0.5, 0.001, 7.5)
    body = thud(0.12, 210, 80, 28) * 0.7
    clang = lp(metal(0.4, 470, 10, partials=(1.0, 2.76, 5.40), bright=0.42), 4500) * 0.45
    debris = pad(crackle(0.35, 240, 1200, 5500, 9.0) * 0.32, bp(N(0.25), 800, 4200) * env(0.25, 0.002, 13) * 0.3)
    return finish(sat(verb(pad(boom, body, clang, debris), 0.3, 0.14), 2.2), -1.0)


# ---------------------------------------------------------------- 能天使枪声：三个变体轮换，0.09 s 内结束
def exu_shot(f_body, crack_hp, mid_lo, mid_hi, click_f):
    crack = hp(N(0.014), crack_hp) * env(0.014, 0.0001, 270) * 0.9
    mid = bp(N(0.035), mid_lo, mid_hi) * env(0.035, 0.0003, 110) * 0.75
    body = thud(0.055, f_body * 1.9, f_body, 66) * 0.65
    slide = at(metal(0.03, click_f, 95, partials=(1.0, 2.4), bright=0.3) * 0.12, 0.024)
    tail = lp(N(0.08), 1500) * env(0.08, 0.002, 42) * 0.14
    return lp(pad(crack, mid, body, slide, tail), 8000, 2)


def match_energy(x, ref, k=1.0, cap_db=-1.0):
    """整段能量对齐 ref（× k），峰值超过 cap 就软限幅；短促枪声按 100 ms RMS 比会被低估，按整段能量比"""
    g = np.sqrt(k * np.sum(ref ** 2) / (np.sum(x ** 2) + 1e-12))
    y = x * g
    cap = 10 ** (cap_db / 20)
    if np.abs(y).max() > cap:
        y = cap * np.tanh(y / cap)
    return y


def exu_hit():
    """命中：极短的「嗒」，不带金属环响，每秒 7–11 次也不累"""
    return finish(pad(bp(N(0.035), 800, 3000) * env(0.035, 0.0003, 120) * 0.7, thud(0.04, 300, 170, 80) * 0.45), -9.0)


def build():
    """(名字) -> 候选波形"""
    return {
        "chain_throw": chain_throw(), "chain_reel": chain_reel(), "chain_swing": chain_swing(),
        "charge_launch": charge_launch(), "charge_rush": charge_rush(), "charge_impact": charge_impact(),
        "exu_atk_a": match_energy(finish(exu_shot(150, 1800, 700, 2600, 2600), -3.0), read_wav("op_exusiai_atk"), 0.8),
        "exu_atk_b": match_energy(finish(exu_shot(175, 2200, 900, 3000, 3100), -3.0), read_wav("op_exusiai_atk"), 0.8),
        "exu_atk_c": match_energy(finish(exu_shot(205, 1500, 600, 2300, 2200), -3.0), read_wav("op_exusiai_atk"), 0.8),
        "exu_hit": match_energy(exu_hit(), read_wav("op_exusiai_hit"), 0.8),
    }


def write_ogg(name, x):
    sf.write(os.path.join(OUT, name + ".ogg"), x.astype(np.float32), SR, format="OGG", subtype="VORBIS")


def write_wav(path, x):
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())


def stats(x):
    return {"dur": len(x) / SR, "peak": 20 * np.log10(np.abs(x).max() + 1e-9), "rms": rms100(x), "cen": centroid(x), "hf": hf_share(x)}


def main():
    new = build()
    if "--apply" in sys.argv:
        m = {"chain_throw": "op_ulpianus_s1", "chain_swing": "op_ulpianus_atk", "charge_launch": "op_ulpianus_launch",
             "charge_rush": "op_ulpianus_rush", "charge_impact": "op_ulpianus_big", "chain_reel": "op_ulpianus_s3",
             "exu_atk_a": "op_exusiai_atk", "exu_atk_b": "op_exusiai_atk_b", "exu_atk_c": "op_exusiai_atk_c", "exu_hit": "op_exusiai_hit"}
        for k, v in m.items():
            write_wav(os.path.join(SFX, v + ".wav"), new[k])
            print("写入", v)
        return
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith((".ogg", ".html")):
            os.remove(os.path.join(OUT, f))
    now = {"chain_throw": "op_ulpianus_s1", "chain_reel": "op_ulpianus_s3", "chain_swing": "op_ulpianus_atk", "charge_launch": None,
           "charge_rush": None, "charge_impact": "op_ulpianus_big", "exu_atk_a": "op_exusiai_atk", "exu_hit": "op_exusiai_hit"}
    rows = []
    for k, x in new.items():
        write_ogg(k + "_after", x)
        st = stats(x)
        old = now.get(k)
        if old:
            o = read_wav(old)
            write_ogg(k + "_before", o)
            rows.append((k, old, stats(o), st))
        else:
            rows.append((k, None, None, st))

    # ---- 局内节奏混音（按 sfx.gd 的音量：OP_VOL atk −11 / hit −10 / s3 −2 / big −6 dB；音高随机取 ±9%）
    # 普攻 0.5 s 一发（约 2 次 / 秒）3 s，随后 S3 过载 6 发 / 秒的连射 3 s；命中跟在出手后 0.12 s
    shots = [0.4 + 0.48 * i for i in range(6)] + [3.4 + 0.11 * i for i in range(28)]
    # 现用
    cur_atk, cur_hit = read_wav("op_exusiai_atk"), read_wav("op_exusiai_hit")
    mix_b = np.zeros(int(6.8 * SR)); mix_a = np.zeros(int(6.8 * SR))
    pr = np.random.default_rng(7)
    vs = [new["exu_atk_a"], new["exu_atk_b"], new["exu_atk_c"]]
    last_hit = -1.0
    for t in shots:
        mix_b = place(mix_b, cur_atk, t, -17.0, pr.uniform(0.91, 1.09))
        mix_a = place(mix_a, vs[pr.integers(3)], t, -17.0, pr.uniform(0.91, 1.09))
        h = t + 0.12
        if h - last_hit >= 0.1:   # OP_GAP：命中至少隔 0.1 s
            mix_b = place(mix_b, cur_hit, h, -14.0 - 2.0, pr.uniform(0.9, 1.1))
            mix_a = place(mix_a, new["exu_hit"], h, -14.0 - 2.0, pr.uniform(0.9, 1.1))
            last_hit = h
    for nm, m in (("exu_mix_before", mix_b), ("exu_mix_after", mix_a)):
        write_ogg(nm, m / max(1.0, np.abs(m).max() / 0.9))

    # 冲锋整段（按代码时序：s3 在发动时、atk 在锚咬住转冲锋时（×0.85、+2 dB）、big 在落地；冲锋时长 0.25 s）
    dur = 0.25
    full_b = np.zeros(int(1.6 * SR)); full_a = np.zeros(int(1.6 * SR))
    full_b = place(full_b, read_wav("op_ulpianus_s3"), 0.0, -2.0)
    full_b = place(full_b, read_wav("op_ulpianus_atk"), 0.3, -9.0, 0.85)
    full_b = place(full_b, read_wav("op_ulpianus_big"), 0.3 + dur, -6.0)
    full_a = place(full_a, new["chain_throw"], 0.0, -4.0)
    full_a = place(full_a, new["charge_launch"], 0.3, -3.0)
    full_a = place(full_a, new["charge_rush"], 0.3, -5.0, 1.0)
    full_a = place(full_a, new["charge_impact"], 0.3 + dur, -3.0)
    for nm, m in (("charge_full_before", full_b), ("charge_full_after", full_a)):
        write_ogg(nm, m / max(1.0, np.abs(m).max() / 0.9))
    rows_s = rows

    # ---- 对照页
    def aud(p):
        return f'<audio controls preload="none" src="{p}"></audio>'
    html = ['<!doctype html><meta charset="utf-8"><title>音效改版试听 10-24</title>',
            '<style>body{font:15px system-ui;margin:24px auto;max-width:980px;background:#14181c;color:#dde}h1{font-size:20px}h2{font-size:16px;margin:26px 0 6px;color:#9cd}'
            'table{border-collapse:collapse;width:100%}td,th{border-bottom:1px solid #2a3138;padding:6px 8px;text-align:left;vertical-align:middle}'
            'th{color:#89a;font-weight:500}small{color:#8a97a3}audio{height:32px;width:260px}</style>',
            '<h1>音效改版试听（docs/113 §13）</h1><p><small>测试一律静音；这页只有点播放才出声，不会自动播放。「改前」是游戏里现用的文件，「改后」是候选。</small></p>']

    def sec(title, note, items):
        html.append(f'<h2>{title}</h2><p><small>{note}</small></p><table><tr><th>名称</th><th>改前</th><th>改后</th><th>数据（时长 / 峰值 / 100 ms RMS / 重心 / 4 kHz 以上）</th></tr>')
        for label, k in items:
            r = [x for x in rows_s if x[0] == k][0]
            b = aud(k + "_before.ogg") if r[1] else "<small>（原来没有这一段）</small>"
            s_a = r[3]
            d = f'后 {s_a["dur"]:.2f}s / {s_a["peak"]:.1f} / {s_a["rms"]:.1f} / {s_a["cen"]:.0f}Hz / {s_a["hf"]*100:.0f}%'
            if r[2]:
                s_b = r[2]
                d = f'前 {s_b["dur"]:.2f}s / {s_b["peak"]:.1f} / {s_b["rms"]:.1f} / {s_b["cen"]:.0f}Hz / {s_b["hf"]*100:.0f}%<br>' + d
            html.append(f'<tr><td>{label}</td><td>{b}</td><td>{aud(k + "_after.ogg")}</td><td><small>{d}</small></td></tr>')
        html.append('</table>')
    sec("一、锁链", "金属链节质感，出钩与收拉分开：出钩 = 链节越抖越快 + 末尾钩头「铛」；收拉 = 棘轮式一格一格过链轮 + 摩擦低鸣 + 绷直「铮」。",
        [("出钩 / 掷锚（乌尔比安 S1，也可给歌蕾蒂娅出钩）", "chain_throw"), ("收拉（钩住后拽回；乌尔比安 S3 原收链位）", "chain_reel"), ("抡锚（乌尔比安普攻）", "chain_swing")])
    sec("二、冲锋三段（乌尔比安 S3）", "起步爆发 → 呼啸（整段加速，最响处接撞击）→ 撞击。冲锋时长 0.14–0.34 s，撞击紧接呼啸。",
        [("起步爆发", "charge_launch"), ("呼啸", "charge_rush"), ("撞击（落点）", "charge_impact")])
    html.append(f'<h2>冲锋整段（按代码时序摆好）</h2><p><small>前：s3「收链」发动时 → 0.3 s 抡锚 → 0.55 s 落地 big。后：出钩 → 起步爆发 + 呼啸 → 撞击。</small></p>'
                f'<table><tr><td>改前</td><td>{aud("charge_full_before.ogg")}</td><td>改后</td><td>{aud("charge_full_after.ogg")}</td></tr></table>')
    sec("三、能天使射击", "0.09 s 内结束、不带长尾；三个变体 A / B / C 随机轮换，再加 ±9% 音高随机；命中改成极短的「嗒」，不带金属环响。",
        [("普攻枪声 A", "exu_atk_a"), ("命中", "exu_hit")])
    html.append('<table><tr><td>枪声 B</td><td colspan="3">' + aud("exu_atk_b_after.ogg") + '</td></tr><tr><td>枪声 C</td><td colspan="3">' + aud("exu_atk_c_after.ogg") + '</td></tr></table>')
    html.append(f'<h2>能天使连射节奏（6 秒）</h2><p><small>前 3 秒普攻约 2 次 / 秒，后 3 秒过载连射约 9 次 / 秒；命中按 0.1 s 节流。按局内音量摆放，不是引擎实录。</small></p>'
                f'<table><tr><td>改前</td><td>{aud("exu_mix_before.ogg")}</td><td>改后</td><td>{aud("exu_mix_after.ogg")}</td></tr></table>')
    open(os.path.join(OUT, "index.html"), "w", encoding="utf-8").write("\n".join(html))
    for r in rows:
        print(r[0], {k: round(v, 2) for k, v in r[3].items()})
    print("OUT", OUT)


if __name__ == "__main__":
    main()
