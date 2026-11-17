# -*- coding: utf-8 -*-
"""敌种 id 写死点清单（docs/367 §3、docs/368 §1）：在 game/scripts/**/*.gd 与主题包 game/themes/**/*.gd 里找 "敌种 id" 字符串字面量（只认整串等于 enemies.json 里某个 id 的引号字面量；
注释与说明文字里的不算），按用途分类计数。

    python tools/enemy_id_scan.py              # 汇总表
    python tools/enemy_id_scan.py --files      # 按文件
    python tools/enemy_id_scan.py --list CAT   # 列出某一类的每一处（文件:行  内容）

分类（按文件路径；Boss 自己的脚本里引用自己 / 自己召唤物的另算「Boss 内部」）：
  boss_self  Boss 脚本内部引用自己或自己的召唤物（enemies/bosses/<名>*.gd、render/<名>*_draw.gd 里出现 <名>）——保持不动
  boss_other Boss 脚本里引用别的敌种（搭档、召唤、联动）
  rule       玩法规则（run/、enemies/ 除 bosses、boss_ai、combat、endings、relic_fx、characters/）
  render     画法 / 特效 / 预警（render/、vfx）
  ui         图鉴 / HUD / 结算 / 界面（gallery、screens/、ui）
  test       测试与机器人驱动（autotest、bot、run/boss_bench、run/*_demo、tests 不扫）
  data       数据门面（data.gd、enemy_db、art.gd 的贴图映射）
  theme      主题包里的脚本（game/themes/<id>/mech|mod/…，docs/364 / 368）：本来就是该主题的内容，允许写自己的敌种
  fp         误报白名单（和敌种同名、但不是敌种引用：德克萨斯的 "path"、特效种类 "tracer"、伤害来源名 "tear"、积木字段 "knight" 等，见 FP）
"""
import argparse, glob, json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import theme_paths as TP

ROOT = TP.ROOT
SCRIPTS = os.path.join(ROOT, "game", "scripts")
THEMES = os.path.join(ROOT, "game", "themes")
## 误报白名单：(相对路径前缀, 这一行里出现的片段)——命中就记 fp，不算写死（docs/368 §1）
FP = [
    ("characters/", '"path"'),                 # 德克萨斯「沿路径」：积木 center / along 字段的值
    ("run/combo.gd", '"path"'),               # 连携里德克萨斯冲刺的 path 键
    ("", '"kind": "tracer"'),                  # 特效种类「拖尾线」
    ("run/combat.gd", 'NO_LOG := ["tear"'),   # 伤害来源名「泪」（不记 dmg_log）
    ("run/telemetry.gd", '"tear"'),            # 伤害来源名
    ("run/run_stats.gd", 'src == "tear"'),     # 伤害来源名
    ("characters/", '"knight"'),               # 召唤物扩展段积木字段 knight（同时治骑士同伴）
    ("run/combat.gd", 'for c in ["founder", "skimmer", "boss", "other"]'),   # 控制遥测报表的分类名（映射已读 enemies.json ctrl_cat）
    ("run/combat.gd", '"founder"'),            # 同上（注释行之外的分类名）
    ("run/build_guide.gd", '"duck"]'),         # 宝箱来源名（elite / boss / squad / duck）
    ("run/run_stats.gd", '"bosses": [{"type": "path"'),   # 作战记录截图用的样例数据
    ("run/run_stats.gd", '{"type": "paranoia", "name"'),
    ("run/run_stats.gd", '"final_boss": {"type": "paranoia"'),
    ("game.gd", 'ThemePack.make_module(self, "'),   # 主题模块键（g.ishar / g.duck / g.knight），不是敌种
    ("run/telemetry.gd", '"duck": g.duck'),   # 遥测字段名
]
STR = re.compile(r'"([a-z][a-z0-9_]*)"')


def enemy_ids():
    return set(json.load(open(TP.data_file("enemies.json"), encoding="utf-8"))["enemies"])


