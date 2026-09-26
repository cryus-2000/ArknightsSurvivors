# -*- coding: utf-8 -*-
"""跑 Godot 无界面测试的公共部分（docs/36）：找 Godot、全机并发上限、结果缓存、报错扫描。
balance_run.py 与 check.py 共用。

全机并发上限：同一台电脑上所有会话的测试加起来最多同时开 GODOT_MAX_PROCS 个 Godot（缺省 = 逻辑核数 - 4）。
每次启动前在 build/.godot_launch.lock 上加锁、数一遍正在运行的 Godot 进程，满了就等。多个会话同时批跑时
不再互相把 CPU 挤爆（2026-09-26 实测：两批同时跑，每局耗时变成 4–5 倍）。

结果缓存：同 seed 的一局现在可以完全复现（docs/36 §3），所以「游戏源文件内容 + 参数」相同的局直接读缓存。
缓存放在主仓库的 build/balance/cache/ 下，所有工作树共用：main 的基线跑过一次，别的会话做 A/B 时直接复用。
"""
import hashlib, json, os, re, subprocess, sys, time

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)


def find_godot():
    import shutil
    for c in [os.environ.get("GODOT"), "godot", "godot4",
              r"E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"]:
        if not c:
            continue
        if os.path.exists(c):
            return c
        if os.sep not in c and shutil.which(c):
            return shutil.which(c)
    sys.exit("找不到 Godot，请设置环境变量 GODOT")


def common_root(root=ROOT):
    """主仓库根目录（在工作树里也指向主仓库），缓存和锁文件放这里，所有工作树共用"""
    try:
        d = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=root, capture_output=True, text=True).stdout.strip()
        if d:
            d = d if os.path.isabs(d) else os.path.join(root, d)
            return os.path.dirname(os.path.abspath(d))
    except OSError:
        pass
    return root


# ---------------------------------------------------------------- 全机并发上限

MAX_PROCS = int(os.environ.get("GODOT_MAX_PROCS", max(2, (os.cpu_count() or 8) - 4)))
_LOCK = os.path.join(common_root(), "build", ".godot_launch.lock")


def count_godot():
    """正在运行的 Godot 进程数（Windows 上 _console 包装进程与真正的进程各算一边，取大的那个）"""
    try:
        if os.name == "nt":
            out = subprocess.run(["tasklist", "/FO", "CSV", "/NH"], capture_output=True).stdout.decode("mbcs", "replace")
            names = [l.split(",")[0].strip('"').lower() for l in out.splitlines() if l.lower().startswith('"godot')]
            con = sum(1 for n in names if "_console" in n)
            return max(con, len(names) - con)
        out = subprocess.run(["ps", "-A", "-o", "comm="], capture_output=True, text=True).stdout
        return sum(1 for l in out.splitlines() if "godot" in l.lower())
    except OSError:
        return 0


def _lock():
    os.makedirs(os.path.dirname(_LOCK), exist_ok=True)
    f = open(_LOCK, "a+b")
    while True:
        try:
            if os.name == "nt":
                import msvcrt
                f.seek(0)
                msvcrt.locking(f.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return f
        except OSError:
            time.sleep(0.1)


def _unlock(f):
    try:
        if os.name == "nt":
            import msvcrt
            f.seek(0)
            msvcrt.locking(f.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl
            fcntl.flock(f, fcntl.LOCK_UN)
    finally:
        f.close()


def run_godot(args, timeout):
    """在全机并发上限内启动一个 Godot，返回 (stdout, stderr, 是否超时)"""
    while True:
        f = _lock()
        try:
            if count_godot() < MAX_PROCS:
                p = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                break
        finally:
            _unlock(f)
        time.sleep(0.5)
    try:
        out, err = p.communicate(timeout=timeout)
        timed_out = False
    except subprocess.TimeoutExpired:
        p.kill()
        out, err = p.communicate()
        timed_out = True
    return out.decode("utf-8", "replace"), err.decode("utf-8", "replace"), timed_out


def ensure_imported(game_dir, timeout=900):
    """新工作树没有 game/.godot 导入缓存时先导入，否则贴图全是空的、快检大面积报错（2026-09-26 实测 18/19 项失败）。
    第一遍导入有时只导入一部分（缓存里只有几个文件），所以导入到缓存文件数不再增加为止，最多 3 遍。返回导入的遍数（0 = 本来就有）"""
    imp = os.path.join(game_dir, ".godot", "imported")

    def count():
        return len(os.listdir(imp)) if os.path.isdir(imp) else 0

    if count() >= 50:
        return 0
    passes = 0
    last = -1
    while passes < 3 and count() != last:
        last = count()
        print("导入资源（%s 没有完整的导入缓存）：第 %d 遍" % (game_dir, passes + 1), flush=True)
        run_godot([find_godot(), "--headless", "--path", game_dir, "--import"], timeout)
        passes += 1
    print("导入完成：缓存 %d 个文件" % count(), flush=True)
    return passes


ERR_RE = re.compile(r"^(SCRIPT ERROR: .*|Parse Error: .*|ERROR: Failed to load script.*)$", re.M)


def script_errors(out, err):
    """脚本错误与解析错误（Godot 写在 stderr；两边都查）"""
    return ERR_RE.findall(out + "\n" + err)


# ---------------------------------------------------------------- 结果缓存

_SRC_EXT = (".gd", ".json", ".tscn", ".tres", ".cfg", ".godot")


def tree_key(game_dir):
    """游戏源文件内容的摘要：scripts / data / tests / 场景与工程文件的内容，加上美术文件名单（有没有某张图会影响少量逻辑）"""
    h = hashlib.sha1()
    for sub in ["scripts", "data", "tests"]:
        base = os.path.join(game_dir, sub)
        for dp, dn, fn in os.walk(base):
            dn.sort()
            for n in sorted(fn):
                if n.endswith(_SRC_EXT):
                    p = os.path.join(dp, n)
                    h.update(os.path.relpath(p, game_dir).replace("\\", "/").encode())
                    with open(p, "rb") as fh:
                        h.update(fh.read().replace(b"\r\n", b"\n"))
    for n in sorted(os.listdir(game_dir)):
        if n.endswith(_SRC_EXT) and os.path.isfile(os.path.join(game_dir, n)):   # 注意 .godot 目录本身也以 .godot 结尾
            with open(os.path.join(game_dir, n), "rb") as fh:
                h.update(n.encode() + fh.read().replace(b"\r\n", b"\n"))
    for art in [os.path.join(os.path.dirname(game_dir), "art", "incoming"), os.path.join(game_dir, "art", "px")]:
        if os.path.isdir(art):
            h.update("|".join(sorted(os.listdir(art))).encode())
    return h.hexdigest()[:16]


def cache_dir():
    return os.path.join(common_root(), "build", "balance", "cache")


def cache_get(tkey, args_key):
    p = os.path.join(cache_dir(), tkey, hashlib.sha1(args_key.encode()).hexdigest()[:20] + ".json")
    if os.path.exists(p):
        try:
            return json.load(open(p, encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return None
    return None


def cache_put(tkey, args_key, rec):
    d = os.path.join(cache_dir(), tkey)
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, hashlib.sha1(args_key.encode()).hexdigest()[:20] + ".json")
    tmp = p + ".tmp%d" % os.getpid()
    json.dump(rec, open(tmp, "w", encoding="utf-8"), ensure_ascii=False)
    os.replace(tmp, p)
