# -*- coding: utf-8 -*-
"""PV 1108 剪辑：按 edit.json 的镜头表逐帧合成（1920×1080 / 竖版 1080×1920，60 帧），配乐 + 实机音效离线混音，ffmpeg 编码。

  python tools/promo/pv.py main  [输出.mp4] [--from 秒 --to 秒] [--preview 秒,秒,…]
  python tools/promo/pv.py vert  [输出.mp4]
  python tools/promo/pv.py small <输入.mp4> <输出.mp4> [MB]      手机看的压缩版（缺省 < 28 MB）

素材：<主仓库>/Claude outputs/pv_1108/clips/<局>_seg_*.mp4（tools/promo/pv_runs.py 在 GCP 上录的 60 帧实机）+ 同名 .sfx.json（这段里真正放出的音效）。
镜头表 edit.json（与本文件同目录）：
  main: [{t0, t1, kind: clip|card|black|title, ...}]
    clip:  src（clips 下文件名）、f（起始帧）、speed（缺省 1）、ramp [源帧 a, 源帧 b, 片中秒 tb]（a→b 线性变速让源帧 b 落在 tb）、
           zoom（放大倍数）、cx / cy（放大中心，0–1）、slow [片中秒起, 倍速]（之后放慢）、cap {text, sub, col}、flash（开头闪白帧数）、
           lp（这一镜配乐低通）、sil（最后 n 秒压暗成剪影：最终 Boss 一闪）
    card:  card = op:<干员> | text
  vert: 同上（画面裁中间 9:16），字幕位置挪到中部偏上
"""
import json, math, os, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fx
from fx import W, H, CYAN, PURPLE, WHITE, INK
import cards
import music

FPS = 60
MAIN = cards.MAIN
PVD = os.path.join(MAIN, "Claude outputs", "pv_1108")
CLIPS = os.path.join(PVD, "clips")
WORK = os.path.join(PVD, "work")
SFXD = os.path.join(fx.WT, "game", "audio", "sfx")
SR = 48000


def ffmpeg():
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


