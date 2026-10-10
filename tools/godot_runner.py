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


def _lock(path=None):
    """在 path（缺省：启动锁）上加独占文件锁，拿到才返回；用 _unlock 释放"""
    path = path or _LOCK
    os.makedirs(os.path.dirname(path), exist_ok=True)
    f = open(path, "a+b")
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


class file_lock:
    """with file_lock(path): ... —— 跨进程独占锁（出包用：build/_export 一次只能有一个 export_build / 验证在用）"""
    def __init__(self, path):
        self.path = path
        self.f = None

    def __enter__(self):
        self.f = _lock(self.path)
        return self

    def __exit__(self, *_):
        _unlock(self.f)


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


# 快检 / 批跑用的固定设置（2026-10-01 协调人：数值发现 prot_test 读到本机存档里的难度 Ⅳ 误报）：
# 每次启动 Godot 都给一个临时的用户目录（Windows 的 APPDATA、Linux 的 XDG_DATA_HOME），里面只有这份 settings.cfg——
# 难度 = 标准、画质 = 高、手动普攻 = 关、静音，其他偏好走缺省；测试改设置（例如 ea_ui 的封面干员）也不会写进玩家的真实存档。
# 设环境变量 ARK_REAL_USERDIR=1 可退回旧行为（用真实用户目录）
TEST_SETTINGS = """[video]
fullscreen=false
res_index=0
quality="high"

[audio]
master=0.0
music=0.0
sfx=0.0
voice=0.0

[input]
manual_attack=false

[progress]
difficulty=0
"""


def _test_userdir():
    if os.environ.get("ARK_REAL_USERDIR") == "1":
        return None, None
    import tempfile
    root = tempfile.mkdtemp(prefix="ark_test_")
    d = os.path.join(root, "ArknightsSurvivors")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "settings.cfg"), "w", encoding="utf-8") as fh:
        fh.write(TEST_SETTINGS)
    env = dict(os.environ, APPDATA=root, XDG_DATA_HOME=root)
    return root, env


def _no_focus_kwargs(args):
    """开窗口的测试局不抢前台（用户 10-06：别让弹窗打扰）：Windows 下以「最小化且不激活」启动，截图仍从画布取帧不受影响；
    设 ARK_SHOW_WINDOW=1 可恢复正常弹窗（肉眼看局时用）。--headless 不受影响"""
    if os.name != "nt" or "--headless" in args or os.environ.get("ARK_SHOW_WINDOW") == "1":
        return {}
    si = subprocess.STARTUPINFO()
    si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    si.wShowWindow = 7   # SW_SHOWMINNOACTIVE
    return {"startupinfo": si}


NO_FOCUS_OVERRIDE = """; 由 tools/godot_runner.py 为测试局临时写入（不入库，跑完即删）：窗口不抢焦点、创建时就在屏幕外
[display]
window/size/no_focus=true
window/size/initial_position_type=0
window/size/initial_position=Vector2i(5000, 100)
"""


def _hide_offscreen(p):
    """开窗口测试局：用 Win32 把该进程的窗口挪到屏幕外并压到 Z 序最底（Godot 自己会把 --position 夹回屏幕内，所以从外面挪）。
    窗口不最小化（最小化后画布不渲染、截图全黑）。后台线程跟到进程结束，前 10 秒每 50 ms、之后每 0.5 秒补一次"""
    if os.name != "nt":
        return
    import ctypes, ctypes.wintypes as W, threading
    u = ctypes.windll.user32
    HWND_BOTTOM = 1

    def family():
        # console 版 Godot exe 会再起一个真正的 GUI 进程，窗口挂在子进程上：按父子关系收集整个进程树
        k = ctypes.windll.kernel32
        class PE(ctypes.Structure):
            _fields_ = [("dwSize", W.DWORD), ("cntUsage", W.DWORD), ("th32ProcessID", W.DWORD), ("th32DefaultHeapID", ctypes.c_void_p),
                        ("th32ModuleID", W.DWORD), ("cntThreads", W.DWORD), ("th32ParentProcessID", W.DWORD), ("pcPriClassBase", ctypes.c_long),
                        ("dwFlags", W.DWORD), ("szExeFile", ctypes.c_char * 260)]
        snap = k.CreateToolhelp32Snapshot(0x2, 0)
        pairs = []
        e = PE(); e.dwSize = ctypes.sizeof(PE)
        if k.Process32First(snap, ctypes.byref(e)):
            while True:
                pairs.append((e.th32ProcessID, e.th32ParentProcessID))
                if not k.Process32Next(snap, ctypes.byref(e)):
                    break
        k.CloseHandle(snap)
        fam = {p.pid}
        changed = True
        while changed:
            changed = False
            for pid, ppid in pairs:
                if ppid in fam and pid not in fam:
                    fam.add(pid); changed = True
        return fam

    def tick():
        hs = []
        fam = family()
        def cb(h, _):
            pid = W.DWORD()
            u.GetWindowThreadProcessId(h, ctypes.byref(pid))
            if pid.value in fam and u.IsWindowVisible(h):
                hs.append(h)
            return True
        u.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, W.HWND, W.LPARAM)(cb), 0)
        if os.environ.get("ARK_NOFOCUS_DEBUG"):
            sys.stderr.write("[nofocus] fam=%s windows=%s\n" % (sorted(fam), hs))
        for h in hs:
            r = W.RECT()
            u.GetWindowRect(h, ctypes.byref(r))
            if r.left > -3000:
                ok = u.SetWindowPos(h, HWND_BOTTOM, -4000, -4000, 0, 0, 0x0001 | 0x0010)   # NOSIZE | NOACTIVATE
                if os.environ.get("ARK_NOFOCUS_DEBUG"):
                    r2 = W.RECT(); u.GetWindowRect(h, ctypes.byref(r2))
                    sys.stderr.write("[nofocus] move %s: %s -> ok=%s now %s\n" % (h, (r.left, r.top), ok, (r2.left, r2.top)))

    def loop():
        t0 = time.time()
        while p.poll() is None:
            try:
                tick()
            except Exception as e:   # 只影响窗口位置，不影响测试结果
                if os.environ.get("ARK_NOFOCUS_DEBUG"):
                    import traceback; traceback.print_exc()
            time.sleep(0.05 if time.time() - t0 < 10 else 0.5)
    threading.Thread(target=loop, daemon=True).start()


