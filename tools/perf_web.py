"""网页帧时测量（docs/50 §17.1 / §16.6 口径的可复用版，10-24 粒子化会话；原测试会话 scratchpad 里的脚本已随清理丢失）。

  python tools/perf_web.py export [--ref HEAD]                 # 导出测量副本到 build/_perfweb/<提交>/（只导一次，同提交复用）
  python tools/perf_web.py run --ref HEAD --tag x -- <游戏参数…>   # 起本地服务 + 独立 Edge（屏幕外 / 副屏），收 PERF / BALANCE 行
      例：-- --balance --perf --realtime --rtfrom=360 --maxt=600 --nodeath --seed=1 --op=mizuki --norecruit --bot=expert --quality=mid --matab=60
      引擎参数（--fixed-fps 60 等）写在游戏参数前面、用 -- 分开，与桌面相同：-- --fixed-fps 60 -- --balance …

测量副本与发布版的差别（只在副本里改，不进仓库）：
  1. 发布版也读命令行参数：`OS.get_cmdline_user_args() if OS.is_debug_build() else …` 一律改为直接读（--bal= / --perf / 测试静音都靠它）；
  2. 网页参数从网址 ?a=<参数>（可多个）进 GODOT_CONFIG.args；
  3. requestAnimationFrame 换 MessageChannel（不被显示器刷新率卡在 16.7 / 33.3 两档，量到的是真实帧耗时，同 §16.6）；
  4. console.log / console.error 另 POST 回本地服务，按行写进 build/_perfweb/<提交>/out_<tag>.txt。
仍带发布版的 WebGL 状态缓存 gl_state.js（§21），不带分片加载器（本地直接读 index.pck / index.wasm）。
Edge 用独立用户目录、关后台节流；窗口放副屏或屏幕外（同 godot_runner）；结束后按 PID 结束这一棵 Edge 进程树。
"""
import argparse, http.server, io, json, os, re, shutil, socket, subprocess, sys, tarfile, threading, time, urllib.parse

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import godot_runner as gr
import release_slim

ROOT = os.path.dirname(TOOLS)
BASE = os.path.join(gr.common_root(), "build", "_perfweb")
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
ARGS_RE = re.compile(r"OS\.get_cmdline_user_args\(\) if OS\.is_debug_build\(\) else PackedStringArray\(\)")
RAF_JS = """<script>
(function(){var ch=new MessageChannel(),q=[];ch.port1.onmessage=function(){var t=performance.now(),a=q;q=[];for(var i=0;i<a.length;i++)a[i](t);};
window.requestAnimationFrame=function(cb){q.push(cb);if(q.length===1)ch.port2.postMessage(0);return q.length;};window.cancelAnimationFrame=function(){};
var buf=[],send=function(){if(!buf.length)return;var b=buf.join("\\n");buf=[];fetch("/log",{method:"POST",body:b}).catch(function(){});};
setInterval(send,1000);var wrap=function(k){var o=console[k];console[k]=function(){var s=Array.prototype.join.call(arguments," ");
if(/^(PERF|PF |BALANCE|TRACE|SCRIPT ERROR|ERROR|USER ERROR)/.test(s)||k!=="log"){buf.push(s);if(/^(PERF|BALANCE|PF FTDONE)/.test(s))send();}return o.apply(console,arguments);};};
wrap("log");wrap("error");wrap("warn");})();
</script>"""


def commit_of(ref):
    return subprocess.run(["git", "-C", ROOT, "rev-parse", "--short=9", ref], capture_output=True, text=True, check=True).stdout.strip()


