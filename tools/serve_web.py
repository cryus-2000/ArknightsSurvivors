# -*- coding: utf-8 -*-
"""本地静态服务（验证网页包用）：python tools/serve_web.py --dir <网页包目录> [--port 8794] [--coi]
--coi 加 COOP / COEP 头（Cross-Origin-Opener-Policy: same-origin、Cross-Origin-Embedder-Policy: require-corp），模拟 itch 勾了
「SharedArrayBuffer support」的情况；不加就是普通托管。只绑 127.0.0.1。
/__itch.html：模拟 itch 的嵌入页（游戏在 iframe 里，allow="fullscreen"；右下角「全屏」按钮像 itch 那样把外层容器全屏），
测网页全屏与 Esc（docs/299）用。"""
import argparse, functools, http.server


ITCH_HTML = """<!doctype html><html><head><meta charset="utf-8"><title>itch embed mock</title>
<style>body{margin:0;background:#222;color:#ccc;font:14px sans-serif}#wrap{position:relative;width:min(1280px,96vw);aspect-ratio:16/9;margin:8px auto;background:#000}
#wrap iframe{width:100%;height:100%;border:0;display:block}#fs{position:absolute;right:0;top:100%;margin-top:4px;z-index:2}
#wrap:fullscreen{width:100vw;height:100vh;margin:0}</style></head><body>
<div id="wrap"><iframe id="game" src="index.html" allow="fullscreen; autoplay; gamepad" allowfullscreen></iframe>
<button id="fs" onclick="document.getElementById('wrap').requestFullscreen()">全屏（外层，像 itch）</button></div>
<div id="log" style="text-align:center"></div>
<script>document.addEventListener('fullscreenchange',function(){document.getElementById('log').textContent='parent fullscreen: '+!!document.fullscreenElement+' @'+Date.now()});</script>
</body></html>"""


class Handler(http.server.SimpleHTTPRequestHandler):
    coi = False

    def do_GET(self):
        if self.path.split("?")[0] == "/__itch.html":
            b = ITCH_HTML.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(b)))
            self.end_headers()
            self.wfile.write(b)
            return
        super().do_GET()

    def end_headers(self):
        if self.coi:
            self.send_header("Cross-Origin-Opener-Policy", "same-origin")
            self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--port", type=int, default=8794)
    ap.add_argument("--coi", action="store_true")
    a = ap.parse_args()
    Handler.coi = a.coi
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", a.port), functools.partial(Handler, directory=a.dir))
    print("serving %s on http://127.0.0.1:%d %s" % (a.dir, a.port, "(COOP/COEP)" if a.coi else ""), flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
