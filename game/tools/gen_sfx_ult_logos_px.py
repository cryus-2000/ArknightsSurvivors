"""逻各斯终结技转平面版音效候选（docs/258 §9，开关 ult/px_plane；用户 11-05「接下来的终结技都带音效来」）。
只用仓库已登记、有授权的录音（Sonniss GDC 2026 Bundle，docs/113 §20：免版税可商用、不需署名、不得再分发原文件、不得用于 AI 训练），
**不用原作客户端解出来的音源**（原 ult_logos_impact 里那层 p_skill_darkholespell 去掉）。工具函数沿用 gen_sfx_ult_seg_1030.py。

槽（写到 <主仓库>/build/ult_sfx/LOPX/，点头前不进游戏；--apply 才写进 game/audio/sfx/）：
  起手 charge / 时停 cast：沿用 11-02 定稿的文件（不重做，这里不出）
  pxglyph_1..3：咒文一个个被写出来的那一声（原 glyph_1..3 太亮：重心 6.7 kHz、4 kHz 以上占 20%，叠多了发尖）——同一段 Kopeikin「astral travel」，
                5 kHz 低通、降调一点，更轻（-18）
  pximpact：最大那一下（冲击帧同帧起）。电光低鸣冲击（ESM）+ 预告片低频轰（Booms 214，900 Hz 低通）+ 长音下坠混响降调 ×0.7 拉成 2.4 秒的低频余音（配慢动作）
            + 一层很轻的碎屑呼啸；高频收着（6 kHz 低通）
  pxsettle：收尾，咒文碎成细丝飘散：astral 降调 ×0.8、4 kHz 低通、慢起慢收（-17）
用法：python game/tools/gen_sfx_ult_logos_px.py [--apply]"""
import argparse, importlib.util, os, sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("seg", os.path.join(HERE, "gen_sfx_ult_seg_1030.py"))
M = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(M)
SR = M.SR


def at(x, t):
    return np.concatenate([np.zeros(int(t * SR)), np.asarray(x, dtype=np.float64)])


def env_in(x, sec):
    n = min(len(x), int(sec * SR))
    x = np.array(x, dtype=np.float64)
    x[:n] *= np.linspace(0.0, 1.0, n) ** 1.5
    return x


def slots():
    imp = M.pad(
        M.sn("elec", 0.0, 0.9, 0.6, fout=0.4) * 0.8,
        M.lp(M.sn("b214", 0.25, 1.6, fout=0.6), 900) * 0.95,
        at(M.lp(M.lib(M.ZW_TONE, 0.6, 1.7, 0.7, fout=1.0), 1200) * 0.55, 0.12),   # ×0.7 降调后约 2.4 秒：慢动作里的低频余音
        at(M.lp(M.sn("debris", 0.1, 0.9, fout=0.4), 4000) * 0.28, 0.05),
    )
    imp = M.fadeio(M.lp(imp, 6000)[:int(2.6 * SR)], 0.002, 0.5)
    glyphs = {"pxglyph_%d" % (i + 1): M.lp(M.hp(M.sn("astral", 0.3, 0.3, r, fout=0.15), 700), 5000) for i, r in enumerate([1.3, 1.4, 1.5])}
    settle = M.fadeio(env_in(M.lp(M.sn("astral", 0.0, 1.2, 0.8, fout=0.6), 4000), 0.25), 0.01, 0.4)
    return {"pximpact": imp, "pxsettle": settle, **glyphs}


LEVEL = {"pximpact": -9.0, "pxsettle": -17.0, "pxglyph": -18.0}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()
    dst = M.SFX if a.apply else os.path.join(M.ROOT, "build", "ult_sfx", "LOPX")
    os.makedirs(dst, exist_ok=True)
    for slot, x in slots().items():
        M.RMS[slot] = LEVEL.get(slot, LEVEL.get(slot.split("_")[0], -15.0))
        dur = M.write(os.path.join(dst, "ult_logos_%s.wav" % slot), np.asarray(x, dtype=np.float64), slot)
        print("ult_logos_%s.wav" % slot, "%.2f s" % dur)
    print("→", dst)


if __name__ == "__main__":
    main()
