// 网页版加载器（tools/export_web.py 把它内联进 index.html 的 <!--SHUIYUE_LOADER--> 处，见 docs/22）
// 1. 分片：index.pck / index.wasm 在导出后被切成若干 gzip 分片（单文件 ≤20 MiB，避开托管平台 25 MB 上限）。
//    拦截引擎对这两个文件的 fetch，并行下载全部分片 → 边下边解压、直接写进一块预先按原文件大小分配好的 Uint8Array 的对应位置
//    （清单里每片带原始长度 p[2]）→ 整块交给引擎。游戏代码不动。
//    2026-10-11 之前是「每片先收齐 gz 字节 → 解开成一块 → 全部分片再拼成整块」，解开的分片和整块同时在内存里，
//    JS 这一侧峰值约 2–3 倍原始大小（docs/33 移动端）。现在 gz 字节与解开的小块都只是流里的临时块，用完即回收，
//    JS 峰值 ≈ 原文件大小（pck + wasm 共约 65 MiB），给 2–3 GB 内存的老手机留余量。
//    浏览器若自作主张解压（Content-Encoding: gzip 被服务器改写），读到的就是原始字节，照样按位置写入。
//    没有 DecompressionStream 的老浏览器（Safari 16.3 以前）：收齐 gz 字节再 inflate（纯 JS，下面的 inflate）。
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
    el.doc.style.left = 'clamp(32px, ' + pct + ', calc(100% - 32px))';
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

  var hasDS = typeof DecompressionStream === 'function';

  // 把一片写进 out 的 [off, off + raw) 区间。gz 片：第一块带 1f 8b 时经 DecompressionStream 解开；否则（服务器已解压）原样写入。
  // 返回写入的字节数；写越界 / 不足都按出错处理（part 会重试）。
  async function once(url, bytes, out, off, raw) {
    var r = await of(url, { cache: 'no-cache' });
    if (!r.ok) throw new Error(url + ' ' + r.status);
    var rd = r.body.getReader(), counted = 0, wrote = 0, gz = null, chunks = null, ds = null, w = null, pump = null, pumpErr = null;
    function sink(v) {   // 解开后的字节 → out
      if (wrote + v.length > raw) throw new Error(url + ' 解开后超过原始长度');
      out.set(v, off + wrote); wrote += v.length;
    }
    try {
      for (;;) {
        var x = await rd.read();
        if (x.done) break;
        var v = x.value;
        var add = Math.min(v.length, bytes - counted);
        if (add > 0) { counted += add; got += add; upd(); }
        if (gz === null) gz = (v.length > 1 && v[0] === 0x1f && v[1] === 0x8b);
        if (!gz) { sink(v); continue; }
        if (hasDS) {
          if (!ds) {
            ds = new DecompressionStream('gzip'); w = ds.writable.getWriter();
            pump = (async function () {   // 与下载并行：解开的块一出来就写进 out，不在内存里攒
              var rr = ds.readable.getReader();
              for (;;) { var y = await rr.read(); if (y.done) break; sink(y.value); }
            })().catch(function (e2) { pumpErr = e2; });
          }
          await w.write(v);
        } else {
          if (!chunks) chunks = [];
          chunks.push(v);
        }
      }
      if (ds) { await w.close(); await pump; if (pumpErr) throw pumpErr; }
      else if (chunks) { sink(inflate(cat(chunks))); chunks = null; }
    } catch (e) {
      got -= counted; upd();
      if (w) { try { w.abort(); } catch (e2) {} }
      throw e;
    }
    got += bytes - counted; upd();
    if (wrote !== raw) throw new Error(url + ' 解开后大小不符：' + wrote + ' ≠ ' + raw);
    return wrote;
  }

  function cat(list) {
    var n = 0; list.forEach(function (b) { n += b.length; });
    var o = new Uint8Array(n), p = 0;
    list.forEach(function (b) { o.set(b, p); p += b.length; });
    return o;
  }

  async function part(url, bytes, out, off, raw) {
    for (var i = 0; ; i++) {
      try { return await once(url, bytes, out, off, raw); }
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
    var out = new Uint8Array(e.size), off = 0, jobs = [];
    e.parts.forEach(function (p) {
      var raw = p.length > 2 ? p[2] : e.size - off;   // 旧清单没有原始长度：只可能是单片
      jobs.push(part(base + p[0], p[1], out, off, raw));
      off += raw;
    });
    if (off !== e.size) return Promise.reject(new Error(name + ' 清单分片长度之和不符：' + off + ' ≠ ' + e.size));
    return Promise.all(jobs).then(function () {
      if (--pending === 0) { done = true; upd(); }
      return new Response(out, { status: 200, headers: { 'Content-Type': e.type, 'Content-Length': String(e.size) } });
    });
  };

  // ---------------------------------------------------------------- 后备：纯 JS gzip 解压（没有 DecompressionStream 的老浏览器）
  // 标准 inflate（RFC 1951），只处理 gzip 单成员；输出按 4 MiB 增长。正常浏览器走不到这里。
  function inflate(src) {
    var pos = 0;
    if (src[0] !== 0x1f || src[1] !== 0x8b || src[2] !== 8) throw new Error('不是 gzip');
    var flg = src[3]; pos = 10;
    if (flg & 4) { var xl = src[pos] | (src[pos + 1] << 8); pos += 2 + xl; }
    if (flg & 8) { while (src[pos++] !== 0); }
    if (flg & 16) { while (src[pos++] !== 0); }
    if (flg & 2) pos += 2;
    var out = new Uint8Array(4 << 20), op = 0;
    function grow(n) { if (op + n > out.length) { var o2 = new Uint8Array(Math.max(out.length * 2, op + n)); o2.set(out); out = o2; } }
    var bitbuf = 0, bitcnt = 0;
    function bits(n) {
      while (bitcnt < n) { bitbuf |= src[pos++] << bitcnt; bitcnt += 8; }
      var v = bitbuf & ((1 << n) - 1); bitbuf >>>= n; bitcnt -= n; return v;
    }
    function huff(lengths) {   // 码长表 → {count, symbol}（zlib puff 做法）
      var n = lengths.length, count = new Uint16Array(16), symbol = new Uint16Array(n), offs = new Uint16Array(16), i;
      for (i = 0; i < n; i++) count[lengths[i]]++;
      count[0] = 0;
      for (i = 1; i < 16; i++) offs[i] = offs[i - 1] + count[i - 1];
      for (i = 0; i < n; i++) if (lengths[i]) symbol[offs[lengths[i]]++] = i;
      return { count: count, symbol: symbol };
    }
    function decode(h) {
      var code = 0, first = 0, index = 0;
      for (var len = 1; len < 16; len++) {
        code |= bits(1);
        var c = h.count[len];
        if (code - c < first) return h.symbol[index + (code - first)];
        index += c; first += c; first <<= 1; code <<= 1;
      }
      throw new Error('inflate: 坏码');
    }
    var LB = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];
    var LE = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
    var DB = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577];
    var DE = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13];
    function codes(lh, dh) {
      for (;;) {
        var sym = decode(lh);
        if (sym < 256) { grow(1); out[op++] = sym; }
        else if (sym === 256) return;
        else {
          sym -= 257;
          var len = LB[sym] + bits(LE[sym]);
          var ds = decode(dh);
          var dist = DB[ds] + bits(DE[ds]);
          grow(len);
          for (var k = 0; k < len; k++) { out[op] = out[op - dist]; op++; }
        }
      }
    }
    var fixL = null, fixD = null;
    for (var last = 0; !last;) {
      last = bits(1);
      var type = bits(2);
      if (type === 0) {
        bitbuf = 0; bitcnt = 0;
        var len = src[pos] | (src[pos + 1] << 8); pos += 4;
        grow(len); out.set(src.subarray(pos, pos + len), op); op += len; pos += len;
      } else if (type === 1) {
        if (!fixL) {
          var l = new Uint8Array(288), i;
          for (i = 0; i < 144; i++) l[i] = 8;
          for (; i < 256; i++) l[i] = 9;
          for (; i < 280; i++) l[i] = 7;
          for (; i < 288; i++) l[i] = 8;
          fixL = huff(l);
          var d = new Uint8Array(30); for (i = 0; i < 30; i++) d[i] = 5;
          fixD = huff(d);
        }
        codes(fixL, fixD);
      } else if (type === 2) {
        var nlen = bits(5) + 257, ndist = bits(5) + 1, ncode = bits(4) + 4;
        var ORD = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];
        var lens = new Uint8Array(19), j;
        for (j = 0; j < ncode; j++) lens[ORD[j]] = bits(3);
        var ch = huff(lens);
        var all = new Uint8Array(nlen + ndist);
        for (j = 0; j < nlen + ndist;) {
          var s = decode(ch);
          if (s < 16) all[j++] = s;
          else {
            var rep = 0, val = 0;
            if (s === 16) { val = all[j - 1]; rep = 3 + bits(2); }
            else if (s === 17) rep = 3 + bits(3);
            else rep = 11 + bits(7);
            while (rep--) all[j++] = val;
          }
        }
        codes(huff(all.subarray(0, nlen)), huff(all.subarray(nlen)));
      } else throw new Error('inflate: 坏块类型');
    }
    return out.subarray(0, op);
  }
})();
