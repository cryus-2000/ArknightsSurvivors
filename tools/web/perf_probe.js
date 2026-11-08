// 性能自检浮层（game/scripts/core/perf_hud.gd，11-07）要的 WASM 内存：引擎建实例时记下它的 WebAssembly.Memory 到 window.__syWasm，
// 浮层每秒读 buffer.byteLength（iOS Safari 没有 performance.memory，WASM 堆是网页版内存的大头）。只包一次实例化，平时零开销
(function () {
  var W = window.WebAssembly;
  if (!W) return;
  function keep(imp, res) {
    try {
      var m = (imp && imp.env && imp.env.memory) || (imp && imp.a && imp.a.memory);
      var inst = res && (res.instance || res);
      if (!m && inst && inst.exports) {
        for (var k in inst.exports) { if (inst.exports[k] instanceof W.Memory) { m = inst.exports[k]; break; } }
      }
      if (!m && imp) {
        for (var ns in imp) { for (var k2 in imp[ns]) { if (imp[ns][k2] instanceof W.Memory) { m = imp[ns][k2]; break; } } if (m) break; }
      }
      if (m) window.__syWasm = m;
    } catch (e) {}
    return res;
  }
  var OM = W.Memory;   // 引擎在 JS 里建内存（emscripten 导入式）时直接记下
  W.Memory = function (d) { var m = new OM(d); window.__syWasm = m; return m; };
  W.Memory.prototype = OM.prototype;
  var inst = W.instantiate, str = W.instantiateStreaming;
  W.instantiate = function (src, imp) { return inst.apply(W, arguments).then(function (r) { return keep(imp, r); }); };
  if (str) W.instantiateStreaming = function (src, imp) { return str.apply(W, arguments).then(function (r) { return keep(imp, r); }); };
  // 11-08 docs/319 §10：WASM 堆里「摸过」的 64 KB 页数（有非零字节；dlmalloc 释放后不还给系统，摸过的页就一直算进进程内存）。
  // 只在 --memlog / 调试时调，扫一遍 400 MB 约 0.3 秒
  window.__syWasmTouched = function () {
    var m = window.__syWasm;
    if (!m) return -1;
    var u = new Uint32Array(m.buffer), P = 16384, n = 0;
    for (var p = 0; p < u.length; p += P) {
      var e = Math.min(u.length, p + P);
      for (var i = p; i < e; i++) { if (u[i] !== 0) { n++; break; } }
    }
    return n / 16;   // MB
  };
})();