def _write_override(args):
    """在 --path 指向的项目目录写 override.cfg（已存在且内容相同就复用，不动别人的）。返回要删除的路径或 None"""
    if "--path" not in args:
        return None
    d = args[args.index("--path") + 1]
    p = os.path.join(d, "override.cfg")
    if os.path.exists(p):
        return None
    try:
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(NO_FOCUS_OVERRIDE)
        return p
    except OSError:
        return None


def run_godot(args, timeout):
    """在全机并发上限内启动一个 Godot，返回 (stdout, stderr, 是否超时)。缺省用临时用户目录 + 固定设置（见 TEST_SETTINGS）"""
    root, env = _test_userdir()
    override = None
    if os.name == "nt" and "--headless" not in args and os.environ.get("ARK_SHOW_WINDOW") != "1":
        env = dict(env or os.environ)
        env["ARK_NO_FOCUS"] = "1"   # 游戏内 settings.gd：不居中、unfocusable、前 6 秒持续最小化
        override = _write_override(args)   # 项目级 no_focus + 初始位置屏幕外：窗口创建那一瞬间就不抢前台、不可见
        if "--position" not in args:
            args = list(args)
            i = args.index("--") if "--" in args else len(args)
            args[i:i] = ["-w", "--position", "5000,100"]
    while True:
        f = _lock()
        try:
            if count_godot() < MAX_PROCS:
                p = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, **_no_focus_kwargs(args))
                if override is not None or (env or {}).get("ARK_NO_FOCUS") == "1":
                    _hide_offscreen(p)
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
    if root:
        import shutil
        shutil.rmtree(root, ignore_errors=True)
    if override and count_godot() == 0:
        try:
            os.remove(override)
        except OSError:
            pass
    return out.decode("utf-8", "replace"), err.decode("utf-8", "replace"), timed_out


_IMPORT_EXT = (".png", ".jpg", ".jpeg", ".webp", ".svg", ".ogg", ".wav", ".mp3", ".ttf", ".otf")
_IMPORTED_RE = re.compile(r'"res://\.godot/imported/([^"]+)"')


def stale_imports(game_dir):
    """导入缓存缺了哪些：.import 里登记的缓存文件不存在，或素材还没有 .import（新拉来的）。跳过带 .gdignore 的目录"""
    imp = os.path.join(game_dir, ".godot", "imported")
    miss = []
    for root, dirs, files in os.walk(game_dir):
        if ".gdignore" in files:
            dirs[:] = []
            continue
        dirs[:] = [d for d in dirs if not d.startswith(".") and not d.startswith("_probe")]
        for f in files:
            p = os.path.join(root, f)
            if f.endswith(".import"):
                with open(p, encoding="utf-8", errors="replace") as fh:
                    for m in _IMPORTED_RE.finditer(fh.read()):
                        if not os.path.exists(os.path.join(imp, m.group(1))):
                            miss.append(m.group(1))
            elif f.lower().endswith(_IMPORT_EXT) and not os.path.exists(p + ".import"):
                miss.append(os.path.relpath(p, game_dir))
    return miss


def ensure_imported(game_dir, timeout=900):
    """新工作树没有 game/.godot 导入缓存时先导入，否则贴图全是空的、快检大面积报错（2026-09-26 实测 18/19 项失败）。
    第一遍导入有时只导入一部分（缓存里只有几个文件），所以导入到缓存文件数不再增加为止，最多 3 遍。返回导入的遍数（0 = 本来就有）"""
    imp = os.path.join(game_dir, ".godot", "imported")

    def count():
        return len(os.listdir(imp)) if os.path.isdir(imp) else 0

    if count() >= 50:
        miss = stale_imports(game_dir)
        if not miss:
            return 0
        # 缓存在但不全：从 main 拉来新图 / 新音频后没导入过，引用它们的测试会失败（2026-09-29 Boss与怪物报告 ea_ui 失败）
        print("导入资源（%s 缺 %d 个导入文件，例如 %s）" % (game_dir, len(miss), miss[0]), flush=True)
        run_godot([find_godot(), "--headless", "--path", game_dir, "--import"], timeout)
        return 1
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
