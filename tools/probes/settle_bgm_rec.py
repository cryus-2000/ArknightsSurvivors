# -*- coding: utf-8 -*-
"""结算配乐录像（10-28 用户「结算的 BGM 还是老的主题曲，换成新的主题曲」）：胜利结算 + 失败（倒下过渡 → 结算）各一段，带声音的 H.264 mp4。
画面：tests/settle_style_rec（胜利段，队长德克萨斯）+ tests/outro_rec --crowd --realtime（失败段），都是 --fixed-fps 30、音频哑驱动。
声音离线按 sfx.gd 的结算规则混（不外放）：音乐总线 vol_target −4 dB；
  胜利：结算入场起 title 从头、group_vol 线性 0 → 1 用 SETTLE_FADE_WIN 秒；
  失败：倒下前是 suno_battle1_base（开局平静层），倒下起 1.2 秒淡出；DEATH_T 时 title 从头、压 SETTLE_LOSE_DB、SETTLE_FADE_LOSE 秒淡入。
录完即删帧目录。输出主仓库 build/settle_redesign/settle_bgm.mp4。用法：python tools/probes/settle_bgm_rec.py
"""
import os, sys, glob, shutil, subprocess
import numpy as np
from PIL import Image, ImageDraw, ImageFont

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
import godot_runner as GR

GAME = os.path.join(ROOT, "game")
OUT = os.path.join(GR.common_root(), "build", "settle_redesign")
W, H, FPS, SR = 1480, 720, 30, 48000
VOL = -4.0
LOSE_DB, FADE_WIN, FADE_LOSE, OUT_T, DEATH_T = -6.0, 2.0, 4.0, 1.2, 2.4
HOLD = 4.0   # 胜利段末尾多停几秒，听主题曲


def godot(scene, d, extra):
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    out, err, to = GR.run_godot([GR.find_godot(), "--path", GAME, "--resolution", "1280x720", "--fixed-fps", str(FPS),
                                 scene, "--", "--shotdir=" + d] + extra, 400)
    errs = [l for l in (out + err).splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l or "OUTRO_REC" in l]
    if errs:
        print(scene, "\n".join(errs[:6]))


def pcm(name):
    import imageio_ffmpeg
    raw = subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-loglevel", "error", "-i", os.path.join(GAME, "audio", "music", name + ".ogg"),
                          "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"], capture_output=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2)


def seg(src, t0, n):
    """src 从 t0 秒起取 n 个采样（循环）"""
    i = (int(t0 * SR) + np.arange(n)) % len(src)
    return src[i]


def main():
    import imageio_ffmpeg
    GR.ensure_imported(GAME)
    dw = os.path.join(OUT, "raw_bgm_win")
    dl = os.path.join(OUT, "raw_bgm_lose")
    godot("res://tests/settle_style_rec.tscn", dw, ["--rec_leader=texas", "--rec_ops=6"])
    godot("res://tests/outro_rec.tscn", dl, ["--crowd", "--realtime"])
    win = sorted(glob.glob(os.path.join(dw, "rec_0_*.png")))
    lose = sorted(glob.glob(os.path.join(dl, "rec_*.png")))
    win = win + [win[-1]] * int(HOLD * FPS)
    title, battle = pcm("title"), pcm("suno_battle1_base")
    g0 = 10 ** (VOL / 20)
    # 胜利段：结算入场即第 0 帧
    nw = int(len(win) / FPS * SR)
    tw = np.arange(nw) / SR
    aw = seg(title, 0.0, nw) * (np.minimum(1.0, tw / FADE_WIN) * g0)[:, None]
    # 失败段：outro_rec 从倒下前 1 秒开始存帧
    nl = int(len(lose) / FPS * SR)
    tl = np.arange(nl) / SR
    death = 1.0
    bat = seg(battle, 30.0, nl) * (np.clip(1.0 - (tl - death) / OUT_T, 0.0, 1.0) * g0)[:, None]
    ts = tl - (death + DEATH_T)
    th = seg(title, 0.0, nl) * (np.where(ts >= 0, np.minimum(1.0, np.maximum(ts, 0) / FADE_LOSE), 0.0) * g0 * 10 ** (LOSE_DB / 20))[:, None]
    audio = np.concatenate([aw, bat + th]).astype(np.float32)
    wav = os.path.join(OUT, "settle_bgm.f32")
    audio.tofile(wav)
    path = os.path.join(OUT, "settle_bgm.mp4")
    f = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 16) if os.path.exists(r"C:\Windows\Fonts\msyh.ttc") else ImageFont.load_default()
    proc = subprocess.Popen([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
                             "-s", "%dx%d" % (W, H), "-r", str(FPS), "-i", "-", "-f", "f32le", "-ac", "2", "-ar", str(SR), "-i", wav,
                             "-vf", "scale=out_color_matrix=bt709:out_range=tv", "-c:v", "libx264", "-preset", "slow", "-crf", "20",
                             "-pix_fmt", "yuv420p", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
                             "-color_range", "tv", "-c:a", "aac", "-b:a", "160k", "-shortest", "-movflags", "+faststart", path], stdin=subprocess.PIPE)
    for frames, label in [(win, "胜利结算：新主题曲从头淡入（2 秒）"), (lose, "失败：战斗曲 1.2 秒收掉 → 黑场 → 主题曲压 6 dB、4 秒慢淡入")]:
        for p in frames:
            im = Image.open(p).convert("RGB")
            canvas = Image.new("RGB", (W, H), (0, 0, 0))
            canvas.paste(im, ((W - im.width) // 2, (H - im.height) // 2))
            dr = ImageDraw.Draw(canvas)
            dr.rectangle((0, 0, dr.textlength(label, font=f) + 16, 24), fill=(0, 0, 0))
            dr.text((8, 2), label, fill=(255, 220, 140), font=f)
            proc.stdin.write(canvas.tobytes())
    proc.stdin.close()
    proc.wait()
    os.remove(wav)
    for d in (dw, dl):
        shutil.rmtree(d, ignore_errors=True)
    print("写出", path, "%.1f MB" % (os.path.getsize(path) / 1048576), "帧", len(win) + len(lose))


if __name__ == "__main__":
    main()
