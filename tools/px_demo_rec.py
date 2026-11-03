# -*- coding: utf-8 -*-
"""pixelfx 放开版图鉴演示录像（协调人 11-03：用户要看实际画面，按图鉴详情页的技能演示录）：game/tests/px_demo_rec.tscn 跑图鉴演示（demo_op），
每招按 E0 → E1 → E2 各一段（图鉴的阶段 + 模式：普攻 = 3、技能 = 0–2、终结技 = 4「演示终结技」），原速 30 帧（--fixed-fps 30，每帧存图），
--sfxtrace 离线混音效 / 语音 / 配乐（混音同 tools/ult_rec.py），每段左上角标招式名和档位，拼成一个 mp4。经 godot_runner 启动：屏幕外、不抢焦点、不开音频设备。
镜头与图鉴一致：视口 = 图鉴舞台框 444×388 × K，gallery/demo_zoom × K（同一取景、K 倍分辨率）。
用法：python tools/px_demo_rec.py <干员> [--segs basic:0,1,2/s1:0,1,2/s2:1,2/s3:2/ult:2] [--k 2] [--jobs 2] [--out 文件] [--extra "--bal=…"]
"""
import argparse, glob, json, os, shutil, subprocess, sys, wave
import numpy as np
from concurrent.futures import ThreadPoolExecutor
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
import imageio_ffmpeg
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FF = imageio_ffmpeg.get_ffmpeg_exe()
ap = argparse.ArgumentParser()
ap.add_argument("op")
ap.add_argument("--segs", default="basic:0,1,2/s1:0,1,2/s2:1,2/s3:2/ult:2")
ap.add_argument("--k", type=int, default=2)
ap.add_argument("--jobs", type=int, default=2)
ap.add_argument("--out", default="")
ap.add_argument("--tmp", default=os.path.join(ROOT, "build", "px_demo_rec"))
ap.add_argument("--extra", default="")
a = ap.parse_args()
a.tmp = os.path.abspath(a.tmp)   # Godot 按 game/ 解析相对路径
MODE = {"basic": 3, "s1": 0, "s2": 1, "s3": 2, "ult": 4}
SECS = {"basic": 4.0, "s1": 6.5, "s2": 7.0, "s3": 7.5, "ult": 10.0}
DZ = 0.68   # balance.json gallery/demo_zoom 缺省
SR = 44100
_dec = {}


