"""收集英文模式下仍显示中文的原文（tests/l10n_shots 写的 missing_*.txt），并成 extra 模块（docs/276 §12）。
  python tools/l10n/collect_missing.py "<出图目录>" [更多目录…]
  python tools/l10n/translate_vertex.py run extra && python tools/l10n/translate_vertex.py proof extra && python tools/l10n/translate_vertex.py csv extra
多半是代码拼出来的片段（「方向键」「塑造」「深蓝之下 [未获得]」）或运行时才拼成的整句。已有的 extra 条目保留，只追加新的。
跳过：纯符号 / 数字为主、单个汉字（单字逐个翻没有意义，多是逐字绘制或图标字）。
"""
import json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "build/l10n_work"
CJK = re.compile(r"[一-鿿]")


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    p = WORK / "extra.items.json"
    items = json.load(open(p, encoding="utf-8")) if p.exists() else []
    have = {i["zh"] for i in items}
    n0 = len(items)
    for d in sys.argv[1:]:
        for f in sorted(Path(d).glob("missing_*.txt")):
            for line in open(f, encoding="utf-8"):
                line = line.strip()
                if not line:
                    continue
                try:
                    zh = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if zh in have or len(CJK.findall(zh)) < 2:
                    continue
                have.add(zh)
                items.append({"key": "extra.%04d" % len(items), "zh": zh, "file": "(运行时拼接)", "path": f.name, "field": "gd"})
    WORK.mkdir(parents=True, exist_ok=True)
    json.dump(items, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("extra：原有 %d，新增 %d，共 %d → %s" % (n0, len(items) - n0, len(items), p))


if __name__ == "__main__":
    main()