# ---------------------------------------------------------------- 读帧
class Reader:
    """顺序读一个 mp4 的帧（只往前；要往回读就重开）"""

    def __init__(self, path):
        self.path = path
        self.p = None
        self.i = -1
        self.cur = None

    def _open(self, start):
        if self.p:
            self.p.kill()
        ss = max(0, start - 2) / FPS
        self.p = subprocess.Popen([ffmpeg(), "-v", "error", "-ss", "%.4f" % ss, "-i", self.path, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                                  stdout=subprocess.PIPE, bufsize=W * H * 3 * 4)
        self.i = int(round(ss * FPS)) - 1
        self.cur = None

    def get(self, k):
        k = max(0, k)
        if self.p is None or k < self.i or k > self.i + 600:
            self._open(k)
        while self.i < k:
            b = self.p.stdout.read(W * H * 3)
            if len(b) < W * H * 3:
                return self.cur if self.cur is not None else np.zeros((H, W, 3), np.uint8)
            self.cur = np.frombuffer(b, np.uint8).reshape(H, W, 3)
            self.i += 1
        return self.cur

    def close(self):
        if self.p:
            self.p.kill()
            self.p = None


_readers = {}


def reader(src):
    if src not in _readers:
        for r in list(_readers.values()):
            r.close()
        _readers.clear()
        _readers[src] = Reader(os.path.join(CLIPS, src))
    return _readers[src]


# ---------------------------------------------------------------- 时间映射
def src_frame(sh, T):
    """片中秒 T → 源帧（浮点）"""
    lt = T - sh["t0"]
    if "ramp" in sh:
        a, b, tb = sh["ramp"]
        la = tb - sh["t0"]
        if lt <= la:
            return a + (b - a) * (lt / la) if la > 0 else b
        return b + (lt - la) * FPS * sh.get("after", 1.0)
    sp = sh.get("speed", 1.0)
    f = sh["f"] + lt * FPS * sp
    if "slow" in sh:
        ts, k = sh["slow"]
        lts = ts - sh["t0"]
        if lt > lts:
            f = sh["f"] + lts * FPS * sp + (lt - lts) * FPS * k
    return f


def frame_time_map(sh, t_list):
    return [src_frame(sh, T) for T in t_list]


# ---------------------------------------------------------------- 画面处理
def zoom_crop(arr, z, cx=0.5, cy=0.5, ow=W, oh=H):
    """以 (cx, cy) 为中心放大 z 倍裁成 ow×oh（竖版：先在源上裁 ow/oh 比例的中间条）"""
    h, w = arr.shape[:2]
    asp = ow / oh
    ch = h / z
    cw = ch * asp
    if cw > w / z * 1.0001 and asp >= w / h:
        cw = w / z
        ch = cw / asp
    x0 = min(max(0, cx * w - cw / 2), w - cw)
    y0 = min(max(0, cy * h - ch / 2), h - ch)
    im = Image.fromarray(arr).crop((int(x0), int(y0), int(x0 + cw), int(y0 + ch)))
    if im.size != (ow, oh):
        im = im.resize((ow, oh), Image.LANCZOS if z < 2.5 else Image.BICUBIC)
    return im


def silhouette(im, a):
    """压暗成剪影（a 0–1）：亮部也压到近黑，只留一圈冷色边光"""
    if a <= 0:
        return im
    arr = np.asarray(im.convert("RGB")).astype(np.float32)
    lum = arr.mean(2, keepdims=True)
    dark = np.clip(lum * 0.18, 0, 40) * np.array([0.6, 0.9, 1.1])
    edge = np.asarray(im.convert("L").filter(ImageFilter.FIND_EDGES)).astype(np.float32)[..., None] / 255.0
    dark = dark + edge * np.array([40, 140, 160]) * 0.6
    out = arr * (1 - a) + dark * a
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def render_shot(sh, T, ow, oh, vert):
    lt = T - sh["t0"]
    dur = sh["t1"] - sh["t0"]
    k = sh["kind"]
    if k == "black":
        return Image.new("RGB", (ow, oh), (0, 0, 0))
    if k == "title":
        return cards.card_title(lt, short=vert, vw=ow, vh=oh).convert("RGB")
    if k == "card":
        im = cards.card_operator(lt, sh["card"][3:], dur)
        if vert:
            im = im.crop(((W - int(H * ow / oh)) // 2 + 260, 0, (W - int(H * ow / oh)) // 2 + 260 + int(H * ow / oh), H)).resize((ow, oh), Image.LANCZOS)
        return im.convert("RGB")
    # clip
    f = src_frame(sh, T)
    arr = reader(sh["src"]).get(int(round(f)) + 0)
    z = sh.get("zoom", 1.0)
    pz = sh.get("push", 0.0) * min(1.0, lt / max(0.01, dur))   # 缓推镜
    im = zoom_crop(arr, z * (1 + pz), sh.get("cx", 0.5), sh.get("cy", 0.5), ow, oh)
    if sh.get("sil"):
        im = silhouette(im, float(sh["sil"]))
    if sh.get("dim_until", 0) > lt:
        im = Image.fromarray((np.asarray(im) * 0.25).astype(np.uint8))
    return im


def apply_fx(im, sh, T, ow, oh, vert):
    lt = T - sh["t0"]
    dur = sh["t1"] - sh["t0"]
    fl = sh.get("flash", 0)
    if fl and lt * FPS < fl:
        a = 1.0 - lt * FPS / fl
        im = Image.blend(im, Image.new("RGB", im.size, (255, 255, 255)), 0.85 * a)
    if sh.get("inv") and lt * FPS < sh["inv"]:
        im = Image.fromarray(255 - np.asarray(im))
    cap = sh.get("cap")
    if cap:
        c0 = cap.get("at", 0.0)
        if lt >= c0:
            base = im.convert("RGBA")
            col = tuple(cap.get("col", CYAN))
            y = int(oh * (0.36 if vert else 0.80))
            cards.caption(base, lt - c0, cap["text"], cap.get("sub", ""), y=y, col=col, dur=dur - c0)
            im = base.convert("RGB")
    sb = sh.get("slash_in")
    if sb and lt < sb:
        base = im.convert("RGBA")
        fx_slash(base, lt, sb, ow, oh, out=True)
        im = base.convert("RGB")
    so = sh.get("slash_out")
    if so and dur - lt < so:
        base = im.convert("RGBA")
        fx_slash(base, so - (dur - lt), so, ow, oh, out=False)
        im = base.convert("RGB")
    return im


def fx_slash(base, t, dur, ow, oh, out):
    d = ImageDraw.Draw(base)
    cols = [CYAN + (255,), WHITE + (255,), INK + (255,)]
    sk = math.tan(-0.32) * oh
    for i, c in enumerate(cols):
        u = fx.ease_out((t - i * 0.03) / max(0.01, dur - 0.06))
        if out:
            x0, x1 = -300 + (ow + 700) * u, ow + 400
        else:
            x0, x1 = -400, -400 + (ow + 800) * u
        if x1 > x0:
            d.polygon([(x0, 0), (x1, 0), (x1 + sk, oh), (x0 + sk, oh)], fill=c)


# ---------------------------------------------------------------- 音频
_wav = {}


def load_sfx(name):
    if name not in _wav:
        p = os.path.join(SFXD, name + ".wav")
        if not os.path.exists(p):
            _wav[name] = None
        else:
            import soundfile as sf
            x, sr = sf.read(p, always_2d=True)
            x = x.mean(1)
            if sr != SR:
                idx = np.arange(0, len(x) - 1, sr / SR)
                x = np.interp(idx, np.arange(len(x)), x)
            _wav[name] = x
    return _wav[name]


def sfx_track(shots, total):
    out = np.zeros(int((total + 2) * SR))
    for sh in shots:
        if sh["kind"] != "clip" or sh.get("mute"):
            continue
        js = os.path.join(CLIPS, sh["src"][:-4] + ".sfx.json")
        if not os.path.exists(js):
            continue
        ev = json.load(open(js, encoding="utf-8"))["sfx"]
        # 片中每帧对应的源帧：反查事件落在片中哪一刻
        n = int(round((sh["t1"] - sh["t0"]) * FPS))
        ts = [sh["t0"] + i / FPS for i in range(n)]
        fs = np.array(frame_time_map(sh, ts))
        if len(fs) < 2:
            continue
        g = 10 ** (sh.get("sfx_db", 0.0) / 20)
        for fr, name, vol, pitch in ev:
            if name.startswith(("voice:", "vduck:")):
                continue   # 无人声：干员语音不进
            if fr < fs.min() or fr > fs.max():
                continue
            i = int(np.argmin(np.abs(fs - fr)))
            if abs(fs[i] - fr) > 1.5 * max(1.0, abs(fs[min(i + 1, len(fs) - 1)] - fs[i])):
                continue
            x = load_sfx(name)
            if x is None:
                continue
            idx = np.arange(0, len(x) - 1, pitch)
            y = np.interp(idx, np.arange(len(x)), x) * 10 ** (vol / 20.0) * g
            at = int(ts[i] * SR)
            j = min(len(out), at + len(y), int(sh["t1"] * SR + 0.25 * SR))
            if j > at:
                out[at:j] += y[: j - at]
    return out


def mix(shots, total, out_wav, vert=False):
    lp = [(s["t0"], s["t1"]) for s in shots if s.get("lp")]
    m = music.build(os.path.join(WORK, "music_%s.wav" % ("vert" if vert else "main")), lp=lp,
                    segs=music.SEGS_VERT if vert else None, tail_fade=1.2 if vert else music.TAIL_FADE)[: int(total * SR)]
    s = sfx_track(shots, total)[: len(m)]
    pk = np.percentile(np.abs(s), 99.9) if np.any(s) else 1.0
    s = s / max(pk, 1e-6) * 0.42
    s = np.tanh(s * 1.2) / 1.2
    y = m * 0.78 + s[:, None]
    y *= 0.95 / max(1e-6, np.abs(y).max())
    import soundfile as sf
    sf.write(out_wav, y.astype(np.float32), SR)
    return out_wav


# ---------------------------------------------------------------- 主流程
def load_edit():
    return json.load(open(os.path.join(HERE, "edit.json"), encoding="utf-8"))


def render(which, out, t_from=None, t_to=None, preview=None):
    ed = load_edit()
    shots = ed[which]
    vert = which == "vert"
    ow, oh = (1080, 1920) if vert else (W, H)
    total = shots[-1]["t1"]
    os.makedirs(WORK, exist_ok=True)
    if preview:
        ims = []
        for T in preview:
            sh = next(s for s in shots if s["t0"] <= T < s["t1"])
            im = apply_fx(render_shot(sh, T, ow, oh, vert), sh, T, ow, oh, vert)
            ims.append(im)
        cols = 4
        tw, th = (480, 270) if not vert else (216, 384)
        sheet = Image.new("RGB", (cols * tw, ((len(ims) + cols - 1) // cols) * th))
        for i, im in enumerate(ims):
            sheet.paste(im.resize((tw, th)), ((i % cols) * tw, (i // cols) * th))
        sheet.save(out, quality=88)
        print(out)
        return
    wav = mix(shots, total, os.path.join(WORK, which + ".wav"), vert)
    f0 = int((t_from or 0) * FPS)
    f1 = int(round((t_to or total) * FPS))
    enc = subprocess.Popen([ffmpeg(), "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (ow, oh), "-r", str(FPS), "-i", "-",
                            "-ss", "%.4f" % (f0 / FPS), "-i", wav, "-map", "0:v", "-map", "1:a", "-c:v", "libx264", "-preset", "slow", "-crf", "16",
                            "-pix_fmt", "yuv420p", "-profile:v", "high", "-c:a", "aac", "-b:a", "256k", "-shortest", "-movflags", "+faststart", out],
                           stdin=subprocess.PIPE)
    for i in range(f0, f1):
        T = i / FPS
        sh = next((s for s in shots if s["t0"] <= T < s["t1"]), shots[-1])
        im = apply_fx(render_shot(sh, T, ow, oh, vert), sh, T, ow, oh, vert)
        enc.stdin.write(np.asarray(im.convert("RGB")).tobytes())
        if i % 300 == 0:
            print("  %5.1f 秒" % T, flush=True)
    enc.stdin.close()
    enc.wait()
    print(out)


def small(src, dst, mb=28.0):
    dur = float(subprocess.run([ffmpeg(), "-i", src], capture_output=True, text=True, errors="replace").stderr.split("Duration: ")[1].split(",")[0].split(":")[-1]) + \
        60 * float(subprocess.run([ffmpeg(), "-i", src], capture_output=True, text=True, errors="replace").stderr.split("Duration: ")[1].split(",")[0].split(":")[-2])
    kbps = int(mb * 8192 / dur) - 160
    tmp = dst + ".log"
    for p in (1, 2):
        subprocess.run([ffmpeg(), "-v", "error", "-y", "-i", src, "-c:v", "libx264", "-preset", "slow", "-b:v", "%dk" % kbps, "-pass", str(p),
                        "-passlogfile", tmp, "-pix_fmt", "yuv420p"] + (["-an", "-f", "mp4", os.devnull] if p == 1 else ["-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", dst]))
    for f in os.listdir(os.path.dirname(dst) or "."):
        if f.startswith(os.path.basename(tmp)):
            os.remove(os.path.join(os.path.dirname(dst) or ".", f))
    print(dst, "%.1f MB" % (os.path.getsize(dst) / 1e6))


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[0] == "small":
        small(a[1], a[2], float(a[3]) if len(a) > 3 else 28.0)
        sys.exit(0)
    which = a[0]
    out = a[1] if len(a) > 1 and not a[1].startswith("--") else os.path.join(PVD, "pv_1108_%s.mp4" % which)
    tf = float(a[a.index("--from") + 1]) if "--from" in a else None
    tt = float(a[a.index("--to") + 1]) if "--to" in a else None
    pv = [float(x) for x in a[a.index("--preview") + 1].split(",")] if "--preview" in a else None
    render(which, out, tf, tt, pv)
