# -*- coding: utf-8 -*-
"""Suno 整首分层配乐演示（docs/164）：按 sfx.gd 同一套调度（小节线切层 / 战斗换段等小节线 / 淡入淡出速率 / vol_target）离线渲染一段带声音的 mp4。

为什么离线：自动测试 / 录制的 Godot 一律静音 Master（AGENTS.md 硬规定，不能加绕过的测试模式），所以没法从游戏里直接录出声音；
这里把 sfx.gd 的调度逻辑原样搬到 Python（同样的 bpm / 首拍偏移 / BAR_AHEAD / STEM_IN / STEM_OUT / 组淡入淡出速率），用同一批 ogg 混出来，
画面是各层音量条 + 当前事件。调度本身的正确性由 tests/suno_layers_test（check.py --only suno_layers）在真实 Sfx 上验证。

用法：python tools/suno_layers_demo.py [输出目录]      缺省写 build/suno_layers/
"""
import json, os, subprocess, sys
import numpy as np
import soundfile as sf
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MUS = os.path.join(ROOT, "game", "audio", "music")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "suno_layers")
os.makedirs(OUT, exist_ok=True)
SR = 32000
STEM_IN, STEM_OUT, BAR_AHEAD, VOL_DB = 10.0, 0.5, 0.1, -4.0
meta = json.load(open(os.path.join(MUS, "suno_layers.json"), encoding="utf-8"))
audio = {}
for t in ("battle1", "battle2", "boss", "final"):
    audio[t] = [sf.read(os.path.join(MUS, f + ".ogg"), dtype="float32", always_2d=True)[0] for f in meta[t]["files"]]

# 事件表（秒）：(时间, 动作, 参数)
EVENTS = [(0.0, "play", "battle1"), (6.0, "lv", 1), (12.0, "lv", 2), (20.0, "lv", 0), (26.0, "play", "battle2"), (34.0, "lv", 2),
          (42.0, "play", "boss"), (54.0, "play", "final"), (64.0, "p2", True)]
CAP = {"battle1": "战斗一 · 平静（只有底层）", "battle2": "战斗换段：等当前曲小节线再换", "boss": "Boss 登场（整曲一层）", "final": "最终 Boss 一阶段（p1）"}
END = 76.0
DT = 0.01
n_steps = int(END / DT)
names = list(audio)
state = {t: {"gv": 0.0, "r_in": 0.8, "r_out": 0.6, "on": [0.0] * len(audio[t]), "sv": [0.0] * len(audio[t]), "t0": 0.0} for t in names}
cur = ""
pending = None
lv, p2 = 0, False
clock_beat = -1
gain = {t: np.zeros((n_steps, len(audio[t]))) for t in names}
caption = [""] * n_steps
cur_log = [""] * n_steps
bar_marks = []


def want(t, i):
    if t.startswith("battle"):
        return 1.0 if [True, lv >= 1, lv >= 2][i] else 0.0
    if t == "final":
        return 1.0 if i == 0 or p2 else 0.0
    return 1.0


def lay_pos(t, now):
    return (now - state[t]["t0"]) % meta[t]["len"]


def start(t, now, fi, fo, frm=0.0):
    global cur, clock_beat
    if cur != "" and cur != t:
        state[cur]["r_out"] = fo
    cur = t
    clock_beat = -1
    state[t]["r_in"] = fi
    state[t]["r_out"] = 0.6
    for i in range(len(state[t]["on"])):
        state[t]["on"][i] = want(t, i)
        state[t]["sv"][i] = state[t]["on"][i]
    state[t]["t0"] = now - frm


