"""素材命名与目录检查（docs/189 的机检部分）。只读，不改任何文件；退出码缺省 0，--strict 时有 ERROR 返回 1（check.py 按 ERROR 判失败，WARN / INFO 只报告）。

    python tools/asset_lint.py              # 汇总 + 每条规则前 8 例
    python tools/asset_lint.py --all        # 列出全部
    python tools/asset_lint.py --json out.json

查什么（规则编号对应 docs/189 §3–§4）：
    N1 ERROR  文件名只许小写字母、数字、下划线（+ @1x / @2x），不许中文、空格、大写、连字符
    N2 WARN   运行时贴图前缀不在登记表里（docs/189 §3.1）
    N3 WARN   op_ / e_ 后的 id 在 data 里找不到（干员 = game/data/characters/*.json，敌人 = enemies.json 及脚本 / 数据里出现过的 e_<id>）
    N4 WARN   fx_ / proj_ / skill_ 后的主人 id 是干员 id 的缩写（fx_eyja、skill_specter …），应写全
    N5 WARN   召唤物没带主人前缀（op_mon3tr_* 应为 op_kaltsit_mon3tr_*，docs/98 §1）
    N6 WARN   名字带版本号 / 临时后缀（_v2、_old、_new、_bak、_tmp、_copy、_test）
    N7 INFO   历史遗留名（水月 player_* / mizuki_runtime_*、初版占位 drifter 等），登记在 LEGACY，不报错
    D1 WARN   game/ 下素材放错目录（音乐不是 ogg、音效不是 wav、语音不是 <干员>_<事件>.ogg、贴图在 audio/ 里 …）
    D2 WARN   源文件放在运行时目录（game/audio/voice/masters 等）
    D3 INFO   收货区 art/incoming 里的非运行时文件（交接文档、清单、批次子目录）：接入后应归档到 art/archive/
    H1 INFO   同内容不同名（sha256 相同）
    L1 ERROR  运行时贴图还在收货区（art/incoming 根目录或 portraits/ / optical_fx/）：游戏不读这里，要搬进 game/art（tools/asset_paths.py 给新路径）
    L2 ERROR  同名贴图出现在 game/art 两个目录（索引名必须全局唯一，docs/189 §2）
"""
import argparse, collections, hashlib, json, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INC = "art/incoming"
RUNTIME_SUBDIRS = ("portraits", "optical_fx")   # 迁移前 art/incoming 下游戏按名字读的子目录（L1 认旧位置用）

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asset_paths import LEGACY, PREFIXES, SUMMONS, index_key   # 前缀登记表与 asset_index / 接入工具共用（docs/189 §3.1）
NAME_RX = re.compile(r"^[a-z0-9]+(_[a-z0-9]+)*(@[12]x)?$")
VER_RX = re.compile(r"_(v\d+|old|new|bak|tmp|copy|test)(_|$)")
VOICE_EVENTS = ("entry", "command", "battle", "skill_1", "skill_2", "skill_3", "w_laugh", "syn_team", "syn_rival")
ASSET_EXT = (".png", ".webp", ".jpg", ".ogg", ".wav", ".mp3", ".ttf", ".otf", ".svg")


def git_files(*paths):
    out = subprocess.run(["git", "-c", "core.quotepath=false", "ls-files", "-z", *paths], cwd=ROOT, capture_output=True).stdout
    return [f for f in out.decode("utf-8").split("\0") if f]


def stem(path):
    b = os.path.basename(path)
    return b[: b.rfind(".")] if "." in b else b


def load_ids():
    ops = {f[:-5] for f in os.listdir(os.path.join(ROOT, "game/data/characters")) if f.endswith(".json")}
    en = set(json.load(open(os.path.join(ROOT, "game/data/enemies.json"), encoding="utf-8"))["enemies"])
    blob = ""
    for d in ("game/scripts", "game/data"):
        for dp, _, fs in os.walk(os.path.join(ROOT, d)):
            for f in fs:
                if f.endswith((".gd", ".json")):
                    blob += open(os.path.join(dp, f), encoding="utf-8").read()
    en |= {m for m in re.findall(r'"e_([a-z0-9]+)', blob)}
    return ops, en


