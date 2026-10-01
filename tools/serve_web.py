# -*- coding: utf-8 -*-
"""本地静态服务（验证网页包用）：python tools/serve_web.py --dir <网页包目录> [--port 8794] [--coi]
--coi 加 COOP / COEP 头（Cross-Origin-Opener-Policy: same-origin、Cross-Origin-Embedder-Policy: require-corp），模拟 itch 勾了
「SharedArrayBuffer support」的情况；不加就是普通托管。只绑 127.0.0.1。"""
import argparse, functools, http.server


class Handler(http.server.SimpleHTTPRequestHandler):
    coi = False

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
