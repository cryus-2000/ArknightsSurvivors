/* 手机网页方向处理（10-26 用户「手机横过去之后能不能就锁住？否则没开方向锁时动一下就会变成竖屏」，docs/22「手机方向」）。
 * tools/export_web.py 内联进 <head>，在 audio_unlock.js 之后、loader.js / container.js 之前；取代预设 head_include 里原来的「请横屏」小段。
 * 只对手机 / 触屏小屏设备生效；电脑浏览器整段不动。
 *   1. 安卓 Chrome：首次触摸（touchend）请求全屏 + screen.orientation.lock('landscape')，失败静默；进入全屏后再锁一次。
 *   2. iOS Safari 没有 orientation.lock：竖屏持续 PORTRAIT_MS（0.5 秒，走动时的短暂抖动不算）后盖一层「请将手机横过来」，并通知游戏暂停；
 *      转回横屏立刻撤掉提示、通知游戏继续（游戏只恢复它自己暂停的那一次）。
 *   3. 竖屏期间冻结 window.innerWidth / innerHeight 为最后一次横屏的值（引擎按它们定画布尺寸）：画布不重排成竖屏界面，
 *      转回横屏时派一次 resize 让引擎重新量。第一次就在竖屏打开页面时没有横屏值可冻，照常排版，转横屏后正常。
 *   4. B站 App 内（container.js 的 window.__syToyEnv.container 为真）：容器方向由 Toy SDK 的 setContainerMode({orientation:'landscape'}) 锁定，本文件不做全屏 / 提示。
 * window.__syOrient：{portrait, onchange(cb)}：给 Godot 的桥（JavaScriptBridge.get_interface("__syOrient")），cb("1" | "0") 在「提示盖上 / 撤掉」时调；注册时回一次当前状态。
 */
(function () {
  var mobile = /Android|iPhone|iPad|iPod/i.test(navigator.userAgent) || (navigator.maxTouchPoints > 1 && Math.min(screen.width, screen.height) < 900);
  var listeners = [];
  var state = { portrait: false };
  window.__syOrient = {
    get portrait() { return state.portrait; },
    onchange: function (cb) {
      if (typeof cb !== 'function') return;
      listeners.push(cb);
      try { cb(state.portrait ? '1' : '0'); } catch (e) {}
    }
  };
  if (!mobile) return;
  var PORTRAIT_MS = 500;
  var mq = window.matchMedia ? window.matchMedia('(orientation: portrait)') : null;
  function inToy() { return !!(window.__syToyEnv && window.__syToyEnv.container); }

  // ---- 冻结 innerWidth / innerHeight（竖屏期间返回最后一次横屏的值）
  var dw = Object.getOwnPropertyDescriptor(window, 'innerWidth') || Object.getOwnPropertyDescriptor(Window.prototype, 'innerWidth');
  var dh = Object.getOwnPropertyDescriptor(window, 'innerHeight') || Object.getOwnPropertyDescriptor(Window.prototype, 'innerHeight');
  var rw = dw && dw.get ? function () { return dw.get.call(window); } : function () { return document.documentElement.clientWidth; };
  var rh = dh && dh.get ? function () { return dh.get.call(window); } : function () { return document.documentElement.clientHeight; };
  var last = null;      // 最后一次横屏时的 {w, h}
  var frozen = false;
  function portraitNow() { return mq ? mq.matches : rh() > rw(); }
  function track() {
    if (!portraitNow()) { last = { w: rw(), h: rh() }; if (frozen) { frozen = false; fire(); } }
  }
  try {
    Object.defineProperty(window, 'innerWidth', { configurable: true, get: function () { return frozen && last ? last.w : rw(); } });
    Object.defineProperty(window, 'innerHeight', { configurable: true, get: function () { return frozen && last ? last.h : rh(); } });
  } catch (e) {}
  function fire() { try { window.dispatchEvent(new Event('resize')); } catch (e) {} }

  // ---- 提示层
  var ov = null, timer = 0;
  function overlay() {
    if (ov) return ov;
    ov = document.createElement('div');
    ov.style.cssText = 'position:fixed;left:0;top:0;right:0;bottom:0;background:#02060a;color:#cfe;display:none;align-items:center;justify-content:center;z-index:9999;font:20px/1.7 sans-serif;text-align:center;touch-action:none';
    ov.innerHTML = '<div><svg width="96" height="96" viewBox="0 0 96 96" fill="none" stroke="#36e2dc" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">'
      + '<rect x="34" y="14" width="28" height="50" rx="4"/><path d="M45 58h6"/><path d="M20 70a34 34 0 0 0 56 8"/><path d="M76 78l-1-10-9 4"/></svg>'
      + '<div style="margin-top:12px">请将手机横过来</div><div style="font-size:13px;opacity:.7">游戏已暂停，转回横屏后继续</div></div>';
    document.body.appendChild(ov);
    return ov;
  }
  function setPortrait(p) {
    if (state.portrait === p) return;
    state.portrait = p;
    overlay().style.display = p ? 'flex' : 'none';
    for (var i = 0; i < listeners.length; i++) { try { listeners[i](p ? '1' : '0'); } catch (e) {} }
  }
  function check() {
    if (inToy()) { frozen = false; if (timer) { clearTimeout(timer); timer = 0; } setPortrait(false); return; }
    if (portraitNow()) {
      if (last) frozen = true;
      if (!timer && !state.portrait) timer = setTimeout(function () { timer = 0; if (portraitNow() && !inToy()) setPortrait(true); }, PORTRAIT_MS);
    } else {
      if (timer) { clearTimeout(timer); timer = 0; }
      var was = frozen;
      track();
      setPortrait(false);
      if (was) fire();
    }
  }
  track();
  window.addEventListener('resize', function () { track(); check(); }, true);
  window.addEventListener('orientationchange', function () { setTimeout(check, 60); });
  if (mq && mq.addEventListener) mq.addEventListener('change', check);
  document.addEventListener('DOMContentLoaded', check);

  // ---- 安卓 Chrome：全屏 + 锁横屏
  var tried = false;
  function lock() {
    try { if (screen.orientation && screen.orientation.lock) screen.orientation.lock('landscape').catch(function () {}); } catch (e) {}
  }
  document.addEventListener('fullscreenchange', function () { if (document.fullscreenElement) lock(); });
  document.addEventListener('webkitfullscreenchange', function () { lock(); });
  document.addEventListener('touchend', function () {
    if (tried || inToy()) return;
    tried = true;
    try {
      var el = document.documentElement;
      var f = el.requestFullscreen || el.webkitRequestFullscreen;
      if (f && !document.fullscreenElement) {
        var p = f.call(el);
        if (p && p.then) p.then(lock).catch(function () { lock(); });
      } else { lock(); }
    } catch (e) {}
  }, { passive: true });
})();
