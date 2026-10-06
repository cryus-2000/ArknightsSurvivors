# -*- coding: utf-8 -*-
"""宣传片（2026-10-06）：按 art/promo/trailer/shots.json 的镜头表录帧、拼片、配乐、编码、校验。分镜见 art/promo/trailer/storyboard.md。

  python tools/promo_trailer.py capture [run,…]   确定性批跑（--fixed-fps 30 + --realtime，每帧 = 1/30 秒游戏时间）录原始帧到
                                                 build/trailer/raw/<run>/rec_<beat>/f####.png（不入库）；走 tools/godot_runner，复用 promo_shots.gd
  python tools/promo_trailer.py scout <run>       同一局先探路：只按 promo_shots.gd 的场面检测截静帧、打印各场面的游戏秒，用来填镜头表的 t0
  python tools/promo_trailer.py music             按镜头表 music 段把 game/audio/music 的乐句拼到片长，末尾 1 秒淡出 → build/trailer/music.wav
  python tools/promo_trailer.py build             拼 1920×1080 横版 + 1080×1920 竖版帧序列（字幕 / 片头 / 片尾 / 手机段），然后编码、出 GIF、联络表、校验
  python tools/promo_trailer.py encode            只编码（帧已拼好时；ffmpeg 来自 PATH 或 imageio_ffmpeg，都没有就退到 OpenCV 无声草稿）
  python tools/promo_trailer.py verify            帧数 / 黑帧 / 重复帧 / 文件大小
  python tools/promo_trailer.py gif               只重出 itch 页的 1280×720 循环 GIF

镜头表（shots.json）：
  runs:  run 名 → {args: 游戏参数, res: 分辨率, only: promo_shots.gd 的检测类别}
  beats: 顺序镜头 → {id, kind: clip|still|title|end|phone, run, t0, dur（秒）, caption, label, trans: cut|xfade, fade_in/out, step}
         clip 从 raw/<run>/rec_<id>/ 取帧；still 取 raw/<run>/<src> 一张静帧缓慢推近；title / end 用 art/promo 主视觉与文案；
         phone 把 19.5:9 的触屏帧放进手机外框
  vertical: 竖版用哪些镜头（id 与时长），居中裁 1080 宽、字幕挪到上方安全区
  music: 曲目、乐句顺序与各句的层
"""
import os, sys, json, glob, shutil, subprocess, time
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
PROMO = os.path.join(ROOT, "art", "promo")
SHOTS = os.path.join(PROMO, "trailer", "shots.json")
OUT = os.path.join(ROOT, "build", "trailer")
RAW = os.path.join(OUT, "raw")
FPS = 30
W, H = 1920, 1080
VW, VH = 1080, 1920
FONT_UI = os.path.join(ROOT, "game", "fonts", "ui.ttf")
FONT_FB = os.path.join(ROOT, "game", "fonts", "ui_fallback.otf")
# docs/37 语义色
CYAN = (54, 226, 220)
GOLD = (244, 192, 78)
TEXT = (236, 240, 244)
SUB = (150, 164, 180)
NAVY = (6, 10, 18)
PANEL = (18, 22, 30)
XFADE = 6          # 交叉叠化帧数
CAP_FADE = 8       # 字幕淡入 / 淡出帧数
SAFE = 0.05        # 字幕安全区（四边 5%）


def font(size, fallback=False):
    return ImageFont.truetype(FONT_FB if fallback else FONT_UI, size)


def load_shots():
    with open(SHOTS, encoding="utf-8") as fh:
        return json.load(fh)


# ---------------------------------------------------------------- 录帧
def _godot_args(gr, run, extra):
    return [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", str(FPS),
            "--resolution", run.get("res", "%dx%d" % (W, H)), "-s", os.path.join(TOOLS, "promo_shots.gd"), "--",
            "--balance", "--realtime", "--nodeath", "--bot=master", "--diff=4"] + list(run["args"]) + extra


