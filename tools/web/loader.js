// 网页版加载器（tools/export_web.py 把它内联进 index.html 的 <!--SHUIYUE_LOADER--> 处，见 docs/22）
// 1. 分片：index.pck / index.wasm 在导出后被切成若干 gzip 分片（单文件 ≤20 MiB，避开托管平台 25 MB 上限）。
//    拦截引擎对这两个文件的 fetch，并行下载全部分片 → 逐片解压 → 按顺序拼回原文件交给引擎。游戏代码不动。
// 2. 加载画面：进度 = 已下载字节 / 分片总字节（真实进度），博士沿进度条跑；下载完显示「正在启动」，
//    引擎移除自带的 #status 后撤掉；引擎报错（#status-notice 显示）时也撤掉，让报错露出来。
(function () {
  var M = /*SHUIYUE_MANIFEST*/null;
  if (!M) return;
  var total = 0, got = 0, done = false;
  Object.keys(M).forEach(function (k) { M[k].parts.forEach(function (p) { total += p[1]; }); });

  var el = {};
  function upd() {
    if (!el.fill) return;
    var f = done ? 1 : Math.min(got / total, 0.999);
    var pct = (f * 100).toFixed(1) + '%';
    el.fill.style.width = pct;
    el.doc.style.left = 'clamp(24px, ' + pct + ', calc(100% - 24px))';
    el.pct.textContent = done ? '正在启动…' : Math.floor(f * 100) + '%  ·  ' + (got / 1048576).toFixed(1) + ' / ' + (total / 1048576).toFixed(1) + ' MB';
  }

  function build() {
    var d = document.createElement('div');
    d.id = 'sy-load';
    d.innerHTML = '<div class="sy-box"><div class="sy-head"><div class="sy-sub">LOADING</div><div class="sy-title">加载中，请耐心等待</div></div>' +
      '<div class="sy-track"><div class="sy-fill"></div><div class="sy-doc"></div></div><div class="sy-pct"></div></div>' +
      '<div class="sy-foot">明日方舟同人作品 · 非商业</div>';
    document.body.appendChild(d);
    el = { root: d, fill: d.querySelector('.sy-fill'), doc: d.querySelector('.sy-doc'), pct: d.querySelector('.sy-pct') };
    upd();
    var t = setInterval(function () {
      var st = document.getElementById('status'), nt = document.getElementById('status-notice');
      if (!st || (nt && nt.style.display === 'block')) {
        clearInterval(t);
        d.classList.add('sy-out');
        setTimeout(function () { d.remove(); }, 400);
      }
    }, 150);
  }
  if (document.body) build(); else document.addEventListener('DOMContentLoaded', build);

  function cat(list, n) {
    var out = new Uint8Array(n), o = 0;
    list.forEach(function (b) { out.set(b, o); o += b.length; });
    return out;
  }

  async function once(url, bytes) {
    var r = await of(url, { cache: 'no-cache' });
    if (!r.ok) throw new Error(url + ' ' + r.status);
    var rd = r.body.getReader(), chunks = [], n = 0, counted = 0;
    try {
      for (;;) {
        var x = await rd.read();
        if (x.done) break;
        chunks.push(x.value); n += x.value.length;
        // 服务器若自作主张解压（Content-Encoding: gzip），读到的字节会比分片大；按分片大小封顶，进度不超 100%
        var add = Math.min(x.value.length, bytes - counted);
        if (add > 0) { counted += add; got += add; upd(); }
      }
    } catch (e) { got -= counted; upd(); throw e; }
    got += bytes - counted; upd();
    var buf = cat(chunks, n);
    if (buf[0] === 0x1f && buf[1] === 0x8b) {
      var st = new Blob([buf]).stream().pipeThrough(new DecompressionStream('gzip'));
      buf = new Uint8Array(await new Response(st).arrayBuffer());
    }
    return buf;
  }

  async function part(url, bytes) {
    for (var i = 0; ; i++) {
      try { return await once(url, bytes); }
      catch (e) { if (i >= 2) throw e; await new Promise(function (r) { setTimeout(r, 800 * (i + 1)); }); }
    }
  }

  var pending = Object.keys(M).length;
  var of = window.fetch.bind(window);
  window.fetch = function (input, init) {
    var url = (typeof input === 'string') ? input : ((input && input.url) || '');
    var path = url.split('?')[0].split('#')[0];
    var name = path.split('/').pop();
    var e = M[name];
    if (!e) return of(input, init);
    var base = path.slice(0, path.length - name.length);
    return Promise.all(e.parts.map(function (p) { return part(base + p[0], p[1]); })).then(function (bufs) {
      var out = cat(bufs, bufs.reduce(function (s, b) { return s + b.length; }, 0));
      if (out.length !== e.size) throw new Error(name + ' 拼接后大小不符：' + out.length + ' ≠ ' + e.size);
      if (--pending === 0) { done = true; upd(); }
      return new Response(out, { status: 200, headers: { 'Content-Type': e.type, 'Content-Length': String(e.size) } });
    });
  };
})();
