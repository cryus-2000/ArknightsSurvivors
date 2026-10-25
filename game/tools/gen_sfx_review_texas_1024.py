"""德克萨斯冲刺音效候选（docs/113 §15，10-24 用户：「冲锋说的是德克萨斯的冲锋」）。
她的冲刺 = 普攻「冲刺斩」/ 战术快递（队长冲刺时同向冲）/ 二技能「冲锋号令·γ型」加长：0.24 s 先快后慢位移 + 沿途斩击，
现在只有 op_texas_atk（Kenney knifeSlice 刀划 0.22 s）在起冲响一下，冲到头且打到人时再放 op_texas_hit（借艾丽妮命中 ×1.1），
没有蹬地爆发、没有位移呼啸、没有收势。这里出三套候选放进试听页第五节（改前 / 合成版 / CC0 录音），不改 game/audio。

先运行 gen_sfx_review_1024.py 与 gen_sfx_review_cc0_1024.py，再运行本脚本。
"""
import os, re, sys, html
import numpy as np
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_sfx_review_cc0_1024 as cc   # fetch / load / process / stats / REV / SRC / SFX
src = open(os.path.join(HERE, "gen_sfx_ops.py"), encoding="utf-8").read()
exec(src[:src.index("SAVED = []")])   # T / N / bp / lp / hp / env / swell / tone / sweep_noise / metal / thud / pad / at / verb
rng = np.random.default_rng(1024)
OUT = os.path.join(cc.REV, "texas")
os.makedirs(OUT, exist_ok=True)


def read_wav(name):
    """「现用」读换音前的基线提交 d872886cc（接入合成版之后工作树里的 op_texas_atk 已经是新文件）"""
    import io, wave, subprocess
    r = subprocess.run(["git", "show", "d872886cc:game/audio/sfx/%s.wav" % name], cwd=HERE, capture_output=True)
    with wave.open(io.BytesIO(r.stdout)) as w:
        return np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float64) / 32768.0


def fit(x, target_rms, cap_db=-1.0):
    x = x * 10 ** ((target_rms - cc.rms100(x)) / 20)
    cap = 10 ** (cap_db / 20)
    if np.abs(x).max() > cap:
        x = cap * np.tanh(x / cap)
    f = min(len(x), int(0.02 * SR))
    x[-f:] *= np.linspace(1, 0, f)
    return x


# ---------------------------------------------------------------- 合成：冲出去（蹬地 + 刃鸣 + 先快后慢的呼啸）/ 收势
def synth_go():
    n = 0.3
    step = thud(0.07, 190, 85, 55) * 0.55
    ring = lp(metal(0.25, 2100, 14, partials=(1.0, 2.76, 5.40), bright=0.35), 6000) * 0.16
    whoosh = sweep_noise(n, 3200, 700, 0.6) * env(n, 0.006, 11.0)
    air = lp(N(n), 1400) * env(n, 0.01, 9.0) * 0.25
    return pad(at(step, 0.0), at(ring, 0.012), whoosh * 0.85, air)


def synth_end():
    scrape = bp(N(0.12), 900, 3200) * env(0.12, 0.002, 38) * 0.5
    tsk = lp(metal(0.16, 2600, 38, partials=(1.0, 2.4, 5.4), bright=0.3), 6000) * 0.3
    foot = thud(0.06, 160, 90, 60) * 0.4
    return pad(scrape, tsk, foot)


# 候选 (名字, 角色, Freesound id, 起点, 终点, 说明)；角色 go = 起冲（起步 + 呼啸），end = 收势 / 命中
CC0 = [
    ("d1", "go", 521999, 0.00, 0.17, "Whoosh / Dash：0.17 s 短促的冲刺风声"),
    ("d2", "go", 803773, 0.00, 0.22, "whoosh 1 short：0.22 s 一下短风"),
    ("d3", "go", 507466, 0.23, 0.62, "Clean fast Swoosh：0.39 s 干净的快速挥风"),
    ("d4", "go", 60004, 0.00, 0.38, "Fast Sword Swing：0.38 s 快速挥剑"),
    ("d5", "go", 522701, 0.33, 0.85, "金属剑快挥带撞击：0.5 s，偏低沉"),
    ("e1", "end", 426322, 0.28, 0.58, "Single Sword Hit：0.3 s 剑击一下"),
    ("e2", "end", 434896, 0.00, 0.45, "Sword Impact：0.45 s 剑身撞击"),
    ("e3", "end", 417035, 0.05, 0.40, "Quick Sword Draw：0.35 s 拔剑出鞘「铮」，可当收势的刃鸣"),
]


