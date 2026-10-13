/* 网页容器适配（tools/export_web.py 内联进 index.html 的 <head>，在 loader.js 之后）
 *
 * B站 Toy（docs/22「B站 Toy 容器」）：只在像是 B站环境（域名含 bilibili / hdslb，或 UA 含 Bili）时异步加载 Toy JS SDK；
 * itch、普通浏览器、桌面版不加载，加载失败也一切照旧。SDK 在、且 toy.isSupport('onContainerChange') 为真（只在 B站 App 内）时：
 *   1. 先 toy.onContainerChange 监听，再 toy.setContainerMode({orientation:'landscape', immersive:true})（手机横屏必须同时沉浸）；
 *      setContainerMode 的 Promise 不算成功，以回调里的状态为准。
 *   2. 用回调的 state.viewport（CSS px）与 state.safeArea 定画布：画布 = viewport 去掉安全边距，贴在安全区左上角，
 *      刘海 / 灵动岛 / 底部横条那几条留黑边（和 iOS Safari 不声明 viewport-fit=cover 时的效果一样），游戏里的界面因此全在安全区内。
 *      做法：改写 window.innerWidth / innerHeight（Godot 的 canvas_resize_policy=2 按它们定画布尺寸），画布 CSS 定位到安全区，
 *      再派一次 resize 让引擎重排；触点坐标 Godot 按画布 getBoundingClientRect 换算，不受影响。
 *   3. 回调 changedFields 含 viewport / safeArea / orientation 时重新布局。
 *   4. 1.5 秒内收不到回调（旧客户端不通知）：回退 CSS env(safe-area-inset-*)，同样按安全区留边。
 * window.__syToyBoot()：已有 window.toy 时手动启动（本地 mock 测试用：先在页面里装假 window.toy，再调它）。
 * window.__sySafe：当前生效的安全边距 {left, top, right, bottom, source}，给测试与 Godot 侧查看。
 * window.__syToyWait()：Promise，SDK 加载结束（成功 / 失败 / 8 秒超时 / 非 B站环境）后给出 window.toy 或 null；
 *   页面里已有 window.toy（本地 mock）时立刻给出。云存档（cloud.js）用它判断要不要启用。
 */
(function () {
  var SDK = "//s1.hdslb.com/bfs/seed/toy/app/sdk/toy-sdk.js";
  var started = false;
  var frame = null;          // {vw, vh, l, t, r, b}：当前画布框（CSS px）
  var innerW = null, innerH = null;
  var toySettled = false, toyWaiters = [];

  function settleToy() {
    if (toySettled) return;
    toySettled = true;
    var w = toyWaiters.splice(0);
    for (var i = 0; i < w.length; i++) w[i](window.toy || null);
  }
  window.__syToyWait = function () {
    return new Promise(function (res) {
      if (window.toy || toySettled) res(window.toy || null);
      else toyWaiters.push(res);
    });
  };

  function realW() { return innerW ? innerW.call(window) : document.documentElement.clientWidth; }
  function realH() { return innerH ? innerH.call(window) : document.documentElement.clientHeight; }

  function n(v) { v = Number(v); return isFinite(v) && v > 0 ? v : 0; }

  // 画布框：vw / vh 为容器可用尺寸（缺省按浏览器真实尺寸），l t r b 为安全边距
  function applyFrame(vw, vh, ins, source) {
    var l = n(ins.left), t = n(ins.top), r = n(ins.right), b = n(ins.bottom);
    frame = { vw: n(vw), vh: n(vh), l: l, t: t, r: r, b: b };
    window.__sySafe = { left: l, top: t, right: r, bottom: b, source: source };
    if (!innerW) {
      try {
        var dw = Object.getOwnPropertyDescriptor(window, "innerWidth") || Object.getOwnPropertyDescriptor(Window.prototype, "innerWidth");
        var dh = Object.getOwnPropertyDescriptor(window, "innerHeight") || Object.getOwnPropertyDescriptor(Window.prototype, "innerHeight");
        innerW = dw && dw.get; innerH = dh && dh.get;
        Object.defineProperty(window, "innerWidth", { configurable: true, get: function () {
          return frame ? Math.max(1, Math.floor((frame.vw || realW()) - frame.l - frame.r)) : realW(); } });
        Object.defineProperty(window, "innerHeight", { configurable: true, get: function () {
          return frame ? Math.max(1, Math.floor((frame.vh || realH()) - frame.t - frame.b)) : realH(); } });
      } catch (e) { return; }
    }
    var c = document.getElementById("canvas");
    if (c) { c.style.position = "fixed"; c.style.left = l + "px"; c.style.top = t + "px"; }
    document.body.style.background = "#000";
    window.dispatchEvent(new Event("resize"));
  }

  function envInsets() {
    var d = document.createElement("div");
    d.style.cssText = "position:fixed;visibility:hidden;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)";
    document.body.appendChild(d);
    var s = getComputedStyle(d);
    var r = { top: parseFloat(s.paddingTop), right: parseFloat(s.paddingRight), bottom: parseFloat(s.paddingBottom), left: parseFloat(s.paddingLeft) };
    d.remove();
    return r;
  }

  function boot() {
    var toy = window.toy;
    if (started || !toy || typeof toy.isSupport !== "function") return;
    if (!document.body) { document.addEventListener("DOMContentLoaded", boot); return; }
    started = true;
    var got = false;
    Promise.resolve(toy.isSupport("onContainerChange")).then(function (ok) {
      if (!ok) return;   // Web 端：容器接口不可用，保持浏览器自己的布局
      // 沉浸后让 env() 能读到刘海边距（回退路径用）
      var m = document.querySelector('meta[name="viewport"]');
      if (m && m.content.indexOf("viewport-fit") < 0) m.content += ", viewport-fit=cover";
      try {
        toy.onContainerChange(function (st) {
          if (!st) return;
          var first = !got;
          got = true;
          var ch = st.changedFields || [];
          if (first || ch.indexOf("viewport") >= 0 || ch.indexOf("safeArea") >= 0 || ch.indexOf("orientation") >= 0 || ch.indexOf("immersive") >= 0) {
            var vp = st.viewport || {};
            applyFrame(vp.width, vp.height, st.safeArea || {}, "toy");
          }
        });
      } catch (e) { started = false; return; }
      Promise.resolve().then(function () {
        return toy.setContainerMode({ orientation: "landscape", immersive: true });   // 手机：横屏必须同时沉浸
      }).catch(function () {});
      setTimeout(function () {
        if (!got) applyFrame(0, 0, envInsets(), "env");   // 旧客户端不通知容器状态：按 CSS 安全边距留边
      }, 1500);
    }).catch(function () { started = false; });
  }
  window.__syToyBoot = boot;

  var likely = /bilibili|hdslb/i.test(location.hostname) || /bili/i.test(navigator.userAgent);
  if (!likely) { settleToy(); return; }
  var s = document.createElement("script");
  s.src = SDK;
  s.async = true;
  s.onload = function () { settleToy(); boot(); };
  s.onerror = settleToy;
  setTimeout(settleToy, 8000);
  document.head.appendChild(s);
})();