def _decode(path):
    """任意音频文件 → 44.1k 单声道 float（ffmpeg 解码，缓存）；缺文件返回 None"""
    if path not in _dec:
        if not os.path.exists(path):
            _dec[path] = None
        else:
            r = subprocess.run([FF, "-loglevel", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"], capture_output=True)
            _dec[path] = np.frombuffer(r.stdout, dtype=np.float32).astype(np.float64) if r.returncode == 0 else None
    return _dec[path]


def _res(p):
    return os.path.join(ROOT, "game", p[len("res://"):].replace("/", os.sep)) if p.startswith("res://") else p


def mix_audio(tr, mus, n_frames):
    """SFXTRACE（音效 / 语音事件）+ MUSTRACE（逐帧配乐采样）→ 单声道 44.1k。增益 = 播放器音量 + 所在总线音量。
    测试局把各总线压到 -80（静音），记录里的总线音量不能用：按玩家缺省设置算（settings.gd：配乐 0.8 / 音效 0.9 / 语音 0.8）"""
    buses = {"Music": 20 * np.log10(0.8), "SFX": 20 * np.log10(0.9), "Voice": 20 * np.log10(0.8)}
    n = int((n_frames / 30.0 + 0.5) * SR)
    fx = np.zeros(n)
    f0 = tr["frame0"]
    for fr, name, vol, pitch in tr["trace"]:
        if name.startswith("vduck:"):
            continue
        if name.startswith("voice:"):
            x, bus = _decode(os.path.join(ROOT, "game", "audio", "voice", name[6:] + ".ogg")), "Voice"
        else:
            x, bus = _decode(os.path.join(ROOT, "game", "audio", "sfx", name + ".wav")), "SFX"
        if x is None or len(x) < 2:
            continue
        idx = np.arange(0, len(x) - 1, float(pitch))
        y = np.interp(idx, np.arange(len(x)), x) * 10 ** ((float(vol) + float(buses.get(bus, 0.0))) / 20.0)
        at = int((fr - f0) / 30.0 * SR)
        if at < 0 or at >= n:
            continue
        j = min(n, at + len(y))
        fx[at:j] += y[: j - at]
    mu = np.zeros(n)
    cut = np.full(n, 20000.0)
    pos = {}
    step = SR // 30
    mg = 10 ** (float(buses.get("Music", 0.0)) / 20.0)
    for fr, hz, ents in mus.get("frames", []):
        at = int((fr - f0) / 30.0 * SR)
        if at < 0 or at >= n:
            continue
        cut[at:at + step] = float(hz)
        live = set()
        for path, vol, ppos in ents:
            x = _decode(_res(path))
            if x is None or len(x) < step:
                continue
            live.add(path)
            p0 = pos.get(path, int(float(ppos) * SR) % len(x))   # 第一次出现按播放位置起，之后每帧推进 1/30 秒（与录像钟 1:1）
            seg = np.take(x, np.arange(p0, p0 + step) % len(x))
            j = min(n, at + step)
            mu[at:j] += seg[: j - at] * 10 ** (float(vol) / 20.0) * mg
            pos[path] = (p0 + step) % len(x)
        for k in list(pos):
            if k not in live:
                del pos[k]
    # 配乐低通（Sfx.music_lp，终结技冲击帧压低）：一阶低通，截止频率逐帧取采样值
    a = 1.0 - np.exp(-2.0 * np.pi * np.minimum(cut, SR * 0.45) / SR)
    y = np.empty(n)
    z = 0.0
    mul, al = mu.tolist(), a.tolist()
    for i in range(n):
        z += al[i] * (mul[i] - z)
        y[i] = z
    out = fx + y
    pk = np.abs(out).max() if n else 0.0
    if pk > 0.89:
        out *= 0.89 / pk
    return out, len(mus.get("frames", [])) > 0 and np.abs(y).max() > 1e-4


def write_wav(path, y):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(y, -1, 1) * 32767).astype(np.int16).tobytes())




def names():
    ch = json.load(open(os.path.join(ROOT, "game", "data", "characters", a.op + ".json"), encoding="utf-8"))
    nm = {"basic": "普攻「%s」" % ch.get("attack", {}).get("name", "")}
    for i, s in enumerate(ch.get("skills", [])[:3]):
        nm["s%d" % (i + 1)] = "%s技能「%s」" % ("一二三"[i], s.get("name", ""))
    ut = json.load(open(os.path.join(ROOT, "game", "data", "ult_text.json"), encoding="utf-8")) if os.path.exists(os.path.join(ROOT, "game", "data", "ult_text.json")) else {}
    un = ut.get("ops", {}).get(a.op, {}).get("ult", {}).get("name", "")
    nm["ult"] = "终结技「%s」" % un if un else "终结技"
    return nm


def font(sz):
    for p in (os.path.join(ROOT, "game", "fonts", "ui.ttf"), os.path.join(ROOT, "game", "fonts", "ui_fallback.otf"), "C:/Windows/Fonts/msyh.ttc"):
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)


