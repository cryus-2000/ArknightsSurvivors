// 网页配乐（11-08 docs/319 §12，tools/web_music.py 出包）：长配乐由浏览器解码播放，不走引擎样本（引擎注册一首 200 秒的曲子要在 WASM 堆里整段解码，
// 堆高水位 +100 MB 且只涨不缩）。sfx.gd 给这些曲目建静音占位播放器，每帧把「哪个占位器在播、从第几秒、音量多少」同步过来（window.__syMus）。
// 用引擎同一个音频上下文（power.js 记在 __syAudioCtx 里：切后台挂起、回前台恢复照旧），各层同一时刻 start，样本级对齐。
// fetch + decodeAudioData 是异步的：第一次播某首要等它解完，晚到的时间从曲中补上（与引擎「迟到的毫秒从曲中补」同口径），不卡主线程。
(function () {
  var M = {}, bufs = {}, loading = {}, srcs = {}, gains = {}, toFree = {};
  var bus = null, lp = null, pre = null, busGain = 1, cut = 20000, fails = 0, dl = 0, lastFail = "";
  window.__syMus = M;
  function ctx() {
    var l = window.__syAudioCtx || [];
    for (var i = l.length - 1; i >= 0; i--) { if (l[i].state !== "closed") return l[i]; }
    return null;
  }
  function out(c) {
    if (!bus || bus.context !== c) {
      lp = c.createBiquadFilter(); lp.type = "lowpass"; lp.frequency.value = cut; lp.Q.value = 0.707;
      bus = c.createGain(); bus.gain.value = busGain;
      bus.connect(lp); lp.connect(c.destination);
      pre = c.createAnalyser(); pre.fftSize = 2048;   // 自测：总线音量之前的电平（测试局静音时也能确认在出声）
    }
    return bus;
  }
  // 手机（power.js 按 24 kHz 建上下文的那类设备，__sySampleRate > 0）：解码后左右声道混成单声道再留着，常驻的解码缓冲减半
  // （200 秒一首 37 → 18 MB，docs/319 §15）。网址带 ?musmono=0 关掉
  var MONO = (window.__sySampleRate || 0) > 0 && new URLSearchParams(location.search).get("musmono") !== "0";
  function mono(c, b) {
    if (!MONO || b.numberOfChannels < 2) return b;
    var n = b.length, m = c.createBuffer(1, n, b.sampleRate), o = m.getChannelData(0), l = b.getChannelData(0), r = b.getChannelData(1);
    for (var i = 0; i < n; i++) o[i] = 0.5 * (l[i] + r[i]);
    return m;
  }
  function load(url) {
    if (bufs[url]) return Promise.resolve(bufs[url]);
    if (loading[url]) return loading[url];
    var c = ctx();
    if (!c) return Promise.reject(new Error("no audio context"));
    loading[url] = fetch(url).then(function (r) {
      if (!r.ok) throw new Error(r.status);
      return r.arrayBuffer();
    }).then(function (a) {
      dl += a.byteLength;
      return new Promise(function (res, rej) { c.decodeAudioData(a, res, rej); });
    }).then(function (b) {
      b = mono(c, b);
      bufs[url] = b; delete loading[url]; return b;
    }, function (e) {
      delete loading[url]; fails++; lastFail = String(url).split("/").pop() + " " + String(e && e.message || e).slice(0, 40);
      console.error("PF WEBMUSIC load fail " + url + " " + e);
      throw e;
    });
    return loading[url];
  }
  function stopId(id) {
    var s = srcs[id];
    if (s && s.src) {
      try { s.src.stop(); } catch (e) {}
      try { s.src.disconnect(); s.g.disconnect(); } catch (e) {}
    }
    var u = s && s.url;
    delete srcs[id];
    if (u && toFree[u]) tryFree(u);
  }
  function tryFree(u) {   // 还有源在用就等它停（stopId 里再试）
    for (var k in srcs) { if (srcs[k].url === u) return; }
    delete bufs[u]; delete toFree[u];
  }
  // list: [[id, url, 从第几秒, 循环起点, 循环终点（曲长）, 线性音量], ...]：同一批一起开（分层同步）
  M.play = function (list) {
    var c = ctx();
    if (!c || !list.length) return;
    var t0 = performance.now(), tok = {};
    list.forEach(function (it) { stopId(it[0]); delete toFree[it[1]]; gains[it[0]] = it[5]; srcs[it[0]] = { tok: tok, url: it[1] }; });
    Promise.all(list.map(function (it) { return load(it[1]); })).then(function (bs) {
      var lead = 0.03, late = (performance.now() - t0) / 1000 + lead, when = c.currentTime + lead;
      list.forEach(function (it, i) {
        var s = srcs[it[0]];
        if (!s || s.tok !== tok) return;   // 解码期间已经停掉 / 换了
        var b = bs[i], src = c.createBufferSource(), g = c.createGain();
        src.buffer = b;
        src.loop = true;
        var ls = Math.max(0, it[3]), le = it[4] > 0 ? Math.min(it[4], b.duration) : b.duration;
        if (le <= ls + 0.05) { ls = 0; le = b.duration; }
        src.loopStart = ls; src.loopEnd = le;
        var off = it[2] + late;
        if (off >= le) off = ls + ((off - ls) % (le - ls));
        g.gain.value = gains[it[0]];
        src.connect(g); g.connect(out(c)); g.connect(pre);
        src.start(when, Math.max(0, off));
        srcs[it[0]] = { src: src, g: g, url: it[1], tok: tok };
      });
    }, function () {});
  };
  M.stop = function (ids) { ids.forEach(stopId); };
  M.gain = function (pairs) {   // [[id, 线性音量], ...]：短平滑，免得逐帧改音量出拉链声
    var c = ctx();
    pairs.forEach(function (p) {
      gains[p[0]] = p[1];
      var s = srcs[p[0]];
      if (s && s.g) { try { s.g.gain.setTargetAtTime(p[1], c.currentTime, 0.015); } catch (e) { s.g.gain.value = p[1]; } }
    });
  };
  M.bus = function (v, hz) {   // 配乐总线（Music × Master 音量与静音）与低通（music_lp）
    busGain = v; cut = hz;
    if (bus) {
      var c = bus.context;
      try { bus.gain.setTargetAtTime(v, c.currentTime, 0.02); lp.frequency.setTargetAtTime(hz, c.currentTime, 0.05); }
      catch (e) { bus.gain.value = v; lp.frequency.value = hz; }
    }
  };
  M.preload = function (urls) { urls.forEach(function (u) { load(u).catch(function () {}); }); };
  M.free = function (urls) {   // 曲目放完：丢掉解码缓冲（正在播的不丢）
    urls.forEach(function (u) { toFree[u] = 1; tryFree(u); });
  };
  M.mb = function () {
    var b = 0;
    for (var u in bufs) { var x = bufs[u]; b += x.length * x.numberOfChannels * 4; }
    return b / 1048576;
  };
  M.level = function () {   // 均方根电平（0–1）
    if (!pre) return 0;
    var d = new Float32Array(pre.fftSize), e = 0;
    pre.getFloatTimeDomainData(d);
    for (var i = 0; i < d.length; i++) e += d[i] * d[i];
    return Math.sqrt(e / d.length);
  };
  M.state = function () {   // 自测 / 日志
    var on = 0; for (var k in srcs) { if (srcs[k].src) on++; }
    return JSON.stringify({ bufs: Object.keys(bufs).length, loading: Object.keys(loading).length, on: on, fails: fails, mb: Math.round(M.mb()), lv: Math.round(M.level() * 10000) / 10000, ctx: (ctx() || {}).state || "none",
      sr: (ctx() || {}).sampleRate || 0, mono: MONO ? 1 : 0, dl: Math.round(dl / 104857.6) / 10, lf: lastFail });   // sr：解码按上下文采样率重采样（iOS 常为 48 kHz，缓冲是 24 kHz 原曲的 2 倍）
  };
})();
