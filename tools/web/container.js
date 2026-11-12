/* 网页容器适配（tools/export_web.py 内联进 index.html 的 <head>，在 loader.js 之后；docs/22「B站 Toy 容器」「Toy 接入」）
 *
 * 何时加载 Toy JS SDK：
 *   - Toy 包（export_web.py --toy 在本文件之前写 window.__SY_TOY = 1）：一律加载；
 *   - 其他包（itch / 本地）：只在像是 B站环境（域名含 bilibili / hdslb，或 UA 含 Bili）时加载；
 *   - 加载失败 / 8 秒超时 / 非 B站环境：一切照旧（浏览器自己的布局，云存档 probe 回 unsupported）。
 *
 * 画布与安全区（11-13 改版，iPhone 17 B站 App 横屏：顶部露白边、左侧灵动岛压字、经验条悬空，docs/22「Toy 接入」）：
 *   - 画布一律铺满整个窗口（不再改写 innerWidth / innerHeight、不再把画布缩进安全区），世界画面铺满全屏；
 *     安全边距写进 window.__sySafe，Godot 侧 Cfg.safe_insets / hud_ins 读它，只让界面内缩。
 *   - 所有包都声明 viewport-fit=cover（iOS 上 env() 才有值，画布才铺满刘海那一侧），加 theme-color 深色；html / body 底色深色（loader.css）。
 *   - 安全边距逐边取大：B站 App 容器状态 safeArea（CSS px）与 CSS env(safe-area-inset-*)；
 *     容器回的 safeArea 像是竖屏的值（横屏却只有 top、左右为 0）时按转过 90° 处理（source = toy-rot）；
 *     iPhone 横屏两边都是 0 而屏幕比例 ≥ 2（刘海 / 灵动岛机型）时按 59 / 0 / 59 / 21 估（source = guess）。
 *   - 窗口 resize、转屏、visualViewport 变化、容器状态变化时重新算（转屏后 env() 要晚一点才更新，300 ms 后再算一次）。
 * SDK 在时：
 *   1. 先 toy.onContainerChange 监听，再 toy.setContainerMode({orientation:'landscape', immersive:true})（手机横屏必须同时沉浸）；
 *      setContainerMode 的 Promise 不算成功，以回调里的状态为准；手机回调里仍不是沉浸横屏时最多再请求 2 次。
 *      onContainerChange 不支持、setContainerMode 支持的客户端照样请求一次。
 *   2. 回调 changedFields 含 viewport / safeArea / orientation / immersive / deviceType 时重新算。
 *   3. 1.5 秒内收不到回调（旧客户端不通知）：试读一次 getContainerState，再不行只用 env()。
 *   4. 沉浸模式下的顶栏胶囊：从容器状态里找 capsule / menuButton / menuButtonRect / topBar / navBar 之类的矩形字段
 *      （{x|left, y|top, width, height}，CSS px，相对 viewport）；找不到时按 iPhone 实测估（guessCapsule，docs/318），写进 __sySafe.capsule。
 * 诊断浮层：网址带 sydiag，或四指同时点屏幕，左上角显示一块半透明文字（窗口 / visualViewport / screen / 画布 / env / 容器状态 / 最终安全边距），再四指点一次关掉。
 * window.__syToyBoot()：已有 window.toy 时手动启动（本地 mock 测试用：先在页面里装假 window.toy，再调它）。
 * window.__sySafe：当前生效的安全边距 {left, top, right, bottom, source, capsule{x,y,w,h}}（CSS px，相对画布 = 整个窗口），Godot 侧 Cfg 读它。
 * window.__syToyEnv：{rev, sdk, container, deviceType, orientation, immersive, viewport{w,h}, safeArea{l,t,r,b}, capsule, source, why}
 *   rev 每次变化 +1；sdk = window.toy 是否存在；container = 是否拿到过容器状态（只在 B站 App 内）。
 * window.__syToy：给 Godot 的桥（JavaScriptBridge.get_interface("__syToy")，参数 / 返回都是字符串）：
 *   env()        → JSON.stringify(__syToyEnv)
 *   onchange(cb) 注册回调；环境每次变化 cb(JSON)，注册时若已有状态立刻回一次
 * window.__syToyWait()：Promise，SDK 加载结束（成功 / 失败 / 8 秒超时 / 非 B站环境）后给出 window.toy 或 null；
 *   页面里已有 window.toy（本地 mock）时立刻给出。云存档（cloud.js）用它判断要不要启用。
 */
