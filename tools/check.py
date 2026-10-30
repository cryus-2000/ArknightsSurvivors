#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""统一测试入口（docs/36）。所有运行都是无界面、静音的。

    python tools/check.py              快检（提交前必跑，约 1 分钟）：核心契约测试 + 每名干员冒烟 + 同 seed 复现
    python tools/check.py --bots       快检 + 机器人标准矩阵（starts × 高手 / 普通 × 4 seed，结果缓存）
    python tools/check.py --ab REF     A/B：临时工作树跑 REF，与当前工作区同 seed 对比机器人标准矩阵
    python tools/check.py --only smoke 只跑某一项（core / smoke / nodes / prot / repro / blocks_eq / regressions / art_lint / slim / op_text / ob_tag / cc_lint / data_lint / px_lint，或单项回归名）
    python tools/check.py --jobs 4     本次最多同时开 4 个 Godot（全机总数另受 GODOT_MAX_PROCS 限制）
    python tools/check.py --auto       按相对 main 的改动只跑相关项目：只改文档 → 不开 Godot；只改说明字段 → +核心契约；
                                       只改某几名干员 → +这些干员的冒烟 / 成长节点 + 复现；其余 → 全量。合入 main 前仍跑全量
    python tools/check.py --rerecord-golden   重录积木等价金样（等价于 --only blocks_eq --eq-all --update-golden）；
                                       谁负责跑 / 什么时候跑见 docs/36 §1.3

每个 Godot 进程的输出按输入内容哈希缓存在主仓库 build/check_cache/（docs/36 §1.2），同样的输入不再重跑；--nocache 关掉。
每次快检把每局的完整输出写到 build/check/quick_<时间>/，失败时报告末尾列出失败项、原因和日志路径。
新工作树没有导入缓存时会先自动导入（docs/36 §2.1）。

退出码 0 = 全部通过；1 = 有失败。任何 SCRIPT ERROR / Parse Error 都算失败。

