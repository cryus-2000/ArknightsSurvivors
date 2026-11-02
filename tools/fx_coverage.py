"""特效全量覆盖表（docs/237，用户 11-02：每位干员整套替换，不留旧帧条）。

从 data/characters/*.json、seg_*.gd 与干员专属脚本、连携 / 终结技脚本、公共特效脚本、enemies.json 与敌方脚本里
抓出所有特效贴图名（fx_* / proj_*），按干员 / 敌方逐个列出，标归属组、出现位置、状态。

状态判定：
- 名字形如 fx_<x>_px_* / proj_<x>_px_*（pixelfx 新帧条）→ 已做
- tools/pixelfx_fx/coverage_<组>.json 里登记的 → 按登记（已做 / 不换 + 理由；原名重画也在这里登记 已做）
- 其余 → 未做

用法：python tools/fx_coverage.py            写 docs/237_fx_coverage.md 并打印覆盖率
      python tools/fx_coverage.py --op skadi 只打印这一人的行（组员报完成时附上）
"""
import argparse
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
G = os.path.join(ROOT, "game")
OUT = os.path.join(ROOT, "docs", "237_fx_coverage.md")

GROUPS = {
	"A": ["skadi", "hoshiguma", "lappland", "texas", "skalter"],
	"B": ["eyjafjalla", "angelina", "logos", "lumen", "suzuran"],
	"C": ["gladiia", "mizuki", "ulpianus", "specter_unchained", "kaltsit"],
	"D": ["irene", "saria", "siege", "wisadel", "exusiai"],
}
OP_GROUP = {op: g for g, ops in GROUPS.items() for op in ops}
OPS = sorted(OP_GROUP, key=lambda o: (OP_GROUP[o], GROUPS[OP_GROUP[o]].index(o)))
# 干员专属脚本（不叫 seg_<id>.gd 的）
OP_SCRIPTS = {
	"specter_unchained": ["characters/blocks/seg_specter.gd"],
	"gladiia": ["characters/blocks/fx_gladiia_s3.gd"],
	"eyjafjalla": ["characters/magma_projectile.gd"],
	"mizuki": ["characters/mizuki_s3_fx.gd"],
	"ulpianus": ["characters/ulpianus_charge_fx.gd", "characters/ulpianus_impact.gd"],
}
LINK_SCRIPTS = ["run/link_fx_a.gd", "run/link_fx_b.gd", "run/link_fx_common.gd", "run/skill_link.gd", "run/link_bond.gd"]
ULT_SCRIPTS = ["run/ult.gd", "run/ult_moves.gd", "run/ult_moves_b.gd", "run/ult_moves_c.gd", "run/ult_fx_c.gd", "run/ult_pixfx.gd"]
COMMON_SCRIPTS = ["characters/blocks/ob_fx.gd", "characters/blocks/ob_core.gd", "characters/blocks/ob_hw.gd",
	"characters/blocks/ob_summon.gd", "characters/blocks/vis_growth.gd", "characters/data_operator.gd",
	"render/vfx.gd", "run/weapons.gd", "run/combat.gd"]
ENEMY_SCRIPTS = ["enemies/telegraph.gd", "enemies/boss_patterns.gd", "enemies/enemy_ai.gd", "enemies/final_attacks.gd",
	"enemies/shot_pool.gd", "enemies/bosses/knight_boss.gd", "render/boss_beam.gd", "render/bullet_fx.gd",
	"render/final_boss_materials.gd"]
GROUP_FILES = {"A": "a", "B": "b", "C": "c", "D": "d", "E": "e", "组长": "lead"}

NAME = re.compile(r"^(fx|proj)_[a-z0-9_]+$")
LIT = re.compile(r"\"((?:fx|proj)_[a-z0-9_]+)\"")
DYN = re.compile(r"\"((?:fx|proj)_[a-z0-9_]*%[sd][a-z0-9_%]*)\"")
PX = re.compile(r"^(fx|proj)_(?!px_)[a-z0-9_]*?_px_")
FUNC = re.compile(r"^\s*(?:static\s+)?func\s+([A-Za-z0-9_]+)")


def cat_of(path):
	p = "/".join(path)
	for key, cat in (("summon", "召唤"), ("elite", "精英化"), ("rage", "成长形态"), ("progression", "成长形态"),
			("skills", "技能"), ("attack", "普攻"), ("trait", "天赋"), ("talent", "天赋"), ("hit_sources", "命中")):
		if key in p:
			if cat == "技能":
				m = re.search(r"skills/(s\d)", p)
				return "技能 " + m.group(1) if m else cat
			return cat
	return path[0] if path else "?"