def _launch(name, run, extra, timeout=3600):
    import godot_runner as gr
    gr.ensure_imported(os.path.join(ROOT, "game"))
    out = os.path.join(RAW, name)
    os.makedirs(out, exist_ok=True)
    args = _godot_args(gr, run, ["--promo_out=" + out.replace(os.sep, "/")] + extra)
    t0 = time.time()
    o, e, to = gr.run_godot(args, timeout)
    with open(os.path.join(out, "run.log"), "w", encoding="utf-8") as fh:
        fh.write(" ".join(args) + "\n\n" + o + "\n----\n" + e)
    lines = [l for l in o.splitlines() if l.startswith("PROMO")]
    print(name, "wall %ds" % (time.time() - t0), "timeout" if to else "", "errors:", gr.script_errors(o, e)[:3])
    return lines


def cmd_scout(names):
    sh = load_shots()
    for name in names:
        run = sh["runs"][name]
        lines = _launch(name + "_scout", run, ["--promo_maxt=%s" % run.get("maxt", 660), "--promo_only=" + run.get("only", "none")])
        print("\n".join(lines))


def cmd_capture(names):
    sh = load_shots()
    for name in names:
        run = sh["runs"][name]
        recs, maxt = [], 0.0
        for b in sh["beats"]:
            if b.get("run") == name and b["kind"] in ("clip", "phone"):   # still 用的是 --promo_only 检测存下的静帧
                recs.append("--promo_rec=%s@%s@%s@1" % (b["id"], b["t0"], b["dur"] + 0.5))   # 多录半秒，叠化 / 裁切有余量
                maxt = max(maxt, b["t0"] + b["dur"] + 1.0)
        # 录帧那一局和探路那一局参数一致（同一套 --promo_only：升级面板的暂停截图也照做），时间线才逐帧相同
        extra = recs + ["--promo_maxt=%s" % maxt, "--promo_only=" + run.get("only", "none")]
        if run.get("nohud"):
            extra.append("--promo_nohud")
        _launch(name, run, extra)
        for b in sh["beats"]:
            if b.get("run") == name:
                n = len(glob.glob(os.path.join(RAW, name, "rec_" + b["id"], "f*.png")))
                print("  %-10s %d 帧（需要 %d）" % (b["id"], n, int(b["dur"] * FPS)))


# ---------------------------------------------------------------- 配乐
def cmd_music(total_s):
    """乐句文件 = 0.1 秒预留 + 8 小节正文 + 1.6 秒余音（docs/21 §54）：按句长 8×240/bpm 叠放，层按 shots.json 指定，末尾 1 秒淡出"""
    import soundfile as sf
    sh = load_shots()
    m = sh["music"]
    mdir = os.path.join(ROOT, "game", "audio", "music")
    seg_len = 8 * 240.0 / m["bpm"]
    sr = 44100
    n_total = int(total_s * sr)
    mix = np.zeros((n_total + sr * 4, 2), dtype=np.float64)
    for i, (seg, layers) in enumerate(m["segments"]):
        at = int(i * seg_len * sr)
        for layer in layers:
            d, r = sf.read(os.path.join(mdir, "%s_%s_%s.ogg" % (m["track"], seg, layer)))
            assert r == sr
            if d.ndim == 1:
                d = np.stack([d, d], 1)
            n = min(len(d), len(mix) - at)
            mix[at:at + n] += d[:n] * float(m.get("gain", 1.0))
    mix = mix[:n_total]
    fade = np.linspace(1.0, 0.0, sr)
    mix[-sr:] *= fade[:, None]
    peak = np.abs(mix).max()
    if peak > 0.95:
        mix *= 0.95 / peak
    os.makedirs(OUT, exist_ok=True)
    p = os.path.join(OUT, "music.wav")
    sf.write(p, mix.astype(np.float32), sr)
    print(p, "%.1f s" % total_s, "peak %.2f" % peak, "segments", [s for s, _ in m["segments"]])
    return p


