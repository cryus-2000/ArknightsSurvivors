"""手机发烫的代理指标（docs/50 §33）：网页手机仿真里分场景量「每秒 CPU 毫秒」——渲染进程（游戏脚本 / 引擎）+ GPU 进程（WebGL 命令执行）。

  python tools/probes/power_web.py --ref HEAD --tag base [-- <额外游戏参数…>]

和 tools/perf_web.py 共用测量副本（build/_perfweb/<提交>/），但页面的 requestAnimationFrame 按 60 Hz 节拍（模拟显示器刷新 + 游戏自己的帧率上限，
同玩家；屏幕外窗口不发真 rAF），不用测帧时用的 MessageChannel 空转。游戏带 --powerseq（run/autotest.gd）：对局 → 暂停 → 选卡 → 对局，各段把段名写进 window.__phase；
这里每秒用 CDP SystemInfo.getProcessInfo 取各进程累计 CPU 时间，按段名把增量记账。iPhone 横屏 844×390、3 倍像素、触屏（同 perf_web --mobile）。
标题页段：--title 不进局，停在标题页 20 秒。
"""
import argparse, http.server, json, os, shutil, socket, subprocess, sys, threading, time, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)
import godot_runner as gr
import perf_web as pw

HIDE_JS = """(async()=>{const L=window.__syAudioCtx||[];const w=()=>new Promise(r=>setTimeout(r,500));const b=L.map(c=>c.state);
const set=v=>{Object.defineProperty(document,'hidden',{configurable:true,get:()=>v});document.dispatchEvent(new Event('visibilitychange'));};
set(true);await w();const h=L.map(c=>c.state);set(false);await w();return JSON.stringify({n:L.length,before:b,hidden:h,after:L.map(c=>c.state)});})()"""
# 屏幕外窗口浏览器不发真 rAF：换成按 60 Hz 节拍的定时器（模拟显示器刷新；后台定时器节流已关），不是测帧时用的空转
RAF_60 = "window.requestAnimationFrame=function(cb){q.push(cb);if(q.length===1){var n=performance.now(),p=1000/60;setTimeout(function(){ch.port2.postMessage(0);},Math.max(0,p-(n%p)));}return q.length;};window.cancelAnimationFrame=function(){};"
RAF_OVERRIDE = "window.requestAnimationFrame=function(cb){q.push(cb);if(q.length===1)ch.port2.postMessage(0);return q.length;};window.cancelAnimationFrame=function(){};"


