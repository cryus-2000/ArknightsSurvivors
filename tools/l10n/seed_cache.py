"""从已提交的 game/l10n/<模块>.csv 反推翻译缓存 build/l10n_work/cache_<模块>.json（工作树被清理、build/ 丢失后用）。
  python tools/l10n/seed_cache.py ops enemies
模型稿与人改稿的英文都写回缓存（人改稿仍以 tools/l10n/review/<模块>.json 为准，合成 CSV 时覆盖）；原文键 / 短版行跳过。
"""
import csv, json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "build/l10n_work"


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    for m in sys.argv[1:]:
        p = WORK / ("cache_%s.json" % m)
        cache = json.load(open(p, encoding="utf-8")) if p.exists() else {}
        n = 0
        for r in csv.DictReader(open(ROOT / "game/l10n" / (m + ".csv"), encoding="utf-8")):
            if r["_source"] in ("模型", "人改") and r["en"] and r["_zh"] not in cache:
                note = r["_note"]
                v = {"en": r["en"]}
                if "候选2：" in note:
                    v["alt"] = note.split("候选2：", 1)[1].split("；", 1)[0]
                cache[r["_zh"]] = v if len(v) > 1 else r["en"]
                n += 1
        json.dump(cache, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=0)
        print(m, "写回", n, "条，缓存共", len(cache))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
