# -*- coding: utf-8 -*-
"""B站 Toy 云存档本地 mock 服务（docs/89 §测试）：同一份网页包开在两个端口 = 两台「设备」（网站源不同，各自的 IndexedDB 本地存档），
共用进程内存里的一份「云端」。index.html 在返回时往 <head> 最前面注入 tools/web/toy_mock.js（假 window.toy），包本身不改。

  python tools/web_cloud_mock.py --dir build/web --ports 8811,8812

控制 / 查看（任一端口）：
  POST /__mock/ctl   {"login": false}            未登录：读写都 reject（type=not_login）
                     {"reject": 2}               接下来 2 次请求 reject（一般错误）
                     {"ratelimit": 3}            接下来 3 次请求 reject 307044（限流）
                     {"reset": true}             清空云端、日志、模式
  GET  /__mock/state 云端内容、模式、请求日志（时间戳、操作、结果）
只绑 127.0.0.1。"""
import argparse, functools, http.server, json, os, re, threading, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOCK_JS = os.path.join(ROOT, "tools", "web", "toy_mock.js")
LOCK = threading.Lock()
STATE = {"store": {}, "login": True, "reject": 0, "ratelimit": 0, "log": []}
KEY_RE = re.compile(r"^[A-Za-z0-9_-]+$")


def _err(t, code, msg):
    return {"ok": False, "err": {"type": t, "code": code, "message": msg}}


def handle(op, body, port):
    with LOCK:
        if op == "ctl":
            if body.get("reset"):
                STATE.update({"store": {}, "login": True, "reject": 0, "ratelimit": 0, "log": []})
            for k in ("login", "reject", "ratelimit"):
                if k in body:
                    STATE[k] = body[k]
            return {"ok": True, "data": None}
        res = None
        if not STATE["login"]:
            res = _err("not_login", -101, "用户未登录")
        elif STATE["ratelimit"] > 0:
            STATE["ratelimit"] -= 1
            res = _err("http_error", 307044, "请求过于频繁，请稍后再试")
        elif STATE["reject"] > 0:
            STATE["reject"] -= 1
            res = _err("http_error", 500, "mock reject")
        elif op == "get":
            keys = body.get("keys")
            st = STATE["store"]
            res = {"ok": True, "data": {k: v for k, v in st.items() if keys is None or k in keys}}
        elif op == "set":
            items = body.get("items") or {}
            bad = [k for k, v in items.items() if not KEY_RE.match(k) or k.startswith("__") or len(k.encode()) > 128
                   or not isinstance(v, str) or len(v.encode()) > 1024]
            if bad or len(set(STATE["store"]) | set(items)) > 128:
                res = _err("invalid_param", 400, "非法参数：%s" % bad[:3])
            else:
                STATE["store"].update(items)
                res = {"ok": True, "data": None}
        elif op == "remove":
            for k in body.get("keys") or []:
                STATE["store"].pop(k, None)
            res = {"ok": True, "data": None}
        else:
            res = _err("invalid_param", 400, "未知操作")
        STATE["log"].append({"t": round(time.time(), 2), "port": port, "op": op, "ok": res["ok"],
                             "code": None if res["ok"] else res["err"]["code"],
                             "keys": len((body.get("items") or {})) if op == "set" else None})
        return res


class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _json(self, obj, code=200):
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        if not self.path.startswith("/__mock/"):
            return self.send_error(404)
        n = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(n) or b"{}")
        self._json(handle(self.path[len("/__mock/"):], body, self.server.server_port))

    def do_GET(self):
        p = self.path.split("?")[0]
        if p == "/__mock/state":
            with LOCK:
                return self._json(STATE)
        if p == "/__mock/toy_mock.js":
            data = open(MOCK_JS, "rb").read()
            self.send_response(200)
            self.send_header("Content-Type", "text/javascript; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            return self.wfile.write(data)
        if p in ("/", "/index.html"):
            html = open(os.path.join(self.directory, "index.html"), encoding="utf-8").read()
            html = html.replace("<head>", '<head>\n<script src="/__mock/toy_mock.js"></script>', 1)
            data = html.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            return self.wfile.write(data)
        return super().do_GET()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--ports", default="8811,8812")
    a = ap.parse_args()
    d = os.path.abspath(a.dir)
    srvs = []
    for port in [int(x) for x in a.ports.split(",")]:
        srv = http.server.ThreadingHTTPServer(("127.0.0.1", port), functools.partial(Handler, directory=d))
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        srvs.append(srv)
        print("mock 设备：http://127.0.0.1:%d/ （%s）" % (port, d), flush=True)
    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
