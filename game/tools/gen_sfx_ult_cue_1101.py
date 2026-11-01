"""终结技提示音三件（用户 11-01，docs/205 §4.9）：全部录音素材（Sonniss GDC 2026 免版税可商用 + Freesound CC0），不用合成音。
1. 超必杀提示音 ult_super_<n>（按 Q 进入超必杀暂停那一刻，20 人共用，叠在各人 sf 前面；ult/super_cue 选哪一版，0 = 不放）：
   格斗游戏超必杀那种短促、亮的「锵」——不用 MUGEN / 卡普空 / SNK 的音效，只按特征从录音里叠
2. 就绪提示音 ult_ready（能量充满那一刻一次，ult/ready_cue）：比超必杀那声轻、短、柔，一听就分得开
3. 逻各斯时停加时钟（用户「秒针滴答几下，然后『咔』一声停住，停住期间很低的嗡鸣，解除时钟声再走起来」）：
   候选 LC1 = 现在的 ① 低鸣 + 时钟、LC2 = ② 低鸣 + 时钟，输出整套 ult_logos_* 到 <主仓库>/build/ult_sfx/LC1|LC2（tools/ult_sfx_review.py --sets 重混对照）
运行：python game/tools/gen_sfx_ult_cue_1101.py            → 候选进 build/ult_sfx/CUE/、LC1/、LC2/
      python game/tools/gen_sfx_ult_cue_1101.py --apply    → ult_super_1..3 / ult_ready 写进 game/audio/sfx/（逻各斯候选不写，选定后再改 gen_sfx_ult_seg_1030.py）
"""
import argparse, os, runpy, shutil
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
S = runpy.run_path(os.path.join(HERE, "gen_sfx_ult_seg_1030.py"), run_name="gen_seg")   # 工具函数 + Sonniss / Freesound 截取（同一套素材登记）
SR, SFX, ROOT = S["SR"], S["SFX"], S["ROOT"]
lib, fsd, sn, pad, at, lp, hp, rev, fadeio, fit, write, RMS = (S[k] for k in ("lib", "fsd", "sn", "pad", "at", "lp", "hp", "rev", "fadeio", "fit", "write", "RMS"))

CLK_A = "344 Audio - Antique Clocks/CLOCKTick_Crooked Antique Clock_344 Audio_Antique Clocks.wav"   # 歪钟：一秒一下，重而闷
CLK_B = "344 Audio - Antique Clocks/CLOCKTick_You're Running Late _344 Audio_Antique Clocks.wav"     # 座钟：0.75 秒一下，滴 / 答交替、清脆
LATCH = "Epic Stock Media - HD Lock And Mechanism Sound Design Kit/MECHLtch_Click Deep Mechanism Latch Button Nearfield Thunk 02_ESM_HDLM.wav"
CLANK = "Epic Stock Media - HD Game Materials/METLImpt_Metal Old File Impact Tap Against Tire Iron Metallic Hit 01_ESM_HDGM.wav"
HUM = "Jake Fielding - Fridge Hums Vol.2/MACHAppl_Deep Fridge Hum, Buzz, Electric Tone, Deep_Jake Fielding_Fridge Hums Pt2.wav"
SHIM = "Epic Stock Media - Anime Game/DSGNStngr_Power Up Bright Positive Successful Light Saturation Crash Shimmer 05_ESM_AG.wav"
CHORD = "Cinematic Sound Design - Ultra Transitions & Impacts/Impact Hit Rapid Chord Reverb.wav"
SLICE = "Epic Stock Media - Tower Defense Game/DSGNStngr_Action Deploy Units Sword Slice Special Move Layered Swish 04_ESM_TDG.wav"
BOOM = "Federico Soler - Effective Trailer Booms Vol. 2/EffectiveTrailer_Booms_Vol2_214.wav"
SPELL = "Epic Stock Media - Fantasy Game 2 - Sound Kit for Enchanted Realms/MAGAngl_Magic Light Spell Enchantment Potion Effect Tonal Bright 03_ESM_FG2.wav"
TING = "Cinematic Sound Design - UI Interaction Elements/Ting Coins.wav"
KALIMBA = "CB_Sounddesign - Applicable Sounds - Organic UI and Building Games SFX/UIMisc_Kalimba 3 Up_CB Sounddesign_APPlicable Sounds.wav"
TICK_A = [2.06, 3.055, 7.035, 8.06, 9.055, 10.06]   # 歪钟里响亮的几下（起点，onset 实测）
TICK_B = [0.755, 1.5, 2.255, 3.005, 3.755, 4.5]      # 座钟：偶数 = 滴、奇数 = 答


def tick(src, t0, gain=1.0, rate=1.0, dur=0.16):
    return hp(lib(src, t0 - 0.006, dur, rate, fout=0.06), 250) * gain


# ---------------------------------------------------------------- 1. 超必杀提示音
def super_cues():
    """① 剑鸣「锵」：出鞘 shwing（Freesound IENBA「Dagger」CC0）+ 亮闪碎光（ESM 动漫 power up 头 0.35 秒）+ 一记很短的低频顿
    ② 金属撞击亮鸣：铁件敲击（ESM 金属材质）升调 + 前面 0.1 秒碎光倒吸 + 特招斩击层（ESM 塔防 special move）
    ③ 和弦冲击：电影冲击和弦（CSD Rapid Chord）截头 0.45 秒 + 出鞘 shwing 高频层"""
    shwing = fsd(611310, 0.42, 0.4, fout=0.15)
    flash = hp(lib(SHIM, 0.13, 0.4, fout=0.2), 2500)
    thump = lp(lib(BOOM, 0.25, 0.3, fout=0.15), 400)
    c1 = pad(shwing, at(flash * 0.55, 0.01), thump * 0.45)
    clank = hp(lib(CLANK, 0.12, 0.34, 1.15, fout=0.2), 600)
    pre = rev(hp(lib(SHIM, 0.13, 0.1, fout=0.03), 3000))
    c2 = pad(pre * 0.5, at(pad(clank, hp(lib(SLICE, 0.4, 0.4, 1.1, fout=0.2), 1500) * 0.5, thump * 0.4), 0.09))
    chord = lib(CHORD, 0.84, 0.45, 1.06, fout=0.2)   # 起点对到和弦最响（0.86）前一点，按下即响
    c3 = pad(chord, hp(shwing, 3000) * 0.5)
    return {"ult_super_1": c1, "ult_super_2": c2, "ult_super_3": c3}