def wr(path, x):
    sf.write(path, x.astype(np.float32), SR, format="OGG", subtype="VORBIS")


def main():
    old_go, old_end = read_wav("op_texas_atk"), read_wav("op_irene_hit")   # 现用：起冲 op_texas_atk；收势 op_texas_hit 借 op_irene_hit ×1.1、−3 dB
    r_go, r_end = cc.rms100(old_go), cc.rms100(old_end)
    wr(os.path.join(OUT, "now_go.ogg"), old_go)
    wr(os.path.join(OUT, "now_end.ogg"), old_end)
    sg, se = fit(cc.process(synth_go(), r_go), r_go), fit(cc.process(synth_end(), r_end), r_end)
    wr(os.path.join(OUT, "synth_go.ogg"), sg)
    wr(os.path.join(OUT, "synth_end.ogg"), se)
    if "--apply" in sys.argv:   # 用户 10-24 定：冲刺用合成版。起冲 -> op_texas_atk（替换 Kenney 刀划），收势 -> op_texas_hit（新增专属文件，原借艾丽妮命中）
        import wave
        for nm, x in (("op_texas_atk", sg), ("op_texas_hit", se)):
            with wave.open(os.path.join(cc.SFX, nm + ".wav"), "wb") as w:
                w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
                w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
            print("写入", nm, "%.2fs" % (len(x) / SR))
    rows, waves = [], {}
    for name, role, sid, a, b, note in CC0:
        m = cc.fetch(sid)
        x = fit(cc.process(cc.load(sid)[int(a * SR):int(b * SR)].copy(), r_go if role == "go" else r_end), r_go if role == "go" else r_end)
        wr(os.path.join(OUT, name + ".ogg"), x)
        waves[name] = x
        rows.append((name, role, sid, a, b, note, m, cc.stats(x)))
        print(name, sid, m["user"], m["license"], "%.2fs pk%.1f rms%.1f cen%.0f hf%.0f%%" % (cc.stats(x)[0], cc.stats(x)[1], cc.stats(x)[2], cc.stats(x)[3], cc.stats(x)[4] * 100))

    # ---- 整段对照：起冲在 0.1 s，冲刺 0.24 s + 停留 0.2 s 后收势在 +0.44 s；第二次冲刺相隔 1.05 s（普攻节奏）。按 sfx.gd 音量：atk −11 dB、收势 hit −13 dB
    def place(mix, x, t, db=0.0):
        st = int(t * SR)
        x = x * 10 ** (db / 20)
        if st + len(x) > len(mix):
            mix = np.pad(mix, (0, st + len(x) - len(mix)))
        mix[st:st + len(x)] += x
        return mix

    def seq(go, end):
        mix = np.zeros(int(2.0 * SR))
        for t0 in (0.1, 1.15):
            mix = place(mix, go, t0, -11.0)
            mix = place(mix, end, t0 + 0.44, -13.0)
        return mix / max(1.0, np.abs(mix).max() / 0.9)
    demos = {"demo_now": seq(old_go, old_end), "demo_synth": seq(sg, se), "demo_cc0_a": seq(waves["d3"], waves["e1"]), "demo_cc0_b": seq(waves["d4"], waves["e2"])}
    for k, v in demos.items():
        wr(os.path.join(OUT, k + ".ogg"), v)

    def aud(p):
        return '<audio controls preload="none" src="%s"></audio>' % p
    h = ["<!--texas-->", "<h1>五、德克萨斯冲刺（docs/113 §15）</h1>",
         "<p><small>她的冲刺：普攻「冲刺斩」、战术快递、二技能「冲锋号令·γ型」加长的那一下，0.24 s 先快后慢，沿途斩击。现在只有起冲一声刀划（Kenney knifeSlice），打到人时收势借艾丽妮命中。"
         "下面分「起冲」「收势」两类，各有现用、合成版、CC0 录音；最后是按代码时序摆好的两次冲刺整段。</small></p>",
         "<h2>起冲（蹬地 + 呼啸，冲刺开始时放）</h2><table><tr><th>候选</th><th>试听</th><th>来源 / 作者 / 许可</th><th>说明</th></tr>",
         "<tr><td>现用版</td><td>%s</td><td><small>op_texas_atk（Kenney RPG knifeSlice，CC0）</small></td><td></td></tr>" % aud("texas/now_go.ogg"),
         "<tr><td>合成版</td><td>%s</td><td><small>程序合成，无外部素材</small></td><td><small>蹬地低频 + 一丝刃鸣 + 3.2→0.7 kHz 下行呼啸（先快后慢），0.3 s</small></td></tr>" % aud("texas/synth_go.ogg")]
    for name, role, sid, a, b, note, m, st in rows:
        if role != "go":
            continue
        h.append('<tr><td>%s</td><td>%s</td><td><small><a href="%s" style="color:#9cd">%s</a><br>%s · %s</small></td><td><small>%s 的 %.2f–%.2f s<br>%s<br>%.2fs / RMS %.1f / 重心 %.0f Hz / 4 kHz 以上 %.0f%%</small></td></tr>'
                 % (name, aud("texas/%s.ogg" % name), m["url"], html.escape(m["title"]), m["user"], m["license"], sid, a, b, html.escape(note), st[0], st[2], st[3], st[4] * 100))
    h.append("</table><h2>收势（冲到头且打到人时放）</h2><table><tr><th>候选</th><th>试听</th><th>来源 / 作者 / 许可</th><th>说明</th></tr>")
    h.append("<tr><td>现用版</td><td>%s</td><td><small>op_texas_hit = 艾丽妮命中 ×1.1</small></td><td></td></tr>" % aud("texas/now_end.ogg"))
    h.append("<tr><td>合成版</td><td>%s</td><td><small>程序合成</small></td><td><small>靴底刹停的摩擦 + 刃「嘶」+ 轻「咚」，0.2 s</small></td></tr>" % aud("texas/synth_end.ogg"))
    for name, role, sid, a, b, note, m, st in rows:
        if role != "end":
            continue
        h.append('<tr><td>%s</td><td>%s</td><td><small><a href="%s" style="color:#9cd">%s</a><br>%s · %s</small></td><td><small>%s 的 %.2f–%.2f s<br>%s<br>%.2fs / RMS %.1f / 重心 %.0f Hz / 4 kHz 以上 %.0f%%</small></td></tr>'
                 % (name, aud("texas/%s.ogg" % name), m["url"], html.escape(m["title"]), m["user"], m["license"], sid, a, b, html.escape(note), st[0], st[2], st[3], st[4] * 100))
    h.append("</table><h2>两次冲刺整段（间隔 1.05 s）</h2><table>")
    for k, label in (("demo_now", "现用版"), ("demo_synth", "合成版（起冲 + 收势）"), ("demo_cc0_a", "CC0：d3 + e1"), ("demo_cc0_b", "CC0：d4 + e2")):
        h.append("<tr><td>%s</td><td>%s</td></tr>" % (label, aud("texas/%s.ogg" % k)))
    h.append("</table><!--/texas-->")
    pth = os.path.join(cc.REV, "index.html")
    t = open(pth, encoding="utf-8").read()
    t = re.sub(r"<!--texas-->.*?<!--/texas-->", "", t, flags=re.S)
    open(pth, "w", encoding="utf-8").write(t + chr(10).join(h))


if __name__ == "__main__":
    main()
