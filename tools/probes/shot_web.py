"""网页手机仿真同一时刻截图（docs/50 §34）：同一局定格后按脚本换档 / 开选卡，逐张截图，对比镜头范围与清晰度。

  python tools/probes/shot_web.py --ref HEAD --tag x [--steps "shot:mid,q:low,wait:2,shot:low,..."] [-- <额外游戏参数…>]

游戏带 --webshot=<秒>（run/autotest.gd）：到点定格（time_scale 0），之后读 window.__cmd（q:low / q:mid / q:high / levelup / freeze）。
步骤：shot:<名> 截图存 build/perf_stack/webshot_<tag>/<名>.png；wait:<秒>；其余原样写进 window.__cmd。iPhone 横屏 844×390、3 倍像素、触屏。
"""
import argparse, base64, http.server, json, os, shutil, socket, subprocess, sys, threading, time, urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)
import godot_runner as gr
import perf_web as pw

DEFAULT_STEPS = "wait:2,shot:mid,q:low,wait:2,shot:low,q:high,wait:2,shot:high,q:mid,wait:2,shot:mid2,levelup,wait:3,shot:cards_mid"


def main():
    argv = sys.argv[1:]
    extra = []
    if "--" in argv:
        i = argv.index("--")
        argv, extra = argv[:i], argv[i + 1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default="HEAD")
    ap.add_argument("--tag", default="shot")
    ap.add_argument("--at", type=float, default=150)
    ap.add_argument("--steps", default=DEFAULT_STEPS)
    ap.add_argument("--dpr", type=float, default=3)
    ap.add_argument("--timeout", type=float, default=900)
    ap.add_argument("--vw", type=int, default=844, help="手机视口宽（CSS 像素）")
    ap.add_argument("--vh", type=int, default=390)
    ap.add_argument("--desktop", action="store_true", help="桌面网页：不开手机仿真，窗口 1280×720")
    a = ap.parse_args(argv)
    d = pw.export(a.ref)
    out = os.path.join(gr.common_root(), "build", "perf_stack", "webshot_" + a.tag)
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    log_p = os.path.join(d, "out_shot_%s.txt" % a.tag)
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
    gargs = ["--", "--webshot=%g" % a.at, "--balance", "--nodeath", "--bot=expert", "--seed=13", "--op=skalter", "--squad=texas,exusiai",
             "--mobilecap", "--memguard=100000"] + extra   # 固定步长快进（同 seed 同一时刻，前后两版截图可逐像素对照）
    url = "http://127.0.0.1:%d/index.html?%s" % (port, urllib.parse.urlencode([("a", x) for x in gargs]))
    ud = os.path.join(pw.BASE, "_edge_shot_" + a.tag)
    shutil.rmtree(ud, ignore_errors=True)
    px, py = gr._TEST_POS if gr._SEC else (-3000, 0)
    with socket.socket() as s2:
        s2.bind(("127.0.0.1", 0))
        dbg = s2.getsockname()[1]
    p = subprocess.Popen([pw.EDGE, "--user-data-dir=" + ud, "--app=about:blank", "--window-position=%d,%d" % (px, py), "--window-size=%s" % ("1280,720" if a.desktop else "%d,%d" % (a.vw, a.vh)),
                          "--no-first-run", "--no-default-browser-check", "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
                          "--disable-backgrounding-occluded-windows", "--disable-features=CalculateNativeWinOcclusion", "--mute-audio",
                          "--remote-debugging-port=%d" % dbg])
    page = pw._cdp_setup(dbg, url, 0, not a.desktop, False, a.dpr, a.vw, a.vh)

    def ev(js):
        r = page.cmd("Runtime.evaluate", {"expression": js, "returnByValue": True})
        return r.get("result", {}).get("result", {}).get("value")

    t0 = time.time()
    ok = False
    while time.time() - t0 < a.timeout:
        time.sleep(1.0)
        if ev("window.__shot||0") == 1:
            ok = True
            break
    if ok:
        for st in a.steps.split(","):
            st = st.strip()
            if st.startswith("shot:"):
                r = page.cmd("Page.captureScreenshot", {"format": "png"})
                png = base64.b64decode(r["result"]["data"])
                open(os.path.join(out, st[5:] + ".png"), "wb").write(png)
                print("shot", st[5:], len(png))
            elif st.startswith("wait:"):
                time.sleep(float(st[5:]))
            else:
                ev("window.__cmd=%s" % json.dumps(st))
                time.sleep(0.3)
        time.sleep(1.5)
    else:
        print("没等到定格（超时）")
    page.close()
    subprocess.run(["taskkill", "/PID", str(p.pid), "/T", "/F"], capture_output=True)
    srv.shutdown()
    shutil.rmtree(ud, ignore_errors=True)
    for l in open(log_p, encoding="utf-8").read().splitlines():
        if l.startswith("PF WEBSHOT") or l.startswith("SCRIPT ERROR") or l.startswith("PF VIEW"):
            print(l)
    print("目录", out)


if __name__ == "__main__":
    main()