ev = list(EVENTS)
label = ""
for k in range(n_steps):
    now = k * DT
    while ev and ev[0][0] <= now + 1e-9:
        _, act, par = ev.pop(0)
        if act == "play":
            if par == cur or (pending and pending["track"] == par):
                pass
            elif par.startswith("battle") and cur.startswith("battle"):
                m = meta[cur]
                bar = 240.0 / m["bpm"]
                pos = lay_pos(cur, now) - m["offset"]
                nxt = np.ceil(pos / bar + 0.0001) * bar - pos
                pending = {"track": par, "at": now + max(nxt, 0.05), "fi": 6.0, "fo": 6.0}
                label = "战斗换段：挂起，等当前曲下一条小节线（%.2f 秒后）" % max(nxt, 0.05)
            else:
                start(par, now, 0.8, 0.6)
                label = {"battle1": "进战斗：平静（只有底层）", "boss": "Boss 登场：整曲一层，旧曲 0.6 秒淡出", "final": "最终 Boss 一阶段：p1（主唱 + 底层）"}.get(par, par)
        elif act == "lv":
            lv = par
            label = {0: "回到平静：退层等小节线、慢慢收", 1: "交战：打击乐在小节线上进", 2: "激战：驱动层（吉他 / 铜管）在小节线上进"}[par]
        elif act == "p2":
            p2 = par
            label = "最终 Boss 半血：二阶段 p2（鼓 / 吉他 / 铜管 / 打击乐）在小节线上叠入"
    if pending and now >= pending["at"]:
        start(pending["track"], now, pending["fi"], pending["fo"], now - pending["at"])
        label = "已换到 %s（新曲在小节线上从头开）" % pending["track"]
        pending = None
    if cur in meta:
        m = meta[cur]
        pos = lay_pos(cur, now)
        beat = int(np.floor((pos - m["offset"] + BAR_AHEAD) * m["bpm"] / 60.0))
        if beat != clock_beat:
            clock_beat = beat
            for i in range(len(state[cur]["on"])):
                w = want(cur, i)
                if w != state[cur]["on"][i] and beat % 4 == 0:
                    state[cur]["on"][i] = w
                    bar_marks.append((now, cur, i, w))
    for t in names:
        s = state[t]
        wnt = 1.0 if t == cur else 0.0
        rate = s["r_in"] if wnt > s["gv"] else s["r_out"]
        s["gv"] = float(np.clip(s["gv"] + np.sign(wnt - s["gv"]) * min(abs(wnt - s["gv"]), DT * rate), 0.0, 1.0))
        for i in range(len(s["sv"])):
            r = STEM_IN if s["on"][i] > s["sv"][i] else STEM_OUT
            d = s["on"][i] - s["sv"][i]
            s["sv"][i] += np.sign(d) * min(abs(d), DT * r)
            gain[t][k, i] = s["gv"] * s["sv"][i]
    caption[k] = label
    cur_log[k] = cur
# 一次也没有淡完的曲子的开播时刻：t0 以事件为准（state 里记了最后一次）；渲染时需要每个时间段各自的 t0，这里简化为按 play 事件逐段重放
# ——为了让声音与上面的状态严格一致，重新按事件顺序记录 t0 历史
t0_hist = {t: [] for t in names}
cur2, ev2, pend2 = "", list(EVENTS), None
for k in range(n_steps):
    now = k * DT
    while ev2 and ev2[0][0] <= now + 1e-9:
        _, act, par = ev2.pop(0)
        if act == "play" and par != cur2 and not (pend2 and pend2[0] == par):
            if par.startswith("battle") and cur2.startswith("battle"):
                m = meta[cur2]
                bar = 240.0 / m["bpm"]
                tt = t0_hist[cur2][-1]
                pos = ((now - tt) % m["len"]) - m["offset"]
                nxt = np.ceil(pos / bar + 0.0001) * bar - pos
                pend2 = (par, now + max(nxt, 0.05))
            else:
                t0_hist[par].append(now)
                cur2 = par
    if pend2 and now >= pend2[1]:
        t0_hist[pend2[0]].append(pend2[1])
        cur2 = pend2[0]
        pend2 = None