(function () {
  var SDK = "//s1.hdslb.com/bfs/seed/toy/app/sdk/toy-sdk.js";
  var started = false;
  var last = null;           // 最近一次容器状态（没有为 null）
  var modeTries = 0;
  var toySettled = false, toyWaiters = [];
  var env = { rev: 0, sdk: false, container: false, deviceType: "unknown", orientation: "", immersive: false,
    viewport: null, safeArea: null, capsule: null, source: "none", why: "" };
  var listeners = [];
  window.__syToyEnv = env;

  function emit() {
    env.rev++;
    env.sdk = !!window.toy;
    var s;
    try { s = JSON.stringify(env); } catch (e) { return; }
    for (var i = 0; i < listeners.length; i++) { try { listeners[i](s); } catch (e2) {} }
  }
  window.__syToy = {
    env: function () { try { env.sdk = !!window.toy; return JSON.stringify(env); } catch (e) { return "null"; } },
    onchange: function (cb) {
      if (typeof cb !== "function") return;
      listeners.push(cb);
      if (env.rev > 0) { try { cb(JSON.stringify(env)); } catch (e) {} }
    }
  };

  function settleToy() {
    if (toySettled) return;
    toySettled = true;
    env.sdk = !!window.toy;
    emit();
    var w = toyWaiters.splice(0);
    for (var i = 0; i < w.length; i++) w[i](window.toy || null);
  }
  window.__syToyWait = function () {
    return new Promise(function (res) {
      if (window.toy || toySettled) res(window.toy || null);
      else toyWaiters.push(res);
    });
  };

  function realW() { return window.innerWidth || document.documentElement.clientWidth; }
  function realH() { return window.innerHeight || document.documentElement.clientHeight; }
  function n(v) { v = Number(v); return isFinite(v) && v > 0 ? v : 0; }

  // 从容器状态里找胶囊矩形（兼容几种可能的字段名 / 形状），返回 {x, y, w, h}（CSS px，相对 viewport）或 null
  function findCapsule(st) {
    var names = ["capsule", "capsuleRect", "menuButton", "menuButtonRect", "menuButtonBoundingClientRect", "topBar", "navBar", "navigationBar"];
    for (var i = 0; i < names.length; i++) {
      var r = st[names[i]];
      if (!r || typeof r !== "object") continue;
      var x = Number(r.x != null ? r.x : r.left), y = Number(r.y != null ? r.y : r.top);
      var w = Number(r.width != null ? r.width : (r.right != null ? r.right - x : NaN));
      var h = Number(r.height != null ? r.height : (r.bottom != null ? r.bottom - y : NaN));
      if (isFinite(x) && isFinite(y) && isFinite(w) && isFinite(h) && w > 0 && h > 0) return { x: x, y: y, w: w, h: h };
    }
    return null;
  }

  // 状态里没有胶囊字段时（11-08 实测：SDK 文档与真机回调都没给矩形）按 B站 App iPhone 沉浸横屏截图估（docs/318）：
  // 胶囊（分享 | 关闭）约宽 82、高 31，右沿离安全区右沿约 12，上沿离顶约 11（CSS px）；外扩成安全区右上 108 × 46 的禁区（viewport 坐标）。
  // 只在手机 / 平板沉浸模式下估；桌面 / 非沉浸（App 自己的顶栏不压网页）不估
  function guessCapsule(st, right) {
    if (!st || !st.immersive || st.deviceType === "desktop") return null;
    return { x: realW() - right - 108, y: 0, w: 108, h: 46, guess: true };
  }

  function envInsets() {
    var r = { top: 0, right: 0, bottom: 0, left: 0 };
    if (!document.body) return r;
    var d = document.createElement("div");
    d.style.cssText = "position:fixed;visibility:hidden;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)";
    document.body.appendChild(d);
    var s = getComputedStyle(d);
    r = { top: n(parseFloat(s.paddingTop)), right: n(parseFloat(s.paddingRight)), bottom: n(parseFloat(s.paddingBottom)), left: n(parseFloat(s.paddingLeft)) };
    d.remove();
    return r;
  }

  // 容器 safeArea 规整：横屏时只有 top（左右都是 0）像是竖屏的值，按转过 90° 处理（刘海 / 灵动岛转到左右，下边只剩横条）
  function sdkInsets(st) {
    var sa = (st && st.safeArea) || {};
    var r = { left: n(sa.left), top: n(sa.top), right: n(sa.right), bottom: n(sa.bottom) };
    if (realW() > realH() && r.top > 0 && !r.left && !r.right) {
      r = { left: r.top, top: 0, right: r.top, bottom: Math.min(r.bottom, 21), rotated: true };
    }
    return r;
  }

  var IOS = /iPhone|iPod/.test(navigator.userAgent);

  function relayout(why) {
    var e = envInsets(), s = last ? sdkInsets(last) : { left: 0, top: 0, right: 0, bottom: 0 };
    var l = Math.max(e.left, s.left), t = Math.max(e.top, s.top), r = Math.max(e.right, s.right), b = Math.max(e.bottom, s.bottom);
    var source = last ? (s.rotated ? "toy-rot" : "toy") : "env";
    var w = realW(), h = realH();
    if (!l && !r && IOS && w > h && w / Math.max(1, h) >= 2.0) {
      l = r = 59; b = Math.max(b, 21); source = "guess";   // 刘海 / 灵动岛 iPhone 横屏（各机型 44–62，取 59），底部横条 21
    }
    var cap = last ? (findCapsule(last) || guessCapsule(last, r)) : null;
    if (cap && !(cap.x < w && cap.y < h && cap.x + cap.w > 0 && cap.y + cap.h > 0)) cap = null;
    var prev = window.__sySafe;
    var cur = { left: l, top: t, right: r, bottom: b, source: source, capsule: cap ? { x: cap.x, y: cap.y, w: cap.w, h: cap.h } : null };
    window.__sySafe = cur;
    env.safeArea = { l: l, t: t, r: r, b: b };
    env.viewport = { w: w, h: h };
    env.capsule = cur.capsule;
    env.source = source;
    env.why = why || "";
    diag();
    if (!prev || JSON.stringify(prev) !== JSON.stringify(cur)) emit();
  }

  var relayTimer = 0;
  function relaySoon(why) {
    relayout(why);
    clearTimeout(relayTimer);
    relayTimer = setTimeout(function () { relayout(why + "+300"); }, 300);   // 转屏后 env() / innerWidth 要晚一点才更新
  }

  function setViewportMeta() {
    var m = document.querySelector('meta[name="viewport"]');
    if (!m) { m = document.createElement("meta"); m.name = "viewport"; m.content = "width=device-width, initial-scale=1.0"; document.head.appendChild(m); }
    if (m.content.indexOf("viewport-fit") < 0) m.content += ", viewport-fit=cover";
    if (!document.querySelector('meta[name="theme-color"]')) {
      var tc = document.createElement("meta"); tc.name = "theme-color"; tc.content = "#04070a"; document.head.appendChild(tc);
    }
  }

  // 诊断浮层（网址带 sydiag 或四指点屏）
  var diagOn = /[?&#]sydiag/.test(location.href), diagEl = null;
  function diag() {
    if (!diagOn) { if (diagEl) diagEl.style.display = "none"; return; }
    if (!document.body) return;
    if (!diagEl) {
      diagEl = document.createElement("pre");
      diagEl.style.cssText = "position:fixed;left:70px;top:8px;z-index:99999;margin:0;padding:6px 8px;background:rgba(0,0,0,.72);color:#9fe;font:10px/1.35 monospace;pointer-events:none;white-space:pre-wrap;max-width:60vw";
      document.body.appendChild(diagEl);
    }
    diagEl.style.display = "block";
    var vv = window.visualViewport, S = window.__sySafe || {}, e = envInsets();
    var cv = document.getElementById("canvas"), cr = cv ? cv.getBoundingClientRect() : null;
    diagEl.textContent = [
      "inner " + realW() + "x" + realH() + "  client " + document.documentElement.clientWidth + "x" + document.documentElement.clientHeight + "  dpr " + devicePixelRatio,
      "vv " + (vv ? Math.round(vv.width) + "x" + Math.round(vv.height) + " @" + Math.round(vv.offsetLeft) + "," + Math.round(vv.offsetTop) + " s" + vv.scale : "-") + "  scroll " + scrollX + "," + scrollY,
      "screen " + screen.width + "x" + screen.height + "  canvas " + (cr ? Math.round(cr.left) + "," + Math.round(cr.top) + " " + Math.round(cr.width) + "x" + Math.round(cr.height) : "-"),
      "env l" + e.left + " t" + e.top + " r" + e.right + " b" + e.bottom,
      "toy " + (last ? JSON.stringify({ d: last.deviceType, o: last.orientation, im: last.immersive, vp: last.viewport, sa: last.safeArea }) : "none") + "  sdk " + !!window.toy,
      "safe l" + S.left + " t" + S.top + " r" + S.right + " b" + S.bottom + " " + S.source + (S.capsule ? " cap " + Math.round(S.capsule.x) + "," + Math.round(S.capsule.y) + " " + S.capsule.w + "x" + S.capsule.h : "") + "  " + (env.why || "")
    ].join("\n");
  }

  function takeState(st) {
    env.container = true;
    last = st;
    if (st.deviceType) env.deviceType = String(st.deviceType);
    if (st.orientation) env.orientation = String(st.orientation);
    if (typeof st.immersive === "boolean") env.immersive = st.immersive;
    relaySoon("toy");
  }

  function boot() {
    var toy = window.toy;
    if (started || !toy || typeof toy.isSupport !== "function") return;
    if (!document.body) { document.addEventListener("DOMContentLoaded", boot); return; }
    started = true;
    var got = false;
    function askMode() {
      Promise.resolve().then(function () {
        return toy.setContainerMode({ orientation: "landscape", immersive: true });   // 手机：横屏必须同时沉浸
      }).catch(function () {});
    }
    Promise.resolve(toy.isSupport("onContainerChange")).then(function (ok) {
      if (!ok) {
        // Web 端：容器接口都不可用，布局按 env()；只有 setContainerMode 可用的客户端照样请求横屏沉浸
        Promise.resolve(toy.isSupport("setContainerMode")).then(function (ok2) { if (ok2) askMode(); }).catch(function () {});
        return;
      }
      try {
        toy.onContainerChange(function (st) {
          if (!st) return;
          var first = !got;
          got = true;
          var ch = st.changedFields || [];
          if (first || ch.indexOf("viewport") >= 0 || ch.indexOf("safeArea") >= 0 || ch.indexOf("orientation") >= 0 || ch.indexOf("immersive") >= 0 || ch.indexOf("deviceType") >= 0) {
            takeState(st);
          }
          // 手机回调里仍不是沉浸横屏（11-13 截图顶部露出一条 App 底色，疑似没进沉浸）：再请求，最多 2 次
          if (st.deviceType === "phone" && (st.orientation !== "landscape" || st.immersive !== true) && modeTries < 2) {
            modeTries++;
            setTimeout(askMode, 400);
          }
        });
      } catch (e) { started = false; return; }
      askMode();
      setTimeout(function () {
        if (got) return;
        // 旧客户端不通知容器状态：先试读一次，再不行只用 env()
        Promise.resolve(typeof toy.getContainerState === "function" ? toy.getContainerState() : null).then(function (st) {
          if (got) return;
          if (st && st.viewport) { got = true; takeState(st); }
          else relaySoon("env");
        }).catch(function () { if (!got) relaySoon("env"); });
      }, 1500);
    }).catch(function () { started = false; });
  }
  window.__syToyBoot = boot;

  // 所有包：声明 viewport-fit=cover，尺寸变化时重算安全边距
  setViewportMeta();
  function onResize() { relaySoon("resize"); }
  window.addEventListener("resize", onResize);
  window.addEventListener("orientationchange", onResize);
  if (window.visualViewport) window.visualViewport.addEventListener("resize", onResize);
  if (document.body) relaySoon("init"); else document.addEventListener("DOMContentLoaded", function () { relaySoon("init"); });
  document.addEventListener("touchstart", function (ev) {
    if (ev.touches && ev.touches.length >= 4) { diagOn = !diagOn; diag(); }
  }, { passive: true });

  if (window.toy) { settleToy(); boot(); return; }   // 页面里已有 window.toy（本地 mock，web_cloud_mock.py 注入）：不再加载 SDK（否则会被真 SDK 覆盖），直接启动
  var likely = !!window.__SY_TOY || /bilibili|hdslb/i.test(location.hostname) || /bili/i.test(navigator.userAgent);
  if (!likely) { settleToy(); return; }
  var s = document.createElement("script");
  s.src = SDK;
  s.async = true;
  s.onload = function () { settleToy(); boot(); };
  s.onerror = settleToy;
  setTimeout(settleToy, 8000);
  document.head.appendChild(s);
})();