冒烟：每名干员各当一次主控，带两名队友（按名单轮换，每人也都当过队友），开局拿全部藏品、直接推到成长线末端、
技力常满，Boss 提前到 0:20 / 0:45 / 1:10（中期 Boss 按局轮换），跑 90 秒游戏时间（10-15 由 120 秒缩短，每个 Boss 仍有 ≥ 20 秒战斗）；另有两局不作弊的自然流程
（高手 / 普通机器人，跑过第一个商人）。看的是「有没有报错、能不能跑完」，不看数值。
主控保护：Boss 来源的扣血截断（单发 / 2 秒合计 / 满血保护 / 持续伤害上限，docs/38 §1.11）的脚本测试。
复现：同一组参数跑两次，BALANCE 结果必须逐字段相同（docs/36 §3）。
美术帧条：tools/art_lint.py 按 docs/87 查 art/incoming 的干员帧条，未豁免的 FAIL 算失败（豁免表在 art_lint.WAIVERS）。
发行包瘦身：tools/release_slim.py 查审阅图排除规则不误伤运行时贴图、导出预设与规则一致、扫描到的文字都在子集字体里（docs/33 §包体瘦身）。
"""
import argparse, datetime, glob, hashlib, heapq, itertools, json, os, re, shutil, statistics, subprocess, sys, tempfile, threading, time
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = GR.ROOT
GAME = os.path.join(ROOT, "game")
OUT_DIR = os.path.join(ROOT, "build", "check")


def op_ids(game=GAME):
    return sorted(os.path.basename(p)[:-5] for p in glob.glob(os.path.join(game, "data", "characters", "*.json")))


# ---------------------------------------------------------------- --auto：按改动文件选项目（docs/44 ②）

# 只改这些字段的 JSON 算「纯文字改动」：说明 / 名字 / 台词，不影响玩法
TEXT_KEYS = {"desc", "name", "en", "cn", "story", "lore", "flavor", "hint", "title", "note", "quote", "text", "tip", "subtitle"}
# 干员范围之外、但改了就要跑全量的角色脚本（基类 / 编队 / 主控）
SHARED_CHAR = {"character", "op_api", "squad", "doctor"}
LEVELS = ["none", "text", "ops", "full"]
SMOKE_SAMPLE = 5   # 分支全量精简时冒烟按 HEAD 轮换抽几名干员（docs/36 §1.4）


def _git(*args):
    # core.quotepath=off：中文等非 ASCII 文件名原样输出（默认会转义成 "docs/49g_\347…" 带引号，分级认不出 docs/ 而误判成 full）
    r = subprocess.run(["git", "-c", "core.quotepath=off"] + list(args), cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.stdout if r.returncode == 0 else ""


def default_base():
    """--changed 缺省的比较基线：origin/claude/integ-1029、origin/main、main 里「离 HEAD 最近」的那个的 merge-base
    （工作树都是从集成分支切出来的；只和 main 比会把集成分支上别人的几百个提交算成自己的改动，永远判成全量）"""
    best = None
    for ref in ("origin/claude/integ-1029", "origin/main", "main"):
        mb = _git("merge-base", "HEAD", ref).strip()
        if not mb:
            continue
        n = _git("rev-list", "--count", mb + "..HEAD").strip()
        if n.isdigit() and (best is None or int(n) < best[0]):
            best = (int(n), mb, ref)
    return best


def changed_files(base=None):
    """相对 base（缺省 main）的改动：merge-base 到 HEAD 的提交 + 工作区未提交的改动 + 未跟踪的新文件。返回 (文件列表, merge-base)"""
    base = (_git("merge-base", "HEAD", base).strip() if base else "") or _git("merge-base", "HEAD", "main").strip()
    files = set()
    if base and base != _git("rev-parse", "HEAD").strip():
        files |= set(_git("diff", "--name-only", base, "HEAD").splitlines())
    files |= set(_git("diff", "--name-only", "HEAD").splitlines())
    # 未跟踪的 .claude/ 下文件（主工作区的技能包、会话设置）不算改动：否则 main 上 --auto 永远被判成全量（10-24）
    files |= set(f for f in _git("ls-files", "--others", "--exclude-standard").splitlines() if not f.startswith(".claude/"))
    return sorted(f.replace("\\", "/") for f in files if f), base


def _strip_text(o):
    if isinstance(o, dict):
        return {k: _strip_text(v) for k, v in o.items() if k not in TEXT_KEYS}
    if isinstance(o, list):
        return [_strip_text(v) for v in o]
    return o


def _json_text_only(path, base):
    """这个 JSON 相对 base 是否只改了说明类字段"""
    try:
        old = json.loads(_git("show", "%s:%s" % (base or "HEAD", path)) or "null")
        new = json.load(open(os.path.join(ROOT, path), encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    return old is not None and _strip_text(old) == _strip_text(new)


def plan_auto():
    """按改动文件定档：none（不开 Godot）< text（+核心契约）< ops（+相关干员冒烟 / 成长节点 / 复现）< full（全量）。
    返回 (档位, 相关干员集合, 理由列表)"""
    files, base = changed_files()
    if not files:
        return "full", set(), ["相对 main 没有改动可比，跑全量"]
    ids = set(op_ids())
    level, ops, why = "none", set(), []

    def bump(lv, reason):
        nonlocal level
        if LEVELS.index(lv) > LEVELS.index(level):
            level = lv
        why.append("%s → %s" % (reason, lv))

    for p in files:
        name = os.path.basename(p)
        stem = name.split(".")[0]
        if p.startswith("docs/") or p.endswith(".md") or p.endswith((".uid", ".import")):
            bump("none", p)
        elif p.startswith("art/incoming/") and ("preview" in name or name.endswith((".json", ".html", ".txt"))):
            bump("none", p)
        elif (p.startswith("art/incoming/op_") or p.startswith("game/art/operators/")) and name.endswith(".png"):
            hit = max((o for o in ids if name.startswith("op_" + o + "_") or name.startswith("op_" + o + "@")), key=len, default=None)
            if hit:
                ops.add(hit)
                bump("ops", p)
            else:
                bump("text", p)   # 召唤物等附属帧条（如 op_mon3tr_*）：只影响画面，核心契约即可
        elif p.startswith("game/data/") and name.endswith(".json"):
            if os.path.exists(os.path.join(ROOT, p)) and _json_text_only(p, base):
                bump("text", p + "（只改说明字段）")
            elif p.startswith("game/data/characters/") and stem in ids:
                ops.add(stem)
                bump("ops", p)
            else:
                bump("full", p)
        elif p.startswith("game/scripts/characters/") and name.endswith(".gd"):
            if stem in ids and stem not in SHARED_CHAR:
                ops.add(stem)
                bump("ops", p)
            else:
                bump("full", p)
        else:
            bump("full", p)
    return level, ops, why


ASSUME_FILES = None   # --assume-files 给的文件列表（测量 / 演示用）


def make_plan(base_arg):
    """--changed：按 tools/check_map.json 选要跑的检查组。返回 (plan, 基线说明)"""
    import check_plan
    if base_arg:
        base, label = base_arg, base_arg
    else:
        b = default_base()
        base, label = (b[1], b[2]) if b else ("main", "main")
    files, mb = changed_files(base)
    if ASSUME_FILES is not None:
        files = ASSUME_FILES   # 测量 / 演示用：不看 git，直接当作这些文件被改了
    plan = check_plan.decide(files, op_ids(), SCENE_REGRESSIONS, lambda f: ASSUME_FILES is None and os.path.exists(os.path.join(ROOT, f)) and _json_text_only(f, mb))
    plan["files"], plan["base"], plan["label"] = files, mb, label
    return plan


def print_plan(plan, compare_old=False):
    print("按改动选项（--changed，基线 %s @ %s）：%d 个改动文件" % (plan["label"], (plan["base"] or "?")[:9], len(plan["files"])), flush=True)
    for f, why, g in plan["rows"][:40]:
        print("    %s → %s → %s" % (f, why, "+".join(g) or "只跑静态项"), flush=True)
    if len(plan["rows"]) > 40:
        print("    …… 另 %d 个文件" % (len(plan["rows"]) - 40), flush=True)
    if plan["unmapped"]:
        print("    注意：%d 个路径没有映射规则，按 unknown（core + 抽样冒烟）保守处理：%s —— 请补进 tools/check_map.json" % (
            len(plan["unmapped"]), "、".join(plan["unmapped"][:6])), flush=True)
    if plan["full"]:
        print("    命中全局公共文件 → 升级为分支全量（精简版，docs/36 §1.4）", flush=True)
    else:
        print("    选中：组 %s；干员 %s；场景回归 %d 项" % ("+".join(sorted(plan["groups"])) or "无", "、".join(sorted(plan["ops"])) or "无", len(plan["scenes"])), flush=True)
    if compare_old and ASSUME_FILES is None:
        lv, ops, why = plan_auto()
        print("    对照旧 --auto 计划：%s%s（%d 个文件；旧口径基线 main）" % (lv, "，干员 " + "、".join(sorted(ops)) if ops else "", len(why)), flush=True)


def check_map():
    """不开 Godot（<0.1 秒）：check_map.json 自检——每个场景回归键必须归组，组 / 规则不引用不存在的东西（docs/204 §2.3）"""
    import check_plan
    errs = check_plan.selftest(SCENE_REGRESSIONS)
    return {"name": "检查映射 check_map", "ok": not errs, "detail": "%d 个场景回归全部归组" % len(SCENE_REGRESSIONS) if not errs else "%d 处映射问题" % len(errs), "errors": errs[:8]}


def check_static():
    """不开 Godot 的检查：game/data 下所有 JSON 能解析"""
    bad = []
    for p in glob.glob(os.path.join(GAME, "data", "**", "*.json"), recursive=True):
        try:
            json.load(open(p, encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as e:
            bad.append("%s：%s" % (os.path.relpath(p, ROOT), str(e)[:120]))
    return {"name": "数据 JSON 解析", "ok": not bad, "detail": "game/data 全部可解析" if not bad else "%d 个文件解析失败" % len(bad), "errors": bad[:5]}


def check_art_lint():
    """不开 Godot：tools/art_lint.py 查 art/incoming 的干员帧条（docs/87）。只有未豁免的 FAIL 算失败；
    豁免表 art_lint.WAIVERS（已开返修单未交付的项，交付合入后删条目）；WARN 不算失败。
    色调 hue 项只比本分支相对 main 分叉点改过的帧条（--changed；在 main 上全部跳过）"""
    import art_lint
    ids, res = art_lint.run(images=False, quiet=True, changed=True)
    by, fails, waived, warns, stale = art_lint.summarize(ids, res)
    name = lambda r: "%s · %s" % (art_lint.NAMES.get(r["op"], r["op"]), art_lint.CN[r["check"]])
    detail = "%d 人：未豁免 FAIL %d、已豁免 %d、WARN %d" % (len(ids), len(fails), len(waived), len(warns))
    if stale:
        detail += "；豁免可删：" + "、".join(name(r) for r in stale)
    errs = ["%s：%s" % (name(r), r["detail"]) for r in fails]
    return {"name": "美术帧条 art_lint", "ok": not fails, "detail": detail + "（明细 python tools/art_lint.py）", "errors": errs[:8]}


def check_release_slim():
    """不开 Godot（约 5 秒）：发行包瘦身规则（tools/release_slim.py，docs/33 §包体瘦身）——审阅图规则没排除运行时引用到的贴图、
    两个导出预设的 exclude_filter 与规则一致、扫描到的文字在子集字体里都有（防以后加文案缺字）"""
    import release_slim
    errs, detail = release_slim.check()
    return {"name": "发行包瘦身 release_slim", "ok": not errs, "detail": detail + "（明细 python tools/release_slim.py --report）", "errors": errs[:8]}


def check_op_text():
    """不开 Godot（约 1 秒）：干员文字的数值占位都求得出值、文字里的字面数字在 base / blocks 里对得上（tools/op_text_check.py，docs/61 §1.4）"""
    import op_text_check
    errs, detail = op_text_check.check()
    return {"name": "干员文字数值 op_text_check", "ok": not errs, "detail": detail, "errors": errs[:8]}


def check_ob_tag():
    """不开 Godot（约 1 秒）：积木瞬时执行器 tag 两两不重叠、data_operator 的单播表 EXEC_SEG 与各执行器分支一致（tools/ob_tag_audit.py，docs/101 §7.3.7）"""
    import ob_tag_audit
    errs, detail = ob_tag_audit.check()
    return {"name": "积木单播表 ob_tag", "ok": not errs, "detail": detail, "errors": errs[:8]}


def check_data_lint():
    """不开 Godot（约 1 秒）：数据契约——json 重复键、waves 引用的敌人 / Boss / 藏品存在且 Boss 已登记、balance.json 疑似拼错的键（tools/data_lint.py，docs/126 R2）"""
    import data_lint
    errs = []
    data_lint.check_dupes(errs)
    data_lint.check_waves(errs)
    unread = data_lint.check_balance(errs, False)
    return {"name": "数据契约 data_lint", "ok": not errs, "detail": "balance.json 无字面读点的键 %d 个（提示）" % len(unread), "errors": errs[:8]}


def check_graph_lint():
    """不开 Godot（<1 秒）：成长线 / 路线 id / 死节点 / 前置 / 事件选项 / 引用键与资源存在（tools/graph_lint.py，docs/204 §4）；
    已登记的命中经 known_red.json 带负责人 + 到期日放行，过期转硬失败；R6（事件插画缺失）只提示"""
    import graph_lint, known_red
    hits = graph_lint.run(ROOT)
    errs = [graph_lint.format_hit(*h) for r in ("R1", "R2", "R3", "R4", "R5") for h in hits.get(r, [])]
    items, lerr = known_red.load()
    left, waived, expired = known_red.waive_errors("图引用 graph_lint", errs, items)
    left = lerr + left
    soft = sum(len(hits.get(r, [])) for r in ("R6", "R9"))
    detail = "无硬命中" if not left else "%d 条硬命中" % len(left)
    if waived:
        detail += "；已知红放行 %d 条（known_red.json）" % len(waived)
    if soft:
        detail += "；提示 %d 条（事件插画等软缺失）" % soft
    exp = {e: it for e, it in expired}
    left = ["已知红过期 %d 天（负责人 %s）：%s" % (exp[e]["expired_days"], exp[e]["owner"], e) if e in exp else e for e in left]
    return {"name": "图引用 graph_lint", "ok": not left, "detail": detail, "errors": left[:8], "waived": [(e, it) for e, it in waived]}


def check_text_reconcile():
    """不开 Godot（<1 秒）：说明文字里的字面数字都能被该条目自己的参数解释（藏品卡面 / 升级卡 / 局外树 / 事件 / 勋章 / 敌人 / 指南 / 干员响应），
    基线内的待核只警告，基线外新增未解释 = 失败（tools/text_reconcile.py，docs/204 §3）"""
    import text_reconcile
    errs, detail, res, per = text_reconcile.check()
    return {"name": "说明对账 text_reconcile", "ok": not errs, "detail": detail, "errors": errs[:8]}


def check_cc_lint():
    """不开 Godot（约 1 秒）：击退累加只在 apply_kb、干员代码不直写敌人 stun / slow / air（tools/op_cc_lint.py，docs/101 §7.3.10）"""
    import op_cc_lint
    errs, detail = op_cc_lint.check()
    return {"name": "敌人控制直写 cc_lint", "ok": not errs, "detail": detail, "errors": errs[:8]}


def check_enemy_art():
    import enemy_art_check
    errs, detail = enemy_art_check.check()
    return {"name": "Enemy art delivery", "ok": not errs, "detail": detail, "errors": errs[:8]}


def check_asset_lint():
    """不开 Godot（约 3 秒）：素材命名与目录（tools/asset_lint.py，docs/189 §5）。ERROR 算失败（运行时贴图留在收货区 L1、重名 L2、非法文件名 N1），WARN 只报告"""
    import asset_lint
    errs, detail = asset_lint.check()
    return {"name": "素材命名与目录 asset_lint", "ok": not errs, "detail": detail + "（明细 python tools/asset_lint.py）", "errors": errs[:8]}


def check_asset_index():
    """不开 Godot（约 1 秒）：运行时贴图索引 game/art/index.json 与磁盘一致、名字不重（tools/asset_index.py，docs/189 §6.1）。
    索引缺名字游戏里就画不出来，所以这项算失败"""
    import asset_index
    errs = asset_index.check()
    return {"name": "贴图索引 asset_index", "ok": not errs, "detail": "game/art/index.json %d 个名字" % len(asset_index.build()[0]), "errors": errs[:8]}


def check_px_lint():
    """不开 Godot（约 5 秒）：像素稿验收工具 tools/px_lint.py 在登记样本上跑通、数字等于校准值（干员美术路 1）；只在 --only px_lint 时跑"""
    import px_lint
    errs, detail = px_lint.check()
    return {"name": "像素稿验收 px_lint", "ok": not errs, "detail": detail, "errors": errs[:8]}


JOBS = GR.MAX_PROCS   # 本次快检的并行数（main 里按 --jobs 设置）
LOG_DIR = None   # 本次快检的日志目录（main 里设置）；每次启动 Godot 的完整输出都写进去，失败时报告里给路径


BAL_ARGS = []   # --bal 透传（见 main）


class Gate:
    """本次快检同时开的 Godot 不超过 --jobs（10-15：原先积木等价 / 成长节点 / 复现在外层线程池的一个槽里又开内层线程池，峰值到 2×jobs）。
    所有检查项的线程一起来排队，空出名额时先放预计最久的（按上一次快检日志里同名进程的用时；没记录的按 30 秒），
    最长的进程先开跑，收尾不再拖一条长尾。"""

    def __init__(self, n, est):
        self.free, self.est = n, est
        self.cv = threading.Condition()
        self.heap = []
        self.seq = itertools.count()

    def run(self, tag, fn):
        me = (-self.est.get(tag, 30.0), next(self.seq))
        with self.cv:
            heapq.heappush(self.heap, me)
            while not (self.free > 0 and self.heap[0] == me):
                self.cv.wait()
            heapq.heappop(self.heap)
            self.free -= 1
            self.cv.notify_all()
        try:
            return fn()
        finally:
            with self.cv:
                self.free += 1
                self.cv.notify_all()


GATE = None   # main 里按 --jobs 建

# ---------------------------------------------------------------- 结果缓存（docs/36 §1.2，10-15）
# 每个 Godot 进程的 (stdout, stderr) 按「它读到的输入的内容哈希 + 参数」缓存，判定逻辑每次照常跑（改了 check.py 的判定不用清缓存）。
# 输入范围两档：
#   logic：game/ 下除图片 / 音频 / 字体 / .import 以外的全部文件（脚本、数据、场景、着色器、测试、项目设置），
#          加上 art/incoming 的图按「文件名 + 尺寸」、json 按内容、音频按文件名（游戏运行时读这个目录，帧宽 = 图宽 / 帧数）；
#          冒烟 / 自然流程 / 成长节点 / 主控保护 / 复现 / 积木等价用这档——这些看的是玩法与报错，不看颜色；
#   full ：game/ 与 art/incoming 下全部文件按内容，核心契约和界面类场景回归用这档。
# 键还含 Godot 可执行文件（路径 + 修改时间）和去掉 --path 的完整参数；超时的结果不缓存。*.uid 不计入（生成的随机 id）。
CACHE_DIR = os.path.join(GR.common_root(), "build", "check_cache")
NOCACHE = False
SCOPES = {}            # {"logic": 哈希, "full": 哈希}，main 里算一次
CACHE_STAT = {"hit": 0, "miss": 0}
ASSET_EXT = (".png", ".jpg", ".jpeg", ".webp", ".svg", ".ogg", ".wav", ".mp3", ".ttf", ".otf", ".woff", ".woff2", ".fnt", ".import")
LOGIC_TAGS = ("冒烟", "自然流程", "nodes_", "prot", "复现", "blocks_eq_", "hold_aim_")


def _blobs(rel):
    """rel 目录下所有文件的 git blob 号：已跟踪且未改动的用索引里的，改过 / 未跟踪的现算 sha1（与 git 同一算法）"""
    def run(*a):
        r = subprocess.run(["git"] + list(a), cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
        return r.stdout if r.returncode == 0 else ""
    blobs = {}
    for line in run("ls-files", "-s", "--", rel).splitlines():
        meta, path = line.split("\t", 1)
        blobs[path] = meta.split()[1]
    dirty = set(run("diff", "--name-only", "--", rel).split("\n")) | set(run("ls-files", "--others", "--exclude-standard", "--", rel).split("\n"))
    for path in dirty:
        if not path:
            continue
        fp = os.path.join(ROOT, path)
        if os.path.isfile(fp):
            data = open(fp, "rb").read()
            blobs[path] = hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()
        else:
            blobs.pop(path, None)   # 工作区删掉了
    return {p: b for p, b in blobs.items() if not p.endswith(".uid") and "/.godot/" not in p}


def _png_size(path):
    try:
        with open(os.path.join(ROOT, path), "rb") as f:
            h = f.read(24)
        return "%dx%d" % (int.from_bytes(h[16:20], "big"), int.from_bytes(h[20:24], "big")) if h[:8] == b"\x89PNG\r\n\x1a\n" else "?"
    except OSError:
        return "?"


def scope_hashes(game=GAME):
    """两档输入的内容哈希（见上）。art/incoming 也算输入：游戏运行时优先读项目外的 art/incoming（scripts/art.gd），
    帧条的帧宽按图宽 / 帧数算——所以 logic 档里 art/incoming 的图按「文件名 + 尺寸」计（改色不失效，改尺寸 / 帧数失效），
    json 按内容计，音频只计文件名（存在与否），md / gif / html 不计；full 档全部按内容计"""
    rel = os.path.relpath(game, ROOT).replace(os.sep, "/")
    g = _blobs(rel)
    art = _blobs("art/incoming")
    out = {}
    h = hashlib.sha256()
    for path in sorted(g):
        if not path.lower().endswith(ASSET_EXT):
            h.update(("%s %s\n" % (path[len(rel):], g[path])).encode("utf-8"))
        elif path.lower().endswith(".png") and path.startswith(rel + "/art/"):   # 已搬进 game/art 的贴图同 art/incoming：按名字 + 尺寸（docs/189）
            h.update(("%s %s\n" % (path[len(rel):], _png_size(path))).encode("utf-8"))
    for path in sorted(art):
        low = path.lower()
        if low.endswith(".png"):
            h.update(("%s %s\n" % (path, _png_size(path))).encode("utf-8"))
        elif low.endswith((".json", ".txt", ".cfg")):
            h.update(("%s %s\n" % (path, art[path])).encode("utf-8"))
        elif low.endswith((".wav", ".ogg", ".mp3")):
            h.update(("%s\n" % path).encode("utf-8"))
    out["logic"] = h.hexdigest()
    h = hashlib.sha256()
    for path in sorted(g):
        h.update(("%s %s\n" % (path[len(rel):], g[path])).encode("utf-8"))
    for path in sorted(art):
        h.update(("%s %s\n" % (path, art[path])).encode("utf-8"))
    out["full"] = h.hexdigest()
    return out


def _cache_key(args, tag):
    if NOCACHE or not SCOPES:
        return None
    scope = "logic" if tag.startswith(LOGIC_TAGS) else "full"
    a = list(args)
    if "--path" in a:
        i = a.index("--path")
        a = a[:i] + a[i + 2:]   # 去掉工作树路径：不同工作树同一份内容可以共用
    exe = a[0] if a else ""
    try:
        exe_id = "%s %d" % (exe, os.path.getmtime(exe))
    except OSError:
        exe_id = exe
    return hashlib.sha256(json.dumps([scope, SCOPES[scope], exe_id, a[1:]], ensure_ascii=False).encode("utf-8")).hexdigest()


def _cache_get(key):
    if not key:
        return None
    try:
        d = json.load(open(os.path.join(CACHE_DIR, key[:2], key + ".json"), encoding="utf-8"))
        return d["out"], d["err"]
    except (OSError, ValueError, KeyError):
        return None


def _cache_put(key, out, err, tag):
    if not key:
        return
    d = os.path.join(CACHE_DIR, key[:2])
    os.makedirs(d, exist_ok=True)
    tmp = os.path.join(d, "%s.%d.tmp" % (key, os.getpid()))
    json.dump({"tag": tag, "time": time.strftime("%Y-%m-%d %H:%M:%S"), "out": out, "err": err}, open(tmp, "w", encoding="utf-8"), ensure_ascii=False)
    os.replace(tmp, os.path.join(d, key + ".json"))


def _last_durations():
    """上一次快检（OUT_DIR 下最新的 quick_*）各日志的「用时 N 秒」，按日志首行的 tag 取：{tag: 秒}"""
    est = {}
    try:
        runs = sorted(d for d in os.listdir(OUT_DIR) if d.startswith("quick_"))
    except OSError:
        return est
    for d in reversed(runs[-6:]):
        p = os.path.join(OUT_DIR, d)
        if p == LOG_DIR:
            continue
        for fn in os.listdir(p):
            try:
                head = open(os.path.join(p, fn), encoding="utf-8", errors="replace").read(400)
            except OSError:
                continue
            m = re.match(r"# (.*)\n# .*\n# 用时 (\d+) 秒", head)
            if m and "缓存命中" not in head:   # 命中缓存的「用时 0 秒」不代表真跑要多久
                est.setdefault(m.group(1), float(m.group(2)))
        if len(est) > 30:
            break
    return est


_TL = threading.local()   # 每个 job 线程累计「真正占用 Godot 的秒数」（不含排队），汇总里逐项列出（docs/204 §1.1）


def _run(args, timeout, tag, *, cache=True):
    """启动一次 Godot（经本次快检的闸门 GATE + godot_runner 的全机并发上限），把 stdout / stderr 写进 LOG_DIR/<tag>.log，返回 (out, err, 超时, 日志路径)"""
    if BAL_ARGS and "--" in args:
        args = list(args) + BAL_ARGS   # --bal=段/键=值 透传给每个 Godot 进程（balance.gd 测试探针）
    box = {}
    key = _cache_key(args, tag) if cache else None
    hit = _cache_get(key)

    def go():
        box["t0"] = time.time()   # 用时从拿到名额算起（排队时间不算）
        box["r"] = GR.run_godot(args, timeout)
    if hit is not None:
        box["t0"], box["r"] = time.time(), (hit[0], hit[1], False)
        CACHE_STAT["hit"] += 1
    else:
        if GATE is not None:
            GATE.run(tag, go)
        else:
            go()
        CACHE_STAT["miss"] += 1
        if not box["r"][2]:
            _cache_put(key, box["r"][0], box["r"][1], tag)   # 超时的不存（多半是负载，不是结果）
    t0 = box["t0"]
    out, err, to = box["r"]
    _TL.secs = getattr(_TL, "secs", 0.0) + (time.time() - t0)
    path = None
    if LOG_DIR:
        safe = re.sub(r"[^\w.-]+", "_", tag).strip("_") or "run"
        path = os.path.join(LOG_DIR, safe + ".log")
        n = 2
        while os.path.exists(path):
            path = os.path.join(LOG_DIR, "%s_%d.log" % (safe, n))
            n += 1
        with open(path, "w", encoding="utf-8") as fh:
            fh.write("# %s\n# 参数：%s\n# 用时 %.0f 秒%s；结束时全机 Godot %d 个%s\n\n## stdout\n%s\n\n## stderr\n%s\n" % (
                tag, " ".join(args[1:]), time.time() - t0, "（超时）" if to else "", GR.count_godot(), "；缓存命中 " + key[:12] if hit is not None else "", out, err))
    return out, err, to, path


def godot_args(godot, extra, game=GAME):
    return [godot, "--headless", "--path", game, "--"] + extra


def parse_balance(out):
    m = re.search(r"^BALANCE (\{.*\})\s*$", out, re.M)
    if not m:
        return None
    try:
        return json.loads(m.group(1))
    except json.JSONDecodeError:
        return None


# ---------------------------------------------------------------- 各项检查

def check_core(godot):
    out, err, to, log = _run([godot, "--headless", "--path", GAME, "-s", "res://tests/test_core.gd"], 300, "core")
    errs = GR.script_errors(out, err)
    m = re.search(r"(\d+) checks, (\d+) failed", out)
    ok = "CORE TESTS PASSED" in out and not errs and not to
    detail = (m.group(0) if m else "没有输出结果")
    fails = re.findall(r"^FAIL: .*$", out + "\n" + err, re.M)
    return {"name": "核心契约测试", "ok": ok, "detail": ("超时 · " if to else "") + detail, "errors": (errs + fails)[:5], "log": log}


def smoke_cases():
    ids = op_ids()
    n = len(ids)
    cases = []
    for k, op in enumerate(ids):
        mates = [ids[(k + 1) % n], ids[(k + 5) % n]]
        cases.append(("冒烟 · " + op, ["--balance", "--seed=1", "--op=" + op, "--squad=" + ",".join(mates), "--bot=expert",
                                      "--maxt=90", "--relics=all", "--maxprog", "--sptest", "--bosstimes=20,45,70", "--forceboss=%d" % (k % 5), "--dccheck"]))
    cases.append(("自然流程 · 高手", ["--balance", "--seed=2", "--op=" + ids[0], "--bot=expert", "--maxt=150", "--dccheck"]))
    cases.append(("自然流程 · 普通", ["--balance", "--seed=3", "--op=" + ids[-1], "--bot=normal", "--maxt=150", "--dccheck"]))
    return cases


def ctrl_errors(d):
    """主控保护的自动检查（docs/38 §1.11，BALANCE 的 ctrl，run/combat.gd）：Boss 存活期间主控僵直、atk_slow 恒为 0，
    移速倍率不低于下限 floor"""
    c = (d or {}).get("ctrl") or {}
    errs = []
    if c.get("stun_t", 0) > 0:
        errs.append("主控保护：Boss 存活期间主控僵直 %.2f 秒（应为 0）" % c["stun_t"])
    if c.get("aslow_t", 0) > 0:
        errs.append("主控保护：Boss 存活期间 atk_slow %.2f 秒（应为 0）" % c["aslow_t"])
    if c.get("move_min", 1) < c.get("floor", 0) - 1e-6:
        errs.append("主控保护：Boss 存活期间移速倍率最低 %.2f（应 ≥%.2f）" % (c["move_min"], c["floor"]))
    # 控制遥测（用户 10-01，run/combat.gd ctrl_src_report）：BALANCE 必须带 ctrl_src，四类来源各有四个字段，数值非负
    cs = (d or {}).get("ctrl_src")
    if d is not None:
        if not isinstance(cs, dict) or "slow_any_t" not in cs:
            errs.append("控制遥测：BALANCE 缺 ctrl_src / slow_any_t")
        else:
            for cat in ("founder", "skimmer", "boss", "other"):
                e = cs.get(cat)
                if not isinstance(e, dict) or any(not isinstance(e.get(k), (int, float)) or e.get(k) < 0 for k in ("freeze_n", "freeze_t", "dash_break_n", "slow_t")):
                    errs.append("控制遥测：ctrl_src.%s 缺字段或为负：%s" % (cat, e))
    return errs


def xp_errors(d):
    """经验守恒（docs/38 §8.13 方案 A，数值 10-01 定的恒等式）：每局 掉落总经验 = 走近捡 + 磁铁 + 回收（含兜底）+ 地上剩余"""
    if d is None:
        return []
    keys = ("xp_dropped", "xp_walk", "xp_magnet", "xp_recall", "xp_ground")
    if any(not isinstance(d.get(k), (int, float)) for k in keys):
        return ["经验守恒：BALANCE 缺 %s" % "/".join(k for k in keys if not isinstance(d.get(k), (int, float)))]
    got = d["xp_walk"] + d["xp_magnet"] + d["xp_recall"] + d["xp_ground"]
    if abs(d["xp_dropped"] - got) > 0.5 + 1e-6 * d["xp_dropped"]:
        return ["经验守恒：掉落 %.1f ≠ 捡 %.1f + 磁铁 %.1f + 回收 %.1f + 地上 %.1f（差 %.1f）" % (
            d["xp_dropped"], d["xp_walk"], d["xp_magnet"], d["xp_recall"], d["xp_ground"], d["xp_dropped"] - got)]
    return []


def dc_errors(d):
    """敌人画法缓存自检（docs/50 §9.9，render/world.gd _dc_verify，冒烟带 --dccheck）：真的比对过（dc_checked > 0），且缓存路径与原路径的
    贴图绘制参数逐项一致、缓存没有过期（dc_bad == 0）。无头模式下 _draw 照常调用，所以快检能跑到"""
    if d is None:
        return []
    p = d.get("prof") or {}
    if int(p.get("dc_checked", 0)) <= 0:
        return ["画法缓存自检：没有比对到任何敌人（dc_checked = 0），--dccheck 没生效？"]
    if int(p.get("dc_bad", 0)) > 0:
        return ["画法缓存自检：%d 次不一致（缓存路径 ≠ 原路径或缓存过期，见日志 ERROR 行）" % int(p["dc_bad"])]
    return []


def run_case(godot, name, extra, timeout=300):
    t0 = time.time()
    out, err, to, log = _run(godot_args(godot, extra), timeout, name)
    errs = GR.script_errors(out, err)
    d = parse_balance(out)
    errs += ctrl_errors(d)
    errs += xp_errors(d)
    if "--dccheck" in extra:
        errs += dc_errors(d)
    ok = d is not None and not errs and not to
    detail = ("超时" if to else ("没有 BALANCE 行" if d is None else "t=%d %s" % (d["t"], "胜" if d.get("win") else "")))
    return {"name": name, "ok": ok, "detail": "%s · %.0fs" % (detail, time.time() - t0), "errors": errs[:3], "data": d, "log": log}


def check_nodes(godot, only=None):
    """成长节点当场生效（tests/node_test.tscn）：每名干员逐个应用 6 个节点，每个节点选下的那一刻必须有东西变化。
    only：只测这些干员（--auto 按改动选）"""
    ids = [o for o in op_ids() if only is None or o in only]

    def one(op):
        out, err, to, log = _run([godot, "--headless", "--path", GAME, "res://tests/node_test.tscn", "--", "--balance", "--seed=1", "--op=" + op], 300, "nodes_" + op)
        lines = re.findall(r"^NODE (\S+) (\d+) (\S+) (\S+) \| imm: (.*?) \| sync: (.*)$", out, re.M)
        empty = [l[3] for l in lines if not l[4].strip() and not l[5].strip()]
        return op, lines, empty, GR.script_errors(out, err), to

    with ThreadPoolExecutor(max(1, len(ids))) as ex:   # 并发由 GATE 管（≤ --jobs），这里只负责一起排队
        res = list(ex.map(one, ids))
    bad = []
    for op, lines, empty, errs, to in res:
        if to or errs or len(lines) != 6 or empty:
            bad.append("%s：%s" % (op, "超时" if to else (errs[0][:120] if errs else ("节点行数 %d" % len(lines) if len(lines) != 6 else "选下当场没变化的节点 " + "、".join(empty)))))
    bad_logs = [LOG_DIR and os.path.join(LOG_DIR, "nodes_" + op + ".log") for op, lines, empty, errs, to in res if to or errs or len(lines) != 6 or empty]
    return {"log": "、".join(p for p in bad_logs if p), "name": "成长节点当场生效", "ok": not bad, "detail": "%d 名干员 × 6 节点" % len(ids) if not bad else "%d 名干员有问题" % len(bad), "errors": bad[:6]}


def check_hold_aim(godot, only=None):
    """按住瞄准全员验收（tests/hold_aim_test.tscn，10-31 取消手动普攻、改为自动普攻 + 按住瞄准）：每名干员当队长，
    不按时打右边近处木桩（自动），模拟按住瞄准 / 触屏瞄准键朝左时打左边木桩，空场按住照常出招，松手回到自动。
    only：只测这些干员（--auto 按改动选）"""
    ids = [o for o in op_ids() if only is None or o in only]

    def one(op):
        out, err, to, log = _run([godot, "--headless", "--audio-driver", "Dummy", "--path", GAME, "res://tests/hold_aim_test.tscn", "--", "--regression", "--balance", "--seed=1", "--op=" + op], 600, "hold_aim_" + op)
        fails = re.findall(r"^FAIL: (.*)$", out + chr(10) + err, re.M)
        return op, ("HOLD AIM %s failures=0" % op) in out, fails, GR.script_errors(out, err), to

    with ThreadPoolExecutor(max(1, len(ids))) as ex:
        res = list(ex.map(one, ids))
    bad = []
    bad_logs = []
    for op, passed, fails, errs, to in res:
        if to or errs or fails or not passed:
            bad.append("%s：%s" % (op, "超时" if to else (errs[0][:120] if errs else (fails[0][:120] if fails else "没有通过标记"))))
            bad_logs.append(os.path.join(LOG_DIR, "hold_aim_" + op + ".log") if LOG_DIR else "")
    return {"log": "、".join(p for p in bad_logs if p), "name": "按住瞄准全员验收", "ok": not bad, "detail": "%d 名干员 × 5 场景" % len(ids) if not bad else "%d 名干员有问题" % len(bad), "errors": bad[:6]}


def check_prot(godot):
    """主控保护（tests/prot_test.tscn，docs/38 §1.11）：Boss 来源单发 ≤40%、2 秒合计 ≤50%、满血保护、Boss 持续伤害每秒 ≤4%"""
    ids = op_ids()
    # 保护机制按参照档验（10-28 danger-pass 把缺省放松到 2 秒 0.68 / 任意来源 0.70 / 满血保护 60 秒、5%，docs/178；机制不变、断言写的是旧档数字）
    ref = ["--bal=boss/leader_2s_cap=0.5", "--bal=protect/any_2s_cap=0.55", "--bal=boss/fullhp_guard_cd=30", "--bal=boss/fullhp_guard_left=0.1"]
    out, err, to, log = _run([godot, "--headless", "--path", GAME, "res://tests/prot_test.tscn", "--", "--balance", "--seed=1",
                              "--op=" + ("wisadel" if "wisadel" in ids else ids[0])] + ref, 300, "prot")
    errs = GR.script_errors(out, err)
    m = re.search(r"(\d+) checks, (\d+) failed", out)
    fails = re.findall(r"^FAIL: .*$", out + "\n" + err, re.M)
    ok = "PROT TESTS PASSED" in out and not errs and not to
    return {"name": "主控保护", "ok": ok, "detail": "超时" if to else (m.group(0) if m else "没有输出结果"), "errors": (errs + fails)[:5], "log": log}


def check_native_eq(godot):
    """原生核心对照（docs/101 §4.7）：本机编过 ark_native（game/bin 有 dll）时，同一局缺省（走原生 EnemyCore）与 --optold=131072
    （OPT_CPP，走 GDScript 核心）各跑一次，TRACE 逐行比（TRACE 每秒带全体敌人位置哈希）；没有 dll 跳过"""
    import glob as _glob
    name = "原生核心对照"
    dlls = sorted(_glob.glob(os.path.join(GAME, "bin", "ark_native.windows.template_*.x86_64.dll")))
    if not dlls:
        return {"name": name, "ok": True, "detail": "跳过（本机没编 ark_native）"}
    # 结果缓存的键只含被跟踪的文件，dll 不在里面：把 dll 的大小 / 修改时间做成一个游戏会忽略的参数放进键里，重编 dll 后不会命中旧结果
    tag = "--nativetag=" + "_".join("%d-%d" % (os.path.getsize(f), int(os.path.getmtime(f))) for f in dlls)
    # DLL 存在不等于扩展加载成功，否则两局都回退到 GDScript 也会误报通过。
    out, err, to, log = _run([godot, "--headless", "--audio-driver", "Dummy", "--path", GAME,
                             "--script", "res://tests/native_core_test.gd", "--", tag], 60, "native_load", cache=False)
    if to or GR.script_errors(out, err) or "NATIVE CORE TEST PASSED" not in out:
        return {"name": name, "ok": False, "detail": "EnemyCore 加载 / 调用失败", "errors": GR.script_errors(out, err)[:3], "log": log}
    base = ["--balance", "--seed=13", "--op=skalter", "--squad=texas,exusiai", "--bot=expert", "--maxt=180", "--trace=1", tag]

    def one(k):
        extra = base + (["--optold=131072"] if k == "gd" else [])
        out, err, to, log = _run(godot_args(godot, extra), 300, "native_eq_" + k)
        return k, out, err, to, log
    with ThreadPoolExecutor(2) as ex:
        res = dict((k, (o, e, to, lg)) for k, o, e, to, lg in ex.map(one, ["native", "gd"]))
    logs = "、".join(r[3] for r in res.values() if r[3])
    tr = {}
    for k, (out, err, to, _lg) in res.items():
        se = GR.script_errors(out, err)
        if to or se:
            return {"name": name, "ok": False, "detail": "%s 局 %s" % (k, "超时" if to else se[0][:160]), "errors": se[:3], "log": logs}
        tr[k] = [l for l in out.splitlines() if l.startswith("TRACE ")]
    a, b = tr["native"], tr["gd"]
    if len(a) < 3 or len(a) != len(b):
        return {"name": name, "ok": False, "detail": "TRACE 行数不同（原生 %d / GDScript %d）" % (len(a), len(b)), "errors": [], "log": logs}
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return {"name": name, "ok": False, "detail": "TRACE 第 %d 行不同：原生「%s」 / GDScript「%s」" % (i + 1, x[:120], y[:120]), "errors": [], "log": logs}
    return {"name": name, "ok": True, "detail": "seed 13 三分钟 TRACE %d 行原生与 GDScript 逐行相同" % len(a), "errors": [], "log": logs}


def check_repro(godot):
    # 第 3 局加 --rngshift：画面随机流 g.vrng 与全局随机流换种子。它们的消耗次数随真实帧间隔变（脚下尘土等按真实时间生成），
    # 玩法读了它们就会「同 seed 偶尔不同」（10-20 逻各斯弹道摆动读 g.vrng，招募了逻各斯的维什戴尔 / 星熊局随机分叉）。
    # 逻各斯在队里，覆盖弹道这一路
    extra = ["--balance", "--seed=7", "--op=wisadel", "--squad=suzuran,logos", "--bot=expert", "--maxt=240"]
    with ThreadPoolExecutor(3) as ex:
        a, b, c = list(ex.map(lambda k: run_case(godot, "复现_%d" % k, extra + (["--rngshift"] if k == 3 else [])), [1, 2, 3]))
    logs = "、".join(x["log"] for x in (a, b, c) if x.get("log"))
    if not (a["ok"] and b["ok"] and c["ok"]):
        why = "；".join("第 %d 局 %s" % (k + 1, x["detail"]) for k, x in enumerate((a, b, c)) if not x["ok"])
        return {"name": "同 seed 复现", "ok": False, "detail": "有一局没跑完（%s）" % why, "errors": a["errors"] + b["errors"] + c["errors"], "log": logs}
    ds = [dict(x["data"]) for x in (a, b, c)]
    # 同屏数量峰值（telemetry peak / peak_min）只观察画面：特效里有绘制时追加的项，两局可能差一两个，不算复现失败
    for d in ds:
        d.pop("prof", None)
        if isinstance(d.get("bot"), dict):
            d["bot"] = {k: v for k, v in d["bot"].items() if k not in ("peak", "peak_min")}
    diff = [k for k in sorted(set(ds[0]) | set(ds[1])) if ds[0].get(k) != ds[1].get(k)]
    shift = [k for k in sorted(set(ds[0]) | set(ds[2])) if ds[0].get(k) != ds[2].get(k)]
    detail = "4:00 游戏时间逐字段相同（含画面 / 全局随机流换种子）"
    if diff:
        detail = "两局不同的字段：" + "、".join(diff[:8])
    elif shift:
        detail = "画面 / 全局随机流换种子后结果变了（玩法读了 g.vrng 或全局 randf）：" + "、".join(shift[:8])
    return {"name": "同 seed 复现", "ok": not diff and not shift, "detail": detail, "errors": [], "log": logs}


# 积木等价测试（docs/61 §测试；10-15 起「数据版 vs 金样」，docs/36 §1.3）：原先数据干员与同一份数值的手写参照（tests/data_ops/*_legacy.gd、
# eqtest_hand.gd，共 7538 行）同 seed 跑、TRACE 与 BALANCE 逐字节比。用户 10-15 批 docs/101 §8 第 4 项「录金样后下线」：
# 下线前（main fd9ce553）两版全部用例逐字节相同，把输出录成金样 game/tests/golden/fd9ce553/（证据快照），手写参照删除（git 历史可追）。
# 现在只跑数据版，与金样比：
#   金样记「本干员侧」与「别处」两个哈希。本干员侧 = 本干员的数据 / 脚本 / 帧条尺寸 + 积木公共文件（op_blocks / data_operator /
#   character / op_api）；别处 = 其余玩法输入（check.logic_entries，不含 game/tests/）。
#   别处没变、输出却变了 → FAIL（只可能是本干员或积木改出来的）；别处变了 → 判「金样过期」。
#   10-21 起「过期」不再静默跳过：ok 照样记 False（除非这一轮正好 --update-golden 把它刷新掉），detail 开头打印醒目
#   提示，让 --auto 的汇总不是绿的；但不计进 errs 硬失败列表——过期不是改坏积木本身，不该让改别处代码的人背锅。
#   下一个改了相关干员 / 积木代码、看到自己这组过期的人负责重录，不是「过期=直接阻断所有人合入」的硬规则。
#   ship 全量通过后 `check.py --only blocks_eq --eq-all --update-golden` 把数据版输出重录到 game/tests/golden_current/（git 跟踪，10-21 起
#   不再靠不进 git 的本地缓存；重录后要把该目录的改动 git add + commit）。
#  kaltsit：数据版的 Mon3tr 出手带通用召唤物标签 summon（手写参照没有），金样录的时候已去掉，比较时同样去掉
EQ_GROUPS = [
    ("eqtest", [
        ("seed1 全节点 + 技力常满", ["--balance", "--seed=1", "--op=eqtest", "--bot=expert", "--maxt=240", "--trace=1", "--maxprog", "--sptest"]),
        ("seed2 自然流程", ["--balance", "--seed=2", "--op=eqtest", "--bot=expert", "--maxt=300", "--trace=1"]),
    ], ["测试脉冲", "测试回声", "测试共鸣", "测试斩", "测试音符"]),
    # 10-13 精英化第 1 批（docs/91 §6）后数据版凯尔希的精一「扑击」/ 精二「回防」/ 八面展开 60% 是新设计，旧手写参照没有：
    # 这组只比精零（不推全节点、不进精英化），守住 Mon3tr 迁积木的本体（随行、爪击、治疗、一技能）
    ("kaltsit", [
        ("seed1 精零 + 技力常满", ["--balance", "--seed=1", "--op=kaltsit", "--bot=expert", "--maxt=45", "--trace=1", "--sptest"]),
        ("seed3 当队友 + 全藏品（精零）", ["--balance", "--seed=3", "--op=wisadel", "--squad=kaltsit,suzuran", "--bot=expert", "--maxt=60", "--trace=1",
                                 "--sptest", "--relics=all"]),
    ], ["Mon3tr", "Mon3tr · 真伤", "Mon3tr · 熔毁"]),
    # 10-14 精英化第 2 批（docs/91 §19 批 2）：四名手写干员迁积木（docs/61 §17），原手写脚本留作参照（tests/data_ops/<id>_legacy.gd，
    # 只把画面随机数换成 g.vrng、少数乘法顺序与同帧先后对齐数据版，见各文件开头）。迁移提交时两版全节点 + 精二逐行相同；
    # 之后加了精一 / 精二新形态（docs/91 §24），旧手写参照没有，所以同凯尔希只比精零（不推全节点、不进精英化）：主控技力常满一局、当队友全藏品一局
    ("skadi", [
        ("seed1 精零 + 技力常满", ["--balance", "--seed=1", "--op=skadi", "--bot=expert", "--maxt=45", "--trace=1", "--sptest"]),
        ("seed3 当队友 + 全藏品（精零）", ["--balance", "--seed=3", "--op=wisadel", "--squad=skadi,suzuran", "--bot=expert", "--maxt=60", "--trace=1",
                                 "--sptest", "--relics=all"]),
    ], ["大剑", "迅捷打击·γ型"]),
    ("eyjafjalla", [
        ("seed1 精零 + 技力常满", ["--balance", "--seed=1", "--op=eyjafjalla", "--bot=expert", "--maxt=45", "--trace=1", "--sptest"]),
        ("seed3 当队友 + 全藏品（精零）", ["--balance", "--seed=3", "--op=wisadel", "--squad=eyjafjalla,suzuran", "--bot=expert", "--maxt=60", "--trace=1",
                                 "--sptest", "--relics=all"]),
    ], ["熔岩弹"]),
    ("logos", [
        ("seed1 精零 + 技力常满", ["--balance", "--seed=1", "--op=logos", "--bot=expert", "--maxt=45", "--trace=1", "--sptest"]),
        ("seed3 当队友 + 全藏品（精零）", ["--balance", "--seed=3", "--op=wisadel", "--squad=logos,suzuran", "--bot=expert", "--maxt=60", "--trace=1",
                                 "--sptest", "--relics=all"]),
    ], ["言", "提喻"]),
    ("ulpianus", [
        ("seed1 精零 + 技力常满", ["--balance", "--seed=1", "--op=ulpianus", "--bot=expert", "--maxt=45", "--trace=1", "--sptest"]),
        ("seed3 当队友 + 全藏品（精零）", ["--balance", "--seed=3", "--op=wisadel", "--squad=ulpianus,suzuran", "--bot=expert", "--maxt=60", "--trace=1",
                                 "--sptest", "--relics=all"]),
    ], ["锚击"]),
    # 10-14 精英化第 3 批（docs/91 §19 批 3）：归溟幽灵鲨 / 水月 / 艾丽妮 / 流明迁积木（docs/61 §19），原手写脚本留作参照（tests/data_ops/<id>_legacy.gd，
    # 只把画面随机数换成 g.vrng，见各文件开头）。迁移提交（22e246dc）时两版全节点 + 精二逐行相同；之后加了精一 / 精二新形态（docs/91 §25），
    # 旧手写参照没有，所以同第 2 批只比精零：主控技力常满一局、当队友一局（不带全藏品：全藏品 40 秒内全队就满精英）
    ("specter_unchained", [
        ("seed1 精零 + 技力常满", ["--balance", "--seed=1", "--op=specter_unchained", "--bot=expert", "--maxt=45", "--trace=1", "--sptest"]),
        ("seed3 当队友（精零）", ["--balance", "--seed=3", "--op=wisadel", "--squad=specter_unchained,suzuran", "--bot=expert", "--maxt=60", "--trace=1", "--sptest"]),
    ], ["锯刃"]),
    ("mizuki", [
        ("seed1 精零 + 技力常满", ["--balance", "--seed=1", "--op=mizuki", "--bot=expert", "--maxt=45", "--trace=1", "--sptest"]),
        ("seed3 当队友（精零）", ["--balance", "--seed=3", "--op=wisadel", "--squad=mizuki,suzuran", "--bot=expert", "--maxt=60", "--trace=1", "--sptest"]),
    ], ["伞击", "触手"]),
    ("irene", [
        ("seed1 精零 + 技力常满", ["--balance", "--seed=1", "--op=irene", "--bot=expert", "--maxt=45", "--trace=1", "--sptest"]),
        ("seed3 当队友（精零）", ["--balance", "--seed=3", "--op=wisadel", "--squad=irene,suzuran", "--bot=expert", "--maxt=60", "--trace=1", "--sptest"]),
    ], ["刺剑", "起风"]),
    ("lumen", [
        ("seed1 精零 + 技力常满", ["--balance", "--seed=1", "--op=lumen", "--bot=expert", "--maxt=45", "--trace=1", "--sptest"]),
        ("seed3 当队友（精零）", ["--balance", "--seed=3", "--op=wisadel", "--squad=lumen,suzuran", "--bot=expert", "--maxt=60", "--trace=1", "--sptest"]),
    ], ["光弹"]),
    # 10-14 精英化第 4 批（docs/91 §19 批 4）：推进之王 / 铃兰 / 维什戴尔 / 塞雷娅迁积木（docs/61 §21），原手写脚本留作参照（tests/data_ops/<id>_legacy.gd，
    # 只把画面随机数换成 g.vrng，见各文件开头）。迁移提交（bf861722）时两版全节点 + 精二逐行相同；之后加了精一 / 精二新形态（docs/91 §26），
    # 旧手写参照没有，所以同第 2、3 批只比精零：主控技力常满一局、当队友一局（星熊队长，不带全藏品：全藏品 40 秒内全队就满精英）
    ("siege", [
        ("seed1 精零 + 技力常满", ["--balance", "--seed=1", "--op=siege", "--bot=expert", "--maxt=45", "--trace=1", "--sptest"]),
        ("seed3 当队友（精零）", ["--balance", "--seed=3", "--op=hoshiguma", "--squad=siege,exusiai", "--bot=expert", "--maxt=60", "--trace=1", "--sptest"]),
    ], ["锤击"]),
    ("suzuran", [
        ("seed1 精零 + 技力常满", ["--balance", "--seed=1", "--op=suzuran", "--bot=expert", "--maxt=45", "--trace=1", "--sptest"]),
        ("seed3 当队友（精零）", ["--balance", "--seed=3", "--op=hoshiguma", "--squad=suzuran,texas", "--bot=expert", "--maxt=60", "--trace=1", "--sptest"]),
    ], ["狐火"]),
    ("wisadel", [
        ("seed1 精零 + 技力常满", ["--balance", "--seed=1", "--op=wisadel", "--bot=expert", "--maxt=45", "--trace=1", "--sptest"]),
        ("seed3 当队友（精零）", ["--balance", "--seed=3", "--op=hoshiguma", "--squad=wisadel,angelina", "--bot=expert", "--maxt=60", "--trace=1", "--sptest"]),
    ], ["炮击"]),
    ("saria", [
        ("seed1 精零 + 技力常满", ["--balance", "--seed=1", "--op=saria", "--bot=expert", "--maxt=45", "--trace=1", "--sptest"]),
        ("seed3 当队友（精零）", ["--balance", "--seed=3", "--op=hoshiguma", "--squad=saria,kaltsit", "--bot=expert", "--maxt=60", "--trace=1", "--sptest"]),
    ], ["拳击"]),
]


def _balance_core(d, drop_tags=()):
    d = dict(d or {})
    d.pop("prof", None)
    if isinstance(d.get("bot"), dict):
        d["bot"] = {k: v for k, v in d["bot"].items() if k not in ("peak", "peak_min")}
    if drop_tags and isinstance(d.get("out_tag"), dict):
        d["out_tag"] = {k: v for k, v in d["out_tag"].items() if k not in drop_tags}
    # docs/88 遥测 sus.heal 的键带子项（「凯尔希·常驻 / 技能」）：数据版按积木分子项、手写参照不分，比较前按来源合并（数值仍逐项比）
    if isinstance(d.get("sus"), dict):
        sus = {}
        for seg, sd in d["sus"].items():
            sd = dict(sd)
            merged = {}
            for k, v in (sd.get("heal") or {}).items():
                base = k.split("·", 1)[0]
                a = merged.get(base, [0.0, 0.0])
                merged[base] = [a[0] + v[0], a[1] + v[1]]
            # 先求和再取整（逐项取整会让 7.025 / 7.026 这种舍入差被当成不等价）
            sd["heal"] = {k: [round(v[0], 2), round(v[1], 2)] for k, v in merged.items()}
            sus[seg] = sd
        d["sus"] = sus
    return d


EQ_ALL = False   # --eq-all：每组跑全部用例；缺省每组只跑第一条（seed1），第二条（seed2 / seed3 当队友）改到云端每日一跑（docs/36 §7.6，10-15）
UPDATE_GOLDEN = False   # --update-golden：本项通过后把数据版输出重录到 game/tests/golden_current/（ship 全量通过后调用，git 跟踪，记得 commit）
GOLDEN_SNAP = os.path.join(GAME, "tests", "golden")
GOLDEN_GIT = os.path.join(GAME, "tests", "golden_current")   # 10-21 起：git 跟踪的当前有效金样，--auto 默认读写都在这里，不依赖任何本机本地缓存
GOLDEN_ROLL = os.environ.get("ARK_GOLDEN_DIR")   # 可选本地覆盖层（不进 git）：只在显式设置 ARK_GOLDEN_DIR 时才读取，读取时优先于 GOLDEN_GIT，
                                                  # 用于大重构对改前对照等临时场景（docs/101 §7.3）。10-22 起不再默认指向 build/golden_cache——
                                                  # 旧的本地缓存残留会遮住 git 里已经刷新的金样，导致合并后误报过期（协调人实测两次），--auto 默认完全不读它
EQ_COMMON = ("game/scripts/characters/op_blocks.gd", "game/scripts/characters/data_operator.gd",
             "game/scripts/characters/character.gd", "game/scripts/characters/op_api.gd",
             "game/scripts/characters/operator_defs.gd", "game/scripts/characters/operator_validate.gd")
# B6 ①（docs/101 §7.3.3，10-15）：op_blocks 拆到 scripts/characters/blocks/ 后，公共段 ob_*.gd 也算积木公共文件（进本干员侧），
# 按人的段 seg_<名>.gd 只进那名干员的本干员侧（不然拆分后的新文件落进「别处」，金样全判过期）
EQ_COMMON_PREFIX = "game/scripts/characters/blocks/ob_"
EQ_SEG = {"specter_unchained": "specter"}   # 干员 id → seg 文件名（不同名的）
_ENTRIES = {}


def logic_entries(game=GAME):
    """玩法输入清单 {路径: 内容标记}，同 scope_hashes 的 logic 档（game/ 非图片音频字体；art/incoming 图按尺寸、json 按内容、音频按名），
    但不含 game/tests/（测试脚本不影响 --balance 局；测试专用干员的 json 单独算进本干员侧）"""
    if "e" not in _ENTRIES:
        rel = os.path.relpath(game, ROOT).replace(os.sep, "/")
        e = {}
        for path, b in _blobs(rel).items():
            if not path.lower().endswith(ASSET_EXT) and not path.startswith(rel + "/tests/"):
                e[path] = b
            elif path.lower().endswith(".png") and path.startswith(rel + "/art/"):   # 同 scope_hashes：game/art 贴图按尺寸
                e[path] = _png_size(path)
        for path, b in _blobs("art/incoming").items():
            low = path.lower()
            if low.endswith(".png"):
                e[path] = _png_size(path)
            elif low.endswith((".json", ".txt", ".cfg")):
                e[path] = b
            elif low.endswith((".wav", ".ogg", ".mp3")):
                e[path] = "-"
        _ENTRIES["e"] = e
    return _ENTRIES["e"]


def eq_hashes(gid):
    """(本干员侧哈希, 别处哈希)"""
    own = set(EQ_COMMON) | {"game/data/characters/%s.json" % gid, "game/tests/data_ops/%s.json" % gid, "game/scripts/characters/%s.gd" % gid,
                            "game/scripts/characters/blocks/seg_%s.gd" % EQ_SEG.get(gid, gid)}
    hs = [hashlib.sha256(), hashlib.sha256()]
    ent = dict(logic_entries())
    if "td" not in _ENTRIES:
        _ENTRIES["td"] = _blobs("game/tests/data_ops")
    tj = "game/tests/data_ops/%s.json" % gid   # 测试专用干员（eqtest）的数据只算进它自己那组
    if tj in _ENTRIES["td"]:
        ent[tj] = _ENTRIES["td"][tj]
    for path, tok in sorted(ent.items()):
        mine = path in own or path.startswith("art/incoming/op_%s_" % gid) or path.startswith("game/art/operators/%s/" % gid) or path.startswith(EQ_COMMON_PREFIX)
        hs[0 if mine else 1].update(("%s %s\n" % (path, tok)).encode("utf-8"))
    return hs[0].hexdigest(), hs[1].hexdigest()


def _golden_file(gid, name):
    return "%s__%s.json" % (gid, name.split()[0])


def load_golden(gid, name):
    """优先 GOLDEN_ROLL（仅在显式设置 ARK_GOLDEN_DIR 时才非空，--auto 默认不读），然后 game/tests/golden_current/（git 跟踪的当前有效金样，--auto 默认命中这里），
    最后 game/tests/golden/<提交>/（下线时的证据快照，取最新一份）"""
    fname = _golden_file(gid, name)
    p = os.path.join(GOLDEN_ROLL, fname) if GOLDEN_ROLL else ""
    if not p or not os.path.exists(p):
        p = os.path.join(GOLDEN_GIT, fname)
    if not os.path.exists(p) and os.path.isdir(GOLDEN_SNAP):
        snaps = sorted(d for d in os.listdir(GOLDEN_SNAP) if os.path.isdir(os.path.join(GOLDEN_SNAP, d)))
        p = os.path.join(GOLDEN_SNAP, snaps[-1], fname) if snaps else ""
    try:
        return json.load(open(p, encoding="utf-8")), p
    except (OSError, ValueError):
        return None, p


def golden_record(gid, name, extra, trace, core):
    own, other = eq_hashes(gid)
    return {"gid": gid, "case": name, "args": extra, "own": own, "other": other,
            "commit": _git("rev-parse", "--short=8", "HEAD").strip(), "time": time.strftime("%Y-%m-%d %H:%M:%S"),
            "trace": trace, "balance": core}


def check_blocks_eq(godot):
    """积木干员 vs 金样（见上）"""
    jobs = [(gid, name, extra) for gid, cases, _ in EQ_GROUPS for name, extra in (cases if EQ_ALL else cases[:1])]

    def one(j):
        gid, name, extra = j
        out, err, to, log = _run(godot_args(godot, extra), 300, "blocks_eq_%s_%s" % (gid, name.split()[0]))
        return j, out, err, to, log
    with ThreadPoolExecutor(max(1, len(jobs))) as ex:   # 并发由 GATE 管（≤ --jobs），这里只负责一起排队
        res = list(ex.map(one, jobs))
    srcs_of = {gid: srcs for gid, _c, srcs in EQ_GROUPS}
    errs, logs, same, stale, nog, rec = [], [], [], [], [], []
    for (gid, name, extra), out, err, to, log in res:
        logs.append(log or "")
        se = GR.script_errors(out, err)
        d = parse_balance(out)
        if to or se or d is None:
            errs.append("%s %s：%s" % (gid, name, "超时" if to else (se[0][:160] if se else "没有 BALANCE 行")))
            continue
        trace = [l for l in out.splitlines() if l.startswith("TRACE ")]
        core = _balance_core(d, ("summon",) if gid == "kaltsit" else ())
        if len(trace) < 30:
            errs.append("%s %s：TRACE 行太少（%d），--trace 没生效？" % (gid, name, len(trace)))
            continue
        # 积木真的在打：各伤害来源都出现在本局的伤害统计里
        blob = json.dumps(d, ensure_ascii=False)
        miss = [x for x in srcs_of[gid] if '"%s"' % x not in blob] if "全节点" in name else []
        if miss:
            errs.append("%s %s：伤害统计里没有这些来源：%s" % (gid, name, "、".join(miss)))
        rec.append(golden_record(gid, name, extra, trace, core))
        gd, gp = load_golden(gid, name)
        tag = "%s %s" % (gid, name.split()[0])
        if gd is None:
            nog.append(tag)
            continue
        own, other = eq_hashes(gid)
        if gd.get("other") != other and not os.environ.get("ARK_EQ_FORCE"):   # ARK_EQ_FORCE=1：过期也照比（纯搬家的大重构对改前金样，docs/101 §7.3）
            stale.append(tag)   # 别处的玩法代码变了：金样过期，不判
            continue
        ta, ba = gd.get("trace", []), gd.get("balance", {})
        bad_t = next((k for k in range(max(len(trace), len(ta))) if k >= len(trace) or k >= len(ta) or trace[k] != ta[k]), None)
        diff = [k for k in sorted(set(core) | set(ba)) if core.get(k) != ba.get(k)]
        if bad_t is None and not diff:
            same.append(tag)
            continue
        why = "本干员侧改了（%s）" % ("数据 / 脚本 / 积木公共文件 / 帧条尺寸" if gd.get("own") != own else "哈希没变却不同：不确定性？")
        if bad_t is not None:
            errs.append("%s：与金样不同，%s；TRACE 第 %d 行：现在「%s」 / 金样「%s」（金样 %s）。有意改行为就用 --update-golden 重录" % (
                tag, why, bad_t + 1, trace[bad_t] if bad_t < len(trace) else "-", ta[bad_t] if bad_t < len(ta) else "-", os.path.relpath(gp, ROOT)))
        else:
            errs.append("%s：与金样不同，%s；BALANCE 字段 %s（金样 %s）。有意改行为就用 --update-golden 重录" % (tag, why, "、".join(diff[:6]), os.path.relpath(gp, ROOT)))
    # rec_ok：本局本身没有真失败（不含「过期」）——决定能不能重录；--update-golden 要靠它才能在「过期」状态下把金样刷新，
    # 否则过期会反过来挡住重录（鸡生蛋）。对外汇总用的 ok 则把「过期」也算不通过（见下，10-21 改）
    rec_ok = not errs and len(rec) == len(jobs)
    recorded = False
    if UPDATE_GOLDEN and rec_ok:
        os.makedirs(GOLDEN_GIT, exist_ok=True)
        for r in rec:
            tmp = os.path.join(GOLDEN_GIT, _golden_file(r["gid"], r["case"]) + ".%d.tmp" % os.getpid())
            json.dump(r, open(tmp, "w", encoding="utf-8"), ensure_ascii=False, indent=0)
            os.replace(tmp, os.path.join(GOLDEN_GIT, _golden_file(r["gid"], r["case"])))
        recorded = True
    # 10-21 改：「过期」不再静默跳过——之前「别处变了就跳过、不算失败」导致金样一旦跟不上大改就全组长期过期，
    # 这项检查形同虚设也没人知道。现在过期时 ok 照样记 False（除非这一轮正好用 --update-golden 把它刷新掉了），
    # 让 --auto 的汇总不是绿的，逼人去重录；但不把它计进 errs/硬失败列表——过期不是改坏积木本身，不该让改别处代码
    # 的人背锅，detail 里只打印醒目提示，不阻断合入（docs/36 §1.3）
    ok = rec_ok and (not stale or recorded)
    same_part = "与金样相同 %d" % len(same)
    if nog:
        same_part += "、没有金样 %d" % len(nog)
    if UPDATE_GOLDEN and rec_ok:
        same_part += "；已重录 %d 份到 game/tests/golden_current（git 跟踪，记得 git add + commit）" % len(rec)
    if stale:
        stale_list = "、".join(stale[:6]) + ("……" if len(stale) > 6 else "")
        if recorded:
            detail = "%s；过期 %d 份已随本次 --update-golden 重录刷新（%s）" % (same_part, len(stale), stale_list)
        else:
            detail = ("⚠ 金样过期需要重录 %d（%s）：别处玩法代码变了，无法比对；下一个改了相关干员 / 积木代码的人请跑 "
                       "`python tools/check.py --only blocks_eq --eq-all --update-golden` 重录；%s") % (len(stale), stale_list, same_part)
    else:
        detail = same_part
    return {"name": "积木等价（数据版 vs 金样）", "ok": ok, "detail": detail, "errors": errs[:5], "log": "、".join(l for l in logs if l)}


# 场景专项回归：默认快检执行全部；--only <key> 可单独复查，仍使用公共日志和错误扫描。
SCENE_REGRESSIONS = {
    "card_desc_fit": ("藏品卡说明放得下（可见成长 7 件必须放得下；其余只报告截断）", "card_desc_fit_test.gd", r"CARD DESC FIT cut=\d+ failures=0", []),
    "command_ai": ("指挥接敌、站定、护主", "command_ai_test", r"COMMAND_AI checks=\d+ failures=0", []),
    "invuln_skill_hold": ("无敌暂缓技能（Boss 无敌时普攻照打、自动技能就绪不放，解除后 1 秒内放出；开关 combat/hold_skill_on_invuln）", "invuln_skill_hold_test", r"INVULN SKILL HOLD checks=\d+ failures=0", ["--balance", "--seed=1"]),
    "assault_dash": ("突击模式低频自冲刺（随行不冲、突击每 7 秒 / 德克萨斯 4.5 秒、归队后不冲）", "assault_dash_test", r"ASSAULT DASH checks=\d+ failures=0", ["--regression", "--balance", "--seed=1", "--op=skadi", "--squad=texas,lappland"]),
    # 以下旧系统（隐藏连携 / 响应动作 / 手动技能 / 契约试点的响应段）在 ult/on（docs/198 终结技，缺省开）下停用：测试固定 --bal=ult/on=0 守旧路径，旧系统删掉时连同测试一起删
    "synergy_a": ("干员连携技（德克萨斯 × 能天使「默契」/ 拉普兰德「恩怨」）：合击动作、冷却、总开关、队长不位移", "synergy_test", r"SYNERGY checks=\d+ failures=0", ["--bal=ult/on=0", "--regression", "--balance", "--seed=1", "--op=texas", "--squad=exusiai,lappland"]),
    "synergy_b": ("干员连携技（集群狩猎：猎人 ≥ 3 人一起扑向同一目标）", "synergy_test", r"SYNERGY checks=\d+ failures=0", ["--bal=ult/on=0", "--regression", "--balance", "--seed=1", "--op=skadi", "--squad=ulpianus,gladiia"]),
    "synergy_c": ("干员连携技（乌尔比安 × 斯卡蒂「手段应当有效」）", "synergy_test", r"SYNERGY checks=\d+ failures=0", ["--bal=ult/on=0", "--regression", "--balance", "--seed=1", "--op=ulpianus", "--squad=skadi"]),
    "synergy_d": ("干员连携技（战争设计：歌蕾蒂娅 S3 控场 → 乌尔比安收割；技能就绪才放、队长不位移）", "synergy_test", r"SYNERGY checks=\d+ failures=0", ["--bal=ult/on=0", "--regression", "--balance", "--seed=1", "--op=gladiia", "--squad=ulpianus"]),
    "synergy_conflict_a": ("干员连携技冲突检查（搭档忙 / 冲锋 / 倒地 / 归队 / 切队长 / 目标死亡 / 非 PLAY / 语音不叠）", "synergy_conflict_test", r"SYNERGY CONFLICT checks=\d+ failures=0", ["--bal=ult/on=0", "--regression", "--balance", "--seed=1", "--op=ulpianus", "--squad=skadi,texas"]),
    "synergy_conflict_b": ("干员连携技冲突检查（同帧只走一条：战争设计取代集群狩猎）", "synergy_conflict_test", r"SYNERGY CONFLICT checks=\d+ failures=0", ["--bal=ult/on=0", "--regression", "--balance", "--seed=1", "--op=gladiia", "--squad=ulpianus,skadi"]),
    "voice_command": ("指挥语音轮换、节流、登场去重", "voice_command_test", r"VOICE COMMAND checks=\d+ failures=0", []),
    "command_wheel": ("指挥圆盘索敌优先级（队友按优先级重排、队长不受影响）", "command_wheel_test", r"COMMAND WHEEL checks=\d+ failures=0", []),
    "eyja_volcanic_weight": ("熔岩弹连续起落点与浮空持续投弹", "eyja_volcanic_weight_test", r"EYJA VOLCANIC WEIGHT failures=0", ["--balance", "--seed=1", "--op=eyjafjalla", "--route=eyjafjalla:meteor"]),
    "siege_ulpianus_art": ("推进之王与乌尔比安原生美术", "siege_ulpianus_art_test", r"SIEGE ULPIANUS ART failures=0", ["--balance", "--seed=1", "--op=siege", "--squad=ulpianus"]),
    "doctor_run": ("博士八帧跑步与混合画布切换", "doctor_run_test", r"DOCTOR RUN failures=0", ["--balance", "--op=mizuki", "--squad=skadi"]),
    "relic_reclassification": ("藏品效果分类与稀有度", "relic_reclassification", r"RELIC_RECLASSIFICATION_OK", []),
    "enemy_status": ("敌人寒冷与侵蚀", "enemy_status_test", r"ENEMY STATUS TEST: 0 failures", []),
    "enemy_attack_variety": ("普通怪精英二招与Boss三招", "enemy_attack_variety_test", r"ENEMY ATTACK VARIETY failures=0", []),
    "reaper_rush": ("钵海收割者受伤狂奔与神经波纹", "reaper_rush_test", r"PASS: reaper rush", []),
    "public_gallery": ("对外图鉴初始与发现解锁", "public_gallery_test", r"PUBLIC GALLERY failures=0", []),
    "boss_variety": ("Boss密集弹幕与刀刃连招", "boss_variety_test", r"BOSS VARIETY failures=0", []),
    "ea_ui": ("EA 标题与 HUD", "ea_ui_test", r"EA UI regression: 0 failures", []),
    "op_select": ("选人页 B+ 键鼠 / 手柄 / 触屏输入", "op_select_input_test", r"OP SELECT INPUT: 0 failures", []),
    "codex": ("图鉴 C4' 键鼠 / 手柄 / 触屏输入与立绘适配", "codex_input_test", r"CODEX INPUT: 0 failures", []),
    "suno_layers": ("Suno 整首分层配乐：载入 / 各层同长 / 小节线切层 / 战斗换段 / Boss / 最终 Boss 二阶段（docs/164）", "suno_layers_test", r"SUNO LAYERS: 0 failures", []),
    "menu_bgm": ("局外配乐：各界面选曲、回标题接着放、选人 ↔ 难度不重开、进局清记忆", "menu_bgm_test", r"MENU BGM: 0 failures", []),
    "credits": ("致谢与声明滚动：键鼠 / 手柄 / 触屏输入", "credits_input_test", r"CREDITS INPUT: 0 failures", []),
    "esc_layers": ("各层 Esc 关闭当前层级 / 设置页键盘与输入法物理键码 / 设置 70% 面板与 × 关闭", "esc_layers_test", r"ESC LAYERS: 0 failures", []),
    "title_menu": ("标题磁贴群 / 难度页：四种菜单组、二维导航、键鼠 / 手柄 / 触屏", "title_menu_input_test", r"TITLE MENU INPUT: 0 failures", []),
    "touch_move": ("触屏摇杆移动：桌面 --touch / 手机比例、大 / 负触点编号（iOS Safari）、两指", "touch_move_test", r"TOUCH MOVE: 0 failures", ["--touch"]),
    "cam_resize": ("换分辨率 / 拖窗口 / 全屏 / 换档后战斗镜头可见高与进局时一致（桌面五种分辨率，docs/50 §38）", "cam_resize_test", r"CAM RESIZE failures=0", []),
    "cam_resize_touch": ("同上，手机横屏比例 + iPhone 1 美术像素 = 4 物理像素", "cam_resize_test", r"CAM RESIZE failures=0", ["--touch"]),
    "touch_layout": ("触屏按键布局：存档往返 / 换比例锚点 / 越界夹进安全区 / 局内按新位置点击 / 编辑页拖动推开调大小 / 选卡让位 / 转屏重算 ui_k", "touch_layout_test", r"TOUCH LAYOUT failures=0", ["--touch"]),
    "economy": ("经济与收藏品上限", "economy_regression", r"ECONOMY REGRESSION: 0 failures", []),
    "node_cards": ("翻节点卡：卡组可复现 / 结局入口必出 / 首通前不开 / 互斥 / 结局只看信物 / 升华三句 / 最晚时刻 / 面板顺序（docs/159）", "node_cards_test", r"NODE CARDS: 0 failures", []),
    "event_trade": ("事件改版：卡组可复现 / 首通前无结局卡 / 交易保底与无代价上限 / 代价灰掉 / 主流派 / 委托 / 暂离归队 / 途中路口（docs/173）", "event_trade_test", r"EVENT TRADE: 0 failures", []),
    # "hunt_approach" 停用（10-25 围猎并进大群，hunt/enabled 0，docs/150）：独立围猎事件不再触发，run/hunt.gd 与测试保留，恢复围猎时一起放回
    "friendly_target": ("中立单位索敌与治疗", "friendly_target_regression", r"FRIENDLY TARGET REGRESSION: 0 failures", []),
    "ishar_p2": ("伊莎玛拉敌对二阶段", "ishar_p2_test", r"ISHAR P2 failures=0", ["--balance", "--bosstest=ishar2"]),
    "ishar_combo": ("伊莎玛拉二阶段连段与图案弹幕", "ishar_combo_test", r"ISHAR COMBO failures=0", []),
    "enemy_demo": ("图鉴敌人攻击演示", "enemy_demo_test", r"ENEMY DEMO failures=0", []),
    "knight_pixel_split": ("队友步行与Boss骑乘资源分离", "knight_pixel_split", r"KNIGHT_PIXEL_SPLIT_OK", []),
    "enemy_pixels": ("怪物像素帧条与锚点", "enemy_pixel_contract", r"ENEMY PIXEL CONTRACT: .*failures=0", []),
    "skill_lifecycle": ("技能生命周期共享模块", "skill_lifecycle_test", r"SKILL LIFECYCLE checks=.*failures=0", ["--balance", "--seed=1", "--op=wisadel"]),
    "attack_phases": ("持续攻击阶段共享模块", "attack_phases_test", r"ATTACK PHASES checks=.*failures=0", ["--balance", "--seed=1", "--op=wisadel"]),
    "wisadel_s2": ("维什戴尔两阶段群攻与四连发", "wisadel_s2_test", r"WISADEL S2 checks=.*failures=0", ["--balance", "--seed=1", "--op=wisadel"]),
    "texas_contract": ("新契约只填 json 试点（德克萨斯）", "texas_contract_test", r"TEXAS CONTRACT failures=0", ["--bal=ult/on=0", "--balance", "--seed=1", "--op=texas"]),
    "wisadel_soul": ("维什戴尔魂灵之影原生身体时间线", "wisadel_soul_test", r"WISADEL SOUL failures=0", ["--balance", "--seed=1", "--op=wisadel"]),
    "m3_hp": ("Mon3tr 血条 / 倒地 / 复活 / 治疗分配（凯尔希）", "m3_hp_test", r"M3 HP failures=0", ["--balance", "--seed=1", "--op=texas", "--squad=kaltsit"]),
    "m3_hp_off": ("Mon3tr 血条总开关关（回旧行为）", "m3_hp_test", r"M3 HP failures=0", ["--balance", "--seed=1", "--op=texas", "--squad=kaltsit", "--bal=kaltsit/m3_hp=0"]),
    "klc_contract": ("凯尔希本体 / 流明 / 艾丽妮新条：出手时刻逐位同旧条、三段刺 / 光柱换条", "klc_contract_test", r"KLC CONTRACT failures=0", ["--balance", "--seed=1", "--op=irene"]),
    "response": ("干员响应动作（冲刺 / 站定）", "response_test", r"RESPONSE failures=0", ["--bal=ult/on=0", "--balance", "--seed=1", "--op=hoshiguma", "--squad=texas,eyjafjalla"]),
    "response_skill": ("干员响应动作（开技能）", "response_test", r"RESPONSE failures=0", ["--bal=ult/on=0", "--balance", "--seed=1", "--op=suzuran", "--squad=texas"]),
    "response_p2a": ("干员响应动作第二批一组（冲刺 / 站定）", "response_test", r"RESPONSE failures=0", ["--bal=ult/on=0", "--balance", "--seed=1", "--op=wisadel", "--squad=exusiai,skadi"]),
    "response_p2b": ("干员响应动作第二批一组（站定 / 开技能）", "response_test", r"RESPONSE failures=0", ["--bal=ult/on=0", "--balance", "--seed=1", "--op=lumen", "--squad=logos,skalter"]),
    "response_p2c": ("推进之王无冲刺响应（用户 10-29 删跟进锤击）", "response_test", r"RESPONSE failures=0", ["--bal=ult/on=0", "--balance", "--seed=1", "--op=texas", "--squad=siege"]),
    "response_p2d": ("干员响应动作第二批二组（塞雷娅 / 凯尔希）", "response_test", r"RESPONSE failures=0", ["--bal=ult/on=0", "--balance", "--seed=1", "--op=texas", "--squad=saria,kaltsit"]),
    "response_p2e": ("干员响应动作第二批二组（水月 / 归溟幽灵鲨）", "response_test", r"RESPONSE failures=0", ["--bal=ult/on=0", "--balance", "--seed=1", "--op=texas", "--squad=mizuki,specter_unchained"]),
    "response_p2f": ("干员响应动作第二批二组（艾丽妮 / 安洁莉娜）", "response_test", r"RESPONSE failures=0", ["--bal=ult/on=0", "--balance", "--seed=1", "--op=texas", "--squad=irene,angelina"]),
    "response_p2g": ("干员响应动作第二批（乌尔比安锚链）", "response_test", r"RESPONSE failures=0", ["--bal=ult/on=0", "--balance", "--seed=1", "--op=texas", "--squad=ulpianus"]),
    "logos_projectiles": ("逻各斯交替弹体与 S1 符文", "logos_projectile_test", r"LOGOS PROJECTILES failures=0", ["--balance", "--seed=1", "--op=logos"]),
    "three_operator_art": ("能天使 / 艾雅法拉 / 逻各斯原生帧条接线", "three_operator_art_test", r"THREE OPERATOR ART failures=0", ["--balance", "--seed=1", "--op=exusiai", "--squad=eyjafjalla,logos"]),
    "attack_timing": ("三人完整攻击与攻速时序", "attack_timing_test", r"ATTACK TIMING checks=.*failures=0", ["--balance", "--seed=1", "--op=wisadel", "--squad=saria,suzuran"]),
    "gallery_demo": ("图鉴敌人演示：近战主体贴身循环不定住 / 敌弹与特效命中后回收", "gallery_demo_test", r"GALLERY DEMO failures=0", []),
    "play_clock": ("倍速模拟时钟", "play_clock_test", r"Play clock regression: 0 failures", []),
    "boss_trial_ui": ("Boss 演练小窗口与入口", "boss_trial_ui_test", r"Boss trial UI regression: 0 failures", []),
    "ishar_human_ui": ("伊莎玛拉人形治疗演练入口", "boss_trial_ui_test", r"Boss trial UI regression: 0 failures", ["--ishar-human"]),
    "boss_trial": ("Boss 演练流程", "boss_trial_test", r"boss_trial_test: 0 failures", []),
    "boss_pressure": ("Boss 攻击节奏", "boss_pressure_test", r"BOSS PRESSURE failures=0", []),
    "final_boss_completion": ("最终四 Boss 完整改造", "final_boss_completion_test", r"FINAL BOSS COMPLETION failures=0", []),
    "beam_audio": ("激光提示音独立声部与并发", "beam_audio_test", r"BEAM AUDIO: 0 failures", []),
    "final_attack_grains": ("最终 Boss 材质颗粒与安全区", "final_attack_grains_test", r"FINAL ATTACK GRAINS failures=0", []),
    "knight_combo": ("骑士连段、取消与喘息", "knight_combo_test", r"KNIGHT COMBO failures=0", []),
    "paranoia_combos": ("偏执泡影连携攻势：连段轮换、打断、转幕、复现", "paranoia_combos_test", r"PARANOIA COMBOS failures=0", []),
    "izumik_card": ("伊祖米克连携、弹幕与拦截通道", "izumik_card_test", r"IZUMIK CARD failures=0", []),
    "mid_boss": ("塑路者 / 接潮组弹幕与连段（docs/170）", "mid_boss_test", r"MID BOSS failures=0", []),
    "final_boss_materials": ("Boss 实体材质与安全区", "final_boss_materials_test", r"FINAL BOSS MATERIALS failures=0", []),
    "final_boss_animation": ("Boss 原生动作与发射时刻", "final_boss_animation_test", r"FINAL BOSS ANIMATION failures=0", []),
    "boss_fx_geometry": ("Boss 特效几何与预警约束", "boss_fx_geometry_test", r"BOSS FX GEOMETRY failures=0", []),
    "render_perf": ("遮罩显存回收与圆环几何一致性", "render_perf_test", r"RENDER PERF failures=0", []),
    "boss_support": ("Boss 保留杂兵、友方保色与枪声混音", "boss_support_test", r"BOSS SUPPORT failures=0", []),
    "boss_boundary": ("Boss 黑潮边界", "boss_boundary_test", r"BOSS BOUNDARY failures=0", []),
    "route_knight": ("结局线事件链（骑士 / 深蓝之心 / 升华）与骑士路线", "route_knight_regression", r"ROUTE KNIGHT REGRESSION: 0 failures", []),
    "event_maxhp": ("事件最大生命 -10%（狂徒妄念）：面板暂停、非满血换算、骑士入队不改生命", "event_maxhp_test", r"EVENT MAXHP TEST: 0 failures", []),
    "enemy_prepare": ("敌人攻击前摇", "enemy_prepare_test", r"ENEMY PREPARE TEST: 0 failures", []),
    "feedback": ("攻击反馈", "feedback_test", r"FEEDBACK TESTS PASSED", []),
    "wisadel_cannon": ("维什戴尔炮击", "wisadel_cannon_test", r"WISADEL CANNON failures=0", ["--op=wisadel"]),
    "wisadel_fx_radius": ("维什戴尔爆炸特效跟着判定半径（实心边对齐判定圈）", "wisadel_fx_radius_test", r"WISADEL FX RADIUS checks=\d+ failures=0", ["--balance", "--seed=1", "--op=wisadel"]),
    "wisadel_boom": ("维什戴尔同处爆炸动画只画一次（伤害照打）", "wisadel_boom_test", r"WISADEL BOOM checks=\d+ failures=0", ["--balance", "--seed=1", "--op=wisadel"]),
    "mon3tr_fx": ("Mon3tr 熔毁效果", "mon3tr_fx_test", r"MON3TR FX failures=0", ["--op=kaltsit"]),
    "relic_impl": ("藏品第二批原语（docs/57）", "relic_impl_test", r"RELIC IMPL failures=0", ["--balance", "--op=siege", "--squad=saria,wisadel"]),
    "gladiia_hook": ("歌蕾蒂娅钩索把人拉到身前（10-24）", "gladiia_hook_test", r"GLADIIA HOOK failures=0", ["--balance", "--op=gladiia"]),
    "hoshiguma_taunt": ("星熊 S1 重斩 + 拉怪（10-30 改版，docs/140）", "hoshiguma_taunt_test", r"HOSHIGUMA TAUNT failures=0", ["--balance", "--op=mizuki", "--squad=hoshiguma"]),
    "ulpianus_charge": ("乌尔比安 S3 冲锋：沿途 + 落地伤害（10-24）", "ulpianus_charge_test", r"ULPIANUS CHARGE failures=0", ["--balance", "--op=ulpianus"]),
    "ulpianus_click": ("乌尔比安 S3 左键点场地释放、点 HUD 不误触（10-26）", "ulpianus_click_test", r"ULPIANUS CLICK failures=0", ["--bal=ult/on=0", "--balance", "--op=ulpianus"]),
    "saria_slots": ("塞雷娅 S3 晶柱碰怪即碎、原位重新长出（10-29）", "saria_slots_test", r"SARIA SLOTS failures=0", ["--balance", "--op=saria"]),
    "exusiai_blocks": ("能天使积木（docs/61 §14）", "exusiai_blocks_test", r"EXUSIAI BLOCKS failures=0", ["--balance", "--op=exusiai"]),
    "suzuran_skill_anim": ("多条技能帧条 + 循环状态（docs/87 §3.5，铃兰）", "suzuran_skill_anim_test", r"SUZURAN SKILL ANIM failures=0", ["--balance", "--op=suzuran", "--squad=lumen"]),
    "angelina_skill_anim": ("统一技能动画契约（安洁莉娜）", "angelina_skill_anim_test", r"ANGELINA SKILL ANIM failures=0", ["--balance", "--op=angelina", "--squad=lumen"]),
    "skalter_specter_anim": ("浊心 / 归溟新美术：出手帧对齐、S3 重锯 / 反向圈换条", "skalter_specter_anim_test", r"SKALTER SPECTER ANIM failures=0", ["--balance", "--op=specter_unchained", "--squad=skalter"]),
    "mizuki_runtime": ("水月完整出手、持续状态、退出与成长", "mizuki_runtime_test", r"MIZUKI RUNTIME .* 0 failed", ["--balance", "--seed=1", "--op=mizuki", "--squad=skadi"]),
    "vis_growth": ("可见成长藏品：散射 / 连发 / 剑气 / 范围 / 召唤物副体与体型、叠层递减、Mon3tr 例外、手机上限（docs/163）", "vis_growth_test", r"VIS GROWTH failures=0", ["--balance", "--seed=1", "--op=exusiai", "--squad=lappland,wisadel"]),
    "lappland_presentation": ("拉普兰德剑气生命周期与技能动作接续", "lappland_presentation_test", r"LAPPLAND PRESENTATION .* 0 failed", ["--balance", "--op=lappland"]),
    "gladiia_presentation": ("歌蕾蒂娅牵引、水柱锚点与场特效收尾", "gladiia_presentation_test", r"GLADIIA PRESENTATION .* 0 failed", ["--balance", "--op=gladiia"]),
    "operator_transitions": ("全员技能起手、移动接续与强化重锤", "operator_transition_test", r"OPERATOR TRANSITIONS .* 0 failed", ["--balance", "--op=mizuki"]),
    "attack_rhythm": ("20 人确认节奏、攻速压缩、逐帧映射、移动让位与技能接管", "attack_rhythm_test", r"ATTACK RHYTHM .* 0 failed", ["--balance", "--seed=1", "--op=mizuki"]),
    "move_attack": ("移动攻击：帧条加载、移动中出手换 move_attack 且出手帧对齐、站定不换、收势不被跑步截掉（docs/128）", "move_attack_test", r"MOVE ATTACK \d+ checks, 0 failed", ["--balance", "--seed=1", "--op=mizuki"]),
    "mizuki_skill_anim": ("水月原生像素起手、命中、收势和持续变体", "mizuki_skill_anim_test", r"MIZUKI SKILL ANIM failures=0", ["--balance", "--op=mizuki", "--squad=skadi"]),
    "settlement": ("结算：历史编队滚动、评级与视觉 RNG", "settlement_test", r"SETTLEMENT failures=0", []),
    "run_stats": ("作战记录：统计守恒（占比合计 100%、来源相加、按干员拆 = dmg_out）+ 界面打开 / 导航 / 桌面与手机排版", "run_stats_test", r"RUN STATS failures=0", ["--balance", "--op=mizuki", "--squad=skadi"]),
    "summon_visual": ("Summon visual clock and native source timeline", "summon_visual_test", r"SUMMON VISUAL failures=0", []),
    "enemy_identity": ("敌人原作机制与类型抗性", "enemy_identity_test", r"ENEMY IDENTITY checks=\d+ failures=0", ["--balance", "--op=sstest"]),
    "summon_seal_blocks": ("召唤 / 封印 / 护盾 / 治疗光环积木（docs/61 §15，测试专用干员 sstest）", "summon_seal_blocks_test", r"SUMMON SEAL BLOCKS failures=0", ["--balance", "--op=sstest"]),
    "build_progression": ("分支培养 + 培养保底（docs/119 §4.1 / §4.2）：一张培养卡进二选一、返回不重抽、只扣一次升级、节点 5 按路线、赠送推进排队 / 固定路线、换人继承选路线、其余干员兼容", "build_progression_test", r"BUILD PROGRESSION failures=0",
                          ["--balance", "--seed=1", "--op=texas", "--squad=hoshiguma,eyjafjalla"]),
    "op_dummy": ("干员木桩表场景（docs/79）：队友身份 + 怪群 5 秒自检", "op_dummy_test", r"OP DUMMY failures=0",
                 ["--balance", "--bot=afk", "--nodeath", "--op=hoshiguma", "--squad=wisadel", "--dummy_op=wisadel", "--dummy_role=mate",
                  "--dummy_scene=horde", "--dummy_stage=2", "--dummy_secs=5", "--dummy_warm=2", "--dummy_check"]),
    "dmg_curve": ("普通怪伤害曲线（docs/194）：单调、封顶、一阶连续、池平均一下 = 目标曲线、换池不跳", "dmg_curve_test", r"DMG CURVE failures=0", []),
    "tide": ("潮位阶梯 0–15（docs/109 §5）：16 级、锚点 0 / 4 / 8 与旧三档逐键、严格累加", "tide_test", r"TIDE failures=0", []),
    "meta": ("认知塑造（docs/109 §4）：节点数据完整（总量 625、前置、推荐顺序）、推荐点法按预算点、--meta=full 点满、测试局缺省不带", "meta_test", r"META failures=0", ["--roster=start5"]),
    "meta_mech": ("认知塑造质变 / 非数值节点（docs/109 §14 v5）：护盾反震、低血回复翻倍、处决、濒死免死、静守、升级再升、开局四选一、免费刷新、首个藏品三选一、绝处逢生复活、未雨绸缪闪避 + 闪避补偿", "meta_mech_test", r"META MECH checks=\d+ failures=0",
        ["--balance", "--seed=1", "--op=wisadel", "--metanodes=sh1,reg3,atk5,hp5,def4,xp4,disp1,disp2,disp3,disp4,dodge1,dodge2,dodge3"]),
    "roster": ("干员解锁（docs/109 §12）：开局 5 人、随机寻访先补齐职业、不重复、定向寻访 2 张、旧券折算、局终 3 / 4 张、满员折细胞、云存档并集", "roster_test", r"ROSTER failures=0", ["--roster=start5"]),
    "tour": ("首局聚光框引导 + 到点小提示（screens/tour.gd）：小提示每样只弹一次并记存档 / 排队、老存档不再弹、TIPS 与 Cfg.TIP_IDS 一致", "tour_test", r"TOUR failures=0", ["--roster=new"]),
    "save_migrate": ("存档迁移样本（docs/126 R1）：难度 diff_ver 1–5、旧倍速、旧亮度缺省、三种旧券、没有 [roster] 段的老存档", "save_migrate_test", r"SAVE MIGRATE failures=0", []),
    "medals": ("蚀刻章「深蓝之下」（core/medals.gd）：章表、藏品 49 / 50 边界与去重、结局 / 协同晋升 / 认知首次与全部、认知重置不收回、套组、读档补录、云存档合并与往返", "medals_test", r"MEDALS failures=0", []),
    "cloud_save": ("B站云存档：打包 / 分片 / 平台限制 / 校验 / 版本 / 合并规则 / Cfg 往返 / 非网页不启用（docs/89）", "cloud_save_test", r"CLOUD SAVE failures=0", []),
    "look": ("观感预设 render/look（角色受光封顶 / 后期曲线 / 亮度缺省）", "look_test", r"LOOK TEST failures=0", []),
    "build_affinity": ("构筑匹配（docs/119 §4.3 / §4.4 → docs/197）：藏品流派 × 干员流派匹配、卡面说明行、强制招募保底与开关", "build_affinity_test", r"BUILD AFFINITY failures=0", ["--balance", "--op=angelina", "--squad=skadi,kaltsit"]),
    "card_desc": ("卡片描述不串台：公共成长 / 填充 / 支援卡不含队长手动技能提示（10-22 截图），干员卡只提自己的技能", "card_desc_test", r"CARD DESC failures=0", ["--balance", "--op=ulpianus", "--squad=skadi,angelina"]),
    "trace_fields": ("TRACE 新增字段 sq / lamp / nd / rl（10-29，docs/126 R3）：只读、不动 rng、对队友位置 / 突击生命 / 技力 / 普攻计时 / 灯火 / 神经损伤 / 藏品数各自敏感、还原后回到原值", "trace_fields_test", r"TRACE FIELDS failures=0", ["--balance", "--op=skadi", "--squad=kaltsit,texas"]),
    "ui_smoke": ("界面冒烟（docs/126 R6）：标题页十屏 + 局内 HUD / 暂停 / 设置 / 属性 / 结算 / 作战记录 / 对局记录各开关两遍，无缺图、无残留节点", "ui_smoke_test", r"UI SMOKE failures=0", []),
    "time_scale_combo": ("时间缩放组合（圆盘 × 倍速 / 顿帧 / 击破慢动作）：有效缩放等于现行组合规则，退出各模态后回到 1", "time_scale_combo_test", r"TIME SCALE COMBO failures=0", ["--balance", "--op=skadi", "--squad=kaltsit"]),
    "runs_log_guard": ("自动测试不写玩家对局记录：tests/ 下场景（含不带 -- 参数直接起的）被 telemetry.save_local 拦下（10-14 / 10-20 / 10-27 runs.jsonl 里的空局）", "runs_log_guard_test", r"RUNS LOG GUARD failures=0", []),
    "hit_fallback": ("g.hit 空描述符沿用上次：特征测试（已知缺陷：空 h 会错记给上一个干员），显式 h 回归保护", "hit_fallback_test", r"HIT FALLBACK failures=0", ["--balance", "--op=skadi", "--squad=kaltsit"]),
    "nerve_rules": ("神经损伤积累规则特征测试（溟痕 / 光环 / 光域 / 锁定 / 满条真伤 / Boss 来源未截断 / 灯火档位），为 afflict 重构兜底", "nerve_rules_test", r"NERVE RULES failures=0", ["--balance", "--op=skadi", "--squad=kaltsit"]),
    "merchant_build_offer": ("第一位商人预告（docs/119 §4.5）：生成时定货架、进店不重抽、联动位、价格同步、售出 / 刷新 / 离开撤销、开关关不提前抽", "merchant_build_offer_test", r"MERCHANT BUILD OFFER failures=0", ["--balance", "--op=skadi", "--squad=kaltsit"]),
}


def check_scene(godot, key):
    name, scene, success, extra = SCENE_REGRESSIONS[key]
    if scene.endswith(".gd"):   # SceneTree 脚本式测试：godot --script res://tests/<名>.gd
        out, err, to, log = _run([godot, "--headless", "--path", GAME, "--script", "res://tests/" + scene] + extra, 180, key)
    else:
        out, err, to, log = _run([godot, "--headless", "--path", GAME, "res://tests/" + scene + ".tscn",
                                 "--", "--regression", "--seed=1"] + extra, 180, key)
    errs = GR.script_errors(out, err)
    match = re.search(r"^" + success + r"(?:\s|;|$)", out, re.M)
    fails = re.findall(r"^(?:FAIL|MISSING).*", out + "\n" + err, re.M)
    ok = bool(match) and not errs and not fails and not to
    return {"name": name, "ok": ok, "detail": "超时" if to else (match.group(0).strip() if match else "没有通过标记"),
            "errors": (errs + fails)[:5], "log": log}


# ---------------------------------------------------------------- 机器人矩阵 / A/B

def run_matrix(game, tag, outdir, seeds=4, bots="expert,normal", preset="starts", extra=None):
    os.makedirs(outdir, exist_ok=True)
    cmd = [sys.executable, os.path.join(ROOT, "tools", "balance_run.py"), "--preset", preset, "--bots", bots, "--seeds", str(seeds),
           "--tag", tag, "--game", game, "--out", outdir]
    if extra:
        cmd += ["--extra=" + extra]
    subprocess.run(cmd, cwd=ROOT)
    files = sorted(glob.glob(os.path.join(outdir, tag + "_*.json")), key=os.path.getmtime)
    return json.load(open(files[-1], encoding="utf-8"))["records"] if files else []


def _fmt(t):
    return "%d:%02d" % (int(t) // 60, int(t) % 60)


def _same(p, q):
    """两局结果相同：只比两边都有的字段（不含 prof），基准提交之后新加的统计字段（如 ctrl）不算差异"""
    return all(p[k] == q[k] for k in (set(p) & set(q)) - {"prof"})


def compare(base, head):
    """按 机器人 × 开局 对比胜率 / 存活 / 终局等级；配对 seed 算出变化的局数"""
    def group(recs):
        g = {}
        for r in recs:
            if "data" in r:
                g.setdefault((r["bot"], r["squad"][0]), {})[r["seed"]] = r["data"]
        return g
    a, b = group(base), group(head)
    lines = ["| 机器人 | 开局 | 胜率 前 | 胜率 后 | 存活 前 | 存活 后 | 等级 前 | 等级 后 | 结果完全相同的局 |", "|---|---|---|---|---|---|---|---|---|"]
    tot = {}
    for key in sorted(set(a) & set(b)):
        x, y = a[key], b[key]
        seeds = sorted(set(x) & set(y))
        if not seeds:
            continue
        same = sum(1 for s in seeds if _same(x[s], y[s]))
        row = []
        for d in (x, y):
            ds = [d[s] for s in seeds]
            row.append((sum(1 for q in ds if q.get("win")) / len(ds), statistics.mean(q["t"] for q in ds), statistics.mean(q["lv"] for q in ds)))
        lines.append("| %s | %s | %d%% | %d%% | %s | %s | %.1f | %.1f | %d / %d |" % (key[0], key[1], row[0][0] * 100, row[1][0] * 100,
                     _fmt(row[0][1]), _fmt(row[1][1]), row[0][2], row[1][2], same, len(seeds)))
        t = tot.setdefault(key[0], [[], [], 0, 0])
        t[0] += [x[s] for s in seeds]
        t[1] += [y[s] for s in seeds]
        t[2] += same
        t[3] += len(seeds)
    for bot, (x, y, same, n) in tot.items():
        wa = sum(1 for q in x if q.get("win")) / len(x)
        wb = sum(1 for q in y if q.get("win")) / len(y)
        lines.append("| **%s 合计** | | %d%% | %d%% | %s | %s | %.1f | %.1f | %d / %d |" % (bot, wa * 100, wb * 100,
                     _fmt(statistics.mean(q["t"] for q in x)), _fmt(statistics.mean(q["t"] for q in y)),
                     statistics.mean(q["lv"] for q in x), statistics.mean(q["lv"] for q in y), same, n))
    return "\n".join(lines)


def ab(ref, seeds, keep):
    croot = GR.common_root()
    sha = subprocess.run(["git", "rev-parse", "--short", ref], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    if not sha:
        sys.exit("找不到提交：" + ref)
    wt = os.path.join(croot, ".claude", "worktrees", "ab-" + sha)
    made = False
    if not os.path.isdir(wt):
        subprocess.run(["git", "worktree", "add", "--detach", wt, sha], cwd=ROOT, check=True)
        made = True
        # 拷导入缓存，免得临时工作树第一次启动重新导入全部资源
        src = os.path.join(GAME, ".godot")
        if os.path.isdir(src) and not os.path.isdir(os.path.join(wt, "game", ".godot")):
            shutil.copytree(src, os.path.join(wt, "game", ".godot"))
    outdir = os.path.join(OUT_DIR, "ab_" + datetime.datetime.now().strftime("%m%d_%H%M"))
    print("A/B：基准 %s（%s） vs 当前工作区；机器人标准矩阵 × %d seed" % (ref, sha, seeds), flush=True)
    base = run_matrix(os.path.join(wt, "game"), "base_" + sha, outdir, seeds)
    head = run_matrix(GAME, "head", outdir, seeds)
    table = compare(base, head)
    print("\n" + table)
    open(os.path.join(outdir, "compare.md"), "w", encoding="utf-8").write("# A/B %s vs 工作区\n\n%s\n" % (sha, table))
    print("\n写入", os.path.join(outdir, "compare.md"))
    if made and not keep:
        subprocess.run(["git", "worktree", "remove", "--force", wt], cwd=ROOT)


# ---------------------------------------------------------------- 主流程

def _timed(f):
    """跑一个检查项，记下它真正占用 Godot 的秒数（_run 累计）；没开 Godot 的静态项记墙钟"""
    _TL.secs = 0.0
    t = time.time()
    r = f()
    r["secs"] = _TL.secs if _TL.secs > 0 else time.time() - t
    return r


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bots", action="store_true", help="快检之后再跑机器人标准矩阵")
    ap.add_argument("--ab", metavar="REF", help="与某个提交做 A/B 对比（机器人标准矩阵）")
    ap.add_argument("--seeds", type=int, default=4)
    ap.add_argument("--keep", action="store_true", help="A/B 结束后保留临时工作树")
    ap.add_argument("--only", choices=["core", "smoke", "nodes", "hold_aim", "prot", "repro", "native_eq", "blocks_eq", "regressions", "art_lint", "slim", "op_text", "ob_tag", "cc_lint", "data_lint", "graph_lint", "check_map", "text_reconcile", "px_lint", "enemy_art", "asset_lint", "asset_index"] + list(SCENE_REGRESSIONS), help="只跑快检里的某一项")
    ap.add_argument("--jobs", type=int, default=GR.MAX_PROCS,
                    help="本次快检最多同时开几个 Godot（缺省 = 全机上限）；全机总数另受 GODOT_MAX_PROCS 限制")
    ap.add_argument("--bal", action="append", default=[], metavar="段/键=值",
                    help="透传给每个 Godot 进程的旋钮覆盖（--bal=enemy/density=1，可重复）；查测试在非缺省旋钮下是否仍过")
    ap.add_argument("--eq-all", action="store_true", help="积木等价每组跑全部用例（缺省只跑 seed1；全部用例由云端每日例行任务跑，docs/36 §7.6）")
    ap.add_argument("--update-golden", action="store_true", help="积木等价通过后把数据版输出重录到 game/tests/golden_current（git 跟踪，ship 全量通过后用，docs/36 §1.3）")
    ap.add_argument("--rerecord-golden", action="store_true",
                    help="等价于 --only blocks_eq --eq-all --update-golden：重录积木等价金样（docs/36 §1.3；谁负责跑见该节）")
    ap.add_argument("--nocache", action="store_true", help="不读也不写结果缓存（build/check_cache，docs/36 §1.2）")
    ap.add_argument("--changed", nargs="?", const="", default=None, metavar="BASE",
                    help="按相对 BASE 的改动文件，用 tools/check_map.json 选要跑的检查组（缺省基线 = origin/claude/integ-1029 / main 里离 HEAD 最近的 merge-base）；"
                         "全局公共文件升级为分支全量，未映射路径保守跑 core + 抽样冒烟（docs/204 §2）")
    ap.add_argument("--assume-files", metavar="A,B", help="测量 / 演示用：不看 git，当作这些文件（逗号分隔）被改了，配合 --changed / --explain")
    ap.add_argument("--explain", action="store_true", help="只打印 --changed 的选项计划并和旧 --auto 的计划对照，不跑任何检查")
    ap.add_argument("--auto", action="store_true",
                    help="--changed 的别名（缺省基线）；分支上判成全量时跑精简版（不跑积木等价 / 自然流程，冒烟抽样），在 main 上跑真全量（docs/36 §1.4）")
    a = ap.parse_args()
    if a.rerecord_golden:   # 等价于 --only blocks_eq --eq-all --update-golden（docs/36 §1.3）
        a.only = "blocks_eq"
        a.eq_all = True
        a.update_golden = True
    if a.auto and a.changed is None:
        a.changed = ""
    if a.assume_files:
        global ASSUME_FILES
        ASSUME_FILES = [x for x in a.assume_files.split(",") if x]
        if a.changed is None:
            a.changed = ""
    if a.explain:
        print_plan(make_plan(a.changed or ""), compare_old=True)
        return 0
    global JOBS, LOG_DIR, BAL_ARGS
    JOBS = max(1, a.jobs)
    BAL_ARGS = ["--bal=" + b for b in a.bal]
    godot = GR.find_godot()
    GR.ensure_imported(GAME)
    if a.ab:
        ab(a.ab, a.seeds, a.keep)
        return 0
    t0 = time.time()
    LOG_DIR = os.path.join(OUT_DIR, "quick_" + datetime.datetime.now().strftime("%m%d_%H%M%S"))
    os.makedirs(LOG_DIR, exist_ok=True)
    load0 = GR.count_godot()
    print("快检：本次最多 %d 个 Godot 并行（全机上限 %d，开始时全机已有 %d 个）；日志 %s" % (JOBS, GR.MAX_PROCS, load0, LOG_DIR), flush=True)
    jobs = [check_static]
    if a.only in (None, "art_lint"):
        jobs.append(check_art_lint)   # 不开 Godot，约 10 秒；--auto 也跑（只改美术时这是唯一相关项）
    if a.only in (None, "slim"):
        jobs.append(check_release_slim)   # 不开 Godot，约 5 秒；--auto 也跑（改文案 / 美术 / 预设都可能碰到）
    if a.only in (None, "op_text"):
        jobs.append(check_op_text)   # 不开 Godot，约 1 秒；--auto 也跑（改干员数值或文字都要对一遍）
    if a.only in (None, "ob_tag"):
        jobs.append(check_ob_tag)   # 不开 Godot，约 1 秒；--auto 也跑（加积木 tag 时防两个执行器认同一个 tag、单播表漏登记）
    if a.only in (None, "enemy_art"):
        jobs.append(check_enemy_art)
    if a.only in (None, "asset_lint"):
        jobs.append(check_asset_lint)   # 不开 Godot；ERROR 算失败（docs/189）
    if a.only in (None, "asset_index"):
        jobs.append(check_asset_index)
    if a.only == "px_lint":
        jobs.append(check_px_lint)   # 不开 Godot；只在 --only px_lint 时跑（不进 --auto / 全量：样本在 codex-art 工作树，别人机器上可能没有）
    if a.only in (None, "data_lint"):
        jobs.append(check_data_lint)   # 不开 Godot，约 1 秒；--auto 也跑（改数据表最容易静默出错的几类）
    if a.only in (None, "graph_lint"):
        jobs.append(check_graph_lint)   # 不开 Godot，<1 秒；--auto 也跑（改成长线 / 路线 / 事件 / 引用键 / 图标最容易静默断链）
    if a.only in (None, "text_reconcile"):
        jobs.append(check_text_reconcile)
    if a.only in (None, "check_map"):
        jobs.append(check_map)
    if a.only in (None, "cc_lint"):
        jobs.append(check_cc_lint)   # 不开 Godot，约 1 秒；--auto 也跑（击退累加漏乘失重、干员绕过 add_cc / set_air）
    branch_full, ops = False, set()
    selective, plan = False, None
    if a.changed is not None and not a.only:
        plan = make_plan(a.changed)
        print_plan(plan, compare_old=True)
        ops = plan["ops"]
        if plan["full"]:
            if _git("branch", "--show-current").strip() != "main":
                branch_full = True   # 分支上的全量：精简版（见下），main 上照旧真全量
        else:
            selective = True
            print("    注意：分级只用于改的过程中；合入 main 的全量在协调人 / 云端 CI 跑", flush=True)
            if "core" in plan["groups"]:
                jobs.append(lambda: check_core(godot))
            if ops:
                jobs += [(lambda c=c: run_case(godot, c[0], c[1])) for c in smoke_cases() if c[0].split(" · ")[-1] in ops]
                jobs.append(lambda: check_nodes(godot, ops))
                jobs.append(lambda: check_hold_aim(godot, ops))
            if "smoke-sample" in plan["groups"]:
                head = _git("rev-parse", "HEAD").strip() or "0"
                allc = smoke_cases()
                names = op_ids()
                k0 = int(head[:8], 16) % max(1, len(names))
                sample = set(names[(k0 + i) % len(names)] for i in range(min(SMOKE_SAMPLE, len(names))))
                jobs += [(lambda c=c: run_case(godot, c[0], c[1])) for c in allc if c[0].startswith("冒烟 · ") and c[0].split(" · ")[-1] in sample]
            if ops or "repro" in plan["groups"]:
                jobs.append(lambda: check_repro(godot))
            if "prot" in plan["groups"]:
                jobs.append(lambda: check_prot(godot))
            jobs += [(lambda key=key: check_scene(godot, key)) for key in SCENE_REGRESSIONS if key in plan["scenes"]]
    if branch_full:
        # 分支全量精简（用户 10-24「全改」，docs/36 §1.4）：积木等价不跑（分支改玩法后金样必然过期、只能报过期，合入后 main 统一重录比对）；
        # 自然流程两局不跑；冒烟只跑改动涉及的干员 + 按 HEAD 轮换抽 SMOKE_SAMPLE 人。其余（核心契约、成长节点、复现、全部定向回归）照旧
        head = _git("rev-parse", "HEAD").strip() or "0"
        ids = op_ids()
        k0 = int(head[:8], 16) % max(1, len(ids))
        sample = set(ids[(k0 + i) % len(ids)] for i in range(min(SMOKE_SAMPLE, len(ids))))
        smoke_ops = sample | ops
        print("分支全量精简：不跑积木等价、自然流程；冒烟 %d / %d 人（改动涉及：%s；轮换抽样：%s）。合入 main 后跑真全量" % (
            len(smoke_ops), len(ids), "、".join(sorted(ops)) or "无", "、".join(sorted(sample))), flush=True)
    if not selective:
        if a.only in (None, "core"):
            jobs.append(lambda: check_core(godot))
        if a.only in (None, "smoke"):
            cases = smoke_cases()
            if branch_full:
                cases = [c for c in cases if c[0].startswith("冒烟 · ") and c[0].split(" · ")[-1] in smoke_ops]
            jobs += [(lambda c=c: run_case(godot, c[0], c[1])) for c in cases]
        if a.only in (None, "nodes"):
            jobs.append(lambda: check_nodes(godot))
        if a.only in (None, "hold_aim"):
            jobs.append(lambda: check_hold_aim(godot))
        if a.only in (None, "prot"):
            jobs.append(lambda: check_prot(godot))
        if a.only in (None, "repro"):
            jobs.append(lambda: check_repro(godot))
        if a.only in (None, "native_eq"):
            jobs.append(lambda: check_native_eq(godot))
        if a.only in (None, "blocks_eq") and not branch_full:
            jobs.append(lambda: check_blocks_eq(godot))
        for key in SCENE_REGRESSIONS:
            if a.only in (None, "regressions", key):
                jobs.append(lambda key=key: check_scene(godot, key))
    global GATE, NOCACHE, EQ_ALL, UPDATE_GOLDEN
    EQ_ALL = a.eq_all
    UPDATE_GOLDEN = a.update_golden
    GATE = Gate(JOBS, _last_durations())
    NOCACHE = a.nocache
    if not NOCACHE:
        SCOPES.update(scope_hashes())
    with ThreadPoolExecutor(max(1, len(jobs))) as ex:   # 各项一起开始，Godot 在 GATE 排队（最久的先开）；不开 Godot 的静态项不占名额
        results = list(ex.map(_timed, jobs))
    import known_red
    kr_items, kr_errs = known_red.load()
    hard, known, expired, stale = known_red.classify(results, kr_items)
    bad = hard + [r for r, _ in expired] + [{"name": "known_red.json", "detail": e, "ok": False} for e in kr_errs]
    lines = []
    for r in results:
        lines.append("%s %s  %s%s" % ("通过" if r["ok"] else "失败", r["name"], r["detail"], "  [%.0f 秒]" % r["secs"] if r.get("secs", 0) >= 1 else ""))
        for e in r.get("errors", []):
            lines.append("      " + e[:220])
    slow = sorted(results, key=lambda r: -r.get("secs", 0))[:10]
    if slow and slow[0].get("secs", 0) >= 1:
        lines.append("\n耗时前 10（秒，不含排队）：" + "；".join("%s %.0f" % (r["name"][:24], r["secs"]) for r in slow if r.get("secs", 0) >= 1))
    if known:
        lines.append("\n已知红（%d 项，known_red.json，未过期，不算失败）：" % len(known))
        lines += ["  · %s — 负责人 %s，到期 %s：%s" % (r["name"], it["owner"], it["due"], it["reason"][:60]) for r, it in known]
    waived = [(r["name"], e, it) for r in results for e, it in r.get("waived", [])]
    if waived:
        lines.append("\n已知红放行的单条错误（%d 条）：" % len(waived))
        lines += ["  · %s — %s，到期 %s" % (e[:90], it["owner"], it["due"]) for _, e, it in waived]
    for r, it in expired:
        lines.append("\n已知红过期 %d 天仍红：%s（负责人 %s，到期 %s）" % (it["expired_days"], r["name"], it["owner"], it["due"]))
    for it in stale:
        lines.append("\n提示：已知红「%s」现在已绿，可从 known_red.json 删除" % it["scope"])
    try:
        os.makedirs(OUT_DIR, exist_ok=True)
        json.dump({"time": datetime.datetime.now().isoformat(timespec="seconds"), "items": [
            {"name": r["name"], "ok": r["ok"], "secs": round(r.get("secs", 0), 1), "detail": r["detail"]} for r in results]},
            open(os.path.join(OUT_DIR, "last_quick.json"), "w", encoding="utf-8"), ensure_ascii=False)
    except OSError:
        pass
    summary = "\n".join(lines) + "\n\n%s：%d 项，失败 %d 项（已知红 %d 项另计），耗时 %.0f 秒（开始时全机 %d 个 Godot，结束时 %d 个）%s" % (
        "快检通过" if not bad else "快检失败", len(results), len(bad), len(known), time.time() - t0, load0, GR.count_godot(),
        "；Godot 结果缓存命中 %d / %d（不用缓存加 --nocache）" % (CACHE_STAT["hit"], CACHE_STAT["hit"] + CACHE_STAT["miss"]) if not NOCACHE else "；未用缓存")
    if bad:
        # 失败项单独再列一遍：名字、原因、完整日志路径（负载高时偶发失败，事后要能查到是哪项、为什么）
        summary += "\n\n失败项：\n" + "\n".join("  · %s — %s\n    日志：%s" % (r["name"], r["detail"], r.get("log") or "（无）") for r in bad)
    print(summary)
    os.makedirs(OUT_DIR, exist_ok=True)
    open(os.path.join(OUT_DIR, "last_quick.txt"), "w", encoding="utf-8").write(summary + "\n")
    if a.bots and not bad:
        outdir = os.path.join(OUT_DIR, "bots_" + datetime.datetime.now().strftime("%m%d_%H%M"))
        run_matrix(GAME, "bots", outdir, a.seeds)
    return 1 if bad else 0


if __name__ == "__main__":
    # 统一 UTF-8 输出：Windows 下缺省是 GBK，别的会话读到的是乱码，看不出哪项失败
    for _s in (sys.stdout, sys.stderr):
        try:
            _s.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    sys.exit(main())