def code_part(line):
    """去掉 ## / # 注释（不在字符串里的），返回代码部分"""
    out, q = [], False
    for i, ch in enumerate(line):
        if ch == '"':
            q = not q
        if ch == "#" and not q:
            break
        out.append(ch)
    return "".join(out)


BOSS_FAMILY = {   # Boss 脚本文件名前缀 → 它自己 / 召唤物的敌种 id
    "ishar": {"ishar", "tear", "ishar_tear"}, "paranoia": {"paranoia", "paranoia_cocoon", "fractal"}, "izumik": {"izumik", "offspring"},
    "knight_boss": {"knight_boss", "knight"}, "saint": {"iberia", "carmen"}, "bishop": {"bishop"}, "archon": {"archon"},
    "immortal": {"immortal"}, "path": {"path", "tracer"},
}


def category(rel, eid, line=""):
    f = rel.replace("\\", "/")
    if f.startswith("themes/"):
        return "theme"
    for pre, frag in FP:
        if f.startswith(pre) and frag in line:
            return "fp"
    base = os.path.basename(f)
    if f.startswith("enemies/bosses/") or (f.startswith("render/") and any(base.startswith(k) for k in BOSS_FAMILY)):
        for k, fam in BOSS_FAMILY.items():
            if base.startswith(k):
                return "boss_self" if eid in fam else "boss_other"
        return "boss_other"
    if base in ("autotest.gd", "bot.gd", "boss_bench.gd", "god_suite.gd", "motion_shot.gd", "ult_bench.gd") or base.endswith("_demo.gd") or base == "demo.gd":
        return "test"
    if f.startswith("render/") or base == "vfx.gd":
        return "render"
    if base in ("gallery.gd", "ui.gd") or f.startswith("screens/"):
        return "ui"
    if base in ("data.gd", "art.gd") or f.startswith("enemies/enemy_db"):
        return "data"
    return "rule"


def scan():
    ids = enemy_ids()
    rows = []
    files = [(p, os.path.relpath(p, SCRIPTS)) for p in glob.glob(os.path.join(SCRIPTS, "**", "*.gd"), recursive=True)]
    files += [(p, "themes/" + os.path.relpath(p, THEMES)) for p in glob.glob(os.path.join(THEMES, "**", "*.gd"), recursive=True)]
    for p, rel in sorted(files, key=lambda x: x[1]):
        rel = rel.replace("\\", "/")
        for ln, line in enumerate(open(p, encoding="utf-8"), 1):
            code = code_part(line)
            for m in STR.finditer(code):
                if m.group(1) in ids:
                    rows.append((rel, ln, m.group(1), category(rel, m.group(1), code), line.strip()[:160]))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--files", action="store_true")
    ap.add_argument("--list")
    a = ap.parse_args()
    for s in (sys.stdout,):
        try:
            s.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            pass
    rows = scan()
    if a.list:
        for r in rows:
            if r[3] == a.list:
                print("%s:%d  [%s]  %s" % (r[0], r[1], r[2], r[4]))
        return 0
    if a.files:
        by = {}
        for r in rows:
            by.setdefault((r[3], r[0]), 0)
            by[(r[3], r[0])] += 1
        for (c, f), n in sorted(by.items(), key=lambda x: (x[0][0], -x[1])):
            print("%-10s %4d  %s" % (c, n, f))
        return 0
    cats = {}
    files = {}
    for r in rows:
        cats[r[3]] = cats.get(r[3], 0) + 1
        files.setdefault(r[3], set()).add(r[0])
    core = [r for r in rows if r[3] not in ("theme", "fp")]
    print("敌种 id 字面量：%d 处 / %d 个文件（不含主题包与误报：核心 %d 处 / %d 个文件）" % (len(rows), len({r[0] for r in rows}), len(core), len({r[0] for r in core})))
    for c in ("boss_self", "boss_other", "rule", "render", "ui", "test", "data", "theme", "fp"):
        print("  %-10s %4d 处 / %3d 个文件" % (c, cats.get(c, 0), len(files.get(c, ()))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