class Report:
    def __init__(self):
        self.items = collections.defaultdict(list)   # (rule, level, title) -> [detail]

    def add(self, rule, level, title, detail):
        self.items[(rule, level, title)].append(detail)


def check_runtime_names(rep, files, ops, ens):
    op_ids = sorted(ops | set(SUMMONS), key=len, reverse=True)
    for f in files:
        s = stem(f)
        base = re.sub(r"@[12]x$", "", s)
        if not NAME_RX.match(s):
            rep.add("N1", "ERROR", "文件名含大写 / 中文 / 空格 / 连字符", f)
            continue
        if VER_RX.search(base):
            rep.add("N6", "WARN", "名字带版本号或临时后缀", f)
        leg = next((k for k in LEGACY if base == k or (k.endswith("_") and base.startswith(k))), None)
        if leg:
            rep.add("N7", "INFO", "历史遗留名（登记在 LEGACY）", f)
            continue
        pre = next((p for p in sorted(PREFIXES, key=len, reverse=True) if base.startswith(p)), None)
        if pre is None:
            rep.add("N2", "WARN", "前缀不在登记表", f)
            continue
        rest = base[len(pre):]
        if pre == "op_":
            oid = next((i for i in op_ids if rest == i or rest.startswith(i + "_")), None)
            if oid is None:
                rep.add("N3", "WARN", "op_ 后的干员 id 在 data/characters 里找不到", f)
            elif oid in SUMMONS:
                rep.add("N5", "WARN", "召唤物没带主人前缀（应为 op_%s_%s_*）" % (SUMMONS[oid], oid), f)
        elif pre == "e_":
            eid = rest.split("_")[0]
            if not any(rest == i or rest.startswith(i + "_") for i in ens):
                rep.add("N3", "WARN", "e_ 后的敌人 id 在 enemies.json / 脚本里找不到", f)
        elif pre in ("fx_", "proj_", "skill_"):
            tok = rest.split("_")[0]
            if tok not in ops and tok not in SUMMONS:
                full = [i for i in ops if i.startswith(tok) and i != tok and len(tok) >= 3]
                if full:
                    rep.add("N4", "WARN", "主人 id 写成缩写（应写全）", "%s（→ %s）" % (f, full[0]))


def check_game_dirs(rep, files, ops):
    for f in files:
        if not f.lower().endswith(ASSET_EXT) or f.startswith(("game/tests/", "game/tools/", "game/addons/")):
            continue
        s, ext = stem(f), os.path.splitext(f)[1].lower()
        if not NAME_RX.match(s):
            rep.add("N1", "ERROR", "文件名含大写 / 中文 / 空格 / 连字符", f)
        if VER_RX.search(s):
            rep.add("N6", "WARN", "名字带版本号或临时后缀", f)
        if "/masters/" in f:
            rep.add("D2", "WARN", "源文件放在运行时目录（应移到 art/archive 或仓库外）", f)
            continue
        if f.startswith("game/audio/"):
            if ext in (".png", ".webp", ".jpg", ".svg"):
                rep.add("D1", "WARN", "贴图放在 audio/ 里", f)
            elif f.startswith("game/audio/music/") and ext != ".ogg":
                rep.add("D1", "WARN", "audio/music 只放 ogg", f)
            elif f.startswith("game/audio/sfx/") and ext != ".wav":
                rep.add("D1", "WARN", "audio/sfx 只放 wav", f)
            elif f.startswith("game/audio/voice/") and f.count("/") == 3:
                m = next((o for o in sorted(ops, key=len, reverse=True) if s.startswith(o + "_")), None)
                if ext != ".ogg" or m is None or s[len(m) + 1:] not in VOICE_EVENTS:
                    rep.add("D1", "WARN", "语音应为 <干员 id>_<事件>.ogg", f)
        elif f.startswith("game/art/") and ext in (".ogg", ".wav", ".mp3"):
            rep.add("D1", "WARN", "音频放在 art/ 里", f)
        elif f.startswith("game/shaders/") and ext in (".png", ".webp"):
            rep.add("D1", "INFO", "贴图放在 shaders/ 里（着色器专用查找表，可接受）", f)
        elif f.count("/") == 2 and f.startswith("game/art/"):
            rep.add("D1", "WARN", "贴图直接放在 game/art/ 根目录（应进分类子目录）", f)


