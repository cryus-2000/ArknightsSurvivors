# -*- coding: utf-8 -*-
"""出包用的导入缓存复用（docs/33 §发版提速，11-17）。

干净副本（build/_export/src、build/_web/src）每次都是 git archive 新解出来的，没有 .godot，Godot 要把 6000 多个素材全部重导一遍。
这里把上一次导出成功后的导入产物按「内容键」存到 build/_import_cache/<变体>/，下一次导入前把键对得上的产物放回干净副本，
Godot 的 --import 只重导键对不上的（新增 / 改过的素材、改过的 .import、改过的导入相关工程设置）。

键（每个素材一个）= sha256(SCHEMA, 全局键, 素材相对路径, 素材字节的 sha256, .import 字节的 sha256)：
  - 全局键 = Godot 可执行文件（路径 + 大小 + 修改时间）+ project.godot 里与导入有关的段（[rendering] [importer_defaults] [editor] [compression] [audio]，整段原文）；
    网页包的 WebP 压缩力度写在 [rendering]，所以 Windows / 网页两个变体天然分开，另外变体名也单独分目录。
  - 键在 Godot 动手之前、对打包副本做完全部改写（字体子集、半分辨率、音频再压缩、.import 改参数……）之后算，存与取用同一时刻的状态。
快照里除了产物，还存导入后的 .import：打包副本里有些 .import 是脚本现写的（tools/web_half.py 生成的 1 倍图 / @h 图，没有 uid 和 [deps]），
Godot 每次都当新文件导入并补写 uid / dest_files。键按导入前的 .import 算，放回时连补好的 .import 一起放回，Godot 就不再重导（uid 沿用上次随机生成的那个，没有别处按 uid 引用这些图）。
放回之后仍由 Godot 自己核对（.godot/imported/<名>-<路径md5>.md5 里的 source_md5 / dest_md5），对不上它会重导；
存的时候也逐条核对 dest_md5 = 产物拼接的 md5，对不上的那条不存（无头导入退出时偶发崩溃写坏的产物不会进缓存）。

缓存目录只留一份快照（每个变体最近一次成功导出），大小约等于一份 .godot/imported（11-17 实测 Windows 约 160 MB、网页约 100 MB）。
ARK_NO_IMPORT_CACHE=1 关掉（取、存都不做），对照用。
"""
import hashlib, json, os, re, shutil, time

SCHEMA = 2   # 2：快照里连导入后的 .import 一起存（11-17）
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "build", "_import_cache")
SECTIONS = ("rendering", "importer_defaults", "editor", "compression", "audio")
_RES_RE = re.compile(r'"(res://[^"]+)"')


def _place(src, dst):
    """硬链接（同盘，几乎不花时间；新写出的文件首次打开要被实时防护扫描，上万个小文件拷贝 + 首读要几分钟，硬链接的不用，11-17 实测 3000 个 34 秒 → 0.8 秒），
    链不了（跨盘等）就拷贝。Godot 只读放回的产物；万一它就地改写了某个文件，存快照时的 md5 核对与下次放回后 Godot 自己的 md5 核对都会发现"""
    if os.path.lexists(dst):
        os.remove(dst)
    try:
        os.link(src, dst)
    except OSError:
        shutil.copyfile(src, dst)


def enabled():
    return os.environ.get("ARK_NO_IMPORT_CACHE") != "1"


def _sha(b):
    return hashlib.sha256(b).hexdigest()


def _file_sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def global_key(gpath, godot):
    st = os.stat(godot)
    txt = open(os.path.join(gpath, "project.godot"), "rb").read().decode("utf-8").replace("\r\n", "\n")
    keep, cur = [], None
    for ln in txt.split("\n"):
        m = re.match(r"^\[([^\]]+)\]\s*$", ln)
        if m:
            cur = m.group(1)
        if cur in SECTIONS:
            keep.append(ln)
    return _sha(("%d|%s|%d|%d|%s" % (SCHEMA, os.path.normcase(os.path.abspath(godot)), st.st_size, int(st.st_mtime), "\n".join(keep))).encode("utf-8"))


