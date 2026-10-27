/* 战绩分享卡的网页端薄封装（tools/export_web.py 接在 cloud.js 之后内联进 index.html；10-28 用户定样式 B）
 *
 * Godot 侧 game/scripts/screens/share_toy.gd 经 JavaScriptBridge.get_interface("__syShare") 调用，Promise → 回调（参数都是字符串）：
 *   probe(cb)        等 Toy SDK 加载结束，cb(JSON {profile, qr, album})：只看 toy.isSupport，不调别的
 *   profile(cb)      toy.getUserProfile() → 头像图片在页面内转成 PNG base64 → cb("ok", JSON {nickname, avatar})；
 *                    toyOpenId 不读、不回传；头像昵称只给 Godot 在本地画卡，这里不上传、不打日志。失败 cb("err", "")
 *   qr(size, cb)     toy.getQrCode({ size }) → cb("ok", 纯 base64 PNG) / cb("err", "")
 *   save(b64, cb)    App 内 toy.saveImageToAlbum({ base64Data })；不支持时退回 <a download>（blob URL）。cb("album" | "download" | "err", "")
 * 非 B站环境（itch、普通浏览器）：window.toy 不存在，probe 全回 false；save 仍可走 <a download>。
 */
(function () {
  function waitToy() {
    if (typeof window.__syToyWait === "function") return window.__syToyWait();
    return Promise.resolve(window.toy || null);
  }
  function call(cb, a, b) {
    try { cb(a, b); } catch (x) {}
  }
  function sup(toy, name) {
    if (!toy || typeof toy.isSupport !== "function") return Promise.resolve(false);
    return Promise.resolve().then(function () { return toy.isSupport(name); }).then(function (r) { return !!r; }, function () { return false; });
  }
  function stripB64(s) {
    s = String(s || "");
    var i = s.indexOf("base64,");
    return i >= 0 ? s.substr(i + 7) : s;
  }
  // 头像 URL → PNG base64（跨域图要 crossOrigin；画不进画布就当没有头像）
  function avatarB64(url) {
    return new Promise(function (ok) {
      if (!url) return ok("");
      var img = new Image();
      img.crossOrigin = "anonymous";
      img.onload = function () {
        try {
          var c = document.createElement("canvas");
          c.width = 128; c.height = 128;
          c.getContext("2d").drawImage(img, 0, 0, 128, 128);
          ok(stripB64(c.toDataURL("image/png")));
        } catch (x) { ok(""); }
      };
      img.onerror = function () { ok(""); };
      img.src = url;
      setTimeout(function () { ok(""); }, 6000);
    });
  }
  function download(b64) {
    var bin = atob(b64), n = bin.length, u8 = new Uint8Array(n);
    for (var i = 0; i < n; i++) u8[i] = bin.charCodeAt(i);
    var url = URL.createObjectURL(new Blob([u8], { type: "image/png" }));
    var a = document.createElement("a");
    a.href = url;
    a.download = "方舟幸存者_战绩.png";
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 10000);
  }

  window.__syShare = {
    probe: function (cb) {
      waitToy().then(function (toy) {
        return Promise.all([sup(toy, "getUserProfile"), sup(toy, "getQrCode"), sup(toy, "saveImageToAlbum")]);
      }).catch(function () { return [false, false, false]; }).then(function (r) {
        call(cb, JSON.stringify({ profile: r[0], qr: r[1], album: r[2] }), "");
      });
    },
    profile: function (cb) {
      Promise.resolve().then(function () { return window.toy.getUserProfile(); }).then(function (p) {
        var nick = String((p && p.nickname) || "");
        return avatarB64(p && p.avatar).then(function (b64) {
          call(cb, "ok", JSON.stringify({ nickname: nick, avatar: b64 }));
        });
      }, function () { call(cb, "err", ""); });
    },
    qr: function (size, cb) {
      Promise.resolve().then(function () { return window.toy.getQrCode({ size: Math.max(80, Math.min(1024, Number(size) | 0)) }); }).then(function (r) {
        call(cb, "ok", stripB64(r && r.base64));
      }, function () { call(cb, "err", ""); });
    },
    save: function (b64, cb) {
      var toy = window.toy;
      sup(toy, "saveImageToAlbum").then(function (ok) {
        if (ok) {
          return toy.saveImageToAlbum({ base64Data: "data:image/png;base64," + b64, hintMsg: "保存战绩分享卡到相册" }).then(function () { call(cb, "album", ""); });
        }
        download(b64);
        call(cb, "download", "");
      }).catch(function () {
        try { download(b64); call(cb, "download", ""); } catch (x) { call(cb, "err", ""); }
      });
    },
  };
})();
