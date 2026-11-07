"""新干员必备件检查（只读，.claude/skills/new-operator 第 ⑧ 步）。

  python tools/new_op_check.py <id> [<id> ...]     # 逐项列「好 / 缺 / 注」
  python tools/new_op_check.py --all               # 全员跑一遍（看哪些人哪些项还缺）
  python tools/new_op_check.py <id> --quiet        # 只列 缺 / 注

缺 = 新干员进池前必须补的；注 = 提醒（借用占位、代码里写死的专属接入、启发式查不准的项），写进设计稿 §7 待办即可。
退出码：有「缺」为 1，否则 0。不启动 Godot、不改任何文件。
--all 跑老干员时「节点画面 全部找不到」多半是启发式看不见（节点靠 seg 参数 + 转平面按条件分支画），以 docs/310 全表为准；
新干员按本脚本的命名习惯接（节点 id / src / _FXR.ev 事件名出现在本人 fx_pxplane_<前缀>.gd 里）就能被认出。

「成长节点画面事件」是启发式：转平面接管后 o.fx 不画（docs/310 §2），节点要靠转平面画出来。
本脚本对每个节点收集 它的积木里的 src 名 / 节点 id / 扩展积木在 seg_<id>.gd 里发出的 _FXR.ev 事件名，
再到 render/fx_pxplane*.gd 里找；一个都找不到报「缺」。找到不等于看得清，最终以图鉴录像为准。
"""
import argparse, glob, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
G = os.path.join(ROOT, "game")


