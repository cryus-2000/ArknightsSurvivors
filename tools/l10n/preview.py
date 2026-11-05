"""给用户看的中英对照页（docs/277）：从 game/l10n/*.csv 挑代表条目，中英并排。

  python tools/l10n/preview.py      # → docs/277_english_preview.md
"""
import csv, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PICK = [
    ("官方名：技能（改正了旧的 WAVEBREAKER）", "op.skadi.skills.1.name"),
    ("暂定名：拉普兰德「噤声」", "op.lappland.skills.2.name"),
    ("技能说明（带变量）", "op.mizuki.skills.1.desc"),
    ("天赋说明", "op.mizuki.talent.desc"),
    ("普攻说明", "op.angelina.attack.desc"),
    ("成长节点名", "op.mizuki.progression.0.name"),
    ("成长节点说明", "op.mizuki.progression.0.desc"),
    ("终结技说明", "ult.ops.texas.ult.desc"),
    ("干员档案（首句换成官方招聘合同原文）", "lore.irene.lore"),
    ("招募卡简介（梗，待定）", "op.kaltsit.gallery.intro"),
    ("招募卡简介（官方原句 + 玩家梗）", "op.suzuran.gallery.intro"),
    ("招募卡简介（梗，待定）", "op.wisadel.gallery.intro"),
    ("招募卡简介（双声部排版）", "op.skalter.gallery.intro"),
    ("敌人名（官方）", "enemy.bone.name"),
    ("敌人档案", "lore.bone.lore"),
    ("Boss 档案", "lore.paranoia.lore"),
    ("Boss 图鉴机制行（含官方结局名）", "enemy.izumik.gallery"),
    ("Boss 出场副标题", "enemy.knight_boss.intro.sub"),
    ("Boss 战横幅", "enemy.gd.izumik.034"),
    ("精英图鉴机制行", "enemy.mimic.gallery"),
]


def cell(s):
    return s.replace("|", "\\|").replace("\n", "<br>")


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    rows = {}
    stats = {}
    for m in ("ops", "enemies"):
        st = {}
        for r in csv.DictReader(open(ROOT / "game/l10n" / (m + ".csv"), encoding="utf-8")):
            rows[r["key"]] = r
            st[r["source"]] = st.get(r["source"], 0) + 1
        stats[m] = st
    out = ["# 277 英文版对照样张（干员 + 怪物，20 条）", "",
           "2026-11-05 第一批英文初稿的代表条目。全部条目在 `game/l10n/ops.csv`、`game/l10n/enemies.csv`（列：key / zh / en / 来源 / 备注）。方案与术语见 docs/276。",
           "", "来源：**官方** = 国际服 en_US 原文；**暂定** = docs/276 §3.6 推荐词，用户可改；**模型** = Vertex Gemini 初稿，过了自动检查；**人改** = 复核时改过。", "",
           "| 模块 | 官方 | 暂定 | 模型 | 人改 | 合计 |", "|---|---|---|---|---|---|"]
    for m, st in stats.items():
        out.append("| %s | %d | %d | %d | %d | %d |" % (m, st.get("官方", 0), st.get("暂定", 0), st.get("模型", 0), st.get("人改", 0), sum(st.values())))
    out += ["", "| # | 类别 | 中文 | English | 来源 | 备注 |", "|---|---|---|---|---|---|"]
    for i, (what, k) in enumerate(PICK, 1):
        r = rows[k]
        out.append("| %d | %s | %s | %s | %s | %s |" % (i, what, cell(r["zh"]), cell(r["en"]), r["source"], cell(r["note"])))
    hard = [r for r in rows.values() if "难翻" in r["note"]]
    out += ["", "## 待用户定：难翻的招募卡简介（%d 条）" % len(hard), "", "| 干员 | 中文 | 推荐 | 候选与说明 |", "|---|---|---|---|"]
    for r in hard:
        out.append("| %s | %s | %s | %s |" % (r["key"].split(".")[1], cell(r["zh"]), cell(r["en"]), cell(r["note"])))
    (ROOT / "docs/277_english_preview.md").write_text("\n".join(out) + "\n", encoding="utf-8")
    print("docs/277_english_preview.md", len(PICK), "条 + 难翻", len(hard))


if __name__ == "__main__":
    main()
