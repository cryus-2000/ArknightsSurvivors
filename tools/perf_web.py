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


def run(ref, tag, game_args, timeout):
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
    p = subprocess.Popen([EDGE, "--user-data-dir=" + ud, "--app=" + url, "--window-position=%d,%d" % (px, py), "--window-size=1280,720",
                          "--no-first-run", "--no-default-browser-check", "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
                          "--disable-backgrounding-occluded-windows", "--disable-features=CalculateNativeWinOcclusion", "--mute-audio"])
    t0 = time.time()
    while not done.is_set() and time.time() - t0 < timeout:
        done.wait(5)
    time.sleep(2)
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
    a = ap.parse_args(argv)
    if a.cmd == "export":
        print(export(a.ref))
    else:
        run(a.ref, a.tag, game_args, a.timeout)


if __name__ == "__main__":
    main()