# 渲染
total = int(END * SR)
mix = np.zeros((total, 2), dtype=np.float32)
tt = np.arange(total) / SR
step_idx = np.minimum((tt / DT).astype(int), n_steps - 1)
for t in names:
    g_all = gain[t]
    for seg, t0 in enumerate(t0_hist[t]):
        t1 = t0_hist[t][seg + 1] if seg + 1 < len(t0_hist[t]) else END
        # 该曲这一段出声的时间范围：从 t0 到（淡出结束 ≈ 下一首开播 + 2 秒 / 或结束）
        a, b = int(t0 * SR), min(total, int((t1 + (2.5 if seg + 1 == len(t0_hist[t]) else 0.0)) * SR))
        b = min(b, total)
        if b <= a:
            continue
        idx = (np.arange(a, b) - a) % len(audio[t][0])
        for i, y in enumerate(audio[t]):
            gg = np.interp(np.arange(a, b) / SR, np.arange(n_steps) * DT, g_all[:, i]).astype(np.float32)
            if seg + 1 < len(t0_hist[t]):   # 被换走之后同一首再回来：只在自己这一段内计入
                gg[(np.arange(a, b) / SR) > t1 + 2.5] = 0.0
            mix[a:b] += y[idx] * gg[:, None]
mix *= 10 ** (VOL_DB / 20)
mix = np.clip(mix, -0.944, 0.944)   # Master 硬限幅 -0.5 dB
sf.write(os.path.join(OUT, "suno_layers_demo.wav"), mix, SR, subtype="PCM_16")
# 画面
W, H, FPS = 960, 540, 30
try:
    FNT = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 22)
    FNS = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 16)
except Exception:
    FNT = FNS = ImageFont.load_default()
frames_dir = os.path.join(OUT, "frames")
os.makedirs(frames_dir, exist_ok=True)
LAYER_NAMES = {"battle1": ["底层", "打击乐", "驱动"], "battle2": ["底层", "打击乐", "驱动"], "boss": ["整曲"], "final": ["p1 一阶段", "p2 二阶段"]}
TRACK_NAMES = {"battle1": "战斗一", "battle2": "战斗二", "boss": "中期 Boss", "final": "最终 Boss"}
COL = [(80, 200, 230), (240, 180, 70), (240, 90, 110)]
for f in range(int(END * FPS)):
    k = min(int(f / FPS / DT), n_steps - 1)
    im = Image.new("RGB", (W, H), (8, 14, 22))
    d = ImageDraw.Draw(im)
    d.text((24, 14), "Suno 整首分层配乐（离线渲染 · 同 sfx.gd 调度）   %02d:%04.1f" % (int(f / FPS) // 60, (f / FPS) % 60), font=FNT, fill=(220, 235, 245))
    y = 64
    for t in names:
        act = cur_log[k] == t
        d.text((24, y), TRACK_NAMES[t], font=FNT, fill=(255, 240, 170) if act else (110, 125, 140))
        for i, ln in enumerate(LAYER_NAMES[t]):
            v = float(gain[t][k, i])
            x0 = 200 + i * 240
            d.rectangle([x0, y + 4, x0 + 200, y + 26], outline=(60, 80, 95))
            d.rectangle([x0, y + 4, x0 + int(200 * v), y + 26], fill=COL[i % 3] if act or v > 0.02 else (40, 55, 65))
            d.text((x0 + 4, y + 28), ln, font=FNS, fill=(150, 165, 180))
        y += 82
    d.rectangle([0, H - 72, W, H], fill=(14, 26, 38))
    d.text((24, H - 62), caption[k], font=FNT, fill=(255, 240, 170))
    d.text((24, H - 30), "条 = 该层当前实际音量（组音量 × 层音量）；切层只落在小节线上", font=FNS, fill=(140, 160, 175))
    im.save(os.path.join(frames_dir, "f%05d.png" % f))
import imageio_ffmpeg
ff = imageio_ffmpeg.get_ffmpeg_exe()
mp4 = os.path.join(OUT, "suno_layers_demo.mp4")
subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(frames_dir, "f%05d.png"), "-i", os.path.join(OUT, "suno_layers_demo.wav"),
                "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "23", "-c:a", "aac", "-b:a", "160k", "-shortest", "-movflags", "+faststart", mp4], check=True)
print("写出", mp4, "%.1f MB" % (os.path.getsize(mp4) / 1e6), "小节线切层事件", len(bar_marks))
for b in bar_marks[:12]:
    print("  t=%.2f %s 层%d -> %s" % b)
