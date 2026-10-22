/* 假 window.toy（只测云存档 / 容器桥，不进发布包；tools/web_cloud_mock.py 注入到 index.html 的 <head> 最前面，docs/89 §测试、docs/22「Toy 接入」）
 * 云存档：云端数据存在 web_cloud_mock.py 进程内存里，两个端口（= 两台「设备」，各自的 IndexedDB 本地存档）共用同一份。
 *   服务端按当前模式模拟：未登录（reject 未登录错误）、reject（一般错误）、307044 限流（接下来 N 次请求）。
 *   同时按平台限制校验 setCloudStorage：key [A-Za-z0-9_-] ≤ 128 字节、不以 __ 开头、value 字符串 ≤ 1024 字节、总 key ≤ 128。
 * 容器（网址带 ?toyc=phone | tablet | desktop 时才开，模拟 B站 App 内）：isSupport('onContainerChange' / 'getContainerState' / 'setContainerMode') 为真；
 *   状态 = {deviceType, viewport: 浏览器可用尺寸, safeArea: 手机横屏左右 44 / 下 21、其余 0, orientation, immersive, changedFields}，
 *   phone 时另带 capsule（右上角 88×32 的顶栏胶囊，相对 viewport），用来验证 Godot 侧把胶囊下沿当额外顶部边距；
 *   setContainerMode 收下方向 / 沉浸后异步回一次 onContainerChange（changedFields 标出变化字段）；窗口 resize 也回一次（viewport 变化）。
 *   ?toyc=old：有 SDK、isSupport 都为真、但永不回调（旧客户端），验证 1.5 秒 env() 回退。
 */
(function () {
  function post(path, body) {
    return fetch("/__mock/" + path, { method: "POST", body: JSON.stringify(body || {}) }).then(function (r) { return r.json(); }).then(function (r) {
      if (!r.ok) {
        var e = new Error("[ToySDK] " + (r.err.message || "error"));
        e.type = r.err.type;
        e.code = r.err.code;
        throw e;
      }
      return r.data;
    });
  }
  var m = /[?&]toyc=([a-z]+)/.exec(location.search);
  var dev = m ? m[1] : "";
  var old = dev === "old";
  var cont = !!dev;
  // 容器可用尺寸用文档根元素的尺寸：container.js 会改写 innerWidth / innerHeight（画布尺寸），不能拿它们当容器尺寸
  function vw() { return document.documentElement.clientWidth; }
  function vh() { return document.documentElement.clientHeight; }
  var mode = { orientation: vw() >= vh() ? "landscape" : "portrait", immersive: false };
  var subs = [];
  function state(changed) {
    var phone = dev === "phone";
    var land = mode.orientation !== "portrait";
    var sa = phone && land ? { left: 44, top: 0, right: 44, bottom: 21 } : (phone ? { left: 0, top: 47, right: 0, bottom: 34 } : { left: 0, top: 0, right: 0, bottom: 0 });
    var st = { deviceType: dev === "old" ? "phone" : dev, viewport: { width: vw(), height: vh() }, safeArea: sa,
      orientation: mode.orientation, immersive: mode.immersive, changedFields: changed || [] };
    if (phone && mode.immersive) st.capsule = { x: vw() - sa.right - 8 - 88, y: 8, width: 88, height: 32 };
    return st;
  }
  function notify(changed) {
    if (old) return;
    var st = state(changed);
    subs.slice().forEach(function (f) { try { f(st); } catch (e) {} });
  }
  window.toy = {
    __mock: true,
    isSupport: function (a) {
      var ok = ["getCloudStorage", "setCloudStorage", "removeCloudStorage"].indexOf(a) >= 0 ||
        (cont && ["onContainerChange", "getContainerState", "setContainerMode"].indexOf(a) >= 0);
      return Promise.resolve(ok);
    },
    getCloudStorage: function (keys) { return post("get", { keys: keys || null }); },
    setCloudStorage: function (items) { return post("set", { items: items }); },
    removeCloudStorage: function (keys) { return post("remove", { keys: keys }); },
    getUserProfile: function () { return Promise.reject(new Error("[ToySDK] mock: getUserProfile 不应被调用")); },
    onContainerChange: function (f) {
      if (!cont) throw new Error("[ToySDK] unsupported");
      subs.push(f);
      setTimeout(function () { if (!old) { try { f(state([])); } catch (e) {} } }, 30);
      return function () { var i = subs.indexOf(f); if (i >= 0) subs.splice(i, 1); };
    },
    getContainerState: function () {
      if (!cont) return Promise.reject(new Error("[ToySDK] unsupported"));
      if (old) return new Promise(function () {});   // 旧客户端：永不回
      return Promise.resolve(state([]));
    },
    setContainerMode: function (req) {
      if (!cont) return Promise.reject(new Error("[ToySDK] unsupported"));
      req = req || {};
      var ch = [];
      if (req.orientation !== undefined && req.orientation !== mode.orientation) { mode.orientation = req.orientation; ch.push("orientation"); }
      if (req.immersive !== undefined && req.immersive !== mode.immersive) { mode.immersive = req.immersive; ch.push("immersive"); }
      if (!ch.length) return Promise.reject(Object.assign(new Error("[ToySDK] invalid_param"), { type: "invalid_param" }));
      setTimeout(function () { notify(ch.concat(dev === "phone" ? ["safeArea"] : [])); }, 120);
      return Promise.resolve();
    }
  };
  var last = vw() + "x" + vh();
  if (cont) window.addEventListener("resize", function () {   // container.js 自己也派 resize：只有容器尺寸真变了才通知
    var now = vw() + "x" + vh();
    if (now !== last) { last = now; notify(["viewport"]); }
  });
})();