def _walk_imports(gpath):
    """同 godot_runner.stale_imports 的遍历规则：跳过带 .gdignore 的目录、以 . 开头的目录"""
    for root, dirs, files in os.walk(gpath):
        if ".gdignore" in files:
            dirs[:] = []
            continue
        dirs[:] = [d for d in dirs if not d.startswith(".") and not d.startswith("_probe")]
        for f in files:
            if f.endswith(".import"):
                src = os.path.join(root, f[:-len(".import")])
                if os.path.isfile(src):
                    yield os.path.relpath(src, gpath).replace(os.sep, "/")


def keys(gpath, godot):
    """{素材相对路径: 键}；导入之前调用"""
    from concurrent.futures import ThreadPoolExecutor
    g = global_key(gpath, godot)
    rels = list(_walk_imports(gpath))

    def one(rel):
        p = os.path.join(gpath, rel)
        return _sha(("%s|%s|%s|%s" % (g, rel, _file_sha(p), _file_sha(p + ".import"))).encode("utf-8"))
    with ThreadPoolExecutor(16) as ex:   # hashlib 读文件 / 算哈希时放开 GIL
        return dict(zip(rels, ex.map(one, rels)))


def _md5_name(rel):
    """Godot ResourceFormatImporter::get_import_base_path：res://.godot/imported/<文件名>-<res 路径的 md5>.md5"""
    res = "res://" + rel
    return ".godot/imported/%s-%s.md5" % (rel.rsplit("/", 1)[-1], hashlib.md5(res.encode("utf-8")).hexdigest())


def _dests(gpath, rel):
    """.import 里 [deps] dest_files 登记的产物（相对 game/），加上 .md5 记录；读不到就返回 None"""
    try:
        txt = open(os.path.join(gpath, rel + ".import"), encoding="utf-8").read()
    except OSError:
        return None
    m = re.search(r"^dest_files=\[(.*)\]\s*$", txt, re.M)
    if not m:
        return None
    files = [r[len("res://"):] for r in _RES_RE.findall(m.group(1))]
    return files + [_md5_name(rel)]