# ---------------------------------------------------------------- 画面元素
def caption_band(size, text, label, alpha, vertical=False):
    """字幕：深色半透明横带 + 左侧青色竖条 + 青色小标签（docs/37 小标签头）+ 正文；水平居中，横版放底部安全区内（冲刺按键牌之上），竖版放上方安全区（HUD 顶栏之下）"""
    w, h = size
    lay = Image.new("RGBA", size, (0, 0, 0, 0))
    if alpha <= 0.0:
        return lay
    d = ImageDraw.Draw(lay)
    fs = 50 if not vertical else 54
    f = font(fs)
    fl = font(24 if not vertical else 28)
    tw = d.textlength(text, font=f)
    lw = d.textlength(label, font=fl) if label else 0
    pad = 28
    bw = int(max(tw, lw) + pad * 2 + 14)
    bh = fs + (36 if label else 0) + pad * 2 - 10
    x0 = (w - bw) // 2   # 居中：横版避开左下声呐 / 右下编队卡，竖版避开顶部击杀 / 时间
    y1 = int(h * (1 - SAFE)) - 60 if not vertical else int(h * 0.26) + bh
    y0 = y1 - bh
    a = int(255 * alpha)
    d.rectangle((x0, y0, x0 + bw, y1), fill=PANEL + (int(205 * alpha),))
    d.line((x0, y0, x0 + bw, y0), fill=(255, 255, 255, int(28 * alpha)), width=1)   # 顶部一线高光
    d.rectangle((x0, y0, x0 + 6, y1), fill=CYAN + (a,))
    ty = y0 + pad - 8
    if label:
        d.text((x0 + pad + 10, ty), label, font=fl, fill=CYAN + (a,))
        ty += 36
    d.text((x0 + pad + 10, ty), text, font=f, fill=TEXT + (a,))
    return lay


def fit_cover(im, size):
    """等比铺满后居中裁"""
    w, h = size
    k = max(w / im.width, h / im.height)
    im = im.resize((max(w, int(round(im.width * k))), max(h, int(round(im.height * k)))), Image.LANCZOS)
    x0, y0 = (im.width - w) // 2, (im.height - h) // 2
    return im.crop((x0, y0, x0 + w, y0 + h))


def navy_bg(size):
    w, h = size
    im = Image.new("RGB", size, NAVY)
    d = ImageDraw.Draw(im)
    for y in range(h):
        t = 1 - abs(y / max(1, h - 1) - 0.5) * 2
        c = tuple(int(NAVY[i] + (22, 34, 50)[i] * t * 0.6) for i in range(3))
        d.line([(0, y), (w, y)], fill=c)
    return im


