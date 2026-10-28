# -*- coding: utf-8 -*-
"""tools/web/lzma_dec.js 回归（docs/187 §5）：Python lzma 按 export_web.py 同一组参数压，node 解，逐字节比对。
覆盖：随机字节（全字面量）、长重复（长匹配 / rep）、真 wasm 片段（有 build/toy/web 或 build/web 时取一段），以及默认参数 lc=3 pb=2。
用法：python tools/test_web_lzma.py
"""
import lzma, os, random, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from export_web import LZMA_FILTERS

NODE = r"""
const fs = require('fs'), dec = require(process.argv[2]);
let bad = 0;
for (const n of process.argv.slice(3)) {
  const src = new Uint8Array(fs.readFileSync(n + '.lzma')), raw = fs.readFileSync(n + '.raw');
  const dst = new Uint8Array(raw.length);
  try { dec(src, dst); } catch (e) { console.log('FAIL', n, e.message); bad++; continue; }
  if (Buffer.compare(Buffer.from(dst), raw) !== 0) { console.log('MISMATCH', n); bad++; }
}
process.exit(bad ? 1 : 0);
"""


def main():
    rnd = random.Random(7)
    cases = {
        "random": bytes(rnd.getrandbits(8) for _ in range(50000)),
        "repeat": b"abcabcab" * 20000 + bytes(range(256)) * 300,
        "mixed": b"".join(bytes(rnd.getrandbits(8) for _ in range(rnd.randint(1, 40))) * rnd.randint(1, 30) for _ in range(3000)),
    }
    for d in ("build/toy/web", "build/web"):
        p = os.path.join(ROOT, d, "index.html")
        if os.path.exists(p):
            cases["html"] = open(p, "rb").read()
            break
    tmp = tempfile.mkdtemp(prefix="lzma_test_")
    names = []
    for k, v in cases.items():
        for tag, f in (("exp", LZMA_FILTERS), ("def", None)):
            n = os.path.join(tmp, "%s_%s" % (k, tag))
            c = lzma.compress(v, format=lzma.FORMAT_ALONE, filters=f) if f else lzma.compress(v, format=lzma.FORMAT_ALONE)
            open(n + ".lzma", "wb").write(c)
            open(n + ".raw", "wb").write(v)
            names.append(n)
    js = os.path.join(tmp, "t.cjs")
    open(js, "w", encoding="utf-8").write(NODE)
    r = subprocess.run(["node", js, os.path.join(ROOT, "tools", "web", "lzma_dec.js")] + names, capture_output=True, text=True)
    print(r.stdout.strip() or "lzma_dec.js：%d 例全部逐字节一致" % len(names))
    sys.exit(r.returncode)


if __name__ == "__main__":
    main()
