"""终结技提示音三件（用户 11-01，docs/205 §4.9）：全部录音素材（Sonniss GDC 2026 免版税可商用 + Freesound CC0），不用合成音。
1. 超必杀提示音 ult_super_<n>（按 Q 进入超必杀暂停那一刻，20 人共用，叠在各人 sf 前面；ult/super_cue 选哪一版，0 = 不放）：
   格斗游戏超必杀那种短促、亮的「锵」——不用 MUGEN / 卡普空 / SNK 的音效，只按特征从录音里叠
2. 就绪提示音 ult_ready（能量充满那一刻一次，ult/ready_cue）：比超必杀那声轻、短、柔，一听就分得开
（逻各斯时停加时钟的 LC1 / LC2 候选已被第五轮「世界」时停声取代，见 gen_sfx_ult_seg_1030.py logos 与 docs/205 §4.10）
运行：python game/tools/gen_sfx_ult_cue_1101.py            → 候选进 build/ult_sfx/CUE/
      python game/tools/gen_sfx_ult_cue_1101.py --apply    → ult_super_1..3 / ult_ready 写进 game/audio/sfx/
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
MBOX = "Sonic Bat - Music Boxes/SBmb_Music Box B 028.wav"   # 八音盒一音：基频 1326 Hz、泛音 2653 / 3980
RING = "David Dumais Audio - Melee Weapons Sound Effects Pack 2/METLImpt_METAL SWING HIT Weapon Swing To Metallic Body Impact And Resonant Tail 01_DDUMAIS_MWP2.wav"   # 0.42 秒处金属共振，3.4 kHz 一层
XBELL = "344 Audio - Christmas Vol. 1/MAGMisc_Magic Christmas Bells 2_344 Audio_Christmas.wav"   # 2.21 秒一串小铃：7–14 kHz 闪烁
TICK_A = [2.06, 3.055, 7.035, 8.06, 9.055, 10.06]   # 歪钟里响亮的几下（起点，onset 实测）
TICK_B = [0.755, 1.5, 2.255, 3.005, 3.755, 4.5]      # 座钟：偶数 = 滴、奇数 = 答


def tick(src, t0, gain=1.0, rate=1.0, dur=0.16):
    return hp(lib(src, t0 - 0.006, dur, rate, fout=0.06), 250) * gain


# ---------------------------------------------------------------- 1. 超必杀提示音
def super_cues():
    """① 剑鸣「锵」：出鞘 shwing（Freesound IENBA「Dagger」CC0）+ 亮闪碎光（ESM 动漫 power up 头 0.35 秒）+ 一记很短的低频顿
    ② 金属撞击亮鸣：铁件敲击（ESM 金属材质）升调 + 前面 0.1 秒碎光倒吸 + 特招斩击层（ESM 塔防 special move）
    ③ 和弦冲击：电影冲击和弦（CSD Rapid Chord）截头 0.45 秒 + 出鞘 shwing 高频层
    ④ 电子游戏「叮——」（11-01 用户要 MUGEN 同款，原文件是卡普空的不能用）：高亮金属单音 + 闪烁尾，0.42 秒，没有低频冲击"""
    shwing = fsd(611310, 0.42, 0.4, fout=0.15)
    flash = hp(lib(SHIM, 0.13, 0.4, fout=0.2), 2500)
    thump = lp(lib(BOOM, 0.25, 0.3, fout=0.15), 400)
    c1 = pad(shwing, at(flash * 0.55, 0.01), thump * 0.45)
    clank = hp(lib(CLANK, 0.12, 0.34, 1.15, fout=0.2), 600)
    pre = rev(hp(lib(SHIM, 0.13, 0.1, fout=0.03), 3000))
    c2 = pad(pre * 0.5, at(pad(clank, hp(lib(SLICE, 0.4, 0.4, 1.1, fout=0.2), 1500) * 0.5, thump * 0.4), 0.09))
    chord = lib(CHORD, 0.84, 0.45, 1.06, fout=0.2)   # 起点对到和弦最响（0.86）前一点，按下即响
    c3 = pad(chord, hp(shwing, 3000) * 0.5)
    # ④ 电子游戏「叮——」：八音盒一音升八度（基频约 2.65 kHz，泛音 5.3 / 8 kHz）+ 剑鸣共振尾里 3.4 kHz 那层 + 圣诞铃 7–14 kHz 闪烁尾，1.2 kHz 以下切掉
    ding = lib(MBOX, 0.03, 0.9, 2.0, fin=0.001, fout=0.2)
    ring = hp(lib(RING, 0.40, 0.6, 1.0, fin=0.002, fout=0.25), 2200)
    sparkle = hp(lib(XBELL, 2.19, 0.5, 1.0, fin=0.002, fout=0.25), 5000)
    c4 = hp(pad(ding * 1.3, ring * 0.7, at(sparkle * 0.12, 0.01)), 1200)
    c4 = c4[:int(0.42 * SR)] * np.exp(-np.arange(min(len(c4), int(0.42 * SR))) / SR / 0.16)
    return {"ult_super_1": c1, "ult_super_2": c2, "ult_super_3": c3, "ult_super_4": c4}


# ---------------------------------------------------------------- 2. 就绪提示音
def ready_cue():
    """轻、短、柔：拇指琴两音上行（CB Sounddesign Kalimba）+ 一点硬币 ting 的亮尾（CSD），没有低频和瞬态冲击，和超必杀那声分得开"""
    return pad(lib(KALIMBA, 0.0, 0.5, fout=0.2), at(hp(lib(TING, 0.09, 0.35, 1.2, fout=0.2), 2500) * 0.3, 0.12))


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


if __name__ == "__main__":
    main()
