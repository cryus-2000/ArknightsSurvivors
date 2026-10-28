// LZMA（.lzma「alone」格式）解码器，给网页加载器解 index.wasm 的 LZMA 分片（docs/187 §5，export_web.py 用 Python lzma 压）。
// 本作自写，按 LZMA SDK 公开规格（LzmaSpec）实现，无第三方代码。
// 直接解进调用方给的 dst（Uint8Array，长度 = 原始字节数）：dst 本身就是滑动窗口，不另分配字典，峰值内存 = 压缩字节 + dst。
// 压缩端写的是「未知长度 + 结束标记」；这里解满 dst.length 就停，提前遇到结束标记或越界都抛错（加载器会重试该片）。
function syLzmaDecode(src, dst) {
  var ip = 13, op = 0, end = dst.length;
  var d = src[0];
  if (d >= 225) throw new Error('lzma: 头部参数不对');
  var lc = d % 9; d = (d / 9) | 0;
  var lp = d % 5, pb = (d / 5) | 0;
  var pbMask = (1 << pb) - 1, lpMask = (1 << lp) - 1;

  function probs(n) { var a = new Uint16Array(n); a.fill(1024); return a; }
  var isMatch = probs(192), isRep = probs(12), isRepG0 = probs(12), isRepG1 = probs(12), isRepG2 = probs(12), isRep0Long = probs(192);
  var lit = probs(0x300 << (lc + lp));
  var posSlot = probs(256), posDec = probs(115), align = probs(16);
  function lenCoder() { return { c: probs(2), low: probs(128), mid: probs(128), high: probs(256) }; }
  var lenDec = lenCoder(), repLenDec = lenCoder();

  // 区间解码器
  if (src[ip] !== 0) throw new Error('lzma: 区间解码器首字节应为 0');
  var range = 0xFFFFFFFF, code = ((src[ip + 1] << 24) | (src[ip + 2] << 16) | (src[ip + 3] << 8) | src[ip + 4]) >>> 0;
  ip += 5;
  function bit(p, i) {
    var v = p[i], bound = (range >>> 11) * v;
    var b;
    if (code < bound) { range = bound; p[i] = v + ((2048 - v) >>> 5); b = 0; }
    else { range -= bound; code -= bound; p[i] = v - (v >>> 5); b = 1; }
    if (range < 0x1000000) { range = (range * 256) >>> 0; code = ((code * 256) + src[ip++]) >>> 0; }
    return b;
  }
  function direct(n) {
    var r = 0;
    while (n--) {
      range >>>= 1;
      var b = code >= range ? 1 : 0;
      if (b) code -= range;
      r = r * 2 + b;
      if (range < 0x1000000) { range = (range * 256) >>> 0; code = ((code * 256) + src[ip++]) >>> 0; }
    }
    return r;
  }
  function tree(p, base, n) {
    var m = 1;
    for (var i = 0; i < n; i++) m = (m << 1) | bit(p, base + m);
    return m - (1 << n);
  }
  function rtree(p, base, n) {
    var m = 1, s = 0;
    for (var i = 0; i < n; i++) { var b = bit(p, base + m); m = (m << 1) | b; s |= b << i; }
    return s;
  }
  function len(L, ps) {
    if (bit(L.c, 0) === 0) return tree(L.low, ps << 3, 3);
    if (bit(L.c, 1) === 0) return 8 + tree(L.mid, ps << 3, 3);
    return 16 + tree(L.high, 0, 8);
  }

  var state = 0, rep0 = 0, rep1 = 0, rep2 = 0, rep3 = 0;
  while (op < end) {
    var ps = op & pbMask;
    if (bit(isMatch, (state << 4) + ps) === 0) {
      var prev = op > 0 ? dst[op - 1] : 0;
      var base = 0x300 * (((op & lpMask) << lc) + (prev >>> (8 - lc)));
      var sym = 1;
      if (state >= 7) {
        var mb = dst[op - rep0 - 1];
        do {
          var mbit = (mb >>> 7) & 1; mb <<= 1;
          var b = bit(lit, base + ((1 + mbit) << 8) + sym);
          sym = (sym << 1) | b;
          if (mbit !== b) break;
        } while (sym < 0x100);
      }
      while (sym < 0x100) sym = (sym << 1) | bit(lit, base + sym);
      dst[op++] = sym & 0xFF;
      state = state < 4 ? 0 : (state < 10 ? state - 3 : state - 6);
      continue;
    }
    var n;
    if (bit(isRep, state) === 0) {
      rep3 = rep2; rep2 = rep1; rep1 = rep0;
      n = len(lenDec, ps);
      state = state < 7 ? 7 : 10;
      var slot = tree(posSlot, (n < 3 ? n : 3) << 6, 6);
      if (slot < 4) rep0 = slot;
      else {
        var nd = (slot >>> 1) - 1, dist = (2 | (slot & 1)) * Math.pow(2, nd);
        if (slot < 14) dist += rtree(posDec, dist - slot, nd);
        else dist += direct(nd - 4) * 16 + rtree(align, 0, 4);
        if (dist === 0xFFFFFFFF) throw new Error('lzma: 提前遇到结束标记（' + op + ' / ' + end + '）');
        rep0 = dist;
      }
    } else {
      if (op === 0) throw new Error('lzma: 数据开头就是重复匹配');
      if (bit(isRepG0, state) === 0) {
        if (bit(isRep0Long, (state << 4) + ps) === 0) {
          state = state < 7 ? 9 : 11;
          dst[op] = dst[op - rep0 - 1]; op++;
          continue;
        }
      } else {
        var dd;
        if (bit(isRepG1, state) === 0) dd = rep1;
        else {
          if (bit(isRepG2, state) === 0) dd = rep2;
          else { dd = rep3; rep3 = rep2; }
          rep2 = rep1;
        }
        rep1 = rep0; rep0 = dd;
      }
      n = len(repLenDec, ps);
      state = state < 7 ? 8 : 11;
    }
    n += 2;
    if (rep0 >= op) throw new Error('lzma: 匹配距离越界');
    if (op + n > end) throw new Error('lzma: 解开后超过原始长度');
    var from = op - rep0 - 1;
    while (n--) dst[op++] = dst[from++];
  }
  if (ip > src.length) throw new Error('lzma: 压缩数据不完整');
  return op;
}
if (typeof module !== 'undefined') module.exports = syLzmaDecode;
