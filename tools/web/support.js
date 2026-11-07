/* B站 Toy「支持作者」奖励的网页端薄封装（tools/export_web.py 接在 share.js 之后内联进 index.html；docs/313，用户 11-07 定）
 *
 * Godot 侧 game/scripts/screens/support_view.gd 经 JavaScriptBridge.get_interface("__sySupport") 调用，Promise → 回调（参数都是字符串）：
 *   check(kind, bvid, cb)   kind = "follow"：toy.getAuthorRelation()，看是否已关注当前 Toy 作者
 *                           kind = "triple"：toy.getVideoUserActions({ videos: [{ bvid }] })，看是否点赞 + 投币 + 收藏
 *                           一律先 toy.isSupport；cb(结果, 详情)：
 *                             "yes"          条件满足
 *                             "no"           没满足（triple 的详情 = 缺的几项，逗号分隔：like,coin,fav）
 *                             "unsupported"  外部浏览器 / 旧客户端（平台说明：引导去 B站 App 打开）
 *                             "login"        没登录
 *                             "err"          其他错误（网络、限流……）
 * 返回结构的字段名按 SDK 文档与常见写法兼容着读（status / data / result 包一层与否都认）；读不出关注状态时按 "err" 处理，不误发奖励也不误报「没关注」。
 * 只读互动状态：不读 toyOpenId、不上传、不打日志。非 B站环境（itch、普通浏览器）：window.toy 不存在，check 回 "unsupported"。
 */
(function () {
  function waitToy() {
    if (typeof window.__syToyWait === "function") return window.__syToyWait();
    return Promise.resolve(window.toy || null);
  }
  function call(cb, a, b) {
    try { cb(a, b || ""); } catch (x) {}
  }
  function sup(toy, name) {
    if (!toy || typeof toy.isSupport !== "function") return Promise.resolve(false);
    return Promise.resolve().then(function () { return toy.isSupport(name); }).then(function (r) { return !!r; }, function () { return false; });
  }
  function errKind(e) {
    var s = String((e && (e.type || e.code || e.message)) || "") + " " + String((e && e.message) || "");
    if (/unsupported/i.test(s)) return "unsupported";
    if (/login|未登录|not.?logged/i.test(s)) return "login";
    return "err";
  }
  function statusKind(st) {
    st = String(st || "").toLowerCase();
    if (!st || st === "ok" || st === "success") return "";
    if (st.indexOf("unsupported") >= 0) return "unsupported";
    if (st.indexOf("login") >= 0) return "login";
    return "err";
  }
  function unwrap(r) {
    if (r && typeof r === "object" && r.data && typeof r.data === "object") return r.data;
    if (r && typeof r === "object" && r.result && typeof r.result === "object") return r.result;
    return r || {};
  }
  function truthy(v) {
    return v === true || v === 1 || v === "1" || v === "true";
  }
  // 关注状态：is_follow / isFollow / following / follow / attention / relation.following 任一字段
  function followed(d) {
    var keys = ["isFollow", "is_follow", "following", "isFollowing", "follow", "followed", "attention", "attentioned"];
    for (var i = 0; i < keys.length; i++) if (d && d[keys[i]] !== undefined) return truthy(d[keys[i]]) ? "yes" : "no";
    if (d && d.relation && typeof d.relation === "object") return followed(d.relation);
    return "err";
  }
  function relation(toy) {
    return Promise.resolve().then(function () { return toy.getAuthorRelation(); }).then(function (r) {
      var k = statusKind(r && r.status);
      return k ? [k, ""] : [followed(unwrap(r)), ""];
    });
  }
  function triple(toy, bvid) {
    return Promise.resolve().then(function () { return toy.getVideoUserActions({ videos: [{ bvid: bvid }] }); }).then(function (r) {
      var k = statusKind(r && r.status);
      if (k) return [k, ""];
      var d = unwrap(r);
      var items = (d && d.items) || (r && r.items) || [];
      var it = null;
      for (var i = 0; i < items.length; i++) {
        var x = items[i] || {};
        if (String(x.bvid || (x.ref && x.ref.bvid) || "") === bvid) { it = x; break; }
      }
      if (!it) it = items[0];
      if (!it) return ["err", ""];
      var ik = statusKind(it.status);
      if (ik) return [ik, ""];
      var miss = [];
      if (!truthy(it.liked) && !truthy(it.like)) miss.push("like");
      if (!(Number(it.coinCount || it.coin_count || 0) > 0)) miss.push("coin");
      if (!truthy(it.favorited) && !truthy(it.favoured) && !truthy(it.favorite)) miss.push("fav");
      return miss.length ? ["no", miss.join(",")] : ["yes", ""];
    });
  }

  window.__sySupport = {
    check: function (kind, bvid, cb) {
      var ability = kind === "triple" ? "getVideoUserActions" : "getAuthorRelation";
      waitToy().then(function (toy) {
        if (!toy) return ["unsupported", ""];
        return sup(toy, ability).then(function (ok) {
          if (!ok) return ["unsupported", ""];
          return kind === "triple" ? triple(toy, String(bvid || "")) : relation(toy);
        });
      }).then(function (r) { call(cb, r[0], r[1]); }, function (e) { call(cb, errKind(e), ""); });
    },
  };
})();
