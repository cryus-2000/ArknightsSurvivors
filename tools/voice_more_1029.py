# -*- coding: utf-8 -*-
"""干员语音扩充（10-29 用户：「语音多一点，否则歌蕾蒂娅一直重复『谁是猎物』」，docs/190）。

每名干员按触发类别建语音池（game/audio/voice/voice_pools.json），sfx.gd 按池洗牌轮换：
  entry   入队 / 开局 / 指挥归队：部署1、部署2、编入队伍、行动出发（≥3）
  command 突击回应：10-22 已确认的那条 + 选中干员1/2、任命队长、部署2、行动出发（≥4）
  skill   技能（三个技能槽共用）：作战中1–4（4 条）
  battle  战斗闲聊：作战中4、行动开始、行动出发 / 任命队长（≥3）
台词一律是该干员原作普通话语音整段（不拼接、不改字），来源与第六批相同（Ark-Voice 固定提交切片 + ArknightsGameData 台词表）。
同一段原句只切一份文件，几个池共用；已用于协同语音（syn_*）的原句不进池。

用法：先把 Ark-Voice voice_data.json、20 条长音轨（voice_cn/<char>.ogg）和 charword_table.json 下到 --src（主仓库 build/arkvoice），
      python tools/voice_more_1029.py --src E:/ArknightsSurvivors/build/arkvoice [--dry]
生成：art/source/voice/<干员>_<池>_<n>.wav 母带、game/audio/voice/ 同名 OGG（voice_ogg.encode，24 kHz 0.7 档）、清单登记、voice_pools.json。
"""
import argparse, hashlib, json, os, sys

import numpy as np
import soundfile as sf

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.join(ROOT, "game", "tools"))
import voice_ogg as VO

VOICE = os.path.join(ROOT, "game", "audio", "voice")
MASTERS = os.path.join(ROOT, "art", "source", "voice")
REV = "79584841f7a28f9d029ec2dc1b72444bce87eb1e"
TEXT_REV = "e8588a82074bf695aa3849959037dd2de7e6e5cf"
# 池 -> (候选原作编号，按优先顺序；新切条目的时长上限秒；目标条数)
POOLS = {
    "entry": (["CN_023", "CN_024", "CN_017", "CN_019", "CN_021", "CN_022"], 6.0, 4),
    "command": (["@command", "CN_021", "CN_022", "CN_018", "CN_024", "CN_019", "CN_023", "CN_017"], 5.5, 4),
    "skill": (["CN_025", "CN_026", "CN_027", "CN_028"], 8.0, 4),
    "battle": (["CN_028", "CN_020", "CN_019", "CN_018", "CN_024", "CN_022"], 6.5, 3),
}


def sha(p):
    with open(p, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--dry", action="store_true")
    a = ap.parse_args()
    vd = json.load(open(os.path.join(a.src, "voice_data.json"), encoding="utf-8"))["data"]
    cw = json.load(open(os.path.join(a.src, "charword_table.json"), encoding="utf-8"))["charWords"]
    man_p = os.path.join(VOICE, "voice_manifest.json")
    man = json.load(open(man_p, encoding="utf-8"))
    by = {}   # (干员, 原作编号) -> 文件主名（已有或新切）
    cmd = {}
    syn = set()
    for c in man["clips"]:
        stem = os.path.splitext(c["file"])[0]
        if c["event"].startswith("syn_"):
            syn.add((c["operator"], c["source_clip"]))
        elif c["event"] != "w_laugh":
            by[(c["operator"], c["source_clip"])] = stem
            if c["event"] == "command":
                cmd[c["operator"]] = c["source_clip"]
    pools, new = {}, []
    for op, cid in man["operators"].items():
        var = vd[cid]["variations"]["CN"]
        names = [c["name"] for c in var["clips"]]
        st = {c["name"]: c["start"] for c in var["clips"]}
        end = {n: (st[names[i + 1]] if i + 1 < len(names) else var["duration"]) for i, n in enumerate(names)}
        pools[op] = {}
        for pool, (cands, cap, want) in POOLS.items():
            got = []
            for n in cands:
                n = cmd[op] if n == "@command" else n
                if len(got) >= want:
                    break
                if n not in st or (op, n) in syn or n in got:
                    continue
                if (op, n) not in by:
                    if end[n] - st[n] > cap:
                        continue
                    k = 2
                    while ("%s_%s_%d" % (op, pool, k)) in by.values():
                        k += 1
                    by[(op, n)] = "%s_%s_%d" % (op, pool, k)
                    new.append((op, cid, n, by[(op, n)], st[n], end[n]))
                got.append(n)
            pools[op][pool] = [by[(op, n)] for n in got]
    total = 0
    for op, cid, n, stem, t0, t1 in new:
        w = cw.get(cid + "_" + n, {})
        sys.stdout.buffer.write(("%-18s %-22s %s %5.2f s %s | %s\n" % (op, stem, n, t1 - t0, w.get("voiceTitle", ""), w.get("voiceText", "").replace("\n", " "))).encode("utf-8"))
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
            "text_source_key": cid + "_" + n, "batch": "voice_more_1029"})
    print("new %d clips, ogg %d B (%.3f MiB)" % (len(new), total, total / 1048576))
    for op in pools:
        print(op, {k: len(v) for k, v in pools[op].items()})
    if a.dry:
        return
    man["voice_more_1029"] = {"date": "2026-10-29", "source_revision": REV, "text_source_revision": TEXT_REV, "pools": "voice_pools.json",
                              "note": "原作整段语音，按触发类别分池洗牌轮换（docs/190）"}
    with open(man_p, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(man, ensure_ascii=False, indent=2) + "\n")
    with open(os.path.join(VOICE, "voice_pools.json"), "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps({"_doc": "干员语音池（tools/voice_more_1029.py 生成，docs/190）：sfx.gd 按池洗牌轮换、同句 60 秒内不重复",
                            "pools": pools}, ensure_ascii=False, indent=1) + "\n")


if __name__ == "__main__":
    main()
