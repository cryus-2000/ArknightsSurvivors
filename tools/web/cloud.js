/* B站 Toy 云存档的网页端薄封装（tools/export_web.py 接在 container.js 之后内联进 index.html；docs/89）
 *
 * Godot 侧 game/scripts/cloud_save.gd 经 JavaScriptBridge.get_interface("__syCloud") 调用，Promise → 回调（参数都是字符串）：
 *   probe(cb)          等 Toy SDK 加载结束（container.js 的 window.__syToyWait），cb("supported" | "unsupported")：
 *                      只看 toy.isSupport('getCloudStorage' / 'setCloudStorage')，不调 getUserProfile、不读 toyOpenId
 *   read(cb)           toy.getCloudStorage()（不带 key = 读全部，一次请求）→ cb("ok", JSON 串) / cb("err", 错误 JSON)
 *   write(json, cb)    toy.setCloudStorage(items)（一次请求带全部分片）→ cb("ok", "") / cb("err", 错误 JSON)
 *   stage(json)        存下最新打包好的内容（空串 = 清掉）；页面隐藏（visibilitychange hidden / pagehide）时这里自己上传一次，
 *                      不经过 Godot（那时引擎可能已经停帧）。成功后清掉，Godot 下次同步时读云端比对即可。
 * 错误 JSON：{code, type, msg}（SDK 的 error.code / error.type / message；307044 = 限流）。
 * 非 B站环境（itch、普通浏览器）：window.toy 不存在，probe 回 "unsupported"，Godot 侧什么都不做。
 */
(function () {
  var staged = "";
  var busy = 0;

  function waitToy() {
    if (typeof window.__syToyWait === "function") return window.__syToyWait();
    return Promise.resolve(window.toy || null);
  }
  function errJson(e) {
    var o = { code: 0, type: "", msg: "" };
    try {
      if (e && typeof e === "object") {
        o.code = Number(e.code) || 0;
        o.type = String(e.type || "");
        o.msg = String(e.message || e.msg || "");
      } else {
        o.msg = String(e);
      }
    } catch (x) {}
    return JSON.stringify(o);
  }
  function call(cb, a, b) {
    try { cb(a, b); } catch (x) {}
  }

  function flushHidden() {
    var toy = window.toy;
    if (!staged || busy || !toy || typeof toy.setCloudStorage !== "function") return;
    var json = staged;
    var items;
    try { items = JSON.parse(json); } catch (x) { staged = ""; return; }
    busy++;
    Promise.resolve().then(function () { return toy.setCloudStorage(items); }).then(function () {
      if (staged === json) staged = "";
    }).catch(function () {}).then(function () { busy--; });
  }

  window.__syCloud = {
    probe: function (cb) {
      waitToy().then(function (toy) {
        if (!toy || typeof toy.isSupport !== "function") return "unsupported";
        return Promise.all([toy.isSupport("getCloudStorage"), toy.isSupport("setCloudStorage")]).then(function (r) {
          return r[0] && r[1] ? "supported" : "unsupported";
        });
      }).catch(function () { return "unsupported"; }).then(function (r) { call(cb, r, ""); });
    },
    read: function (cb) {
      busy++;
      Promise.resolve().then(function () { return window.toy.getCloudStorage(); }).then(function (r) {
        busy--;
        call(cb, "ok", JSON.stringify(r || {}));
      }, function (e) {
        busy--;
        call(cb, "err", errJson(e));
      });
    },
    write: function (json, cb) {
      busy++;
      Promise.resolve().then(function () { return window.toy.setCloudStorage(JSON.parse(json)); }).then(function () {
        busy--;
        if (staged === json) staged = "";
        call(cb, "ok", "");
      }, function (e) {
        busy--;
        call(cb, "err", errJson(e));
      });
    },
    stage: function (json) { staged = json ? String(json) : ""; },
    staged: function () { return staged; }
  };

  document.addEventListener("visibilitychange", function () {
    if (document.visibilityState === "hidden") flushHidden();
  });
  window.addEventListener("pagehide", flushHidden);
})();