def walk_json(o, path, out):
	if isinstance(o, dict):
		for k, v in o.items():
			if k in ("sprites", "extra_sprites", "gallery"):
				continue
			walk_json(v, path + [k], out)
	elif isinstance(o, list):
		for i, v in enumerate(o):
			walk_json(v, path + [str(i)], out)
	elif isinstance(o, str) and NAME.match(o):
		out.append((o, cat_of(path), "/".join(path)))


def scan_gd(rel):
	p = os.path.join(G, "scripts", rel)
	if not os.path.exists(p):
		return [], []
	hits, dyn, fn = [], [], ""
	for i, line in enumerate(open(p, encoding="utf-8"), 1):
		m = FUNC.match(line)
		if m:
			fn = m.group(1)
		if line.lstrip().startswith("#"):
			continue
		for n in LIT.findall(line):
			hits.append((n, fn, "%s:%d" % (rel, i)))
		for n in DYN.findall(line):
			dyn.append((n, "%s:%d" % (rel, i)))
	return hits, dyn


def load_overrides():
	ov = {}
	for g, f in GROUP_FILES.items():
		p = os.path.join(ROOT, "tools", "pixelfx_fx", "coverage_%s.json" % f)
		if os.path.exists(p):
			for k, v in json.load(open(p, encoding="utf-8")).items():
				if not k.startswith("_"):
					ov[k] = dict(v, by=g)
	return ov


# 连携 / 终结技贴图的两三字母简写（fx_<简写>_* / fx_lk_<简写>_*，函数名 _<简写>_*）
CODES = {"an": "angelina", "ey": "eyjafjalla", "eyja": "eyjafjalla", "gl": "gladiia", "hs": "hoshiguma", "ir": "irene",
	"irv": "irene", "la": "lappland", "lp": "lappland", "lo": "logos", "lu": "lumen", "mz": "mizuki", "sa": "saria",
	"sd": "skadi", "sk": "skalter", "sg": "siege", "sp": "specter_unchained", "sz": "suzuran", "ul": "ulpianus",
	"ws": "wisadel", "wd": "wisadel", "ka": "kaltsit", "kl": "kaltsit", "tx": "texas", "ex": "exusiai"}
CODE = re.compile(r"^(?:fx|proj)_(?:lk_)?([a-z]+?)(?:_|\d)")
FN_CODE = re.compile(r"^_?([a-z]+)_")


def owner_by_name(name, fn=""):
	s = name + " " + fn.lower()
	for op in sorted(OPS, key=len, reverse=True):
		if op in s:
			return op
	if "specter" in s:
		return "specter_unchained"
	m = CODE.match(name)
	if m and m.group(1) in CODES:
		return CODES[m.group(1)]
	m = FN_CODE.match(fn.lower())
	if m and m.group(1) in CODES:
		return CODES[m.group(1)]
	return ""


class Table:
	def __init__(self):
		self.rows = {}   # (owner, name) -> {"cats": set, "locs": list}

	def add(self, owner, name, cat, loc):
		r = self.rows.setdefault((owner, name), {"cats": set(), "locs": []})
		r["cats"].add(cat)
		if len(r["locs"]) < 4:
			r["locs"].append(loc)


def status(owner, name, ov):
	o = ov.get("%s|%s" % (owner, name)) or ov.get("*|%s" % name)
	if o:
		return o.get("status", "?"), o.get("new", ""), o.get("why", "")
	if PX.match(name):
		return "已做", name, ""
	return "未做", "", ""


def build():
	ov = load_overrides()
	ops, link, ult, common, enemy = Table(), Table(), Table(), Table(), Table()
	dyns = []
	for op in OPS:
		p = os.path.join(G, "data", "characters", op + ".json")
		out = []
		walk_json(json.load(open(p, encoding="utf-8")), [], out)
		for n, c, path in out:
			ops.add(op, n, c, "json " + path)
		short = "specter" if op == "specter_unchained" else op
		for rel in ["characters/blocks/seg_%s.gd" % short] + OP_SCRIPTS.get(op, []):
			hits, dyn = scan_gd(rel)
			for n, fn, loc in hits:
				ops.add(op, n, "脚本", loc)
			dyns += dyn
	for files, t in ((LINK_SCRIPTS, link), (ULT_SCRIPTS, ult)):
		for rel in files:
			hits, dyn = scan_gd(rel)
			dyns += dyn
			for n, fn, loc in hits:
				t.add(owner_by_name(n, fn) or "公共", n, "连携" if t is link else "终结技", loc)
	for rel in COMMON_SCRIPTS:
		hits, dyn = scan_gd(rel)
		dyns += dyn
		for n, fn, loc in hits:
			common.add("公共", n, "公共", loc)
	ed = json.load(open(os.path.join(G, "data", "enemies.json"), encoding="utf-8"))
	for en, spec in ed.get("enemies", {}).items():
		out = []
		walk_json(spec, [], out)
		for n, c, path in out:
			enemy.add(en, n, path.split("/")[0], "enemies.json " + en + "/" + path)
	for rel in ENEMY_SCRIPTS:
		hits, dyn = scan_gd(rel)
		dyns += dyn
		for n, fn, loc in hits:
			enemy.add(os.path.basename(rel)[:-3], n, "脚本", loc)
	return ov, ops, link, ult, common, enemy, dyns