def one(seg):
    mv, el = seg
    tag = "%s_%s_e%d" % (a.op, mv, el)
    fdir = os.path.join(a.tmp, tag)
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir)
    n = int(SECS[mv] * 30)
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--fixed-fps", "30", "res://tests/px_demo_rec.tscn", "--",
            "--rec_op=" + a.op, "--rec_stage=%d" % el, "--rec_mode=%d" % MODE[mv], "--rec_dir=" + fdir.replace(os.sep, "/"), "--rec_start=1.0", "--rec_n=%d" % n,
            "--rec_w=%d" % (444 * a.k), "--rec_h=%d" % (388 * a.k), "--bal=gallery/demo_zoom=%g" % (DZ * a.k), "--bal=fx/px_unleashed=1", "--sfxtrace"] + a.extra.split()
    o, e, to = GR.run_godot([x for x in args if x], 900)
    got = len(glob.glob(os.path.join(fdir, "rec_*.png")))
    tr = mus = None
    for ln in o.splitlines():
        if ln.startswith("SFXTRACE "):
            tr = json.loads(ln[9:])
        elif ln.startswith("MUSTRACE "):
            mus = json.loads(ln[9:])
    print(tag, "帧", got, "/", n, "声音", "有" if tr else "无", "错误", GR.script_errors(o, e)[:3], "超时" if to else "", flush=True)
    return seg, fdir, got, tr, mus


# 先导入一遍：重导出的帧条（同名改内容）不会在运行时自动重导，不导就录到旧图（11-04 实际踩过）；Godot 只重导 md5 变了的，很快
GR.run_godot([GR.find_godot(), "--headless", "--path", os.path.join(ROOT, "game"), "--import"], 900)
segs = [(mv, int(e)) for part in a.segs.split("/") for mv, es in [part.split(":")] for e in es.split(",")]
os.makedirs(a.tmp, exist_ok=True)
with ThreadPoolExecutor(a.jobs) as ex:
    res = list(ex.map(one, segs))
NM = names()
ft = font(15 * a.k)
parts = []
for (mv, el), fdir, got, tr, mus in res:
    if not got:
        continue
    label = "%s · 精%s" % (NM.get(mv, mv), "零一二"[el]) if mv != "ult" else NM["ult"] + "（不分档）"
    for p in sorted(glob.glob(os.path.join(fdir, "rec_*.png"))):   # 左上角标签（半透明底条）
        im = Image.open(p).convert("RGBA")
        ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(ov)
        bb = d.textbbox((0, 0), label, font=ft)
        d.rectangle((0, 0, bb[2] + 16 * a.k, bb[3] + 10 * a.k), fill=(4, 14, 30, 170))
        d.text((8 * a.k, 4 * a.k), label, font=ft, fill=(228, 238, 246, 255))
        Image.alpha_composite(im, ov).convert("RGB").save(p)
    seg = os.path.join(a.tmp, "%s_%s_e%d.mp4" % (a.op, mv, el))
    wav = os.path.join(fdir, "mix.wav")
    y, _ = mix_audio(tr or {"frame0": 0, "trace": []}, mus or {}, got)
    write_wav(wav, y)
    subprocess.run([FF, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(fdir, "rec_%05d.png"), "-i", wav,
                    "-c:v", "libx264", "-preset", "veryfast", "-crf", "14", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-ar", "44100", "-shortest", seg], check=True)
    parts.append(seg)
lst = os.path.join(a.tmp, "%s_list.txt" % a.op)
open(lst, "w").write("".join("file '%s'\n" % p.replace("\\", "/") for p in parts))
total = sum(SECS[mv] for (mv, el), f, g_, t_, m_ in res if g_)
kbps = min(12000, int(24.0 * 8 * 1024 / max(total, 1.0)) - 160)   # 整条 ≤ 24 MiB
out = a.out or os.path.join(ROOT, "build", "px_demo_rec", "%s_demo.mp4" % a.op)
subprocess.run([FF, "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c:v", "libx264", "-preset", "slow", "-b:v", "%dk" % kbps,
                "-maxrate", "%dk" % int(kbps * 1.3), "-bufsize", "%dk" % (kbps * 2), "-pix_fmt", "yuv420p", "-r", "30", "-c:a", "aac", "-b:a", "160k", out], check=True)
print("demo", out, "%.1f MiB" % (os.path.getsize(out) / 1048576), "段数", len(parts))
