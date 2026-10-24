"""音效第三轮（docs/113 §14，10-24 用户：「出钩出锚的都太难听了，去网上看看有没有相关的素材」）：
锁链 / 钩爪 / 落锚的 CC0 现成录音候选。只用 Freesound 上许可为 Creative Commons 0 的条目（页面核对过），
下载的是页面公开的 HQ 试听 mp3（同一条目、同一许可），放主仓库 build/sfx_candidates_1024/freesound/（不进 git、不进包），
截取 + 统一处理后写进试听包 build/sfx_review_1024/cc0/*.ogg，并把「CC0 候选」一节追加到 index.html（和现用版、合成版并排）。

处理（每个候选一样）：截取 → 50 Hz 高通 → 5.5 kHz 4 阶低通（去刺）→ 5 ms 淡入 / 30 ms 淡出 → 按 100 ms RMS 对齐现用文件（出钩 / 收拉 −15.6 dBFS，落地 −9 dBFS），峰值软限幅 −1 dBFS。
先运行 gen_sfx_review_1024.py 再运行本脚本。用户点头后 --apply <候选名>=<游戏文件> 写进 game/audio/sfx/（单声道 44.1 kHz wav）。
"""
import os, re, sys, json, html, subprocess, urllib.request, urllib.parse
import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt

HERE = os.path.dirname(os.path.abspath(__file__))
common = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=HERE, capture_output=True, text=True).stdout.strip()
ROOT = os.path.dirname(os.path.abspath(os.path.join(HERE, common)))
SRC = os.path.join(ROOT, "build", "sfx_candidates_1024", "freesound")
REV = os.path.join(ROOT, "build", "sfx_review_1024")
OUT = os.path.join(REV, "cc0")
SFX = os.path.join(HERE, "..", "audio", "sfx")
SR = 44100

# 角色 -> 候选 (名字, Freesound id, 起点 s, 终点 s, 说明)
CANDS = {
    "throw": ("出钩 / 出锚（掷出去、锁链放出）", -15.6, [
        ("t1", 733608, 4.00, 4.68, "chains_whipAndTighten 前半「甩」：0.68 s 一整下甩链，最完整的一声"),
        ("t2", 733608, 2.25, 2.60, "chains_whipAndTighten 里更短的一下：0.35 s 干脆的抖链"),
        ("t3", 792318, 0.72, 1.15, "钩枪伸出：0.43 s 钩爪射出去的机械 + 链声"),
        ("t4", 541975, 0.00, 0.58, "grappling hook：0.58 s 现成的钩爪音效"),
        ("t5", 675781, 0.55, 1.60, "铁锚入水前锁链往外放：1 s 链越放越快（出锚）"),
    ]),
    "reel": ("收拉（绷紧、拽回）", -15.6, [
        ("r1", 733608, 6.06, 7.34, "chains_whipAndTighten 后半「收紧」：1.3 s 链绷直 + 摩擦"),
        ("r2", 792318, 2.25, 2.93, "钩枪收回：0.7 s 链回卷"),
        ("r3", 386174, 0.30, 1.40, "Chain pulley 750 kg 拉链：1.1 s 重链过滑轮"),
        ("r4", 235959, 0.75, 1.80, "Chain Drag 拖地：1 s 链在地上拖拽、绷紧"),
        ("r5", 405417, 0.00, 1.00, "Pulling Chain：1 s 拉链"),
    ]),
    "slam": ("落锚 / 砸地（锚头落地、链砸地）", -9.0, [
        ("i1", 819711, 1.75, 2.30, "Chain Impact：0.55 s 链砸地一下"),
        ("i2", 871034, 0.00, 0.60, "metal_chain_drop2：0.6 s 一团链掉在金属上"),
        ("i3", 235959, 1.25, 1.75, "Chain Drag 里最响的一下：0.5 s 链拖到头的磕碰"),
        ("i4", 167916, 1.45, 2.05, "Steel chain hard clicking：0.6 s 硬链节磕碰"),
    ]),
}
# 现用 / 合成版的对照（试听包里已有）
NOW = {"throw": ("op_ulpianus_s1", "chain_throw"), "reel": ("op_ulpianus_s3", "chain_reel"), "slam": ("op_ulpianus_big", "charge_impact")}


def get(u, binary=False):
    d = urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": "Mozilla/5.0"}), timeout=60).read()
    return d if binary else d.decode("utf-8")