def rows_md(t, ov, group_of, filt=None):
	lines = ["| 归属 | 组 | 特效名 | 出现在 | 状态 | 新名 / 理由 | 位置（前 4 处） |", "|---|---|---|---|---|---|---|"]
	cnt = {"已做": 0, "不换": 0, "未做": 0}
	for (owner, name), r in sorted(t.rows.items()):
		if filt and owner != filt:
			continue
		st, new, why = status(owner, name, ov)
		cnt[st if st in cnt else "未做"] += 1
		lines.append("| %s | %s | `%s` | %s | %s | %s | %s |" % (owner, group_of(owner), name, "、".join(sorted(r["cats"])),
			st, (("`%s`" % new) if new and new != name else "") + ((" " + why) if why else ""), "<br>".join(r["locs"])))
	return lines, cnt


def pct(c):
	tot = sum(c.values())
	return "%d / %d（%.0f%%）" % (c["已做"] + c["不换"], tot, 100.0 * (c["已做"] + c["不换"]) / tot) if tot else "0 / 0"


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--op", default="")
	a = ap.parse_args()
	ov, ops, link, ult, common, enemy, dyns = build()
	og = lambda o: OP_GROUP.get(o, "组长")
	if a.op:
		for t, title in ((ops, "干员"), (link, "连携"), (ult, "终结技")):
			lines, c = rows_md(t, ov, og, a.op)
			print("## %s %s  %s" % (a.op, title, pct(c)))
			print("\n".join(lines))
		return 0
	md = ["# 237 特效全量覆盖表（自动生成，别手改）", "",
		"用户 11-02：每位干员的特效**整套替换**，不能有打到敌人的旧帧条漏网。本表由 `python tools/fx_coverage.py` 生成；"
		"状态改动写进各组自己的 `tools/pixelfx_fx/coverage_<组>.json`（键 `干员|特效名`，值 `{\"status\": \"已做\"|\"不换\", \"new\": 新名, \"why\": 理由}`；"
		"`*|特效名` 对所有归属生效），然后重新生成。新帧条按 `fx_<id>_px_*` 命名的自动算已做。",
		"", "**验收口径（docs/229 §9 补充）：** 某位干员只有在本表里他的全部行（干员段 + 连携段）都是「已做」或「不换（有理由）」才算完成；"
		"组员报完成时附 `python tools/fx_coverage.py --op <id>` 的输出。终结技主视觉按规范只统一不重做，单列不计入完成判定。",
		"", "**不在表里的：** 字符串拼出来的动态名（见文末清单，归属组手查）、人物本体精灵（op_*）。", ""]
	summary = ["## 0 覆盖率", "", "| 归属 | 组 | 干员段 | 连携段 | 终结技（不计） |", "|---|---|---|---|---|"]
	tot = {"已做": 0, "不换": 0, "未做": 0}
	for op in OPS:
		_, c1 = rows_md(ops, ov, og, op)
		_, c2 = rows_md(link, ov, og, op)
		_, c3 = rows_md(ult, ov, og, op)
		for k in tot:
			tot[k] += c1[k] + c2[k]
		summary.append("| %s | %s | %s | %s | %s |" % (op, og(op), pct(c1), pct(c2), pct(c3)))
	_, ce = rows_md(enemy, ov, lambda o: "E")
	_, cc = rows_md(common, ov, lambda o: "组长")
	summary += ["", "干员合计（干员段 + 连携段）：%s；敌方：%s；公共：%s" % (pct(tot), pct(ce), pct(cc)), ""]
	md += summary
	for title, t, g in (("1 干员（技能 / 普攻 / 天赋 / 召唤 / 精英化 / 状态）", ops, og), ("2 连携（link_fx_*、skill_link、link_bond）", link, og),
			("3 终结技（只统一不重做，不计完成）", ult, og), ("4 公共（ob_fx / vfx / weapons …，组长与 fx-basic-atk）", common, lambda o: "组长"),
			("5 敌方 / Boss（E 组）", enemy, lambda o: "E")):
		lines, c = rows_md(t, ov, g)
		md += ["## " + title, "", "覆盖：" + pct(c), ""] + lines + [""]
	md += ["## 6 动态拼名（不进上表，归属组手查）", ""]
	for n, loc in sorted(set(dyns)):
		md.append("- `%s`  %s" % (n, loc))
	open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(md) + "\n")
	print("\n".join(summary))
	print("写入", os.path.relpath(OUT, ROOT))
	return 0


if __name__ == "__main__":
	sys.exit(main())