def export(ref):
    c = commit_of(ref)
    out = os.path.join(BASE, c)
    if os.path.exists(os.path.join(out, "index.pck")):
        return out
    work = os.path.join(BASE, "_src_" + c)
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    data = subprocess.run(["git", "archive", "--format=tar", ref, "game", "art/incoming"], cwd=ROOT, stdout=subprocess.PIPE, check=True).stdout
    tarfile.open(fileobj=io.BytesIO(data)).extractall(work, filter="data")
    n = 0
    for dp, _, fs in os.walk(os.path.join(work, "game", "scripts")):
        for f in fs:
            if f.endswith(".gd"):
                p = os.path.join(dp, f)
                s = open(p, encoding="utf-8").read()
                s2, k = ARGS_RE.subn("OS.get_cmdline_user_args()", s)
                if k:
                    open(p, "w", encoding="utf-8", newline="").write(s2)
                    n += k
    print("[副本] 发布版读命令行：改了 %d 处" % n)
    art_src = os.path.join(work, "art", "incoming")
    art_dst = os.path.join(work, "game", "art", "incoming")
    os.makedirs(art_dst, exist_ok=True)
    sib = set(os.listdir(art_src))
    for f in os.listdir(art_src):
        if f.lower().endswith(".png") and os.path.isfile(os.path.join(art_src, f)) and not release_slim.is_review_art(f) and not release_slim.is_fallback_2x(f, sib):
            shutil.copy2(os.path.join(art_src, f), art_dst)
    gpath = os.path.join(work, "game")
    exe = gr.find_godot()
    subprocess.run([exe, "--headless", "--path", gpath, "--import"], capture_output=True)
    tmp = os.path.join(BASE, "_out_" + c)
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp)
    p = subprocess.run([exe, "--headless", "--path", gpath, "--export-release", "Web", os.path.join(tmp, "index.html")], capture_output=True, text=True, encoding="utf-8", errors="replace")
    if not os.path.exists(os.path.join(tmp, "index.pck")):
        print(p.stdout[-3000:], p.stderr[-3000:])
        sys.exit("导出失败")
    html = open(os.path.join(tmp, "index.html"), encoding="utf-8").read()
    gl = open(os.path.join(TOOLS, "web", "gl_state.js"), encoding="utf-8").read()
    html = html.replace("<head>", "<head>\n" + RAF_JS + "\n<script>\n" + gl + "\n</script>", 1)
    html, k = re.subn(r'"args":\s*\[\]', '"args":new URLSearchParams(location.search).getAll("a")', html)
    if k != 1:
        sys.exit("index.html 里找不到 \"args\":[]（Godot 网页模板变了？）")
    open(os.path.join(tmp, "index.html"), "w", encoding="utf-8").write(html)
    shutil.rmtree(out, ignore_errors=True)
    os.rename(tmp, out)
    shutil.rmtree(work, ignore_errors=True)
    print("[导出] %s  pck %.1f MB" % (out, os.path.getsize(os.path.join(out, "index.pck")) / 1e6))
    return out


# ---------------------------------------------------------------- 低配模拟（docs/50 §28）：DevTools 协议（CPU 节流 / 手机视口 / 触屏）
def _ws_connect(url):
    """最小 WebSocket 客户端（只发文本帧、收文本帧，够 DevTools 用；不引第三方库）"""
    import base64, struct
    u = urllib.parse.urlparse(url)
    s0 = socket.create_connection((u.hostname, u.port), timeout=10)
    s = _Sock(fileno=s0.detach())   # 子类才能挂属性（cmd）
    s.settimeout(30)
    key = base64.b64encode(os.urandom(16)).decode()
    s.sendall(("GET %s HTTP/1.1\r\nHost: %s:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n"
               % (u.path, u.hostname, u.port, key)).encode())
    buf = b""
    while b"\r\n\r\n" not in buf:
        buf += s.recv(4096)

    def send(obj):
        data = json.dumps(obj).encode()
        hdr = bytearray([0x81])
        n = len(data)
        if n < 126:
            hdr.append(0x80 | n)
        elif n < 65536:
            hdr.append(0x80 | 126)
            hdr += struct.pack(">H", n)
        else:
            hdr.append(0x80 | 127)
            hdr += struct.pack(">Q", n)
        mask = os.urandom(4)
        hdr += mask
        s.sendall(bytes(hdr) + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))

    def recv():
        def rd(k):
            out = b""
            while len(out) < k:
                c = s.recv(k - len(out))
                if not c:
                    raise OSError("closed")
                out += c
            return out
        b0, b1 = rd(2)
        n = b1 & 0x7F
        if n == 126:
            n = struct.unpack(">H", rd(2))[0]
        elif n == 127:
            n = struct.unpack(">Q", rd(8))[0]
        return rd(n).decode("utf-8", "replace")
    return s, send, recv


class _Sock(socket.socket):
    pass


def _cdp_setup(port, url, throttle, mobile, throttle_late=False):
    """等 Edge 起来，按需开 CPU 节流 / 手机视口 + 触屏，再导航到游戏页（先设好再加载，游戏启动时就认成触屏设备）"""
    t0 = time.time()
    tgt = None
    while time.time() - t0 < 30 and tgt is None:
        try:
            import urllib.request
            lst = json.loads(urllib.request.urlopen("http://127.0.0.1:%d/json" % port, timeout=2).read())
            tgt = next((x for x in lst if x.get("type") == "page"), None)
        except Exception:
            time.sleep(0.5)
    if tgt is None:
        print("[网页] DevTools 连不上，按不节流跑")
        return None
    s, send, recv = _ws_connect(tgt["webSocketDebuggerUrl"])
    mid = [0]

    def cmd(method, params=None):
        mid[0] += 1
        send({"id": mid[0], "method": method, "params": params or {}})
        while True:
            m = json.loads(recv())
            if m.get("id") == mid[0]:
                return m
    if throttle and throttle > 1 and not throttle_late:
        cmd("Emulation.setCPUThrottlingRate", {"rate": throttle})
    if mobile:
        cmd("Emulation.setDeviceMetricsOverride", {"width": 844, "height": 390, "deviceScaleFactor": 3, "mobile": True,
                                                    "screenOrientation": {"type": "landscapePrimary", "angle": 90}})
        cmd("Emulation.setTouchEmulationEnabled", {"enabled": True, "maxTouchPoints": 5})
        cmd("Emulation.setUserAgentOverride", {"userAgent": "Mozilla/5.0 (Linux; Android 13; Pixel 6a) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36",
                                               "platform": "Linux armv8l"})
    cmd("Page.navigate", {"url": url})
    s.cmd = cmd
    return s   # 连接留着：断开后节流会失效