def main():
    argv = sys.argv[1:]
    extra = []
    if "--" in argv:
        i = argv.index("--")
        argv, extra = argv[:i], argv[i + 1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default="HEAD")
    ap.add_argument("--tag", default="power")
    ap.add_argument("--title", action="store_true")
    ap.add_argument("--secs", type=float, default=400, help="最长等多久（含启动；段走完写 end 就提前结束）")
    ap.add_argument("--dpr", type=float, default=3)
    ap.add_argument("--hidecheck", action="store_true", help="对局开始后模拟页面隐藏 / 再显示，读 AudioContext 状态（tools/web/power.js 自测）")
    a = ap.parse_args(argv)
    d = pw.export(a.ref)
    html = open(os.path.join(d, "index.html"), encoding="utf-8").read()
    assert RAF_OVERRIDE in html, "测量副本的 rAF 替身变了"
    open(os.path.join(d, "index_power.html"), "w", encoding="utf-8").write(html.replace(RAF_OVERRIDE, RAF_60))
    log_p = os.path.join(d, "out_%s.txt" % a.tag)
    open(log_p, "w").close()

    class H(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *x, **k):
            super().__init__(*x, directory=d, **k)

        def do_POST(self):
            body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode("utf-8", "replace")
            with open(log_p, "a", encoding="utf-8") as fh:
                fh.write(body + "\n")
            self.send_response(204)
            self.end_headers()

        def log_message(self, *x):
            pass

    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", port), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    run_args = ["--balance", "--realtime", "--nodeath", "--bot=expert", "--seed=13", "--op=skalter", "--squad=texas,exusiai", "--mobilecap", "--memguard=100000"]
    gargs = ["--", "--powerseq"] + ([] if a.title else run_args) + extra
    url = "http://127.0.0.1:%d/index_power.html?%s" % (port, urllib.parse.urlencode([("a", x) for x in gargs]))
    ud = os.path.join(pw.BASE, "_edge_" + a.tag)
    shutil.rmtree(ud, ignore_errors=True)
    px, py = gr._TEST_POS if gr._SEC else (-3000, 0)
    with socket.socket() as s2:
        s2.bind(("127.0.0.1", 0))
        dbg = s2.getsockname()[1]
    p = subprocess.Popen([pw.EDGE, "--user-data-dir=" + ud, "--app=about:blank", "--window-position=%d,%d" % (px, py), "--window-size=844,390",
                          "--no-first-run", "--no-default-browser-check", "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
                          "--disable-backgrounding-occluded-windows", "--disable-features=CalculateNativeWinOcclusion", "--mute-audio",
                          "--remote-debugging-port=%d" % dbg])
    page = pw._cdp_setup(dbg, url, 0, True, False, a.dpr)
    ver = json.loads(urllib.request.urlopen("http://127.0.0.1:%d/json/version" % dbg, timeout=5).read())
    bs, bsend, brecv = pw._ws_connect(ver["webSocketDebuggerUrl"])
    mid = [0]

    def bcmd(method, params=None):
        mid[0] += 1
        bsend({"id": mid[0], "method": method, "params": params or {}})
        while True:
            m = json.loads(brecv())
            if m.get("id") == mid[0]:
                return m

    def proc_cpu():
        r = bcmd("SystemInfo.getProcessInfo").get("result", {}).get("processInfo", [])
        out = {}
        for x in r:
            out[x["type"]] = out.get(x["type"], 0.0) + float(x["cpuTime"])
        return out

    def phase():
        r = page.cmd("Runtime.evaluate", {"expression": "window.__phase||''", "returnByValue": True})
        return r.get("result", {}).get("result", {}).get("value", "")

    acc = {}
    t0 = time.time()
    last = proc_cpu()
    lt = time.time()
    while time.time() - t0 < a.secs:
        time.sleep(1.0)
        ph = phase()
        cur = proc_cpu()
        now = time.time()
        if ph and ph != "end":
            a_ = acc.setdefault(ph, {"wall": 0.0})
            a_["wall"] += now - lt
            for k in cur:
                a_[k] = a_.get(k, 0.0) + cur[k] - last.get(k, 0.0)
        last, lt = cur, now
        if ph == "end":
            break
        if a.hidecheck and ph:
            r = page.cmd("Runtime.evaluate", {"expression": HIDE_JS, "awaitPromise": True, "returnByValue": True})
            print("HIDECHECK", r.get("result", {}).get("result", {}).get("value"))
            a.hidecheck = False
    page.close()
    bs.close()
    subprocess.run(["taskkill", "/PID", str(p.pid), "/T", "/F"], capture_output=True)
    srv.shutdown()
    shutil.rmtree(ud, ignore_errors=True)
    res = {}
    print("段\t秒\t渲染进程 ms/s\tGPU 进程 ms/s\t合计 ms/s")
    for ph, v in acc.items():
        w = max(0.01, v["wall"])
        rr = v.get("renderer", 0.0) * 1000 / w
        gg = v.get("gpu", 0.0) * 1000 / w
        res[ph] = {"wall": round(w, 1), "renderer": round(rr, 1), "gpu": round(gg, 1), "sum": round(rr + gg, 1)}
        print("%s\t%.0f\t%.0f\t%.0f\t%.0f" % (ph, w, rr, gg, rr + gg))
    for l in open(log_p, encoding="utf-8").read().splitlines():
        if l.startswith("PF POWER") or l.startswith("SCRIPT ERROR"):
            print(l)
    print("POWERJSON " + json.dumps(res, ensure_ascii=False))


if __name__ == "__main__":
    main()