def title_card(size, vertical=False):
    """片头：主视觉 keyart_1920x1080；竖版裁人物段放中间，标题用封面同款像素字另写在上方"""
    key = Image.open(os.path.join(PROMO, "keyart_1920x1080.png")).convert("RGB")
    if not vertical:
        return fit_cover(key, size)
    import promo_cover as C
    w, h = size
    im = navy_bg(size)
    crop = key.crop((420, 560, 1500, 1050)).resize((w, int(490 * w / 1080)), Image.LANCZOS)   # 人物段，避开左上标语和右下小字
    im.paste(crop, (0, (h - crop.height) // 2 + 140))
    t1 = C.pixel_text(C.TITLE, 17, 8, (232, 226, 208), (138, 154, 168), outline=(3, 6, 12))
    t2 = C.pixel_text(C.TITLE_EN, 9, 4, CYAN, (30, 120, 130), outline=(3, 6, 12))
    y = int(h * 0.17)
    im.paste(t1, ((w - t1.width) // 2, y), t1)
    im.paste(t2, ((w - t2.width) // 2, y + t1.height + 20), t2)
    return im


def end_card(size, lines, vertical=False):
    import promo_cover as C
    w, h = size
    im = navy_bg(size)
    d = ImageDraw.Draw(im)
    t1 = C.pixel_text(C.TITLE, 17, 7 if not vertical else 8, (232, 226, 208), (138, 154, 168), outline=(3, 6, 12))
    t2 = C.pixel_text(C.TITLE_EN, 9, 3 if not vertical else 4, CYAN, (30, 120, 130), outline=(3, 6, 12))
    block = t1.height + 16 + t2.height + 70 + sum(sz + 26 for _, sz, _ in lines)
    y = (h - block) // 2
    im.paste(t1, ((w - t1.width) // 2, y), t1)
    y += t1.height + 16
    im.paste(t2, ((w - t2.width) // 2, y), t2)
    y += t2.height + 70
    d.line((w // 2 - 160, y - 30, w // 2 + 160, y - 30), fill=CYAN, width=2)
    for txt, sz, col in lines:
        f = font(sz)
        tw = d.textlength(txt, font=f)
        d.text(((w - tw) // 2, y), txt, font=f, fill=col)
        y += sz + 26
    return im


def phone_frame(shot, size, caption, vertical=False):
    """19.5:9 触屏帧放进手机外框（复用 promo_xhs.phone_mock 的画法），信箱进目标画幅"""
    w, h = size
    im = navy_bg(size)
    sw = int(w * (0.78 if not vertical else 0.92))
    sh = int(sw * shot.height / shot.width)
    s = shot.resize((sw, sh), Image.LANCZOS)
    bx, by = (w - sw) // 2, (h - sh) // 2 - (20 if not vertical else 0)
    d = ImageDraw.Draw(im)
    m = 22 if not vertical else 14
    d.rounded_rectangle((bx - m * 2, by - m, bx + sw + m * 2, by + sh + m), radius=40, fill=(8, 10, 14), outline=(138, 154, 168), width=4)
    im.paste(s, (bx, by))
    d.rounded_rectangle((bx - m - 10, by + sh // 2 - 40, bx - m - 4, by + sh // 2 + 40), radius=3, fill=(30, 34, 40))
    return im


# ---------------------------------------------------------------- 拼片
def beat_frames(b, vertical=False):
    """一个镜头的帧（PIL RGB，目标画幅）。clip / phone 从原始帧取；title / end 生成静帧"""
    size = (VW, VH) if vertical else (W, H)
    n = int(round(b["dur"] * FPS))
    if b["kind"] == "title":
        im = title_card(size, vertical)
        return [im] * n
    if b["kind"] == "end":
        lines = [(l, sz, {"cyan": CYAN, "gold": GOLD, "sub": SUB, "text": TEXT}[c]) for l, sz, c in b["lines"]]
        if vertical:
            lines = [(l, int(sz * 1.15), c) for l, sz, c in lines]
        return [end_card(size, lines, vertical)] * n
    if b["kind"] == "still":
        # 静帧 + 缓慢推近（升级面板：批跑里机器人当帧选卡，面板只在 promo_shots.gd 暂停截图那一帧完整出现，录不成连续帧）
        src = sorted(glob.glob(os.path.join(RAW, b["run"], b["src"])))[0]
        im = Image.open(src).convert("RGB")
        if im.size != size:
            im = fit_cover(im, size)
        out = []
        for k in range(n):
            z = 1.0 + (b.get("zoom", 0.04)) * k / max(1, n - 1)
            cw, ch = int(size[0] / z), int(size[1] / z)
            x0, y0 = (size[0] - cw) // 2, (size[1] - ch) // 2
            out.append(im.crop((x0, y0, x0 + cw, y0 + ch)).resize(size, Image.LANCZOS))
        return out
    files = sorted(glob.glob(os.path.join(RAW, b["run"], "rec_" + b["id"], "f*.png")))
    skip = int(round(b.get("skip", 0) * FPS))
    files = files[skip:][::int(b.get("step", 1))][:n]   # step=2：升级面板暂停时原始帧是 60 帧/秒的卡片入场，抽成 30
    if len(files) < n:
        print("  警告：%s 只有 %d 帧（要 %d），末帧补足" % (b["id"], len(files), n))
        files = files + [files[-1]] * (n - len(files)) if files else []
    out = []
    for fp in files:
        fr = Image.open(fp).convert("RGB")
        if b["kind"] == "phone":
            out.append(phone_frame(fr, size, b.get("caption"), vertical))
        elif vertical:
            out.append(fit_cover(fr, size) if b.get("vcrop", "center") == "center" else fit_cover(fr, size))
        else:
            out.append(fr if fr.size == size else fit_cover(fr, size))
    return out


def blend(a, b, t):
    return Image.blend(a, b, t)


def assemble(sh, vertical=False):
    """按镜头表把帧串起来：硬切或 6 帧交叉叠化；字幕淡入淡出；返回 [(PIL, beat_id)]"""
    size = (VW, VH) if vertical else (W, H)
    seq = sh["vertical"]["beats"] if vertical else [b["id"] for b in sh["beats"]]
    bid = {b["id"]: b for b in sh["beats"]}
    frames = []
    prev_tail = []
    for i, ent in enumerate(seq):
        b = dict(bid[ent if isinstance(ent, str) else ent["id"]])
        if not isinstance(ent, str):
            b.update({k: v for k, v in ent.items() if k != "id"})
        fs = beat_frames(b, vertical)
        n = len(fs)
        cap = b.get("caption")
        for k, im in enumerate(fs):
            im = im.copy()
            if cap:
                fin = min(1.0, (k + 1) / CAP_FADE) if k < CAP_FADE else 1.0
                fout = min(1.0, (n - k) / CAP_FADE) if n - k <= CAP_FADE else 1.0
                lay = caption_band(size, cap, b.get("label", ""), min(fin, fout), vertical)
                im = Image.alpha_composite(im.convert("RGBA"), lay).convert("RGB")
            if b.get("fade_in") and k < int(b["fade_in"] * FPS):
                im = blend(Image.new("RGB", size, (0, 0, 0)), im, (k + 1) / (b["fade_in"] * FPS))
            if b.get("fade_out") and n - k <= int(b["fade_out"] * FPS):
                im = blend(Image.new("RGB", size, (0, 0, 0)), im, (n - k) / (b["fade_out"] * FPS))
            fs[k] = im
        if b.get("trans", "cut") == "xfade" and frames:
            # 叠化：本镜头前 XFADE 帧和上一镜头的最后 XFADE 帧混合（总帧数减少 XFADE）
            tail = frames[-XFADE:]
            del frames[-XFADE:]
            for k in range(XFADE):
                frames.append((blend(tail[k][0], fs[k], (k + 1) / (XFADE + 1)), b["id"]))
            fs = fs[XFADE:]
        frames.extend((im, b["id"]) for im in fs)
        print("  %-8s %-6s %3d 帧 %s" % (b["id"], b["kind"], n, cap or ""))
    return frames


def write_frames(frames, d):
    if os.path.isdir(d):
        shutil.rmtree(d)
    os.makedirs(d)
    for i, (im, _) in enumerate(frames):
        im.save(os.path.join(d, "f%05d.png" % i), compress_level=1)
    with open(os.path.join(d, "index.json"), "w", encoding="utf-8") as fh:   # 每帧属于哪个镜头（verify 用来放过片头 / 片尾静帧与淡入淡出）
        json.dump([bid for _, bid in frames], fh)
    return len(frames)


# ---------------------------------------------------------------- 编码
def find_ffmpeg():
    p = shutil.which("ffmpeg")
    if p:
        return p, "PATH"
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe(), "imageio_ffmpeg"
    except Exception:
        return None, None


def encode(frame_dir, out_mp4, music=None):
    ff, src = find_ffmpeg()
    n = len(glob.glob(os.path.join(frame_dir, "f*.png")))
    if ff:
        cmd = [ff, "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(frame_dir, "f%05d.png")]
        if music and os.path.exists(music):
            cmd += ["-i", music, "-c:a", "aac", "-b:a", "192k", "-shortest"]
        cmd += ["-c:v", "libx264", "-crf", "18", "-preset", "slow", "-pix_fmt", "yuv420p", "-movflags", "+faststart", out_mp4]
        subprocess.run(cmd, check=True)
        print("编码 ffmpeg(%s) libx264 crf18 yuv420p faststart%s → %s %.1f MB" % (src, " + AAC" if music else "", out_mp4, os.path.getsize(out_mp4) / 1048576))
        return "ffmpeg:" + src
    import cv2
    im0 = Image.open(os.path.join(frame_dir, "f00000.png"))
    wr = cv2.VideoWriter(out_mp4, cv2.VideoWriter_fourcc(*"avc1"), FPS, im0.size)
    if not wr.isOpened():
        sys.exit("OpenCV 写不了 H.264（avc1）")
    for i in range(n):
        wr.write(cv2.cvtColor(np.asarray(Image.open(os.path.join(frame_dir, "f%05d.png" % i)).convert("RGB")), cv2.COLOR_RGB2BGR))
    wr.release()
    print("编码 OpenCV avc1 草稿（无声；装 ffmpeg 后重跑 encode）→ %s %.1f MB" % (out_mp4, os.path.getsize(out_mp4) / 1048576))
    return "opencv"


def cmd_encode():
    sh = load_shots()
    music = os.path.join(OUT, "music.wav") if sh.get("music") else None
    enc = encode(os.path.join(OUT, "frames"), os.path.join(OUT, "trailer_1080p.mp4"), music)
    vm = os.path.join(OUT, "music_vertical.wav")
    encode(os.path.join(OUT, "frames_v"), os.path.join(OUT, "trailer_vertical.mp4"), vm if os.path.exists(vm) else None)
    return enc


# ---------------------------------------------------------------- GIF / 联络表 / 校验
def make_gif(sh):
    g = sh["gif"]
    b = {x["id"]: x for x in sh["beats"]}[g["beat"]]
    files = sorted(glob.glob(os.path.join(RAW, b["run"], "rec_" + b["id"], "f*.png")))
    skip = int(round(g.get("skip", 0) * FPS))
    files = [files[skip + int(round(i * FPS / g["fps"]))] for i in range(int(g["dur"] * g["fps"])) if skip + int(round(i * FPS / g["fps"])) < len(files)]
    frames = [Image.open(f).convert("RGB").resize((1280, 720), Image.LANCZOS) for f in files]
    ims = [fr.quantize(g.get("colors", 128), method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE) for fr in frames]
    p = os.path.join(OUT, "trailer_loop_1280x720.gif")
    ims[0].save(p, save_all=True, append_images=ims[1:], duration=int(1000 / g["fps"]), loop=0, optimize=True, disposal=1)
    print("GIF", p, len(ims), "帧", "%.1f s" % (len(ims) / g["fps"]), "%.1f MB" % (os.path.getsize(p) / 1048576))


def contact_sheet(frames, path):
    """每个镜头取中间一帧，横 4 列"""
    seen, picks = {}, []
    for i, (_, bid) in enumerate(frames):
        seen.setdefault(bid, []).append(i)
    for bid, idx in seen.items():
        picks.append((bid, frames[idx[len(idx) // 2]][0], idx[0], idx[-1]))
    cols, tw, th = 4, 480, 270
    rows = (len(picks) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw, rows * (th + 34)), NAVY)
    d = ImageDraw.Draw(sheet)
    f = font(20)
    for i, (bid, im, a, z) in enumerate(picks):
        x, y = (i % cols) * tw, (i // cols) * (th + 34)
        sheet.paste(im.resize((tw, th), Image.LANCZOS), (x, y))
        d.text((x + 8, y + th + 6), "%s  f%d–%d  %.1f–%.1f s" % (bid, a, z, a / FPS, z / FPS), font=f, fill=TEXT)
    sheet.save(path)
    print("联络表", path)


def verify(frame_dir, planned_s, sh):
    """帧数 = 计划时长；黑帧只允许出现在带 fade_in / fade_out 的镜头里；连续重复帧只允许在 title / end 静帧镜头里"""
    files = sorted(glob.glob(os.path.join(frame_dir, "f*.png")))
    n = len(files)
    print("校验 %s：%d 帧 = %.2f s（计划 %.2f s）" % (os.path.basename(frame_dir), n, n / FPS, planned_s))
    idx = json.load(open(os.path.join(frame_dir, "index.json"), encoding="utf-8"))
    kinds = {b["id"]: b for b in sh["beats"]}
    prev = None
    black, dup, run_dup = [], [], 0
    for i, fp in enumerate(files):
        b = kinds[idx[i]]
        a = np.asarray(Image.open(fp).convert("L").resize((192, 108)), dtype=np.int16)
        if a.mean() < 6 and not (b.get("fade_in") or b.get("fade_out")):
            black.append(i)
        if prev is not None:
            diff = np.abs(a - prev).mean()
            if diff < 0.05:
                run_dup += 1
                if run_dup >= 3 and b["kind"] not in ("title", "end"):   # 实机镜头里连续 3 帧不变 = 录丢帧 / 暂停
                    dup.append(i)
            else:
                run_dup = 0
        prev = a
    ok = abs(n / FPS - planned_s) < 0.5
    print("  黑帧 %d 个%s；长重复段帧 %d 个%s" % (len(black), (" @" + str(black[:8])) if black else "", len(dup), (" @" + str(dup[:8])) if dup else ""))
    return ok and not black and not dup


def planned_seconds(sh, vertical=False):
    seq = sh["vertical"]["beats"] if vertical else [b["id"] for b in sh["beats"]]
    bid = {b["id"]: b for b in sh["beats"]}
    tot, first = 0.0, True
    for ent in seq:
        b = dict(bid[ent if isinstance(ent, str) else ent["id"]])
        if not isinstance(ent, str):
            b.update(ent)
        tot += b["dur"] - (XFADE / FPS if b.get("trans", "cut") == "xfade" and not first else 0.0)
        first = False
    return tot


def cmd_build(encode_too=True):
    sh = load_shots()
    os.makedirs(OUT, exist_ok=True)
    print("横版 1920×1080")
    fr = assemble(sh)
    n = write_frames(fr, os.path.join(OUT, "frames"))
    contact_sheet(fr, os.path.join(OUT, "contact.png"))
    print("竖版 1080×1920")
    frv = assemble(sh, vertical=True)
    nv = write_frames(frv, os.path.join(OUT, "frames_v"))
    del fr, frv
    # 配乐：横版一份；竖版从同一混音截到竖版片长、另做 1 秒淡出
    if sh.get("music"):
        import soundfile as sf
        cmd_music(n / FPS)
        d, sr = sf.read(os.path.join(OUT, "music.wav"))
        cut = d[:int(nv / FPS * sr)].copy()
        cut[-sr:] *= np.linspace(1.0, 0.0, sr)[:, None]
        sf.write(os.path.join(OUT, "music_vertical.wav"), cut.astype(np.float32), sr)
    make_gif(sh)
    enc = cmd_encode() if encode_too else "none"
    ok1 = verify(os.path.join(OUT, "frames"), planned_seconds(sh), sh)
    ok2 = verify(os.path.join(OUT, "frames_v"), planned_seconds(sh, True), sh)
    for f in ["trailer_1080p.mp4", "trailer_vertical.mp4", "trailer_loop_1280x720.gif", "contact.png"]:
        p = os.path.join(OUT, f)
        if os.path.exists(p):
            print("  %-28s %.1f MB" % (f, os.path.getsize(p) / 1048576))
    print("encoder:", enc, "| verify:", "通过" if ok1 and ok2 else "有问题")


if __name__ == "__main__":
    a = sys.argv[1:]
    cmd = a[0] if a else "build"
    if cmd == "scout":
        cmd_scout(a[1].split(","))
    elif cmd == "capture":
        sh = load_shots()
        cmd_capture(a[1].split(",") if len(a) > 1 else list(sh["runs"]))
    elif cmd == "music":
        cmd_music(float(a[1]) if len(a) > 1 else planned_seconds(load_shots()))
    elif cmd == "build":
        cmd_build("--no-encode" not in a)
    elif cmd == "encode":
        cmd_encode()
    elif cmd == "verify":
        sh = load_shots()
        verify(os.path.join(OUT, "frames"), planned_seconds(sh), sh)
        verify(os.path.join(OUT, "frames_v"), planned_seconds(sh, True), sh)
    elif cmd == "gif":
        make_gif(load_shots())
    else:
        sys.exit(__doc__)