def check_intake(rep, inc_files):
    for f in inc_files:
        parts = f.split("/")
        if f.endswith(".png") and (len(parts) == 3 or (len(parts) == 4 and parts[2] in RUNTIME_SUBDIRS)):
            rep.add("L1", "ERROR", "运行时贴图还在收货区（游戏不读，搬进 game/art：python tools/asset_paths.py <路径> 给新路径）", f)
        elif len(parts) == 3:
            rep.add("D3", "INFO", "收货区根目录的交接文档 / 清单", f)
        elif parts[2] not in RUNTIME_SUBDIRS:
            rep.add("D3", "INFO", "收货区批次子目录（接入后归档）", "/".join(parts[:3]) + "/")


def check_dups(rep, files):
    by = collections.defaultdict(list)
    for f in files:
        with open(os.path.join(ROOT, f), "rb") as fh:
            by[hashlib.sha256(fh.read()).hexdigest()].append(f)
    for v in by.values():
        if len(v) > 1:
            rep.add("H1", "INFO", "同内容不同名", " = ".join(sorted(v)))


def run():
    """跑全部规则，返回 (Report, 运行时贴图数, game/ 文件数)"""
    ops, ens = load_ids()
    inc = git_files(INC)
    game = git_files("game")
    # 运行时贴图：game/art 里进索引的（docs/189 §6.1）；还留在收货区的报 L1
    runtime = [f for f in game if f.startswith("game/art/") and index_key(f[len("game/art/"):]) is not None]
    moved = runtime
    rep = Report()
    import asset_index
    for d in asset_index.build()[1]:
        rep.add("L2", "ERROR", "同名贴图出现在 game/art 两个目录（索引名必须全局唯一）", d)
    check_runtime_names(rep, runtime, ops, ens)
    check_game_dirs(rep, [f for f in game if f not in set(moved)], ops)
    check_intake(rep, inc)
    check_dups(rep, sorted(set(runtime) | {f for f in game if f.lower().endswith((".png", ".webp", ".ogg", ".wav")) and "/masters/" not in f
                                           and not f.startswith(("game/tests/", "game/tools/", "game/addons/"))}))
    return rep, len(runtime), len(game)


def check():
    """check.py 用（docs/189 §5）：ERROR 算失败（返回明细），WARN / INFO 只报告；detail 给各级数量与 WARN 规则分布"""
    rep, nr, ng = run()
    tally = collections.Counter()
    warn = collections.Counter()
    for (rule, level, _), det in rep.items.items():
        tally[level] += len(set(det))
        if level != "INFO":
            warn[rule] += len(set(det))
    rules = "、".join("%s %d" % kv for kv in sorted(warn.items()))
    errs = ["%s %s：%s" % (rule, title, d) for (rule, level, title), det in sorted(rep.items.items()) if level == "ERROR" for d in sorted(set(det))]
    return errs, "ERROR %d、WARN %d、INFO %d（%s）" % (tally["ERROR"], tally["WARN"], tally["INFO"], rules or "无")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--all", action="store_true", help="列出全部条目")
    ap.add_argument("--json", help="另写一份机器可读结果")
    ap.add_argument("--strict", action="store_true", help="有 ERROR 时退出码 1")
    a = ap.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    rep, nr, ng = run()
    order = {"ERROR": 0, "WARN": 1, "INFO": 2}
    tally = collections.Counter()
    out = []
    for (rule, level, title), det in sorted(rep.items.items(), key=lambda kv: (order[kv[0][1]], kv[0][0])):
        det = sorted(set(det))
        tally[level] += len(det)
        out.append({"rule": rule, "level": level, "title": title, "count": len(det), "items": det})
        print("%-5s %s %s：%d" % (level, rule, title, len(det)))
        for d in det if a.all else det[:8]:
            print("        " + d)
        if not a.all and len(det) > 8:
            print("        …（共 %d，--all 看全部）" % len(det))
    print("\n素材检查：运行时贴图 %d 张、game/ 文件 %d 个；ERROR %d、WARN %d、INFO %d" %
          (nr, ng, tally["ERROR"], tally["WARN"], tally["INFO"]))
    if a.json:
        json.dump(out, open(a.json, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    sys.exit(1 if a.strict and tally["ERROR"] else 0)


if __name__ == "__main__":
    main()