def run(ref, tag, game_args, timeout, throttle=0, mobile=False, lowgpu=False):
    d = export(ref)
    log_p = os.path.join(d, "out_%s.txt" % tag)
    open(log_p, "w").close()
    done = threading.Event()

    class H(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *a, **k):
            super().__init__(*a, directory=d, **k)

        def do_POST(self):
            body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode("utf-8", "replace")
            with open(log_p, "a", encoding="utf-8") as fh:
                fh.write(body + "\n")
            if "PERF " in body or "BALANCE " in body or "PF FTDONE" in body:
                done.set()
            self.send_response(204)
            self.end_headers()

        def log_message(self, *a):
            pass

    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", port), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    url = "http://127.0.0.1:%d/index.html?%s" % (port, urllib.parse.urlencode([("a", x) for x in game_args]))
    ud = os.path.join(BASE, "_edge_" + tag)
    shutil.rmtree(ud, ignore_errors=True)
    px, py = gr._TEST_POS if gr._SEC else (-3000, 0)
    emu = bool(throttle) or mobile
    dbg = 0
    if emu:
        with socket.socket() as s2:
            s2.bind(("127.0.0.1", 0))
            dbg = s2.getsockname()[1]
    p = subprocess.Popen([EDGE, "--user-data-dir=" + ud, "--app=" + ("about:blank" if emu else url), "--window-position=%d,%d" % (px, py),
                          "--window-size=%s" % ("844,390" if mobile else "1280,720"),
                          "--no-first-run", "--no-default-browser-check", "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
                          "--disable-backgrounding-occluded-windows", "--disable-features=CalculateNativeWinOcclusion", "--mute-audio"]
                         + (["--remote-debugging-port=%d" % dbg] if emu else []) + (["--force_low_power_gpu"] if lowgpu else []))
    late = bool(throttle) and "--rtfrom" in " ".join(game_args)   # 后期场景：快进段不节流，看到 PF RTFROM 再开
    cdp = _cdp_setup(dbg, url, throttle, mobile, late) if emu else None
    t0 = time.time()
    while not done.is_set() and time.time() - t0 < timeout:
        done.wait(2)
        if late and cdp is not None and "PF RTFROM" in open(log_p, encoding="utf-8").read():
            cdp.cmd("Emulation.setCPUThrottlingRate", {"rate": throttle})
            print("[网页] 快进结束，开 CPU 节流 %gx" % throttle)
            late = False
    time.sleep(2)
    if cdp is not None:
        cdp.close()
    subprocess.run(["taskkill", "/PID", str(p.pid), "/T", "/F"], capture_output=True)
    srv.shutdown()
    shutil.rmtree(ud, ignore_errors=True)
    lines = open(log_p, encoding="utf-8").read().splitlines()
    perf = [l for l in lines if l.startswith("PERF ")]
    print("[网页] %s：%d 行，PERF %d，用时 %.0f 秒%s" % (tag, len(lines), len(perf), time.time() - t0, "" if done.is_set() else "（超时）"))
    if perf:
        summarize(json.loads(perf[-1][5:]))
    return log_p


def summarize(pf):
    for k in sorted(pf):
        v = pf[k]
        if isinstance(v, dict) and "ft_mean" in v:
            print("  %-12s n=%5d 平均 %6.2f P50 %6.2f P95 %6.2f P99 %6.2f >16.7 %5.1f%% 敌人中位 %s 绘制调用 %s" % (
                k, v["n"], v["ft_mean"], v["ft_med"], v["ft_p95"], v["ft_p99"], v["over16_pct"], v["en_med"], v["dc_med"]))


def main():
    argv = sys.argv[1:]
    game_args = []
    if "--" in argv:
        i = argv.index("--")
        argv, game_args = argv[:i], argv[i + 1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["export", "run"])
    ap.add_argument("--ref", default="HEAD")
    ap.add_argument("--tag", default="run")
    ap.add_argument("--timeout", type=float, default=1800)
    ap.add_argument("--throttle", type=float, default=0, help="低配模拟：CPU 节流倍数（DevTools，4 / 6）")
    ap.add_argument("--mobile", action="store_true", help="低配模拟：手机横屏视口 844×390、3 倍像素、触屏、安卓 UA")
    ap.add_argument("--lowgpu", action="store_true", help="低配模拟：Edge 用核显（--force_low_power_gpu）")
    a = ap.parse_args(argv)
    if a.cmd == "export":
        print(export(a.ref))
    else:
        run(a.ref, a.tag, game_args, a.timeout, a.throttle, a.mobile, a.lowgpu)


if __name__ == "__main__":
    main()
