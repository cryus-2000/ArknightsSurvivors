// 加载期错误捕获 + 诊断卡（11-16 B站 Toy「加载很久、加载不出来」，docs/22「加载链路」）。
// export_web.py 把它作为 head 里第一个自有 script 单独内联（不和 loader.js 等拼在一起：那一大块里有语法错时整块不跑，这里照样能报）。
// 只用 ES5、不依赖别的脚本。诊断卡画在首帧壳 tools/web/boot_shell.html 的 #sy-boot-err 上（壳在 body 最前，纯 HTML / CSS）。
// 诊断卡：阶段与停留秒数、各分片字节、第一条报错、系统与内核、是否在 B站 App、包版本、内存；按钮「重试」「复制诊断信息」「继续等待」，
// 下写「截图这张卡私信 UP 主」（Toy 不许放站外链接 / 联系方式）。只在本机显示 / 复制，不往任何服务器发。
//   window.__syBootFail(title, detail)：加载失败（下载重试用尽 / 引擎报错 / 内核过旧）——整页换成首帧壳 + 红色诊断卡
//   window.__syBootWarn(title, detail, force)：提醒（加载超过 20 秒 / 进度停住 / 本页脚本出错）——浮在加载页上，加载照常进行；
//     玩家点过「继续等待」后只有 force（新的报错、进度停住）才再弹
//   window.__syBootHideWarn()：收起提醒（loader.js：进度恢复时收起「停住」提醒）
//   window.__syBootOk = true：加载完成（加载器撤页时置），之后不再弹
//   window.__syDiagText()：诊断文字（诊断卡 / 复制 / container.js 四指浮层共用）
//   window.__syErrs：捕获到的错误（最多 8 条）；window.__syFirstErr：第一条（脚本错误或 loader.js 记的下载失败）
(function () {
  var errs = window.__syErrs = [];
  var BUILD = /*SY_BUILD*/'';   // 包版本（export_web.py 写 commit；同 build.txt）
  var pending = null, dismissed = false, timer = 0, t0 = Date.now();
  function $(id) { try { return document.getElementById(id); } catch (e) { return null; } }
  function T(zh, a, b) {   // 译文（boot_l10n.js 的 __syT；那段没跑时按中文原文填占位）
    if (window.__syT) return window.__syT(zh, a, b);
    var s = zh;
    if (a !== undefined) s = s.split('{0}').join(String(a));
    if (b !== undefined) s = s.split('{1}').join(String(b));
    return s;
  }

  // ---------------------------------------------------------------- 诊断文字
  function sys() {
    var ua = navigator.userAgent || '', os = '', core = '', m;
    if ((m = /HarmonyOS[ /]?([\d.]*)/.exec(ua))) os = 'HarmonyOS ' + m[1];
    else if ((m = /Android ([\d.]+)/.exec(ua))) os = 'Android ' + m[1];
    else if ((m = /OS (\d+)_(\d+)(?:_\d+)? like Mac OS X/.exec(ua))) os = 'iOS ' + m[1] + '.' + m[2];
    else if (/Windows/.test(ua)) os = 'Windows';
    else if (/Mac OS X/.test(ua)) os = 'macOS';
    else os = navigator.platform || T('未知系统');
    if ((m = /Chrome\/([\d]+)/.exec(ua))) core = 'Chrome ' + m[1] + (/; wv\)/.test(ua) ? ' WebView' : '');
    else if ((m = /Version\/([\d.]+).*Safari/.exec(ua))) core = 'Safari ' + m[1];
    else if (/AppleWebKit/.test(ua)) core = 'WebKit';
    else core = T('未知内核');
    return os + ' · ' + core;
  }
  function env() {
    var ua = navigator.userAgent || '', m = /(BiliApp|bili-universal|bili-inter|bili-blue|bili-hd|BiliComic)\/?([\d.]*)/i.exec(ua);
    var te = window.__syToyEnv, inApp = !!m || !!(te && te.container);
    var s = inApp ? T('B站 App') + (m && m[2] ? ' ' + m[2] : '') : T('不在 B站 App 内');
    s += ' · ' + T('包 {0}', BUILD || window.__syBuild || '?');
    var mem = [];
    if (navigator.deviceMemory) mem.push(T('设备内存约 {0} GB', navigator.deviceMemory));
    try { if (performance.memory) mem.push(T('JS 堆 {0} MB', Math.round(performance.memory.usedJSHeapSize / 1048576))); } catch (e) {}
    return s + (mem.length ? ' · ' + mem.join(' · ') : '');
  }
  function mb(x) { return (x / 1048576).toFixed(1); }
  window.__syDiagText = function () {
    var D = window.__syLoadDiag, now = Date.now(), L = [];
    if (D) {
      L.push(T('阶段：') + T(D.phase) + ' · ' + T('已停 {0} 秒（共 {1} 秒）', Math.round((now - D.since) / 1000), Math.round((now - t0) / 1000)));
      var ps = [];
      for (var i = 0; i < D.parts.length; i++) {
        var p = D.parts[i];
        ps.push(p.n + ' ' + (p.got >= p.tot ? mb(p.tot) + ' ' + T('齐') : mb(p.got) + '/' + mb(p.tot)) + (p.st ? ' (' + p.st + ')' : ''));
      }
      if (ps.length) L.push(T('分片：') + ps.join(' · '));
    } else L.push(T('阶段：') + T('加载器没有运行 · 共 {0} 秒', Math.round((now - t0) / 1000)));
    L.push(T('报错：') + (window.__syFirstErr || T('无')));
    L.push(T('系统：') + sys());
    L.push(T('环境：') + env());
    return L.join('\n');
  };

  // ---------------------------------------------------------------- 诊断卡
  function refresh() {
    var g = $('sy-boot-dg');
    if (g) g.textContent = window.__syDiagText();
  }
  function show(kind, title, detail, force) {
    var c = $('sy-boot-err');
    if (!c) { pending = [kind, title, detail, force]; return; }   // 壳还没解析到：DOMContentLoaded 后补上
    var cur = c.getAttribute('data-k');
    if (cur === 'fatal' && kind !== 'fatal') return;   // 失败卡片不被提醒盖掉
    if (kind !== 'fatal' && dismissed && !force) return;
    if (force) dismissed = false;
    if (kind === 'fatal') {   // 失败：壳进失败态、没什么可等的（壳解析前就失败时在这里补，见 pending）
      var b = $('sy-boot'), m = $('sy-boot-msg'), w = $('sy-boot-wait');
      if (b) b.className = 'fail';
      if (m) m.textContent = T('加载失败');
      if (w) w.style.display = 'none';
    }
    c.setAttribute('data-k', kind);
    c.className = 'on ' + kind;
    var t = $('sy-boot-et'), d = $('sy-boot-ed');
    if (t) t.textContent = title;
    if (d) d.textContent = detail || '';
    refresh();
    if (!timer) timer = setInterval(function () {
      var cc = $('sy-boot-err');
      if (!cc || window.__syBootOk) { clearInterval(timer); timer = 0; return; }
      if (cc.className.indexOf('on') === 0) refresh();
    }, 1000);
  }
  window.__syBootFail = function (title, detail) {
    if (window.__syBootOk) return;
    window.__syBootFailed = true;
    show('fatal', title || T('加载失败'), detail, true);
  };
  window.__syBootWarn = function (title, detail, force) {
    if (window.__syBootOk || window.__syBootFailed) return;
    show('warn', title, detail, force);
  };
  window.__syBootHideWarn = function () {
    var c = $('sy-boot-err');
    if (c && c.getAttribute('data-k') === 'warn') { c.className = ''; c.removeAttribute('data-k'); }
  };
  window.__syDiagWait = function () {   // 「继续等待」：收起，之后只有新的报错 / 进度停住才再弹
    dismissed = true;
    window.__syBootHideWarn();
  };
  window.__syDiagCopy = function () {
    var t = window.__syDiagText(), b = $('sy-boot-copy');
    var c = $('sy-boot-err'), head = $('sy-boot-et');
    if (head && c && c.className.indexOf('on') === 0) t = head.textContent + '\n' + t;
    function said(s) { if (!b) return; b.textContent = s; setTimeout(function () { b.textContent = T('复制诊断信息'); }, 2000); }
    function legacy() {
      var ok = false, ta = document.createElement('textarea');
      ta.value = t; ta.setAttribute('readonly', '');
      ta.style.cssText = 'position:fixed;left:-9999px;top:0;opacity:0';
      document.body.appendChild(ta);
      ta.select();
      try { ta.setSelectionRange(0, t.length); } catch (e) {}
      try { ok = document.execCommand('copy'); } catch (e) {}
      ta.parentNode.removeChild(ta);
      if (ok) return said(T('已复制'));
      try {   // 都不行：选中卡上的文字，玩家长按复制
        var g = $('sy-boot-dg'), r = document.createRange(), sel = window.getSelection();
        r.selectNodeContents(g); sel.removeAllRanges(); sel.addRange(r);
      } catch (e) {}
      said(T('请长按文字复制'));
    }
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) { navigator.clipboard.writeText(t).then(function () { said(T('已复制')); }, legacy); return; }
    } catch (e) {}
    legacy();
  };
  document.addEventListener('DOMContentLoaded', function () {
    if (pending) { var p = pending; pending = null; show(p[0], p[1], p[2], p[3]); }
    if (!BUILD && !window.__syBuild) {   // 本地重新注入的包没写版本：读同目录 build.txt（只读本包文件，不发任何数据）
      try {
        var x = new XMLHttpRequest();
        x.open('GET', 'build.txt', true);
        x.onload = function () { if (x.status === 200) window.__syBuild = String(x.responseText || '').trim().slice(0, 16); };
        x.send();
      } catch (e) {}
    }
  });

  // ---------------------------------------------------------------- 错误捕获
  function ours(file) {   // 本页内联脚本 / index.js 出的错才立刻提示；SDK 等外部脚本（跨域只给 "Script error."）只记下
    if (!file) return false;
    try {
      var u = new URL(file, location.href);
      return u.origin === location.origin;
    } catch (e) { return false; }
  }
  function note(msg, file, line, own) {
    var s = String(msg).slice(0, 200) + (file ? ' @' + (String(file).split('?')[0].split('#')[0].split('/').pop() || 'index.html') + ':' + (line || 0) : '');
    if (errs.length < 8) errs.push(s);
    if (!own || window.__syBootOk) return;
    if (!window.__syFirstErr) window.__syFirstErr = s;
    var old = /SyntaxError|Unexpected (token|identifier)|Invalid or unexpected/i.test(String(msg));   // 语法错误多半是内核太旧（引擎要 Chrome 85 以上）
    window.__syBootWarn(old ? T('页面脚本无法运行，可能是内核版本过旧') : T('页面脚本出错'),
      old ? T('安卓：在应用商店更新「Android System WebView」或「Chrome」后重新打开。iPhone：升级到 iOS 15 以上。') : T('加载可能停住。停住时点「重试」。'), true);
  }
  window.addEventListener('error', function (e) {
    if (!e || (e.target && e.target !== window)) return;   // 图片等资源加载失败不算（加载器自己的下载另有重试和提示）
    note(e.message || (e.error && e.error.message) || 'error', e.filename, e.lineno, ours(e.filename));
  }, true);
  window.addEventListener('unhandledrejection', function (e) {
    var r = e && e.reason;
    note(T('未处理的异步错误：') + ((r && r.message) || r), '', 0, false);
  });
})();