# ---------------------------------------------------------------- 2. 就绪提示音
def ready_cue():
    """轻、短、柔：拇指琴两音上行（CB Sounddesign Kalimba）+ 一点硬币 ting 的亮尾（CSD），没有低频和瞬态冲击，和超必杀那声分得开"""
    return pad(lib(KALIMBA, 0.0, 0.5, fout=0.2), at(hp(lib(TING, 0.09, 0.35, 1.2, fout=0.2), 2500) * 0.3, 0.12))


# ---------------------------------------------------------------- 3. 逻各斯时停 + 时钟
def logos_clock(v):
    """cast（时停起点，0.48 秒凝住，到爆开约 1.1 秒）：前 0.45 秒秒针三下（越走越紧）→ 0.46「咔」停住（深闩扣 + 钟锤一记闷响 + 金属余震）
    → 停住期间原来的 ① / ② 低鸣 + 一层很低的电器嗡鸣（冰箱压缩机，200 Hz 低通）；原来低鸣里的钟声删掉（换成这套）
    impact（爆开 = 时间恢复）：原来的爆开 + 0.55 秒起时钟重新走（滴、答、滴，渐弱）
    v=1：歪钟（重、闷）+ ① 号角低鸣；v=2：座钟（清脆滴答）+ ② 空腔嗡鸣"""
    seg = S["logos"](v) if v == 2 else S["logos"]()
    src, ts = (CLK_A, TICK_A) if v == 1 else (CLK_B, TICK_B)
    ticks = pad(at(tick(src, ts[0], 0.55), 0.0), at(tick(src, ts[1], 0.7), 0.17), at(tick(src, ts[2], 0.85), 0.31))
    stop = pad(lp(lib(LATCH, 0.0, 0.38, 0.8, fout=0.15), 6000), tick(src, ts[3], 0.9, 0.7, 0.3) * 0.8, hp(lib(CLANK, 0.12, 0.34, 0.75, fout=0.25), 400) * 0.35)
    hum = lp(lib(HUM, 20.0, 1.0, fout=0.4), 200)
    if v == 1:
        suck = rev(lp(sn("b214", 0.25, 1.0, fout=0.05), 1500))[-int(0.5 * SR):]
        hold = pad(lp(sn("braam", 0.3, 1.0, 0.7, fout=0.5), 1200), lp(sn("drone", 8.0, 1.0, 0.8, fout=0.5), 2000) * 0.4)
    else:
        suck = pad(rev(sn("debris", 0.1, 0.8, fout=0.05))[-int(0.6 * SR):], rev(lp(sn("tbraam", 1.8, 0.8, 0.8, fout=0.05), 2500))[-int(0.6 * SR):] * 0.8)
        hold = pad(lp(sn("drone", 8.0, 1.2, 0.6, fout=0.5), 900), lp(sn("indamb", 8.0, 1.2, 0.8, fout=0.5), 1500) * 0.6)
    cast = pad(suck * 0.8, ticks * 0.9, at(stop, 0.46), at(pad(hold, hum * 0.7), 0.48))
    resume = pad(at(tick(src, ts[4], 0.6), 0.0), at(tick(src, ts[5], 0.45), 0.36 if v == 1 else 0.3), at(tick(src, ts[0], 0.3), 0.72 if v == 1 else 0.6))
    d = dict(seg)
    d["cast"] = fadeio(fit(cast, 1.3), 0.01, 0.35)
    duck = np.ones(len(seg["impact"]))   # 爆开的尾巴 0.45 秒起压低，让时钟重新走起来听得见（压 12 dB）
    i0, i1 = int(0.45 * SR), int(0.65 * SR)
    duck[i0:i1] = np.linspace(1.0, 0.25, i1 - i0)
    duck[i1:] = 0.25
    d["impact"] = pad(seg["impact"] * duck, at(resume * 3.0, 0.55))
    return d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()
    cand = os.path.join(ROOT, "build", "ult_sfx")
    RMS.update({"super": -10.0, "ready": -17.0})
    dst = SFX if a.apply else os.path.join(cand, "CUE")
    os.makedirs(dst, exist_ok=True)
    for k, x in {**super_cues(), "ult_ready": ready_cue()}.items():
        print(k, "%.2f" % write(os.path.join(dst, k + ".wav"), np.asarray(x, dtype=np.float64), "super" if "super" in k else "ready"))
    for v in (1, 2):
        od = os.path.join(cand, "LC%d" % v)
        shutil.rmtree(od, ignore_errors=True)
        os.makedirs(od)
        info = []
        for slot, x in logos_clock(v).items():
            if x is None:
                continue
            RMS[slot] = S["level"](slot, np.asarray(x))
            info.append("%s %.2f" % (slot, write(os.path.join(od, "ult_logos_%s.wav" % slot), np.asarray(x, dtype=np.float64), slot)))
        print("LC%d" % v, " / ".join(info))


if __name__ == "__main__":
    main()