def fetch(sid):
    """下载一条（已有则读 meta），页面核对许可必须是 CC0"""
    os.makedirs(SRC, exist_ok=True)
    mp = os.path.join(SRC, "meta.json")
    meta = json.load(open(mp, encoding="utf-8")) if os.path.exists(mp) else {}
    if str(sid) in meta and os.path.exists(os.path.join(SRC, "%s.mp3" % sid)):
        return meta[str(sid)]
    s = get("https://freesound.org/search/?" + urllib.parse.urlencode({"q": str(sid), "advanced": 0, "g": 1}))
    user = re.search(r'data-sound-id="%s"\s+data-username="([^"]*)"' % sid, s).group(1)
    pg = get("https://freesound.org/people/%s/sounds/%s/" % (user, sid))
    if "publicdomain/zero/1.0" not in pg:
        raise SystemExit("%s 不是 CC0，停" % sid)
    title = html.unescape(re.search(r'og:title" content="(.*?) by ', pg).group(1))
    mp3 = re.search(r'data-mp3="([^"]+)"', pg).group(1).replace("-lq.mp3", "-hq.mp3")
    open(os.path.join(SRC, "%s.mp3" % sid), "wb").write(get(mp3, True))
    meta[str(sid)] = {"user": user, "title": title, "license": "CC0 1.0", "url": "https://freesound.org/people/%s/sounds/%s/" % (user, sid),
                      "dur": float(re.search(r'data-duration="([\d.]+)"', pg).group(1))}
    json.dump(meta, open(mp, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    return meta[str(sid)]


def load(sid):
    x, sr = sf.read(os.path.join(SRC, "%s.mp3" % sid), dtype="float64")
    if x.ndim > 1:
        x = x.mean(1)
    if sr != SR:
        x = np.interp(np.arange(int(len(x) * SR / sr)) * sr / SR, np.arange(len(x)), x)
    return x


def rms100(x):
    n = int(0.1 * SR)
    c = np.cumsum(np.r_[0, x ** 2])
    return 10 * np.log10(np.max(c[n:] - c[:-n]) / n + 1e-12) if len(x) > n else 10 * np.log10(np.sum(x ** 2) / n + 1e-12)


def process(x, target_rms):
    x = sosfilt(butter(1, 50, btype="high", fs=SR, output="sos"), x)
    x = sosfilt(butter(4, 5500, fs=SR, output="sos"), x)
    fi, fo = int(0.005 * SR), int(0.03 * SR)
    x[:fi] *= np.linspace(0, 1, fi)
    x[-fo:] *= np.linspace(1, 0, fo)
    x = x * 10 ** ((target_rms - rms100(x)) / 20)
    cap = 10 ** (-1 / 20)
    if np.abs(x).max() > cap:
        x = cap * np.tanh(x / cap)
    return x


def stats(x):
    s = np.abs(np.fft.rfft(x)) ** 2
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return len(x) / SR, 20 * np.log10(np.abs(x).max() + 1e-9), rms100(x), (s * f).sum() / (s.sum() + 1e-12), s[f >= 4000].sum() / (s.sum() + 1e-12)


def build():
    os.makedirs(OUT, exist_ok=True)
    rows = {}
    for role, (_, tgt, items) in CANDS.items():
        for name, sid, a, b, note in items:
            m = fetch(sid)
            x = process(load(sid)[int(a * SR):int(b * SR)].copy(), tgt)
            sf.write(os.path.join(OUT, name + ".ogg"), x.astype(np.float32), SR, format="OGG", subtype="VORBIS")
            rows[name] = (m, a, b, note, stats(x))
            print(name, sid, m["user"], m["license"], "%.2fs pk%.1f rms%.1f cen%.0f hf%.0f%%" % (stats(x)[0], stats(x)[1], stats(x)[2], stats(x)[3], stats(x)[4] * 100))
    return rows


def page(rows):
    def aud(p):
        return '<audio controls preload="none" src="%s"></audio>' % p
    h = ["<!--cc0-->", "<h1>四、CC0 现成录音候选（docs/113 §14）</h1>",
         "<p><small>全部是 Freesound 上许可为 Creative Commons 0 的录音（公有领域，可商用、不必署名；接入时仍在致谢页写明来源）。截取后统一：50 Hz 高通 + 5.5 kHz 低通（去刺）+ 响度对齐现用文件。"
         "每行的「来源」是原页面，点开可核对许可和原声。</small></p>"]
    for role, (title, tgt, items) in CANDS.items():
        old, syn = NOW[role]
        h.append("<h2>%s</h2><table><tr><th>候选</th><th>试听</th><th>来源 / 作者 / 许可</th><th>截取与听感提示</th></tr>" % title)
        h.append('<tr><td>现用版</td><td>%s</td><td><small>游戏里现在的 %s</small></td><td></td></tr>' % (aud("%s_before.ogg" % {"throw": "chain_throw", "reel": "chain_reel", "slam": "charge_impact"}[role]), old))
        h.append('<tr><td>合成版（第一轮）</td><td>%s</td><td><small>程序合成，无外部素材</small></td><td></td></tr>' % aud("%s_after.ogg" % syn))
        for name, sid, a, b, note in items:
            m, _, _, _, st = rows[name]
            h.append('<tr><td>%s</td><td>%s</td><td><small><a href="%s" style="color:#9cd">%s</a><br>%s · %s</small></td><td><small>%s 的 %.2f–%.2f s<br>%s<br>%.2fs / 峰值 %.1f / RMS %.1f / 重心 %.0f Hz / 4 kHz 以上 %.0f%%</small></td></tr>'
                     % (name, aud("cc0/%s.ogg" % name), m["url"], html.escape(m["title"]), m["user"], m["license"], sid, a, b, html.escape(note), st[0], st[1], st[2], st[3], st[4] * 100))
        h.append("</table>")
    h.append("<!--/cc0-->")
    p = os.path.join(REV, "index.html")
    s = open(p, encoding="utf-8").read()
    s = re.sub(r"<!--cc0-->.*?<!--/cc0-->", "", s, flags=re.S)
    open(p, "w", encoding="utf-8").write(s + "\n".join(h))


if __name__ == "__main__":
    page(build())
