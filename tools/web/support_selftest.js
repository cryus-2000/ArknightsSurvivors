/* tools/web/support.js 的自测（docs/313）：node tools/web/support_selftest.js —— 用假 window.toy 模拟 SDK 返回，查 check() 的回调结果。
 * 覆盖：关注 yes / no、关注字段读不出 → err、三连 yes / 缺项 no、isSupport 为假 → unsupported、调用抛 [ToySDK] unsupported、未登录、没有 window.toy。
 * 全部通过打印 "SUPPORT JS failures=0"，退出码 0。
 */
const fs = require("fs");
const path = require("path");
const src = fs.readFileSync(path.join(__dirname, "support.js"), "utf8");

function load(toy) {
  const window = { toy: toy };
  new Function("window", src)(window);
  return window.__sySupport;
}
function check(api, kind, bvid) {
  return new Promise((ok) => api.check(kind, bvid, (a, b) => ok([a, b])));
}
const sup = (names) => (n) => Promise.resolve(names.indexOf(n) >= 0);
const ALL = ["getAuthorRelation", "getVideoUserActions"];
const BV = "BV1xx411c7mD";
const cases = [
  ["关注 yes", { isSupport: sup(ALL), getAuthorRelation: () => Promise.resolve({ status: "ok", data: { isFollow: true } }) }, "follow", ["yes", ""]],
  ["关注 no（不包 data）", { isSupport: sup(ALL), getAuthorRelation: () => Promise.resolve({ following: false }) }, "follow", ["no", ""]],
  ["关注字段读不出", { isSupport: sup(ALL), getAuthorRelation: () => Promise.resolve({ status: "ok", data: { medal: null } }) }, "follow", ["err", ""]],
  ["关注 status unsupported", { isSupport: sup(ALL), getAuthorRelation: () => Promise.resolve({ status: "unsupported" }) }, "follow", ["unsupported", ""]],
  ["三连 yes", { isSupport: sup(ALL), getVideoUserActions: () => Promise.resolve({ status: "ok", result: { items: [{ bvid: BV, status: "ok", liked: true, coinCount: 2, favorited: true }] } }) }, "triple", ["yes", ""]],
  ["三连缺投币收藏", { isSupport: sup(ALL), getVideoUserActions: () => Promise.resolve({ items: [{ ref: { bvid: BV }, liked: true, coinCount: 0, favorited: false }] }) }, "triple", ["no", "coin,fav"]],
  ["isSupport 为假", { isSupport: sup([]), getAuthorRelation: () => Promise.reject(new Error("不应调用")) }, "follow", ["unsupported", ""]],
  ["调用抛 unsupported", { isSupport: sup(ALL), getVideoUserActions: () => Promise.reject(Object.assign(new Error("[ToySDK] unsupported"), { type: "unsupported" })) }, "triple", ["unsupported", ""]],
  ["未登录", { isSupport: sup(ALL), getAuthorRelation: () => Promise.reject(new Error("[ToySDK] not logged in")) }, "follow", ["login", ""]],
  ["没有 window.toy", null, "follow", ["unsupported", ""]],
];
(async () => {
  let fails = 0;
  for (const [name, toy, kind, want] of cases) {
    const got = await check(load(toy), kind, BV);
    const okk = got[0] === want[0] && got[1] === want[1];
    if (!okk) fails++;
    console.log((okk ? "ok   " : "FAIL ") + name + " → " + JSON.stringify(got) + (okk ? "" : " 期望 " + JSON.stringify(want)));
  }
  console.log("SUPPORT JS failures=" + fails);
  process.exit(fails ? 1 : 0);
})();
