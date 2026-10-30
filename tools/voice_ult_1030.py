# -*- coding: utf-8 -*-
"""终结技固定语音（docs/205 §2，用户 10-30 在语音挑选页选定）。

每名干员终结技固定说一句原作整段语音（data/ult_audio.json ops.<干员>.voice = 文件主名）：
  已有文件的原句直接用；游戏里还没有的新切 <干员>_ult.ogg（来源与切法同 tools/voice_more_1029.py）。
ultOnly 的干员：选中那句从 voice_pools.json 各池撤掉（只在终结技说），少一句的池用同角色还没用过的战斗条目补
（补的句子也是原作整段，必要时新切 <干员>_<池>_<n>.ogg）。

用法：先把 Ark-Voice voice_data.json、需要的长音轨（voice_cn/<char>.ogg）和 charword_table.json 下到 --src（主仓库 build/arkvoice），
      python tools/voice_ult_1030.py --src E:/ArknightsSurvivors/build/arkvoice [--dry]
"""
import argparse, json, os, sys

import numpy as np
import soundfile as sf

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.join(ROOT, "game", "tools"))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import voice_ogg as VO
from voice_more_1029 import REV, TEXT_REV, VOICE, MASTERS, sha

ULT_AUDIO = os.path.join(ROOT, "game", "data", "ult_audio.json")
# 用户 10-30 定稿（语音挑选页 picks + docs/205 §2 ★）：干员 -> (原作编号, 只在终结技说)
PICKS = {
    "texas": ("CN_030", False), "exusiai": ("CN_030", True), "skalter": ("CN_018", False), "kaltsit": ("CN_025", False),
    "ulpianus": ("CN_022", False), "skadi": ("CN_028", False), "gladiia": ("CN_028", True), "angelina": ("CN_028", True),
    "eyjafjalla": ("CN_028", False), "wisadel": ("CN_020", False), "specter_unchained": ("CN_028", False), "mizuki": ("CN_027", False),
    "saria": ("CN_024", False), "suzuran": ("CN_025", False), "logos": ("CN_024", True), "hoshiguma": ("CN_028", True),
    "siege": ("CN_030", False), "irene": ("CN_028", True), "lappland": ("CN_029", True), "lumen": ("CN_020", False),
}
# 补位候选（战斗中说得通的条目，按优先顺序）：作战中 1–4、行动开始、部署 1/2、选中 1/2、行动出发。
# 不用结算 / 任命类（高难行动结束、3 星结束、任命队长），也不用带 {@nickname} 的。先找这名干员还没进任何池的，再退而用别的池里已有的（同一池不重复）
# 每个池按自己的语境排（入队 / 突击用部署、选中、编入、行动出发类，技能 / 闲聊用作战中、行动开始类；同 voice_more_1029 的池表）
FILL = {"entry": ["CN_023", "CN_024", "CN_017", "CN_019", "CN_021", "CN_022"],
        "command": ["CN_021", "CN_022", "CN_024", "CN_019", "CN_023", "CN_017"],
        "skill": ["CN_025", "CN_026", "CN_027", "CN_028", "CN_020", "CN_019"],
        "battle": ["CN_028", "CN_020", "CN_019", "CN_024", "CN_022", "CN_025", "CN_026", "CN_027"]}
