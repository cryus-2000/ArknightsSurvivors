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
  // 混音放到 OfflineAudioContext 里渲染（音频线程，单声道目标按规范 0.5 × (L + R) 下混）：原来主线程逐样本循环，200 秒一首 480 万次，
  // iPhone 上换曲那一帧卡几十到上百毫秒（11-09 真机 7:02 中期 Boss 登场换曲一帧 342 ms，docs/319 §20）。没有 OfflineAudioContext 才退回主线程循环
  function mono(c, b) {
    if (!MONO || b.numberOfChannels < 2) return Promise.resolve(b);
    var O = window.OfflineAudioContext || window.webkitOfflineAudioContext;
    if (O) {
      try {
        var oc = new O(1, b.length, b.sampleRate), s = oc.createBufferSource();
        s.buffer = b; s.connect(oc.destination); s.start(0);
        return new Promise(function (res) {
          var done = function (m) { res(m && m.numberOfChannels === 1 ? m : b); };
          var p = oc.startRendering();
          if (p && p.then) p.then(done, function () { res(b); });
          else oc.oncomplete = function (e) { done(e.renderedBuffer); };
        });
      } catch (e) {}
    }
    var n = b.length, m = c.createBuffer(1, n, b.sampleRate), o = m.getChannelData(0), l = b.getChannelData(0), r = b.getChannelData(1);
    for (var i = 0; i < n; i++) o[i] = 0.5 * (l[i] + r[i]);
    return Promise.resolve(m);
  }
  function decode(c, url) {
    return fetch(url).then(function (r) {
      if (!r.ok) throw new Error(r.status);
      return r.arrayBuffer();
    }).then(function (a) {
      dl += a.byteLength;
      return new Promise(function (res, rej) { c.decodeAudioData(a, res, rej); });
    });
  }
  var premix = MONO && new URLSearchParams(location.search).get("muspremix") !== "0";
  // 二阶段预混（11-11 docs/332 §2）：最终 Boss 二阶段 p1（一阶段底层）+ p2（加强层）两份缓冲同驻，手机配乐 19 → 37 MB（iPhone 11:21 峰值）。
  // 出包另存 p1 + p2 的单声道预混（tools/web_music.py）：p2 的占位器在手机上解码的是预混；预混开播后底层 p1 的增益按 g1 − g2 交叉淡出，
  // 降到 0 就停掉并丢掉 p1 的缓冲，同一时刻只留一首（交接只有预混解码到开播后约 0.15 秒）。二阶段退回时重新解 p1、按预混的进度对齐接上。
  // 预混文件缺失时照旧解 p2 原文件（两份同驻，行为与旧版一样）。网址带 ?muspremix=0 一并关掉
  var PAIRS = {"music_suno_final_p2.m4a": {base: "music_suno_final_p1.m4a", mix: "music_suno_final_p12_mono.m4a"}};
  var isMix = {}, retired = {};   // isMix：这个 url 的缓冲是预混；retired：底层 id -> url（GD 那边还在播，这边已停掉放手）
  function load(url) {
    delete toFree[url];   // 新的播放或预热请求可接回正在解码的同一首
    if (bufs[url]) return Promise.resolve(bufs[url]);
    if (loading[url]) return loading[url];
    var c = ctx();
    if (!c) return Promise.reject(new Error("no audio context"));
    var decoded, pr = premix && PAIRS[url];
    if (premix && url === "music_suno_final_p1.m4a") {
      decoded = decode(c, "music_suno_final_p1_mono.m4a").catch(function () { return decode(c, url); });
    } else if (pr) {
      decoded = decode(c, pr.mix).then(function (b) { b.__syMix = 1; return b; }, function () { return decode(c, url); });
    } else {
      decoded = decode(c, url);
    }
    loading[url] = decoded.then(function (b) {
      return mono(c, b);
    }).then(function (b) {
      delete loading[url];
      if (b.__syMix) isMix[url] = 1; else delete isMix[url];
      bufs[url] = b;
      if (toFree[url]) tryFree(url);
      return b;
    }, function (e) {
      delete loading[url];
      if (toFree[url]) tryFree(url);
      fails++; lastFail = String(url).split("/").pop() + " " + String(e && e.message || e).slice(0, 40);
      console.error("PF WEBMUSIC load fail " + url + " " + e);
      throw e;
    });
    return loading[url];
  }
  function stopId(id) {
    delete retired[id];
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
    if (loading[u]) return;   // 保留释放请求，避免迟到的解码缓冲再次常驻
    for (var k in srcs) { if (srcs[k].url === u) return; }
    delete bufs[u]; delete toFree[u];
  }
  // list: [[id, url, 从第几秒, 循环起点, 循环终点（曲长）, 线性音量], ...]：同一批一起开（分层同步）
  M.play = function (list) {
    var c = ctx();
    if (!c || !list.length) return;
    var t0 = performance.now(), tok = {};
    list.forEach(function (it) { stopId(it[0]); gains[it[0]] = it[5]; srcs[it[0]] = { tok: tok, url: it[1] }; });
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
        g.gain.value = eff(it[0]);
        src.connect(g); g.connect(out(c)); g.connect(pre);
        src.start(when, Math.max(0, off));
        srcs[it[0]] = { src: src, g: g, url: it[1], tok: tok, when: when, t0: when - Math.max(0, off), ls: ls, le: le };
      });
      pairSync(when);
    }, function () {});
  };
  M.stop = function (ids) { ids.forEach(stopId); pairSync(); };
  M.gain = function (pairs) {   // [[id, 线性音量], ...]：短平滑，免得逐帧改音量出拉链声
    var c = ctx();
    pairs.forEach(function (p) {
      gains[p[0]] = p[1];
      var s = srcs[p[0]];
      if (s && s.g) { try { s.g.gain.setTargetAtTime(eff(p[0]), c.currentTime, 0.015); } catch (e) { s.g.gain.value = eff(p[0]); } }
    });
    pairSync();
  };
  // ---- 二阶段预混（PAIRS）
  function mixOf(baseUrl) {   // 底层 url 对应的、正在出声（或已排好开播）的预混源
    for (var u in PAIRS) {
      if (PAIRS[u].base !== baseUrl || !isMix[u]) continue;
      for (var k in srcs) { if (srcs[k].url === u && srcs[k].src) return { id: k, s: srcs[k] }; }
    }
    return null;
  }
  function baseIdOf(baseUrl) {
    for (var k in srcs) { if (srcs[k].url === baseUrl) return k; }
    for (var r in retired) { if (retired[r] === baseUrl) return r; }
    return null;
  }
  function eff(id) {   // 实际给到 Web Audio 的增益：预混在播时底层只补 g1 − g2 那一部分（预混 = p1 + p2）
    var g = gains[id] || 0, s = srcs[id];
    if (!s) return g;
    var m = mixOf(s.url);
    return m ? Math.max(0, g - (gains[m.id] || 0)) : g;
  }
  function pairSync(at) {
    if (!premix) return;
    var c = ctx();
    if (!c) return;
    for (var u in PAIRS) {
      var pr = PAIRS[u], m = mixOf(pr.base), bid = baseIdOf(pr.base);
      if (bid === null) continue;
      var s = srcs[bid];
      var need = m ? Math.max(0, (gains[bid] || 0) - (gains[m.id] || 0)) : (gains[bid] || 0);
      if (s && s.src && m) {
        var t = Math.max(c.currentTime, at || 0, m.s.when || 0);
        try {
          s.g.gain.cancelScheduledValues(c.currentTime);
          if (t > c.currentTime + 0.001) s.g.gain.setValueAtTime(need, t);   // 预混开播那一刻（样本级）把底层同时切到差值，不叠也不空
          else s.g.gain.setTargetAtTime(need, c.currentTime, 0.015);
        } catch (e) { s.g.gain.value = need; }
        if (need <= 0.001) {
          if (c.currentTime >= (m.s.when || 0) + 0.1) {
            stopId(bid); retired[bid] = pr.base; toFree[pr.base] = 1; tryFree(pr.base);   // 预混已出声：停掉底层、丢掉它的缓冲
          } else {
            setTimeout(pairSync, Math.ceil(((m.s.when || 0) + 0.12 - c.currentTime) * 1000));
          }
        }
      } else if (retired[bid] && need > 0.01) {
        // 二阶段退回（预混音量降下来了）：重新解底层，按预混的进度对齐接上
        var ref = m ? m.s : null, tok = {};
        delete retired[bid];
        srcs[bid] = { tok: tok, url: pr.base };
        (function (bid, base, tok, ref) {
          load(base).then(function (b) {
            var s2 = srcs[bid];
            if (!s2 || s2.tok !== tok) return;
            var lead = 0.03, when = c.currentTime + lead, src = c.createBufferSource(), g = c.createGain();
            var ls = ref ? ref.ls : 0, le = ref ? ref.le : b.duration;
            src.buffer = b; src.loop = true; src.loopStart = ls; src.loopEnd = Math.min(le, b.duration);
            var off = ref ? when - ref.t0 : 0;
            if (off >= le) off = ls + ((off - ls) % Math.max(le - ls, 0.1));
            g.gain.value = eff(bid);
            src.connect(g); g.connect(out(c)); g.connect(pre);
            src.start(when, Math.max(0, off));
            srcs[bid] = { src: src, g: g, url: base, tok: tok, when: when, t0: when - Math.max(0, off), ls: ls, le: le };
          }, function () {});
        })(bid, pr.base, tok, ref);
      }
    }
  }
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
      sr: (ctx() || {}).sampleRate || 0, mono: MONO ? 1 : 0, mix: Object.keys(isMix).length, ret: Object.keys(retired).length, dl: Math.round(dl / 104857.6) / 10, lf: lastFail });   // sr：解码按上下文采样率重采样（iOS 常为 48 kHz，缓冲是 24 kHz 原曲的 2 倍）
  };
})();