def rd(p):
    try:
        with open(p, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def rj(p):
    try:
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def all_ids():
    return sorted(os.path.splitext(os.path.basename(p))[0] for p in glob.glob(os.path.join(G, "data", "characters", "*.json")))


def walk(o, path=""):
    """深度遍历，产出 (路径, 字典)"""
    if isinstance(o, dict):
        yield path, o
        for k, v in o.items():
            if not str(k).startswith("_"):
                yield from walk(v, path + "/" + str(k))
    elif isinstance(o, list):
        for i, v in enumerate(o):
            yield from walk(v, "%s[%d]" % (path, i))


PH = re.compile(r"\{\$([^}]*)\}")
KEY = re.compile(r"\$([A-Za-z_][A-Za-z0-9_]*)")


class Rep:
    def __init__(self, oid, quiet):
        self.oid, self.quiet, self.rows = oid, quiet, []

    def ok(self, item, msg=""):
        self.rows.append(("好", item, msg))

    def miss(self, item, msg):
        self.rows.append(("缺", item, msg))

    def note(self, item, msg):
        self.rows.append(("注", item, msg))

    def chk(self, cond, item, msg_bad, msg_ok=""):
        (self.ok(item, msg_ok) if cond else self.miss(item, msg_bad))
        return cond

    def dump(self):
        n_miss = sum(1 for r in self.rows if r[0] == "缺")
        n_note = sum(1 for r in self.rows if r[0] == "注")
        print("== %s：缺 %d · 注 %d · 好 %d" % (self.oid, n_miss, n_note, len(self.rows) - n_miss - n_note))
        for lv, item, msg in self.rows:
            if self.quiet and lv == "好":
                continue
            print("  [%s] %s%s" % (lv, item, ("：" + msg) if msg else ""))
        return n_miss


def tex_exists(name):
    for d in ("operators", "fx", "ui", ""):
        for pat in ("%s/**/%s.png", "%s/**/%s@2x.png", "%s/**/%s@1x.png"):
            if glob.glob(os.path.join(G, "art", pat % (d, name)), recursive=True):
                return True
    return False


def check(oid, quiet=False):
    R = Rep(oid, quiet)
    p = os.path.join(G, "data", "characters", oid + ".json")
    d = rj(p)
    if d is None:
        R.miss("characters/%s.json" % oid, "不存在或不是合法 JSON")
        return R.dump()
    base = d.get("base", {})

    # ---- ③ 主 JSON 字段
    for k in ("id", "name", "en", "class", "lanes", "col", "trail_col", "base", "leader", "sprites",
              "attack", "skills", "talent", "hit_sources", "progression", "gallery"):
        R.chk(k in d and d[k] not in ("", [], {}), "字段 " + k, "没写")
    if not d.get("branch"):
        R.note("字段 branch", "没写原作职业分支名（代码不读，只作资料；拉普兰德写了「领主」）")
    R.chk(d.get("id") == oid, "id 与文件名一致", "id = %r" % d.get("id"))
    sk = d.get("skills", [])
    R.chk(len(sk) == 3, "三技能", "skills 有 %d 条" % len(sk))
    bsk = (d.get("blocks") or {}).get("skills", [])
    for i, s in enumerate(sk):
        for k in ("name", "en", "sp", "desc", "icon"):
            R.chk(k in s, "skills[%d].%s" % (i, k), "没写")
        has_dur = s.get("permanent") or "dur" in s or (i < len(bsk) and "dur" in bsk[i])
        if not has_dur:
            R.note("skills[%d] 时长" % i, "skills 与 blocks.skills 都没写 dur / permanent（瞬发或手写脚本定时）")
    for k in ("max_hp", "armor", "arts_res", "regen"):
        R.chk(k in d.get("leader", {}), "leader." + k, "没写")
    gal = d.get("gallery", {})
    R.chk(bool(gal.get("desc")), "gallery.desc（图鉴说明）", "没写")
    R.chk(bool(gal.get("tags")), "gallery.tags", "没写")
    if R.chk(bool(gal.get("intro")), "gallery.intro（招募卡简介）", "没写（用户亲写，先交草稿）"):
        if "草稿" in gal.get("intro", ""):
            R.note("gallery.intro", "还是草稿，等用户定稿")
    blocks = d.get("blocks")
    if not blocks and not d.get("script", "").endswith("data_operator.gd"):
        R.note("blocks", "没有 blocks：手写脚本干员（%s），积木校验不适用" % d.get("script"))

    # ---- 成长线结构
    prog = d.get("progression", [])
    types = [(x.get("type"), x.get("level")) for x in prog]
    want = [("custom", None), ("custom", None), ("elite", 1), ("custom", None), ("custom", None), ("elite", 2)]
    R.chk(types == want, "成长线 6 节点结构", "实际 %s（应为 节点 节点 精一 分支 路线 精二）" % types)
    node_ids = []
    for x in prog:
        if x.get("type") == "custom":
            node_ids.append(x.get("id"))
            for k in ("name", "icon", "desc"):
                R.chk(bool(x.get(k)), "节点 %s.%s" % (x.get("id"), k), "没写")
        for sub in ("branch", "routes"):
            for kk, v in (x.get(sub) or {}).items():
                node_ids.append(v.get("id", kk))
                for k in ("name", "icon", "desc"):
                    R.chk(bool(v.get(k)), "节点 %s.%s.%s" % (x.get("id"), sub, kk), "没写 " + k)
        if x.get("type") == "elite":
            R.chk(bool(x.get("attack", {}).get("name")), "精%s 普攻变化 attack.name" % x.get("level"), "没写（docs/91 §0.5）")
    branch_node = prog[3] if len(prog) > 3 else {}
    R.chk(bool(branch_node.get("branch")) and bool(branch_node.get("branch_desc")) and bool(branch_node.get("bot")),
          "节点 4 二选一（branch / branch_desc / bot）", "不全")
    R.chk(bool(prog[4].get("routes")) if len(prog) > 4 else False, "节点 5 路线 routes", "没写")
    node_ids = list(dict.fromkeys([n for n in node_ids if n]))
    for x in prog:
        icon = x.get("icon")
        if icon and not tex_exists(icon):
            R.miss("节点图标 " + icon, "game/art 下找不到")
    for s in sk:
        if s.get("icon") and not tex_exists(s["icon"]):
            R.miss("技能图标 " + s["icon"], "game/art 下找不到（tools/make_skill_icons.py）")

    # ---- 文字占位 {$key}
    bad = set()
    # 全局占位：operator_defs.gd 往占位表里加的 tb["k_*"]（开局档位 / 密度换算）
    glob_keys = set(re.findall(r'tb\["(\w+)"\]', rd(os.path.join(G, "scripts", "characters", "operator_defs.gd"))))
    for path, o in walk({k: d.get(k) for k in ("attack", "skills", "talent", "progression", "gallery")}):
        for k, v in o.items():
            if isinstance(v, str):
                for ph in PH.findall(v):
                    for key in KEY.findall("$" + ph):
                        if key not in base and key not in glob_keys:
                            bad.add(key)
    R.chk(not bad, "文字占位都在 base", "base 里没有：" + "、".join(sorted(bad)))

    # ---- 积木：src 登记、节点都有积木
    srcs = set()
    hs = d.get("hit_sources", {})
    if blocks:
        for path, o in walk(blocks):
            if "shape" in o and isinstance(o.get("src"), str):
                srcs.add(o["src"])
        miss = sorted(s for s in srcs if s not in hs)
        R.chk(not miss, "伤害 src 都在 hit_sources", "没登记：" + "、".join(miss))
        bp = blocks.get("progression", {})
        s_blocks = json.dumps(blocks, ensure_ascii=False)
        for n in node_ids:
            R.chk(n in bp or re.search(r"node:%s\b" % re.escape(n), s_blocks), "节点 %s 有积木" % n,
                  "blocks.progression 里没有、也没有积木带 cond node:%s" % n)
        R.chk(len(blocks.get("skills", [])) == 3, "blocks.skills 3 条", "有 %d 条" % len(blocks.get("skills", [])))
        R.chk("attack" in blocks, "blocks.attack", "没写")

    # ---- ④ 转平面与节点画面事件
    pxp_main = rd(os.path.join(G, "scripts", "render", "fx_pxplane.gd"))
    m = re.search(r"const IDS := \{([^\n]*)\}", pxp_main)
    in_ids = bool(m and re.search(r'"%s"\s*:\s*true' % re.escape(oid), m.group(1)))
    R.chk(in_ids, "fx_pxplane.gd IDS（转平面接管）", "不在名单里：特效还是旧画法")
    R.chk(os.path.exists(os.path.join(G, "data", "fx_pxplane", oid + ".json")), "data/fx_pxplane/%s.json（颗粒 / 照地光）" % oid, "没有")
    R.chk(os.path.exists(os.path.join(G, "data", "pxp_%s.json" % oid)), "data/pxp_%s.json（转平面帧条表）" % oid, "没有（tools/pxplane_bake_%s.py）" % oid)
    pxp_files = [f for f in glob.glob(os.path.join(G, "scripts", "render", "fx_pxplane*.gd"))]
    mp = re.search(r'"res://data/pxp_%s\.json":\s*"(\w*)"' % re.escape(oid), pxp_main)
    R.chk(mp is not None, "fx_pxplane.gd METAS（帧条表 + 键前缀）", "没登记 pxp_%s.json" % oid)
    pre = mp.group(1).rstrip("_") if mp else ""

    def _stem(f):
        return os.path.basename(f)[len("fx_pxplane_"):-3]
    own_px = [f for f in pxp_files if os.path.basename(f) != "fx_pxplane.gd" and pre
              and (_stem(f) == pre or _stem(f).startswith(pre) or pre.startswith(_stem(f)))]
    if own_px:
        R.ok("本人转平面画法文件", ", ".join(os.path.basename(f) for f in own_px))
    elif in_ids:
        R.note("本人转平面画法文件", "没有单独的 fx_pxplane_<前缀>.gd，画法写在 fx_pxplane.gd 里（节点事件按全文件查，可能误判为有）")
    px_text = "\n".join(rd(f) for f in own_px + [os.path.join(G, "scripts", "render", "fx_pxplane.gd")])
    seg_p = os.path.join(G, "scripts", "characters", "blocks", "seg_%s.gd" % oid)
    seg = rd(seg_p)
    n_vis = 0
    seg_funcs = re.split(r"\n(?=(?:static )?func )", seg) if seg else []
    if blocks:
        bp = blocks.get("progression", {})
        for n in node_ids + ["elite1", "elite2"]:
            sub = [bp.get(n)] if n in bp else []
            for path, o in walk(blocks):
                if isinstance(o.get("cond"), str) and re.search(r"node:%s\b" % re.escape(n), o["cond"]):
                    sub.append(o)
            toks = set()
            if n not in ("elite1", "elite2"):
                toks.add(n)
            evs = set()
            for o2 in sub:
                for _, o3 in walk(o2):
                    if isinstance(o3.get("src"), str):
                        toks.add(o3["src"])
                    v = o3.get("verb")
                    if isinstance(v, str) and seg:
                        mm = re.search(r'"verb\.%s"[^\n]*:\s*\n\s*(\w+)\(' % re.escape(v), seg)
                        if mm:
                            fm = re.search(r"func %s\(.*?(?=\n(?:static )?func |\Z)" % mm.group(1), seg, re.S)
                            if fm:
                                evs |= set(re.findall(r'_FXR\.ev\(\s*\w+\s*,\s*"(\w+)"', fm.group(0)))
            # seg 里提到这个节点的函数（cond node:<n> / "<n>" 参数版本）发出的转平面事件
            if seg and n not in ("elite1", "elite2"):
                for fb in seg_funcs:
                    if re.search(r'node:%s\b|"%s"' % (re.escape(n), re.escape(n)), fb):
                        evs |= set(re.findall(r'_FXR\.ev\(\s*\w+\s*,\s*"(\w+)"', fb))
            found = sorted(t for t in toks | evs if re.search(r'"%s"' % re.escape(t), px_text) or (t in evs and t in px_text))
            if found:
                R.ok("节点画面 %s" % n, "转平面里有：" + "、".join(found))
                n_vis += 1
            elif not in_ids:
                R.note("节点画面 %s" % n, "未接转平面，按旧画法（o.fx）查")
            else:
                R.note("节点画面 %s" % n, "启发式没找到（%s）：可能走 shape 钩子按条件分支画，也可能真的没画；"
                       "对 docs/310 全表 + 图鉴录像确认" % ("、".join(sorted(toks | evs)) or "无名字可查"))
        if in_ids and n_vis == 0:
            R.miss("节点画面", "全部节点在转平面里都找不到对应：o.fx 不画，节点提示要发 _FXR.ev（docs/310 §2）")

    # ---- 帧条
    spr = d.get("sprites", {})
    for slot, v in spr.items():
        if isinstance(v, dict) and "tex" in v:
            t = v["tex"]
            if not tex_exists(t):
                R.miss("帧条 %s（%s）" % (slot, t), "game/art 下没有")
            elif not t.startswith("op_%s_" % oid):
                R.note("帧条 %s" % slot, "借用 %s（占位）" % t)
    for x in d.get("extra_sprites", []):
        R.chk(x in spr, "extra_sprites.%s 有槽" % x, "sprites 里没有这个槽")
    for slot in ("idle", "run", "attack", "death"):
        R.chk(slot in spr, "帧条槽 " + slot, "没写")
    if "skill" not in spr:
        R.note("帧条槽 skill", "没写 skill 槽（技能动作用别的槽，见 sprites.skills）")
    idx = rj(os.path.join(G, "art", "index.json")) or {}
    own_tex = [v["tex"] for v in spr.values() if isinstance(v, dict) and str(v.get("tex", "")).startswith("op_%s_" % oid)]
    nidx = [t for t in own_tex if not any(t + suf in idx for suf in ("", "@2x", "@1x"))]
    R.chk(not nidx, "帧条进 art/index.json", "没进索引（先跑 python tools/asset_index.py）：" + "、".join(nidx))
    R.chk(oid in ((rj(os.path.join(G, "art", "operators", "avatar_eyes.json")) or {}).get("ops", {})),
          "avatar_eyes.json（HUD 头像眼睛对齐）", "没有")

    # ---- 其他数据
    lore = (rj(os.path.join(G, "data", "lore.json")) or {}).get(oid)
    if R.chk(isinstance(lore, dict), "lore.json 档案", "没有"):
        R.chk(bool(lore.get("profile")) and bool(lore.get("lore")), "lore.json profile + lore", "不全")
    bal = rj(os.path.join(G, "data", "balance.json")) or {}
    R.chk(oid in bal.get("operators", {}), "balance.json operators.%s" % oid, "没有（先全 0）")
    R.chk(oid in bal.get("vis_nodes", {}).get("team", {}), "balance.json vis_nodes/team（精二全队效果）", "没有（docs/249）")
    ut = (rj(os.path.join(G, "data", "ult_text.json")) or {}).get("ops", {}).get(oid, {})
    R.chk(bool(ut.get("ult")), "ult_text.json 终结技", "没有")
    R.chk(bool(ut.get("link")), "ult_text.json 连携", "没有")
    R.chk(oid in (rj(os.path.join(G, "data", "ult_audio.json")) or {}).get("ops", {}), "ult_audio.json", "没有")
    br = rd(os.path.join(ROOT, "tools", "balance_run.py"))
    mo = re.search(r"\nOPS\s*=\s*\[(.*?)\]", br, re.S)
    R.chk(bool(mo and ('"%s"' % oid) in mo.group(1)), "tools/balance_run.py OPS", "没加")

    # ---- ⑥ 音效 / 语音
    vp = (rj(os.path.join(G, "audio", "voice", "voice_pools.json")) or {}).get("pools", {}).get(oid)
    if R.chk(bool(vp), "voice_pools.json", "没有语音池"):
        files = [c for lst in vp.values() if isinstance(lst, list) for c in lst]
        nf = [c for c in files if not os.path.exists(os.path.join(G, "audio", "voice", c + ".ogg"))]
        R.chk(not nf, "语音文件", "缺 .ogg：" + "、".join(sorted(set(nf))))
    vm = rj(os.path.join(G, "audio", "voice", "voice_manifest.json")) or {}
    R.chk(oid in vm.get("operators", {}), "voice_manifest.json operators（原作编号）", "没有")
    sfx = rd(os.path.join(G, "scripts", "sfx.gd"))
    own_sfx = glob.glob(os.path.join(G, "audio", "sfx", "op_%s_*.wav" % oid))
    if own_sfx:
        R.ok("专属音效", "%d 个 op_%s_*" % (len(own_sfx), oid))
    elif ("op_%s_" % oid) in sfx:
        R.note("专属音效", "没有 op_%s_* 文件，sfx.gd 里有映射（OP_ALT 借用）" % oid)
    else:
        R.note("专属音效", "没有文件也没有 OP_ALT 映射：普攻 / 技能会用缺省音")
    R.chk(bool(glob.glob(os.path.join(G, "audio", "sfx", "ult_%s_*.wav" % oid))), "终结技音效 ult_%s_*" % oid, "没有（docs/205，录音候选给用户挑）")

    # ---- 专属脚本
    if seg:
        R.chk(os.path.exists(seg_p + ".uid"), "seg_%s.gd.uid" % oid, "没有（让 Godot 生成，随脚本同一提交）")
        chain = [rd(f) for f in glob.glob(os.path.join(G, "scripts", "characters", "**", "*.gd"), recursive=True)]
        R.chk(any(('extends "res://scripts/characters/blocks/seg_%s.gd"' % oid) in t for t in chain), "seg_%s.gd 接进继承链" % oid,
              "没有文件 extends 它（op_blocks.gd 链尾要改指向）")
        R.note("专属脚本", "有 seg_%s.gd：设计稿 §3 要写明为什么积木不够" % oid)
    for name, rel in (("测试场景", "tests/%s_*_test.gd" % oid),):
        g2 = glob.glob(os.path.join(G, rel))
        if g2:
            R.ok(name, ", ".join(os.path.basename(x) for x in g2))

    # ---- 文档
    docs = glob.glob(os.path.join(ROOT, "docs", "*.md"))
    design = [f for f in docs if ("`%s`" % oid) in rd(f).split("\n", 1)[0]]
    if design:
        R.ok("设计稿（docs 标题含 `%s`）" % oid, ", ".join(os.path.basename(f) for f in design))
    elif any(oid in rd(os.path.join(ROOT, "docs", f)) for f in ("61_operator_blocks.md", "91_elite_forms.md")):
        R.note("设计稿", "没有单独设计稿；老干员的设计分散在 docs/59 / 61 / 91 / 202（新干员必须有一份，照 docs/122）")
    else:
        R.miss("设计稿（docs 标题含 `%s`）" % oid, "没找到（照 .claude/skills/new-operator/templates/design_template.md）")
    d76 = rd(os.path.join(ROOT, "docs", "76_language_style.md"))
    appx = d76[d76.find("## 附录 A"):] if "## 附录 A" in d76 else ""
    R.chk(d.get("name", "?") in appx, "docs/76 附录 A 来源", "附录 A 里没有这名干员")

    # ---- 纯数据化缺口：代码表里写死的接入（只提示）
    hard = {
        "core/roster.gd（稀有度 / 寻访权重）": "scripts/core/roster.gd",
        "sfx.gd（音色 / 响度表）": "scripts/sfx.gd",
        "art.gd（帧条别名 / 帧数表）": "scripts/art.gd",
        "run/skill_link.gd（连携）": "scripts/run/skill_link.gd",
        "run/combo.gd（精英读招）": "scripts/run/combo.gd",
        "run/ult_aim.gd（终结技瞄准预览）": "scripts/run/ult_aim.gd",
        "render/melee_impact.gd（命中色）": "scripts/render/melee_impact.gd",
    }
    for label, rel in hard.items():
        if ('"%s"' % oid) in rd(os.path.join(G, rel)):
            R.note("代码写死", label)
    ultm = [os.path.basename(f) for f in glob.glob(os.path.join(G, "scripts", "run", "ult_moves*.gd")) if ('"%s"' % oid) in rd(f)]
    if ultm:
        R.note("代码写死", "终结技招式实现：" + ", ".join(ultm))
    else:
        R.miss("终结技实现", "run/ult_moves*.gd 里没有 \"%s\"" % oid)
    return R.dump()


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("ids", nargs="*")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()
    ids = all_ids() if a.all else a.ids
    if not ids:
        ap.error("给干员 id 或 --all")
    total = 0
    for oid in ids:
        total += check(oid, a.quiet)
    print("合计缺 %d 项" % total)
    sys.exit(1 if total else 0)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
