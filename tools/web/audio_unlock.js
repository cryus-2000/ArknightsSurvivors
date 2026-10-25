// iOS Safari 网页声音兜底（10-26 用户 iPhone 实机「听不到声音」，docs/22「iOS 声音」）。放在最前，引擎建 AudioContext 之前装好。
// 1. 记下页面上所有 AudioContext（引擎的 Web Audio 样本 / 流都挂在它上面），在每次用户手势（touchend / click / keydown / pointerup）里 resume：
//    iOS 只认手势回调里同步调的 resume，状态还会因来电 / 锁屏 / 切后台变成 interrupted，回来要再叫醒；页面重新可见（visibilitychange / pageshow）时也试一次。
// 2. navigator.audioSession.type = 'playback'（iOS 16.4+）：让网页声音不受侧边静音键管（默认 ambient 会被静音键静音）。
//    更老的 iOS 没有这个接口：首次手势里放一段静音的 <audio> 循环，系统把页面当「播放」类别，Web Audio 同样不受静音键管。
// 3. iOS 上首次手势后弹一次小提示（只一次，localStorage 记）：没有声音时先看静音键与音量。
(function () {
  var AC = window.AudioContext || window.webkitAudioContext;
  var ctxs = [];
  if (AC) {
    var W = function () {
      var c = new (Function.prototype.bind.apply(AC, [null].concat([].slice.call(arguments))))();
      ctxs.push(c);
      return c;
    };
    W.prototype = AC.prototype;
    try { window.AudioContext = W; if (window.webkitAudioContext) window.webkitAudioContext = W; } catch (e) {}
  }
  var ua = navigator.userAgent || '';
  var ios = /iPhone|iPad|iPod/i.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
  var sess = navigator.audioSession;
  function setSession() { try { if (sess && sess.type !== 'playback') sess.type = 'playback'; } catch (e) {} }
  setSession();
  var el = null;
  function silent() {
    if (!ios || sess || el) return;
    try {
      el = document.createElement('audio');
      el.src = 'data:audio/wav;base64,UklGRkQDAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YSADAACAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgA==';
      el.loop = true;
      el.setAttribute('playsinline', '');
      el.volume = 0.01;
      var p = el.play();
      if (p && p.catch) p.catch(function () { el = null; });
    } catch (e) { el = null; }
  }
  function wake() {
    setSession();
    for (var i = 0; i < ctxs.length; i++) {
      var c = ctxs[i];
      if (c.state !== 'running' && c.state !== 'closed') { try { c.resume(); } catch (e) {} }
    }
  }
  function toast() {
    if (!ios) return;
    try {
      if (localStorage.getItem('sy_audio_hint')) return;
      localStorage.setItem('sy_audio_hint', '1');
    } catch (e) {}
    var t = document.createElement('div');
    t.textContent = '没有声音时，请检查手机侧边的静音键与音量。';
    t.style.cssText = 'position:fixed;left:50%;bottom:18px;transform:translateX(-50%);z-index:9998;background:rgba(2,10,16,.86);color:#cfe;font:13px/1.5 sans-serif;padding:8px 16px;border:1px solid #2a6a70;pointer-events:none;transition:opacity .6s';
    document.body.appendChild(t);
    setTimeout(function () { t.style.opacity = '0'; }, 5000);
    setTimeout(function () { if (t.parentNode) t.parentNode.removeChild(t); }, 5700);
  }
  var first = true;
  function gesture() {
    wake();
    silent();
    if (first) { first = false; setTimeout(toast, 800); }
  }
  ['touchend', 'click', 'keydown', 'pointerup'].forEach(function (t) { document.addEventListener(t, gesture, { passive: true, capture: true }); });
  document.addEventListener('visibilitychange', function () { if (!document.hidden) wake(); });
  window.addEventListener('pageshow', wake);
})();