CAP = {"entry": 6.0, "command": 5.5, "skill": 8.0, "battle": 6.5}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--dry", action="store_true")
    a = ap.parse_args()
    vd = json.load(open(os.path.join(a.src, "voice_data.json"), encoding="utf-8"))["data"]
    cw = json.load(open(os.path.join(a.src, "charword_table.json"), encoding="utf-8"))["charWords"]
    man_p = os.path.join(VOICE, "voice_manifest.json")
    man = json.load(open(man_p, encoding="utf-8"))
    pools_p = os.path.join(VOICE, "voice_pools.json")
    pj = json.load(open(pools_p, encoding="utf-8"))
    pools = pj["pools"]
    by, syn = {}, set()   # (干员, 原作编号) -> 文件主名
    for c in man["clips"]:
        stem = os.path.splitext(c["file"])[0]
        if c["event"].startswith("syn_"):
            syn.add((c["operator"], c["source_clip"]))
        elif c["event"] != "w_laugh":
            by.setdefault((c["operator"], c["source_clip"]), stem)
    stems = set(by.values())
    new, ult, log = [], {}, []

    def span(op, n):
        var = vd[man["operators"][op]]["variations"]["CN"]
        names = [c["name"] for c in var["clips"]]
        st = {c["name"]: c["start"] for c in var["clips"]}
        if n not in st:
            return None
        i = names.index(n)
        return st[n], (st[names[i + 1]] if i + 1 < len(names) else var["duration"])

    def cut(op, n, stem):
        t0, t1 = span(op, n)
        by[(op, n)] = stem
        stems.add(stem)
        new.append((op, man["operators"][op], n, stem, t0, t1))
        return stem

    for op, (n, only) in PICKS.items():
        stem = by.get((op, n)) or cut(op, n, op + "_ult")
        ult[op] = stem
        if not only:
            continue
        used = {s for p in pools[op].values() for s in p}
        for pool, lst in pools[op].items():
            if stem not in lst:
                continue
            lst.remove(stem)
            fl = FILL[pool]
            for m in [x for x in fl if by.get((op, x)) not in used] + [x for x in fl if by.get((op, x)) in used]:
                if m == n or (op, m) in syn or by.get((op, m)) in lst or "{@" in cw.get(man["operators"][op] + "_" + m, {}).get("voiceText", ""):
                    continue
                sp = span(op, m)
                if sp is None or (((op, m) not in by) and sp[1] - sp[0] > CAP[pool]):
                    continue
                if (op, m) in by:
                    s2 = by[(op, m)]
                else:
                    k = 2
                    while "%s_%s_%d" % (op, pool, k) in stems:
                        k += 1
                    s2 = cut(op, m, "%s_%s_%d" % (op, pool, k))
                lst.append(s2)
                used.add(s2)
                log.append("%s %s 池：撤 %s，补 %s（%s）" % (op, pool, stem, s2, m))
                break
            else:
                log.append("%s %s 池：撤 %s，没有可补的" % (op, pool, stem))
    total = 0
    for op, cid, n, stem, t0, t1 in new:
        w = cw.get(cid + "_" + n, {})
        sys.stdout.buffer.write(("切 %-18s %-24s %s %5.2f s %s | %s\n" % (op, stem, n, t1 - t0, w.get("voiceTitle", ""), w.get("voiceText", "").replace("\n", " "))).encode("utf-8"))
        if a.dry:
            continue
        x, sr = sf.read(os.path.join(a.src, cid + ".ogg"), dtype="float32")
        assert sr == VO.SR and x.ndim == 1
        s0, s1 = int(round(t0 * sr)), int(round(t1 * sr))
        wav = os.path.join(MASTERS, stem + ".wav")
        sf.write(wav, np.clip(x[s0:s1], -1, 1), sr, subtype="PCM_16")
        ogg = os.path.join(VOICE, stem + ".ogg")
        VO.encode(wav, ogg, VO.DEFAULT_Q)
        total += os.path.getsize(ogg)
        man["clips"].append({
            "operator": op, "event": stem[len(op) + 1:], "file": stem + ".ogg", "source_operator": cid, "source_clip": n,
            "source_start_seconds": t0, "source_end_seconds": t1, "source_start_sample": s0, "source_end_sample": s1,
            "duration_seconds": round((s1 - s0) / sr, 3), "sha256": sha(wav), "ogg_quality": VO.DEFAULT_Q,
            "master": "art/source/voice/" + stem + ".wav", "ogg_sha256": sha(ogg),
            "source_url": "https://raw.githubusercontent.com/isHarryh/Ark-Voice/%s/voice_cn/%s.ogg" % (REV, cid),
            "source_revision": REV, "source_audio_sha256": sha(os.path.join(a.src, cid + ".ogg")), "source_language": "CN",
            "source_title": w.get("voiceTitle", ""), "text": w.get("voiceText", ""),
            "text_source_url": "https://raw.githubusercontent.com/Kengxxiao/ArknightsGameData/%s/zh_CN/gamedata/excel/charword_table.json" % TEXT_REV,
            "text_source_key": cid + "_" + n, "batch": "voice_ult_1030"})
    for line in log:
        sys.stdout.buffer.write((line + "\n").encode("utf-8"))
    for op, stem in ult.items():
        sys.stdout.buffer.write(("终结技 %-18s %s\n" % (op, stem)).encode("utf-8"))
    print("new %d clips, ogg %d B" % (len(new), total))
    if a.dry:
        return
    man["voice_ult_1030"] = {"date": "2026-10-30", "source_revision": REV, "text_source_revision": TEXT_REV,
                             "note": "终结技固定语音（docs/205 §2，用户选定）；ult_audio.json voice 指向文件主名"}
    with open(man_p, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(man, ensure_ascii=False, indent=2) + "\n")
    with open(pools_p, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(pj, ensure_ascii=False, indent=1) + "\n")
    s = open(ULT_AUDIO, encoding="utf-8").read()
    for op, stem in ult.items():   # 保持手排的一行一人格式：在每人那行开头插 "voice"
        key = '    "%s": {' % op
        assert s.count(key) == 1, op
        if '"voice"' not in s[s.index(key):s.index("\n", s.index(key))]:
            s = s.replace(key, key + '"voice": "%s", ' % stem)
    json.loads(s)
    with open(ULT_AUDIO, "w", encoding="utf-8", newline="\n") as f:
        f.write(s)


if __name__ == "__main__":
    main()
