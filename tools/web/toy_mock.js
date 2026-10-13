/* 假 window.toy（只测云存档，不进发布包；tools/web_cloud_mock.py 注入到 index.html 的 <head> 最前面，docs/89 §测试）
 * 云端数据存在 web_cloud_mock.py 进程内存里，两个端口（= 两台「设备」，各自的 IndexedDB 本地存档）共用同一份。
 * 服务端按当前模式模拟：未登录（reject 未登录错误）、reject（一般错误）、307044 限流（接下来 N 次请求）。
 * 同时按平台限制校验 setCloudStorage：key [A-Za-z0-9_-] ≤ 128 字节、不以 __ 开头、value 字符串 ≤ 1024 字节、总 key ≤ 128。
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
  window.toy = {
    __mock: true,
    isSupport: function (a) {
      return Promise.resolve(["getCloudStorage", "setCloudStorage", "removeCloudStorage"].indexOf(a) >= 0);
    },
    getCloudStorage: function (keys) { return post("get", { keys: keys || null }); },
    setCloudStorage: function (items) { return post("set", { items: items }); },
    removeCloudStorage: function (keys) { return post("remove", { keys: keys }); },
    getUserProfile: function () { return Promise.reject(new Error("[ToySDK] mock: getUserProfile 不应被调用")); }
  };
})();