def _dest_ok(gpath, rel, files):
    """.md5 里的 source_md5 / dest_md5 与实际文件一致（dest_md5 = 产物按顺序拼接后的 md5，FileAccess::get_multiple_md5）"""
    try:
        txt = open(os.path.join(gpath, files[-1]), encoding="utf-8").read()
    except OSError:
        return False
    sm = re.search(r'source_md5="([0-9a-f]+)"', txt)
    dm = re.search(r'dest_md5="([0-9a-f]+)"', txt)
    if not sm or not dm:
        return False
    h = hashlib.md5()
    with open(os.path.join(gpath, rel), "rb") as fh:
        h.update(fh.read())
    if h.hexdigest() != sm.group(1):
        return False
    h = hashlib.md5()
    for f in files[:-1]:
        p = os.path.join(gpath, f)
        if not os.path.isfile(p):
            return False
        with open(p, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
    return h.hexdigest() == dm.group(1)


def restore(gpath, variant, godot):
    """导入前调用：键对得上的产物放回 gpath；返回 (键表, 命中数)。键表留给 save()"""
    t0 = time.time()
    k = keys(gpath, godot)
    if not enabled():
        print("[导入缓存] 已关闭（ARK_NO_IMPORT_CACHE=1）", flush=True)
        return k, 0
    base = os.path.join(CACHE, variant)
    try:
        man = json.load(open(os.path.join(base, "manifest.json"), encoding="utf-8"))
    except (OSError, ValueError):
        man = {}
    from concurrent.futures import ThreadPoolExecutor

    def one(item):
        rel, key = item
        e = man.get(rel)
        if not e or e.get("key") != key:
            return 0
        srcs = [os.path.join(base, "files", f) for f in e["files"]]
        if not all(os.path.isfile(s) for s in srcs):
            return 0
        for f, s in zip(e["files"], srcs):
            d = os.path.join(gpath, f)
            os.makedirs(os.path.dirname(d), exist_ok=True)
            _place(s, d)
        return 1
    items = list(k.items())
    with ThreadPoolExecutor(16) as ex:
        got = list(ex.map(one, items))
    hit = sum(got)
    miss = [rel for (rel, _), g in zip(items, got) if not g]
    print("[导入缓存] %s：命中 %d / %d 个素材（%.1f 秒），其余由 Godot 重导" % (variant, hit, len(k), time.time() - t0), flush=True)
    if miss:
        from collections import Counter
        by = Counter(os.path.dirname(r) or "." for r in miss).most_common(6)
        print("[导入缓存] 未命中 %d 个，按目录：%s%s" % (len(miss), "、".join("%s %d" % kv for kv in by),
              "；例如 " + "、".join(miss[:4]) if len(miss) <= 12 else ""), flush=True)
    return k, hit


def save(gpath, variant, k):
    """导出成功后调用：按 restore() 算的键把产物存成新快照（先写 <变体>.new 再整目录换掉旧的）"""
    if not enabled():
        return
    t0 = time.time()
    base = os.path.join(CACHE, variant)
    new = base + ".new"
    shutil.rmtree(new, ignore_errors=True)
    from concurrent.futures import ThreadPoolExecutor
    man, bad = {}, 0
    rels = list(k)

    def check(rel):   # 核对通过的才拷进新快照
        files = _dests(gpath, rel)
        if not files or not _dest_ok(gpath, rel, files):
            return None
        files = files + [rel + ".import"]   # 导入后的 .import 也存：web_half 现写的 .import 没有 uid / deps，Godot 导入时补上，放回时要用补好的那份
        for f in files:
            d = os.path.join(new, "files", f)
            os.makedirs(os.path.dirname(d), exist_ok=True)
            _place(os.path.join(gpath, f), d)
        return files
    with ThreadPoolExecutor(16) as ex:
        checked = list(ex.map(check, rels))
    for rel, files in zip(rels, checked):
        if files:
            man[rel] = {"key": k[rel], "files": files}
        else:
            bad += 1
    os.makedirs(new, exist_ok=True)
    with open(os.path.join(new, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(man, fh, ensure_ascii=False, separators=(",", ":"))
    old = base + ".old"
    shutil.rmtree(old, ignore_errors=True)
    if os.path.isdir(base):
        os.replace(base, old)
    os.replace(new, base)
    shutil.rmtree(old, ignore_errors=True)
    print("[导入缓存] %s：存了 %d 个素材的产物（%d 个核对不过没存，%.1f 秒）" % (variant, len(man), bad, time.time() - t0), flush=True)


def prewarm_tree(root, label=""):
    """把 root 下所有文件用 32 个线程各读一遍。刚写出的文件第一次被打开时要过实时防护扫描（系统设置，不改），
    Godot 与发布检查 / 字体子集都是逐个串行读，1.4 万个新文件首读约 124 秒；并行先读一遍约 6 秒，之后再读就是缓存命中（11-17 实测，第二遍 1.2 秒）。
    只读不写，产物不受影响"""
    from concurrent.futures import ThreadPoolExecutor
    t0 = time.time()
    files = [os.path.join(r, f) for r, _, fs in os.walk(root) for f in fs]

    def rd(p):
        try:
            with open(p, "rb") as fh:
                while fh.read(1 << 20):
                    pass
        except OSError:
            pass
    with ThreadPoolExecutor(32) as ex:
        list(ex.map(rd, files))
    print("[预读] %s%d 个文件 %.1f 秒" % (label + "：" if label else "", len(files), time.time() - t0), flush=True)
