// 网页帧时浮层（docs/50 §21.7，10-21）：网址带 ?fps=1 时左上角显示最近 10 秒的帧间隔 平均 / p50 / p95 / p99 与超 16.7 ms 的占比，
// 每秒刷新；不带参数时什么都不做。给真机 / B站 Toy 预览量帧率用，只读 requestAnimationFrame 的时间戳，不碰游戏
(function () {
  if (!/[?&]fps=1/.test(location.search)) return;
  var ts = [], last = 0, box = null, shown = 0;
  function pct(a, q) { return a[Math.min(a.length - 1, Math.floor(q * a.length))]; }
  function tick(t) {
    if (last > 0) ts.push([t, t - last]);
    last = t;
    while (ts.length && t - ts[0][0] > 10000) ts.shift();
    if (t - shown > 1000 && ts.length > 10) {
      shown = t;
      if (!box) {
        box = document.createElement('div');
        box.style.cssText = 'position:fixed;left:4px;top:4px;z-index:99999;pointer-events:none;background:rgba(0,0,0,.6);color:#9fe;font:11px/1.35 monospace;padding:3px 6px;white-space:pre';
        document.body.appendChild(box);
      }
      var d = ts.map(function (x) { return x[1]; }).sort(function (a, b) { return a - b; });
      var sum = 0, over = 0;
      for (var i = 0; i < d.length; i++) { sum += d[i]; if (d[i] > 16.7) over++; }
      box.textContent = 'ms  avg ' + (sum / d.length).toFixed(1) + '  p50 ' + pct(d, 0.5).toFixed(1) + '  p95 ' + pct(d, 0.95).toFixed(1) +
        '  p99 ' + pct(d, 0.99).toFixed(1) + '\n>16.7 ' + (100 * over / d.length).toFixed(0) + '%  n ' + d.length + '  ' + innerWidth + 'x' + innerHeight + ' dpr ' + devicePixelRatio;
    }
    requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);
})();
