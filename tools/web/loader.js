// 局间整页重载的「去哪一页」标记（core/run_reload.gd，docs/319 §14 / §21）：sessionStorage、localStorage、网址参数 syrl 三处都写，
// 读任意一处（取最新，3 分钟内有效）。B站 App 的 WebView 重载后 sessionStorage 不一定还在（11-09 真机：认知塑造重载后落在标题）
// 测试：网址带 nosess=1 时 sessionStorage 不可用（模拟 B站 App 容器，docs/319 §21）
try { if (/[?&]nosess=1/.test(location.search)) Object.defineProperty(window, 'sessionStorage', { get: function () { throw new Error('no sessionStorage'); } }); } catch (e) {}
window.__syRL = {
  KEY: 'sy_reload',
  peek: function () {
    var best = null, c = [];
    try { c.push(sessionStorage.getItem(this.KEY)); } catch (e) {}
    try { c.push(localStorage.getItem(this.KEY)); } catch (e) {}
    try { var q = new URLSearchParams(location.search).get('syrl'); if (q) c.push(decodeURIComponent(q)); } catch (e) {}
    for (var i = 0; i < c.length; i++) {
      try { var o = JSON.parse(c[i] || 'null'); if (o && o.act && (!best || Number(o.t || 0) > Number(best.t || 0))) best = o; } catch (e) {}
    }
    return best && Date.now() - Number(best.t || 0) < 180000 ? best : null;
  },
  take: function () {
    var o = this.peek();
    try { sessionStorage.removeItem(this.KEY); } catch (e) {}
    try { localStorage.removeItem(this.KEY); } catch (e) {}
    try {
      var u = new URL(location.href);
      if (u.searchParams.has('syrl') || u.searchParams.has('_rl')) { u.searchParams.delete('syrl'); u.searchParams.delete('_rl'); history.replaceState(null, '', u.toString()); }
    } catch (e) {}
    return o;
  },
  put: function (o) {
    o.t = Date.now();
    var j = JSON.stringify(o);
    try { sessionStorage.setItem(this.KEY, j); } catch (e) {}
    try { localStorage.setItem(this.KEY, j); } catch (e) {}
    return j;
  }
};
// 网页版加载器（tools/export_web.py 把它内联进 index.html 的 <!--SHUIYUE_LOADER--> 处，见 docs/22）
// 1. 分片：index.pck / index.wasm 在导出后被切成若干 gzip 分片（单文件 ≤20 MiB，避开托管平台 25 MB 上限）。
//    拦截引擎对这两个文件的 fetch，并行下载全部分片 → 边下边解压、直接写进一块预先按原文件大小分配好的 Uint8Array 的对应位置
//    （清单里每片带原始长度 p[2]）→ 整块交给引擎。游戏代码不动。
//    2026-10-11 之前是「每片先收齐 gz 字节 → 解开成一块 → 全部分片再拼成整块」，解开的分片和整块同时在内存里，
//    JS 这一侧峰值约 2–3 倍原始大小（docs/33 移动端）。现在 gz 字节与解开的小块都只是流里的临时块，用完即回收，
//    JS 峰值 ≈ 原文件大小（pck + wasm 共约 65 MiB），给 2–3 GB 内存的老手机留余量。
//    浏览器若自作主张解压（Content-Encoding: gzip 被服务器改写），读到的就是原始字节，照样按位置写入。
//    没有 DecompressionStream 的老浏览器（Safari 16.3 以前）：收齐 gz 字节再 inflate（纯 JS，下面的 inflate）。
// 2. 加载画面「声呐测绘」（用户 10-25 定，样式在 loader.css）：声呐进度环 = 下载字节进度占 0–60%，下载解压完以后是引擎启动（拿不到真实进度），
//    环按已等秒数向 80% 渐近；引擎起来后 boot_screen.gd 回传实际进度，仍显示这同一页，
//    逐个编译脚本并准备主菜单；扫描扇面是 CSS 动画，主线程被引擎占住时也在转。左下日志：下载资源 → 解压校验 → 准备主菜单；
//    右下提示每 4 秒换一句（同 game/scripts/screens/loading_tips.gd，改机制时一起核对）。
//    Godot 主菜单就绪（__syBootDone）后撤掉；引擎报错时撤掉，让报错露出来。
(function () {
  var M = /*SHUIYUE_MANIFEST*/null;
  if (!M) return;
  // 11-08 iPhone B站 App 内存崩溃自动刷新后：页面整体被挪开约 2 px，WebView 原生的粉色底从左 / 上边缘露出来，整页还带一层粉罩（docs/318 #5）。
  // 刷新时 iOS 会恢复上次的滚动 / 缩放偏移，所以这里不恢复滚动、始终贴回 0,0；html / body 的底色与锁滚动见 loader.css
  try {
    if ('scrollRestoration' in history) history.scrollRestoration = 'manual';
    var pin = function () { if (window.scrollX || window.scrollY) window.scrollTo(0, 0); };
    window.addEventListener('scroll', pin, { passive: true });
    window.addEventListener('resize', pin);
    window.addEventListener('pageshow', pin);
  } catch (e) {}
  var total = 0, got = 0, done = false;
  Object.keys(M).forEach(function (k) { M[k].parts.forEach(function (p) { total += p[1]; }); });

  var el = {}, bootT0 = 0, bootProgress = null, bootLabel = "", shownProgress = 0;
  var TIPS = [
    '「大群来袭」前 3 秒有紫色预警。包围圈总留一个缺口，没有箭头的一侧就是突围方向。',
    '冲刺中无敌。',
    '灯火只在受击时损失，拾取灯油补充。灯火 ≥ 70 时技力回复 +30%。',
    '商人在 2:00、5:00、8:00 出现，只停留 60 秒。',
    '2:30 起安全区分 4 轮收缩。看到「黑潮将至」就往白色虚线圈里走。',
    '伪装成补给箱的箱形恐鱼会现形扑来，击败后掉落 10 枚源石锭。',
    '同一件藏品再次拿到会升级。',
    '精英一解锁二技能与天赋，精英二解锁三技能。'
  ];
  var R = 192, C = 2 * Math.PI * R;
  function mb(x) { return (x / 1048576).toFixed(1); }
  function upd() {
    if (!el.ring) return;
    var f, busy = false;
    if (bootProgress !== null) { f = bootProgress; busy = true; }
    else if (!done) f = 0.6 * Math.min(got / Math.max(1, total), 1);
    else {
      if (!bootT0) bootT0 = performance.now();
      var s = (performance.now() - bootT0) / 1000;
      f = BV === 4 ? 0.6 : 0.6 + 0.2 * (1 - Math.exp(-s / 6));   // 方向 4（PRTS 认证终端）：拿不到真实进度就不动，刻度环上显示不定进度（p4Init）   // 引擎启动：拿不到真实进度，按已等秒数向 80% 渐近；之后游戏内启动页（boot_screen.gd）从 80% 接着走
      busy = true;
    }
    f = shownProgress = Math.max(shownProgress, Math.min(1, f));
    window.__syPct = f;   // 游戏内启动页从这里接着走（boot_screen.gd）
    if (el.v) {   // 新方向：按真实阶段记系统日志
      var dl0 = got >= total, st;
      if (!dl0) st = { key: 'dl', text: '资源下载 · ' + mb(Math.min(got, total)) + ' / ' + mb(total) + ' MB' };
      else if (!done) st = { key: 'unz', text: '解压校验' };
      else if (bootProgress === null) st = { key: 'eng', text: '启动引擎 · ' + Math.floor((performance.now() - bootT0) / 1000) + ' s' };
      else if (bootLabel === '准备主菜单' && !logs.some(function (l) { return l.key.indexOf('b读取') === 0; })) st = { key: 'eng', text: '启动引擎', ok: true };   // __syBootUp：引擎起来了，还没开始编译
      else st = { key: 'b' + bootLabel, text: String(bootLabel).replace('读取 · ', '编译 · ').replace(/^准备主菜单$/, '渲染预热 · 准备主菜单'), ok: bootProgress >= 1 };
      if (!logs.length) logs.push({ key: 'wake', t: 0, s: '终端唤醒 · 链路建立', ok: true });
      updV(el.v, f, st);
      return;
    }
    el.ring.style.strokeDashoffset = String(C * (1 - f));
    el.num.innerHTML = Math.floor(f * 100) + '<span>%</span>';
    var dl = got >= total;
    el.l1.className = dl ? 'ok' : 'now';
    el.l1.innerHTML = (dl ? '<b>[ OK ]</b>' : '<b>[ .. ]</b>') + '下载资源　' + mb(Math.min(got, total)) + ' / ' + mb(total) + ' MB';
    el.l2.className = done ? 'ok' : (dl ? 'now' : '');
    el.l2.innerHTML = (done ? '<b>[ OK ]</b>' : (dl ? '<b>[ .. ]</b>' : '<b>[ -- ]</b>')) + '解压校验';
    el.l3.className = busy ? 'now' : '';
    el.l3.innerHTML = (busy ? '<b>[ .. ]</b>' : '<b>[ -- ]</b>') + '启动引擎' + (busy ? '　' + Math.floor((performance.now() - bootT0) / 1000) + ' s' : '');
    if (bootProgress !== null) el.l3.textContent = (bootProgress >= 1 ? '[ OK ] ' : '[ .. ] ') + bootLabel;
  }

  // ---------------------------------------------------------------- 启动页新方向（10-30 用户「更加有 PRTS 的感觉，但是保留点深海的特色」）
  // ui/boot_v（导出时写进 /*SHUIYUE_BOOT_V*/，网址 ?boot=N 可临时换）：0 = 上面的「声呐测绘」原样；1 终端开机 / 2 深潜 / 3 声呐终端，
  // 画法与游戏内 boot_views.gd 同一套（桌面原生包看那边，网页只看这里）。系统日志按真实阶段逐行加（下载 → 解压 → 启动引擎 → Godot 回传的编译类别 → 主菜单），
  // 进度同上面的 f；海雪微粒 / 扫描扇面 / 光标都是 CSS 动画（合成线程跑，引擎占住主线程时也在动），系统「减少动态效果」时停住。
  var BV = (function () { var q = typeof location !== 'undefined' && /[?&]boot=(\d)/.exec(location.search); return q ? +q[1] : /*SHUIYUE_BOOT_V*/0; })();
  var t0 = performance.now(), logs = [], logKey = '';
  function nowS() { return (performance.now() - t0) / 1000; }
  // 同一阶段 / 类别只占一行（Godot 回传的编译类别是穿插着来的，再读到就回到那一行、不刷新行）；
  // 换到新阶段时它之前的非编译行标 OK，编译阶段结束（准备主菜单）时全部类别标 OK
  function logStep(key, text, ok) {
    var hit = -1;
    for (var i = 0; i < logs.length; i++) if (logs[i].key === key) hit = i;
    var comp = key.indexOf('b读取') === 0;
    if (hit < 0) {
      logs.forEach(function (l) { if (!comp || l.key.indexOf('b读取') !== 0) l.ok = true; });
      logs.push({ key: key, t: nowS(), s: text, ok: !!ok });
      hit = logs.length - 1;
    } else { logs[hit].s = text; if (ok) logs[hit].ok = true; }
    logKey = key;
  }
  function esc(s) { return String(s).replace(/[&<>]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]; }); }
  function snowLayer(n) {   // 海雪：一个 1px 元素挂 n 个 box-shadow，整层向上平移循环
    var sh = [];
    for (var i = 0; i < n; i++) {
      var h1 = Math.abs(Math.sin(i * 12.9898) * 43758.5453) % 1, h2 = Math.abs(Math.sin(i * 78.233) * 12543.123) % 1;
      sh.push((h1 * 100).toFixed(2) + 'vw ' + (h2 * 100).toFixed(2) + 'vh 0 ' + (h2 > 0.6 ? '1px' : '0') + ' rgba(150,230,240,' + (0.15 + 0.35 * h2).toFixed(2) + ')');
    }
    return '<div class="sv-snow"><i style="box-shadow:' + sh.join(',') + '"></i><i style="box-shadow:' + sh.join(',') + '"></i></div>';
  }
  var JELLY = '<svg class="sv-jelly" viewBox="-40 -30 80 100"><path d="M-34 0 A34 26 0 0 1 34 0 Q28 4 22 0 Q17 4 11 0 Q6 4 0 0 Q-6 4 -11 0 Q-17 4 -22 0 Q-28 4 -34 0Z" fill="rgba(140,235,242,.16)" stroke="rgba(150,240,255,.5)" stroke-width="1.2"/>' +
    '<g fill="none" stroke="rgba(150,240,255,.32)" stroke-width="1"><path d="M-24 3 q3 16 -1 32 t1 30"/><path d="M-12 3 q-3 18 1 34 t-1 28"/><path d="M0 3 q3 18 -1 36 t1 26"/><path d="M12 3 q-3 16 1 32 t-1 30"/><path d="M24 3 q3 18 -1 34 t1 24"/></g></svg>';
  var FOOT = '<div class="sy-foot">明日方舟同人作品 · 非商业 · 与鹰角网络无关</div>';
  function head(title, code) {
    return '<div class="sv-head"><b class="sy-en">PRTS</b><span>' + title + '</span>' + (code ? '<em class="sv-code"></em>' : '') + '</div>';
  }
  function logBox(cls) { return '<div class="sv-log ' + (cls || '') + '"><div class="sv-cap sy-en">SYSTEM LOG</div><div class="sv-lines"></div></div>'; }
  function tipBox(cls) { return '<div class="sv-tip ' + (cls || '') + '"><div class="sv-cap sy-en">NOTE</div><div class="bd"></div></div>'; }

  // ---------------------------------------------------------------- 方向 4：PRTS 认证终端（11-05 用户「codex 的加载页可以替换我们目前的加载页」）
  // 起点是 Codex 演示（docs/reference/prts-entry-1105），同日按用户意见对齐局内 PRTS（画法与桌面 boot_views.draw_v4 一一对应）：
  // 标志呼吸 + 光晕 + 大淡三角、外圈细环上两组反向慢转弧段、方位菱形节点 + 读数、环两侧水平细线 + 往外走的青光、60 格刻度环 = 进度。
  // 进度全接真实状态：下载字节 → 解压 → 引擎启动（拿不到进度：不定进度——刻度环上一段青格慢转、百分比 ---，不按时间推）→ Godot 回传 → 读完整圈转青。
  // 标志 = loader_rhodes.png（用户给的 240×240 原图）最近邻采样到 120×120，亮度 > 112 留、> 168 冷白、其余次灰（同 screens/rhodes_logo.gd）。
  // 11-05 用户「为什么感觉有点卡」：引擎编译 wasm / Godot 编译脚本时主线程会被占住几百毫秒到几秒，画布那几秒停住。
  // 所以凡是「一直在动」的（标志 / 光晕 / 三角呼吸、弧段转动、细线青光）都是 DOM + CSS 动画（只动 opacity / transform，走合成线程，主线程忙时照样流畅）；
  // 画布只画静态底 + 进度（刻度、文字、分项），内容变了才重画。系统「减少动态效果」时 CSS 动画全停。
  function p4Init(d) {
    var cv = d.querySelector('.p4c'), ctx = cv.getContext('2d'), fx = d.querySelector('.p4fx');
    var v = { root: d, tip: { style: {}, textContent: '' }, f: 0, stage: { text: '' }, ind: false, lines: null };
    var rm = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    var img = new Image(), T0 = performance.now(), readyT = -1, lastSig = '', lay = '';
    var LN = 240;   // 11-08：标志按原图 240 原分辨率做阈值（原来先最近邻降到 120，「RHODES ISLAND」小字笔画被采丢，iPhone 上显示成「RI ODES」）
    var box4 = d.querySelector('.p4box');
    // 安全区（11-08 用户 iPhone B站 App 横屏：灵动岛挡左侧日志、右上胶囊压住标题，docs/318）：container.js 拿到容器状态后把 innerWidth / innerHeight 改成安全区尺寸、
    // 安全边距写进 __sySafe；原来本页画布铺满整屏、却按安全区尺寸画，结果被拉伸，标志 / 按钮和画布错位。现在整页底色仍铺满，
    // 画布 / 动效层 / 页脚 / 「开始游戏」都放进贴在安全区里的 .p4box，坐标系与 Godot 画布一致。
    // 胶囊（分享 / 关闭）：用 __sySafe.capsule（画布坐标；SDK 没给矩形时 container.js 按 iPhone 实测估，Godot 侧 Cfg.safe_insets 用同一个）
    function safe() {
      var s = window.__sySafe, w = innerWidth, h = innerHeight;
      var r = s ? { l: s.left, t: s.top, w: w, h: h, cap: s.capsule } : { l: 0, t: 0, w: w, h: h, cap: null };
      return r;
    }
    img.onload = function () {
      var a = fx.querySelector('.p4logo'), ax = a.getContext('2d');
      a.width = a.height = LN;
      ax.imageSmoothingEnabled = false; ax.drawImage(img, 0, 0, LN, LN);
      var id = ax.getImageData(0, 0, LN, LN), px = id.data;
      for (var i = 0; i < px.length; i += 4) {
        var lv = (px[i] + px[i + 1] + px[i + 2]) / 3;
        if (lv > 112 && px[i + 3] > 127) { var hi = lv > 168; px[i] = hi ? 236 : 146; px[i + 1] = hi ? 238 : 151; px[i + 2] = hi ? 240 : 160; px[i + 3] = 255; }
        else px[i + 3] = 0;
      }
      ax.putImageData(id, 0, 0);
      fx.classList.add('on');   // 淡入（CSS transition）
    };
    img.src = 'loader_rhodes.png';
    var BG = '#0f1013', TX = '#eceef0', SUB = '#9297a0', ACC = '#36e2dc', RULE = '#353943';
    var clamp = function (x) { return Math.max(0, Math.min(1, x)); }, ease = function (x) { return 1 - Math.pow(1 - clamp(x), 3); };
    function box(x, y, w, h, c, a) { ctx.globalAlpha = a === undefined ? 1 : a; ctx.fillStyle = c; ctx.fillRect(Math.round(x), Math.round(y), Math.ceil(w), Math.ceil(h)); ctx.globalAlpha = 1; }
    function lab(s, x, y, sz, c, al) { ctx.fillStyle = c; ctx.font = Math.round(sz) + 'px Consolas,"Microsoft YaHei","PingFang SC",monospace'; ctx.textAlign = al || 'left'; ctx.fillText(s, Math.round(x), Math.round(y)); }
    function head(x, y, s, k, rw) { box(x, y - 6 * k, 18 * k, 2, TX); lab(s, x + 26 * k, y, 13 * k, TX); box(x, y + 12 * k, rw, 1, RULE); }
    // 动效层的位置（CSS 像素），只在窗口尺寸变时重排
    function layout(W, H, dpr, k, cx, cy, span, R, R2, hl, hx1, sf) {
      var key = W + 'x' + H + '|' + sf.l + ',' + sf.t;
      if (lay === key) return;
      lay = key;
      box4.style.cssText = 'left:' + sf.l + 'px;top:' + sf.t + 'px;width:' + sf.w + 'px;height:' + sf.h + 'px';
      var q = function (sel) { return fx.querySelector(sel); }, px = function (x) { return (x / dpr).toFixed(1) + 'px'; };
      fx.style.cssText = 'left:' + px(cx) + ';top:' + px(cy);
      var lg = q('.p4logo'); lg.style.width = lg.style.height = px(span); lg.style.left = lg.style.top = px(-span / 2);
      lg.style.imageRendering = span / dpr * (window.devicePixelRatio || 1) >= LN ? 'pixelated' : 'auto';   // 屏上够 240 物理像素才最近邻放大；不够就平滑缩小（缩小时最近邻会丢笔画）
      var ha = q('.p4halo'); ha.style.width = ha.style.height = px(R * 2.5); ha.style.left = ha.style.top = px(-R * 1.25);
      var gw = q('.p4glow'); gw.style.width = gw.style.height = px(span * 1.3); gw.style.left = gw.style.top = px(-span * 0.65);
      var T = R * 0.66 / 0.66 * 1.5, tri = q('.p4tri');   // 外接圆 1.5 倍环
      tri.setAttribute('viewBox', [-T, -T, 2 * T, 2 * T].join(' ')); tri.style.width = tri.style.height = px(2 * T); tri.style.left = tri.style.top = px(-T);
      tri.innerHTML = '<polygon points="0,' + (-T) + ' ' + (T * 0.866) + ',' + (T * 0.5) + ' ' + (-T * 0.866) + ',' + (T * 0.5) + '"/>';
      [['.p4rot.a', R2, 3, 34, 1.5], ['.p4rot.b', R2 + 7 * k, 2, 14, 2]].forEach(function (o) {
        var el = q(o[0]), r = o[1], cc = 2 * Math.PI * r, seg = cc * o[3] / 360, gap = cc / o[2] - seg, e = r + 4 * k;
        el.style.width = el.style.height = px(2 * e); el.style.left = el.style.top = px(-e);
        el.innerHTML = '<svg viewBox="' + [-e, -e, 2 * e, 2 * e].join(' ') + '"><circle r="' + r + '" stroke-width="' + o[4] * dpr + '" stroke-dasharray="' + seg + ' ' + gap + '"/></svg>';
      });
      var len = hl - (hx1 - cx);
      ['.p4run.r', '.p4run.l'].forEach(function (sel, i) {
        var el = q(sel);
        el.style.cssText = 'left:' + px(i ? -(hx1 - cx) - len : hx1 - cx) + ';top:' + px(0) + ';width:' + px(len) + ';--len:' + px(len - 26 * k) + ';--w:' + px(26 * k);
      });
    }
    function frame() {
      if (!d.isConnected) return;
      frameId = requestAnimationFrame(frame);
      var sf = safe(), dpr = Math.min(2, window.devicePixelRatio || 1), W = Math.round(sf.w * dpr), H = Math.round(sf.h * dpr);
      var t = (performance.now() - T0) / 1000, p = v.f, rd = d.classList.contains('sy-ready') || p >= 1;
      if (rd && readyT < 0) readyT = performance.now();
      var u = readyT < 0 ? -1 : (performance.now() - readyT) / 1000;
      // 画布只在内容变时重画（进度格 / 日志 / 阶段 / 不定进度的转格 / 读完脉冲 / 计时到 0.1 秒）
      var spin = Math.floor((t * 14) % 60);
      var cap = sf.cap, gb = d.querySelector('.sy-go'), sig = [W, H, document.documentElement.clientWidth, document.documentElement.clientHeight, sf.l, sf.t, cap ? cap.x + ',' + cap.y + ',' + cap.w + ',' + cap.h : '', gb ? 1 : 0, Math.floor(p * 1000), v.stage.text, logs.length, logs.filter(function (l) { return l.ok; }).length, v.ind ? spin : -1, rd, rd && u < 0.6 ? Math.floor(u * 30) : -1, Math.floor(t * 30), got, done, bootProgress].join('|');   // 30 次 / 秒：刻度环 / 当前格 / 日志小方块随呼吸
      if (sig === lastSig) return;
      lastSig = sig;
      // 画布铺满整屏（底色 / 点阵 / 扫描纹一直画到刘海和圆角下面，安全区边上无接缝），其余内容平移进安全区
      var de = document.documentElement, FW = Math.max(W, Math.round(de.clientWidth * dpr)), FH = Math.max(H, Math.round(de.clientHeight * dpr));
      if (cv.width !== FW || cv.height !== FH) { cv.width = FW; cv.height = FH; }
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      var k = Math.max(0.8, Math.min(2.4, H / 540)), cx = W / 2, cy = H * 0.42, m = 22 * k;
      var br = rm ? 1 : 0.5 + 0.5 * Math.cos(t * 2 * Math.PI / 2.6), rb = rd ? 1 : 0.8 + 0.2 * br;   // 呼吸相位（同 CSS p4br：0 秒最亮）
      var span = 120 * Math.max(1, Math.floor(H * 0.34 / 120)), R = span * 0.66, R2 = R + 22 * k;
      var hx0 = cx - R - 46 * k, hx1 = cx + R + 46 * k, hl = W > 760 * dpr ? W / 2 - 200 * k : W / 2 - 10;
      layout(W, H, dpr, k, cx, cy, span, R, R2, hl, hx1, sf);
      box(0, 0, FW, FH, BG);
      ctx.fillStyle = SUB; ctx.globalAlpha = 0.12;
      for (var gx = 0; gx < FW; gx += 24 * k) for (var gy = 0; gy < FH; gy += 24 * k) ctx.fillRect(Math.round(gx), Math.round(gy), 1, 1);
      ctx.fillStyle = '#000';
      for (var sy = 0; sy < FH; sy += 3) ctx.fillRect(0, sy, FW, 1);
      ctx.globalAlpha = 1;
      ctx.setTransform(1, 0, 0, 1, Math.round(sf.l * dpr), Math.round(sf.t * dpr));
      lab('SYS 1105 · T+' + ('00' + (rm ? 0 : t).toFixed(1)).slice(-5), cx, 28 * k, 10 * k, SUB, 'center');
      lab('PRTS', m, 28 * k, 12 * k, TX); lab('/ 启动校验', m + 44 * k, 28 * k, 12 * k, SUB);
      // 胶囊压在标题行上：右侧字与分隔线都停在胶囊左边 12 px；放不下（会碰到中间 SYS 读数）就不写。胶囊伸到右侧面板标题：面板下移
      var hr = W - m, cl = cap ? cap.x * dpr : W, py = 104 * k;
      if (cap && cl < W - m && cap.y * dpr < 48 * k) hr = cl - 12 * dpr;
      if (cap && cl < W - m && (cap.y + cap.h) * dpr + 24 * k > py - 12 * k) py = (cap.y + cap.h) * dpr + 36 * k;
      ctx.font = Math.round(11 * k) + 'px Consolas,"Microsoft YaHei","PingFang SC",monospace';
      if (W > 600 * dpr && hr - ctx.measureText('ARKNIGHTS FAN GAME').width > cx + 90 * k) lab('ARKNIGHTS FAN GAME', hr, 28 * k, 11 * k, SUB, 'right');
      box(m, 40 * k, hr - m, 1, RULE);
      box(cx - hl, cy, hx0 - (cx - hl), 1, RULE); box(hx1, cy, cx + hl - hx1, 1, RULE);
      box(cx - hl - 1.5, cy - 1, 3, 3, SUB); box(cx + hl - 1.5, cy - 1, 3, 3, SUB);
      var lit = Math.floor(p * 60);
      ctx.lineCap = 'butt';
      for (var i = 0; i < 60; i++) {
        var a = -Math.PI / 2 + 2 * Math.PI * i / 60, mj = i % 5 === 0, l = (mj ? 9 : 5) * k, col, al;
        if (rd) { col = ACC; al = 0.9; }
        else if (v.ind && ((i - spin + 60) % 60) < 5) { col = ACC; al = 0.35 + 0.13 * ((i - spin + 60) % 60); }   // 不定进度：一段青格慢转
        else if (i < lit) { col = TX; al = 0.85; }
        else if (i === lit && !v.ind) { col = ACC; al = (0.55 + 0.45 * br) / rb; }   // 当前格随呼吸闪
        else { col = SUB; al = 0.2 + 0.14 * br; }
        ctx.globalAlpha = Math.min(1, al * rb); ctx.strokeStyle = col; ctx.lineWidth = (mj ? 2 : 1.5) * dpr;
        ctx.beginPath(); ctx.moveTo(cx + Math.cos(a) * R, cy + Math.sin(a) * R); ctx.lineTo(cx + Math.cos(a) * (R + l), cy + Math.sin(a) * (R + l)); ctx.stroke();
      }
      ctx.globalAlpha = 0.18; ctx.strokeStyle = SUB; ctx.lineWidth = 1; ctx.beginPath(); ctx.arc(cx, cy, R - 6 * k, 0, 2 * Math.PI); ctx.stroke();
      ctx.globalAlpha = 0.1 + 0.12 * br; ctx.beginPath(); ctx.arc(cx, cy, R2, 0, 2 * Math.PI); ctx.stroke();
      if (rd && !rm && u >= 0 && u < 0.5) { var q = ease(u / 0.5); ctx.globalAlpha = 0.6 * (1 - q); ctx.strokeStyle = ACC; ctx.lineWidth = 1.5 * dpr; ctx.beginPath(); ctx.arc(cx, cy, R + 14 * k + q * 40 * k, 0, 2 * Math.PI); ctx.stroke(); }
      var nd = 4 * k;
      for (var j = 0; j < 4; j++) {
        var na = -Math.PI / 2 + j * Math.PI / 2, nx = cx + Math.cos(na) * R2, ny = cy + Math.sin(na) * R2;
        ctx.globalAlpha = 0.7; ctx.fillStyle = j === 2 ? SUB : TX;
        ctx.beginPath(); ctx.moveTo(nx, ny - nd); ctx.lineTo(nx + nd, ny); ctx.lineTo(nx, ny + nd); ctx.lineTo(nx - nd, ny); ctx.closePath(); ctx.fill();
      }
      ctx.globalAlpha = 1;
      lab('000', cx, cy - R2 - 10 * k, 9 * k, SUB, 'center'); lab('090', cx + R2 + 10 * k, cy - 6 * k, 9 * k, SUB); lab('270', cx - R2 - 10 * k, cy - 6 * k, 9 * k, SUB, 'right');
      var ly = cy + R + 48 * k;
      if (gb) {   // 「开始游戏」（CSS px，相对 .p4box）：上沿在「认证通过」基线下 14 px（11-08 原来两处各算各的，iPhone 上按钮盖住字的下半）；底下给 RHODES ISLAND / 页脚让出 24 px，放不下时字跟着按钮往上让
        var bh = sf.h < 520 ? 42 : 50, gt = Math.round(Math.min(ly / dpr + 14, sf.h - 24 - bh));
        if (gb.style.top !== gt + 'px') gb.style.top = gt + 'px';
        ly = Math.min(ly, (gt - 12) * dpr);
      }
      if (!rd) {
        lab(v.stage.text || '', cx, ly, 16 * k, TX, 'center');
        lab('ARCHIVE INDEX  ' + (v.ind ? '---' : ('00' + Math.floor(p * 100)).slice(-3)) + '%', cx, ly + 20 * k, 10 * k, SUB, 'center');
      } else lab('认证通过', cx, ly, 16 * k, ACC, 'center');
      if (W > 760 * dpr) {
        var lx = m, rx = W - m - 150 * k;
        head(lx, py, '启动校验', k, 170 * k);
        logs.slice(Math.max(0, logs.length - 4)).forEach(function (ln, i) {
          var yy = py + 35 * k + i * 24 * k;
          box(lx, yy - 4 * k, 3 * k, 3 * k, ln.ok ? TX : (ln.key === logKey ? ACC : RULE), ln.ok || ln.key !== logKey ? 1 : 0.45 + 0.55 * br);
          lab(ln.s, lx + 12 * k, yy + 1 * k, 11 * k, ln.ok ? TX : SUB);
        });
        head(rx, py, '资源索引', k, 150 * k);
        var bp = bootProgress === null ? 0 : clamp((bootProgress - 0.6) / 0.4);
        [['DOWNLOAD', clamp(got / Math.max(1, total))], ['UNPACK', done ? 1 : 0], ['ENGINE', bootProgress !== null ? 1 : -1], ['WARMUP', rd ? 1 : bp]].forEach(function (q2, i) {
          var yb = py + 38 * k + i * 32 * k, fq = q2[1];
          lab(q2[0], rx, yb, 10 * k, SUB); box(rx, yb + 8 * k, 150 * k, 1, RULE);
          if (fq < 0) { var eph = (t / 1.6) % 1; if (done) box(rx + ease(eph) * 126 * k, yb + 7.5 * k, 24 * k, 2, ACC, Math.sin(eph * Math.PI)); }   // 引擎启动：不定进度（两端淡入淡出，不硬跳回）
          else box(rx, yb + 7.5 * k, Math.floor(fq * 150 * k), 2, fq >= 1 ? ACC : TX);
        });
      }
      lab('RHODES ISLAND', m, H - 20 * k, 11 * k, SUB);
      ctx.globalAlpha = rd ? 1 : 0.6 + 0.4 * br;
      lab(rd ? 'ACCESS / GRANTED' : 'ACCESS / PENDING', W - m, H - 20 * k, 11 * k, rd ? ACC : SUB, 'right');
      ctx.globalAlpha = 1;
    }
    var frameId = requestAnimationFrame(frame);
    v.stop = function () {
      cancelAnimationFrame(frameId);
      img.onload = null;
    };
    return v;
  }

  function buildV(d) {
    var segs = '';
    for (var i = 0; i < 50; i++) segs += '<i></i>';
    var h = '';
    if (BV === 4) {   // PRTS 认证终端（11-05，Codex docs/reference/prts-entry-1105；同桌面 boot_views.draw_v4）：画布逐帧画，扫描线 / 不定进度是 CSS 动画
      h = '<canvas class="p4c"></canvas><div class="p4box"><div class="p4fx"><b class="p4halo"></b><b class="p4glow"></b><svg class="p4tri"></svg><canvas class="p4logo" width="240" height="240"></canvas>' +
        '<div class="p4rot a"></div><div class="p4rot b"></div><div class="p4run r"><b></b></div><div class="p4run l"><b></b></div></div>' + FOOT + '</div>';
    } else if (BV === 1) {
      h = '<div class="sv-scan"></div>' + snowLayer(46) + head('罗德岛作战终端 · 启动程序', 1) +
        '<div class="sv-body1">' + logBox('sv-frame') + tipBox() + '</div>' +
        '<div class="sv-prog"><div class="sv-segs">' + segs + '</div><div class="sv-pct">000%</div><div class="sv-what"></div></div>';
    } else if (BV === 2) {
      var ticks = '';   // 深度尺：每 10 m 一格、每 100 m 长刻度 + 读数（0–1500 m，1.2 px / m，随进度整条上移）
      for (var dm = 0; dm <= 1500; dm += 10) {
        ticks += '<i class="' + (dm % 100 ? '' : 'mj') + '" style="top:' + (dm * 1.2) + 'px">' + (dm % 100 ? '' : '<b>-' + dm + '</b>') + '</i>';
      }
      h = '<div class="sv-deep"></div>' + snowLayer(60) + head('深潜观测 · 终端接入', 0) +
        '<div class="sv-body2">' + logBox('sv-frame') + tipBox() + '</div>' +
        '<div class="sv-gauge"><div class="sv-rule"><div class="sv-ruler">' + ticks + '</div></div><div class="sv-read"><div class="sv-cap sy-en">DEPTH</div><div class="sv-depth">-0000<small>m</small></div><div class="sv-sync"></div></div></div>' +
        '<div class="sv-jwrap">' + JELLY + '</div>';
    } else {   // 3 声呐终端（10-31 第三版：照用户给的 PRTS 参考做终端版式（同日用户「不要用浅色」改成深海底浅色线）——盘后巨大空心 PRTS、圈心本作徽记、右上低多边形网格；
               //   去掉水母；声呐接触点 = 日志里的每一项真实加载步骤，扫描扇面扫过时闪亮，读完变实心；读到最后整屏渐暗成深海色接标题页）
      var tk = '', lab = '';
      for (var k = 0; k < 72; k++) {
        var a = -Math.PI / 2 + 2 * Math.PI * k / 72, mj = k % 6 === 0, r0 = 188, r1 = mj ? 200 : 194;
        tk += '<line x1="' + (Math.cos(a) * r0).toFixed(1) + '" y1="' + (Math.sin(a) * r0).toFixed(1) + '" x2="' + (Math.cos(a) * r1).toFixed(1) + '" y2="' + (Math.sin(a) * r1).toFixed(1) + '" stroke-width="' + (mj ? 2 : 1.5) + '"/>';
      }
      [[0, -214], [222, 4], [0, 224], [-222, 4]].forEach(function (q, i) { lab += '<text x="' + q[0] + '" y="' + q[1] + '">' + ('00' + i * 90).slice(-3) + '</text>'; });
      // 低多边形网格（几何动效，10-31）：右上一片（左下会压到系统日志），连线按进度逐条亮出（updV 给前 n 条加 on），节点缓慢漂移（CSS）
      var net = '';
      [0].forEach(function (corner) {
        var np = [];
        for (var ni = 0; ni < 16; ni++) {
          var hx = Math.abs(Math.sin((ni + corner * 31) * 91.7) * 4375.85) % 1, hy = Math.abs(Math.sin((ni + corner * 31) * 47.3) * 2937.11) % 1;
          var qx = 34 * hx, qy = 34 * hy * hy;
          np.push(corner === 0 ? [100 - qx, qy] : [qx, 100 - qy]);
        }
        np.forEach(function (pt, i) {
          var ds = np.map(function (q, j) { return [Math.hypot((q[0] - pt[0]) * 16 / 9, q[1] - pt[1]), j]; }).filter(function (x) { return x[1] !== i; }).sort(function (x, y) { return x[0] - y[0]; });
          for (var kk = 0; kk < 3; kk++) net += '<line x1="' + pt[0].toFixed(2) + '" y1="' + pt[1].toFixed(2) + '" x2="' + np[ds[kk][1]][0].toFixed(2) + '" y2="' + np[ds[kk][1]][1].toFixed(2) + '"/>';
        });
        np.forEach(function (pt, i) { net += '<rect class="nd" x="' + (pt[0] - 0.2).toFixed(2) + '" y="' + (pt[1] - 0.35).toFixed(2) + '" width=".4" height=".7" style="animation-delay:-' + (i * 0.7).toFixed(1) + 's"/>'; });
      });
      var wave = '';
      for (var wi = 0; wi <= 20; wi++) wave += (wi === 0 ? 'M' : 'L') + (-33 + 66 * wi / 20).toFixed(1) + ' ' + (27 + Math.sin(wi / 20 * 2 * Math.PI) * 3.2).toFixed(1);   // 徽记里的一道浪
      h = '<svg class="sv-net" viewBox="0 0 100 100" preserveAspectRatio="none">' + net + '</svg>' +
        '<div class="sv-brand"><b>PRTS</b><em class="sy-en">SONAR TERMINAL</em><span>声呐终端 · 链路建立</span></div>' +
        '<div class="sv-dial"><svg viewBox="-230 -230 460 460"><defs><linearGradient id="sv-sw" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#5ee6e6" stop-opacity="0"/><stop offset="1" stop-color="#5ee6e6" stop-opacity=".2"/></linearGradient></defs>' +
        '<circle r="180" fill="rgba(6,11,16,.82)" stroke="#dfe9ee" stroke-width="1.5"/><circle r="119" fill="none" stroke="rgba(112,135,148,.5)"/><circle r="60" fill="none" stroke="rgba(112,135,148,.4)"/>' +
        '<line x1="-180" y1="0" x2="180" y2="0" stroke="rgba(112,135,148,.3)"/><line x1="0" y1="-180" x2="0" y2="180" stroke="rgba(112,135,148,.3)"/>' +
        '<g class="sy-sweep"><path d="M0 0 L180 0 A180 180 0 0 0 127 -127 Z" fill="url(#sv-sw)"/><line x1="0" y1="0" x2="180" y2="0" stroke="rgba(223,233,238,.55)"/></g>' +
        '<g class="sv-contacts"></g><g class="sv-ticks">' + tk + '</g><g class="sv-az">' + lab + '</g>' +
        '<g class="sv-geo1"><path d="M0 -78 L78 0 L0 78 L-78 0 Z" fill="none" stroke="rgba(223,233,238,.55)"/></g><g class="sv-geo2"><path d="M0 -100 L100 0 L0 100 L-100 0 Z" fill="none" stroke="rgba(223,233,238,.3)"/></g>' +
        '<g class="sv-orbit"><path d="M206 0 l8 5 l0 -10 Z" transform="rotate(0)"/><path d="M206 0 l8 5 l0 -10 Z" transform="rotate(120)"/><path d="M206 0 l8 5 l0 -10 Z" transform="rotate(240)"/></g>' +
        '<path d="M0 -54 L54 0 L0 54 L-54 0 Z" fill="#060b10" stroke="#dfe9ee" stroke-width="3"/><path d="' + wave + '" fill="none" stroke="#dfe9ee" stroke-width="1.5"/>' +
        '</svg><div class="sv-center"><div class="sv-num">0.0%</div></div><div class="sv-ri sy-en">RHODES ISLAND</div></div>' +
        '<div class="sv-log sv-left"><div class="sv-cap sy-en">SYSTEM LOG</div><div class="sv-lines"></div></div>' +
        '<div class="sv-tele"><div class="sv-cap sy-en">TELEMETRY</div><div class="sv-rows"></div>' + tipBox('sv-in') + '</div>' +
        '<div class="sv-build"></div><div class="sv-dark"></div>';
      var sweepT0 = performance.now();
      d.__sweepT0 = sweepT0;
    }
    d.className = 'sv sv' + BV;
    d.innerHTML = BV === 4 ? h : h + FOOT;   // 方向 4 的页脚在安全区框 .p4box 里
    var q = function (s) { return d.querySelector(s); };
    if (BV === 4) return p4Init(d);
    return { root: d, lines: q('.sv-lines'), tip: q('.sv-tip .bd'), code: q('.sv-code'), segs: d.querySelectorAll('.sv-segs i'), pct: q('.sv-pct'),
      what: q('.sv-what'), ruler: q('.sv-ruler'), depth: q('.sv-depth'), sync: q('.sv-sync'), deep: q('.sv-deep'), jelly: q('.sv-jwrap'),
      ticks: d.querySelectorAll('.sv-ticks line'), num: q('.sv-num'), rows: q('.sv-rows'), contacts: q('.sv-contacts'), build: q('.sv-build'), dark: q('.sv-dark'), net: d.querySelectorAll('.sv-net line') };
  }

  // 每次 upd() 调：f = 进度 0–1，stage = {key, text, ok}，n / total = 编译到第几个（Godot 回传后才有）
  function updV(v, f, stage) {
    logStep(stage.key, stage.text, stage.ok);
    if (BV === 4) { v.f = f; v.stage = stage; v.ind = done && bootProgress === null; return; }
    var nmax = window.innerHeight < 520 ? 7 : (window.innerHeight > window.innerWidth ? 9 : 12);   // 矮屏（手机横屏）/ 竖屏少留几行，不压页脚和提示
    var html = '', start = Math.max(0, logs.length - nmax);
    for (var i = start; i < logs.length; i++) {
      var ln = logs[i], cur = ln.key === logKey && !ln.ok;
      html += '<div class="' + (ln.ok ? 'ok' : (cur ? 'now' : 'wait')) + (nowS() - ln.t < 0.35 ? ' nw' : '') + '"><b>[' + ('000' + ln.t.toFixed(2)).slice(-6) + ']</b><span>' + esc(ln.s) + '</span><u></u><em>' + (ln.ok ? 'OK' : (cur ? '<i class="sv-cur">_</i>' : '..')) + '</em></div>';
    }
    if (v.lines.innerHTML !== html) v.lines.innerHTML = html;
    var pc = Math.floor(f * 100);
    if (v.code) v.code.textContent = (BV === 3 ? 'RI-SONAR 07' : 'NODE AS-07') + ' · T+' + ('00' + nowS().toFixed(1)).slice(-5);
    if (BV === 1) {
      var lit = f * v.segs.length;
      for (var s = 0; s < v.segs.length; s++) v.segs[s].className = lit >= s + 1 ? 'on' : (lit > s ? 'half' : '');
      v.pct.textContent = ('00' + pc).slice(-3) + '%';
      v.what.textContent = stage.text;
    } else if (BV === 2) {
      var dep = Math.floor(1200 * f);
      v.ruler.style.transform = 'translateY(' + (-dep * 1.2) + 'px)';
      v.depth.innerHTML = '-' + ('000' + dep).slice(-4) + '<small>m</small>';
      v.sync.textContent = '同步 ' + pc + '%';
      v.deep.style.opacity = String(f);
      v.jelly.style.opacity = String(Math.max(0, Math.min(1, (f - 0.82) / 0.18)));
      v.jelly.style.transform = 'translateY(' + (12 * (1 - Math.max(0, (f - 0.82) / 0.18))) + 'vh)';
    } else {
      var lt = Math.floor(f * v.ticks.length);
      for (var k = 0; k < v.ticks.length; k++) v.ticks[k].setAttribute('class', k < lt ? 'on' : (k === lt ? 'cur' : ''));
      v.num.textContent = (Math.floor(f * 1000) / 10).toFixed(1) + '%';
      // 接触点：日志每一项（第一行除外），按 key 定方位 / 距离；扫过时的闪亮与扫描扇面同相（CSS 动画延迟按扇面已转的时间算）
      var ch = '', el3 = ((performance.now() - v.root.__sweepT0) / 1000) % 3.2;
      for (var ci = 1; ci < logs.length; ci++) {
        var key = logs[ci].key, hs = 0;
        for (var q = 0; q < key.length; q++) hs = (hs * 31 + key.charCodeAt(q)) % 100003;
        var ang = (Math.abs(Math.sin(hs * 0.731 + 12.9898)) * 43758.5453 % 1) * 2 * Math.PI;
        var rad = 180 * (0.3 + 0.6 * (Math.abs(Math.sin(hs * 0.731 + 25.9796)) * 43758.5453 % 1));
        if (key === 'b接入完成 · 等待指令') { ang = Math.PI / 2; rad = 144; }   // 钉在 180 方位：「开始游戏」的引线从它竖直落到按钮上（同桌面 boot_views）
        var x = (Math.cos(ang) * rad).toFixed(1), y = (Math.sin(ang) * rad).toFixed(1);
        var hit = (ang / (2 * Math.PI)) * 3.2, dl = (((hit - el3) % 3.2) + 3.2) % 3.2 - 3.2;
        ch += '<g class="' + (logs[ci].ok ? 'dn' : 'go') + '" transform="translate(' + x + ' ' + y + ')"><g class="lt" style="animation-delay:' + dl.toFixed(2) + 's">' +
          '<circle class="gl" r="10" style="animation-delay:' + dl.toFixed(2) + 's"/><circle class="pg" r="6" style="animation-delay:' + dl.toFixed(2) + 's"/>' +
          (logs[ci].ok ? '<rect x="-3" y="-3" width="6" height="6"/>' : '<rect class="bx" x="-4" y="-4" width="8" height="8"/><rect x="-1.5" y="-1.5" width="3" height="3"/>') +
          '<text x="8" y="-5">' + ('0' + ci).slice(-2) + '</text></g></g>';
      }
      if (v.contacts.__n !== logs.length + ':' + logs.filter(function (l) { return l.ok; }).length) {   // 只在接触点增减 / 读完时重建（闪亮相位按重建时刻算）
        v.contacts.innerHTML = ch;
        v.contacts.__n = logs.length + ':' + logs.filter(function (l) { return l.ok; }).length;
      }
      v.rows.innerHTML = '<div><b>同步</b>' + (Math.floor(f * 1000) / 10).toFixed(1) + '%</div><div><b>接触</b>' + (logs.length - 1) + '</div><div><b>阶段</b>' + esc(stage.text) + '</div>';
      v.build.textContent = 'BUILD 1031 · T+' + ('00' + nowS().toFixed(1)).slice(-5);
      v.dark.style.opacity = String(Math.max(0, Math.min(1, (f - 0.93) / 0.07)) * 0.6);
      var ne = Math.floor(v.net.length * Math.min(1, f * 1.05));
      if (v.net.__n !== ne) { for (var e = 0; e < v.net.length; e++) v.net[e].setAttribute('class', e < ne ? 'on' : ''); v.net.__n = ne; }
    }
  }

  function build() {
    var d = document.createElement('div');
    d.id = 'sy-load';
    if (BV > 0) {   // 新方向（ui/boot_v 1–3）：同一个 #sy-load，撤页 / 进度回传的生命周期不变
      document.body.appendChild(d);
      var v = buildV(d);
      el = { root: d, v: v, tip: v.tip, ring: true };
      return finish(d);
    }
    var blips = '';
    [[70, -96, 0], [-110, 40, 1.1], [30, 130, 2.0], [-60, -120, 2.6]].forEach(function (b) {
      blips += '<circle class="sy-blip" cx="' + b[0] + '" cy="' + b[1] + '" r="3" fill="#5ee6e6" style="animation-delay:' + b[2] + 's"/>';
    });
    d.innerHTML = '<div class="sy-grid"></div><img class="sy-logo" src="loader_logo.png" alt=""><div class="sy-fan">ARKNIGHTS FAN GAME · 非商业</div>' +
      '<div class="sy-sonar"><svg viewBox="-210 -210 420 420"><defs><linearGradient id="sy-sw" x1="0" y1="0" x2="1" y2="0">' +
      '<stop offset="0" stop-color="#5ee6e6" stop-opacity="0"/><stop offset="1" stop-color="#5ee6e6" stop-opacity=".35"/></linearGradient></defs>' +
      '<circle r="180" fill="none" stroke="#2a3c46"/><circle r="120" fill="none" stroke="#1f2e36"/><circle r="60" fill="none" stroke="#1f2e36"/>' +
      '<line x1="-190" y1="0" x2="190" y2="0" stroke="#1a272e"/><line x1="0" y1="-190" x2="0" y2="190" stroke="#1a272e"/>' +
      '<path class="sy-sweep" d="M0 0 L180 0 A180 180 0 0 0 127 -127 Z" fill="url(#sy-sw)"/>' + blips +
      '<circle r="' + R + '" fill="none" stroke="#1d2a32" stroke-width="6"/>' +
      '<circle class="sy-ring" r="' + R + '" fill="none" stroke="#5ee6e6" stroke-width="6" stroke-dasharray="' + C + '" stroke-dashoffset="' + C + '" transform="rotate(-90)"/>' +
      '<g stroke="#3b4f5a" stroke-width="1.5"><line x1="0" y1="-200" x2="0" y2="-210"/><line x1="200" y1="0" x2="210" y2="0"/><line x1="0" y1="200" x2="0" y2="210"/><line x1="-200" y1="0" x2="-210" y2="0"/></g>' +
      '</svg><div class="sy-center"><div class="sy-num">0<span>%</span></div><div class="sy-sub sy-en">SONAR · BOOT</div></div></div>' +
      '<div class="sy-panel sy-log"><div class="hd sy-en">TERMINAL LOG</div><div class="bd"><div></div><div></div><div></div></div></div>' +
      '<div class="sy-panel sy-tips"><div class="hd sy-en">TIPS</div><div class="bd"></div></div>' +
      '<div class="sy-foot">明日方舟同人作品 · 非商业 · 与鹰角网络无关</div>';
    document.body.appendChild(d);
    var lines = d.querySelectorAll('.sy-log .bd div');
    el = { root: d, ring: d.querySelector('.sy-ring'), num: d.querySelector('.sy-num'), l1: lines[0], l2: lines[1], l3: lines[2], tip: d.querySelector('.sy-tips .bd') };
    finish(d);
  }

  // 局间整页重载回来（window.__syRL 有标记，core/run_reload.gd）：盖一层「潮汐航标」—— 同对局出发时的载入页（screens/loading_screen.gd）：
  // 深海底图压暗 + 暗角、三只水母浮沉、居中标志、左上同人声明、三层像素浪线（进度点亮）、百分比 / 阶段、提示轮换（11-09 用户：别出开机那套加载页）。
  // 只是画面：进度读 window.__syPct（本加载器 upd 写），撤页跟着加载器根节点一起撤
  function rlPage(d, act) {
    var cv = document.createElement('canvas');
    cv.id = 'sy-rlpage';
    cv.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;z-index:30;image-rendering:pixelated;background:#000308';
    d.appendChild(cv);
    var img = function (s) { var i = new Image(); i.src = s; return i; };
    var bg = img('rl_bg.png'), lg = img('loader_logo.png'), js = [img('rl_j0.png'), img('rl_j1.png'), img('rl_j2.png')];
    var t0 = performance.now(), ti = Math.floor(Math.random() * TIPS.length), tt = 0, shown = 0;
    var GO = { meta: '正在返回认知塑造…', hunt: '正在前往寻访…', restart: '正在准备下一局…', title: '正在返回主界面…' }[act] || '正在返回…';
    var rm = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    var LAY = [[-8, 2.5, 0.2, 0.9, [158, 230, 240], [82, 110, 133], [26, 77, 102], 0.16], [-4, 3, 0.13, -1.3, [92, 224, 230], [64, 89, 112], [13, 51, 71], 0.4],
               [0, 2, 0.09, 1.7, [46, 184, 199], [46, 69, 89], [5, 23, 36], 0.92]];
    var rgb = function (c, a) { return 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + a + ')'; };
    function frame() {
      if (!cv.isConnected) return;
      var dpr = Math.min(window.devicePixelRatio || 1, 2), W = cv.clientWidth, H = cv.clientHeight;
      if (cv.width !== Math.round(W * dpr) || cv.height !== Math.round(H * dpr)) { cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr); }
      var x = cv.getContext('2d'), t = (performance.now() - t0) / 1000;
      x.setTransform(dpr, 0, 0, dpr, 0, 0); x.imageSmoothingEnabled = false;
      x.fillStyle = '#000308'; x.fillRect(0, 0, W, H);
      var k = Math.min(W / 1280, H / 720), bk = Math.max(W / 428, H / 240);
      if (bg.complete && bg.naturalWidth) { x.globalAlpha = 1; x.drawImage(bg, (W - 428 * bk) / 2, (H - 240 * bk) / 2, 428 * bk, 240 * bk); x.fillStyle = 'rgba(0,3,8,0.45)'; x.fillRect(0, 0, W, H); }
      var vg = x.createRadialGradient(W / 2, H / 2, Math.min(W, H) * 0.25, W / 2, H / 2, Math.max(W, H) * 0.75);
      vg.addColorStop(0, 'rgba(0,3,8,0)'); vg.addColorStop(1, 'rgba(0,3,8,0.75)'); x.fillStyle = vg; x.fillRect(0, 0, W, H);
      var bob = rm ? 0 : Math.sin(t * 1.15) * 7 * k, pul = rm ? 0 : Math.sin(t * 1.15 + 0.6) * 0.025;
      var s0w = 129 * 1.6 * k * (1 + pul), s0h = 139 * 1.6 * k * (1 - pul);
      var jr = [[W * 0.5 - s0w / 2, H * 0.3 - s0h / 2 + bob, s0w, s0h, 0.95],
                [W * 0.715, H * 0.305 + (rm ? 0 : Math.sin(t * 0.9 + 2) * 5 * k), 34 * 1.6 * k, 52 * 1.6 * k, 0.55],
                [W * 0.267, H * 0.365 + (rm ? 0 : Math.sin(t * 1.3 + 4) * 4 * k), 24 * 2 * k, 36 * 2 * k, 0.6]];
      [1, 2, 0].forEach(function (i) { var j = js[i]; if (j.complete && j.naturalWidth) { x.globalAlpha = jr[i][4]; x.drawImage(j, jr[i][0], jr[i][1], jr[i][2], jr[i][3]); } });
      x.globalAlpha = 1;
      if (lg.complete && lg.naturalWidth) x.drawImage(lg, W / 2 - 241 * k, H * 0.628, 482 * k, 86 * k);
      x.font = Math.max(9, 11 * k) + 'px sans-serif'; x.fillStyle = 'rgba(128,163,176,1)'; x.textBaseline = 'alphabetic';
      x.fillText('ARKNIGHTS FAN GAME   明日方舟同人作品 · 非商业', 24 * k, 33 * k + 8);
      // 进度：浪头追真实进度（带一点冲过头）
      var f = Math.max(0, Math.min(1, Number(window.__syPct || 0)));
      shown += (f - shown) * (rm ? 1 : 0.12);
      var c = Math.max(3, Math.round(3 * k)), x0 = Math.floor(W * 0.125 / c) * c, x1 = Math.floor(W * 0.875 / c) * c, y = Math.floor(H * 0.8 / c) * c, tm = Math.max(0.5, Math.min(1, H / 720));
      var n = Math.floor((x1 - x0) / c), lit = Math.floor(n * shown);
      for (var L = 0; L < 3; L++) {
        var ly = LAY[L];
        for (var i = 0; i < n; i++) {
          var ph = i * ly[2] + (rm ? 0 : t * ly[3]) + L * 1.7;
          var cy = Math.round(ly[0] * tm) - Math.round(ly[1] * tm * (Math.sin(ph) * 0.7 + Math.sin(ph * 0.43 + 1.1) * 0.3));
          var px = x0 + i * c, py = y + cy * c;
          x.fillStyle = rgb(ly[6], ly[7]); x.fillRect(px, py + c, c, (L === 2 ? Math.round(8 * tm) : 3) * c);
          x.fillStyle = rgb(i <= lit ? ly[4] : ly[5], 1); x.fillRect(px, py, c, c);
        }
      }
      x.font = Math.max(11, 14 * k) + 'px sans-serif'; x.textAlign = 'center'; x.fillStyle = 'rgba(168,194,201,1)';
      x.fillText(GO + '  ' + Math.floor(f * 100) + '%', W / 2, y + Math.round(8 * tm) * c + 22 * k + 6);
      tt = t - Math.floor(t / 3.5) * 3.5; ti = (Math.floor(t / 3.5) + ti0) % TIPS.length;
      var ta = rm ? 1 : Math.min(1, tt / 0.25, (3.5 - tt) / 0.25);
      x.globalAlpha = Math.max(0, ta); x.fillText('TIPS   ' + TIPS[ti], W / 2, H * 0.935 + 6);
      x.globalAlpha = 1; x.textAlign = 'left';
      frameId = requestAnimationFrame(frame);
    }
    var ti0 = ti;
    var frameId = requestAnimationFrame(frame);
    return function () { cancelAnimationFrame(frameId); };
  }

  function finish(d) {
    // 标题页 _ready 会在稳帧前消费返回动作。盖层和开始握手共用建页时的判定。
    var reload = window.__syRL.peek();
    var stopReload = reload ? rlPage(d, reload.act) : null;
    var unbindReady = null;
    var ti = Math.floor(Math.random() * TIPS.length);
    el.tip.textContent = TIPS[ti];
    upd();
    var tick = 0, closing = false, tipTimer = 0;
    var out = function () {
      if (closing) return;
      closing = true;
      clearInterval(t);
      clearTimeout(tipTimer);
      if (unbindReady) unbindReady();
      d.classList.add('sy-out');
      setTimeout(function () {
        if (stopReload) stopReload();
        if (el.v && el.v.stop) el.v.stop();
        d.remove();
        d.querySelectorAll('canvas').forEach(function (canvas) {
          canvas.width = canvas.height = 0;
        });
        el = {};   // 分片 fetch 在撤页之后仍可能调 upd()。
        delete window.__syBootUp;
        delete window.__syBootReady;
        delete window.__syBootProgress;
        delete window.__syBootDone;
      }, 400);
    };
    // One visual owner: download, engine and Godot warm-up update this same page.
    window.__syBootUp = function () {
      bootProgress = Math.max(shownProgress, 0.6);
      bootLabel = '准备主菜单';
      upd();
    };
    // 11-01：读完不自动进标题页。Godot 稳帧后调 __syBootReady → 这里出「开始游戏」，玩家点任意处 / 按任意键置 window.__syStart，
    // boot_screen.gd 每帧读到后揭开标题页并调 __syBootDone 撤页（同桌面 boot_views.draw_start）
    var ready = false;
    window.__syBootReady = function () {
      if (ready || closing) return;
      ready = true;
      bootProgress = 1;
      bootLabel = '接入完成 · 等待指令';
      upd();
      // 手机网页局与局之间的整页重载（core/run_reload.gd，docs/319 §14）：玩家刚点过「再来一局 / 回标题」，读完直接开始，不再要一次「开始游戏」
      if (reload) {
        window.__syStart = 1;
        return;
      }
      // 按钮挂在页面根上（盘 / 声呐圈有 transform，挂进去会被同在根上的收尾压暗层 .sv-dark 盖住），位置按圈的实际外框算：圈下留一段，
      // 不压页脚声明；方向 3 竖屏盘下是系统日志，放底部
      var dial = d.querySelector('.sv-dial') || d.querySelector('.sy-sonar');
      var touch = window.matchMedia && window.matchMedia('(pointer: coarse)').matches;
      var rm = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      var LAB = '开始游戏', SCR = '0123456789ABCDEF#/<>+=';
      var b = document.createElement('button');
      b.type = 'button';
      b.className = 'sy-go';
      b.innerHTML = '<b class="gw"></b><b class="fl"></b><b class="sc"></b><svg class="fr"></svg><i class="c0"></i><i class="c1"></i><i class="c2"></i><i class="c3"></i>' +
        '<b class="r0"></b><b class="r1"></b><span>' + LAB.split('').map(function (c) { return '<s>' + (rm ? c : '') + '</s>'; }).join('') + '</span>' +
        '<em class="sy-en">' + (touch ? 'TAP TO START' : 'PRESS ANY KEY') + '</em>';
      // 边框三条路径按按钮像素写（矮屏换尺寸时重写）：tr 两条从上沿正中分向两边描出，bd 整框（呼吸），fw 一段青光沿边慢转
      var frame = function () {
        var w = b.offsetWidth, hh = b.offsetHeight, fr = b.querySelector('.fr');
        if (!w || fr.__w === w + 'x' + hh) return;
        fr.__w = w + 'x' + hh;
        fr.setAttribute('width', w); fr.setAttribute('height', hh); fr.setAttribute('viewBox', '0 0 ' + w + ' ' + hh);
        var m = w / 2, bd = 'M' + m + ' 0H' + w + 'V' + hh + 'H0V0Z';
        fr.innerHTML = '<path class="tr" pathLength="1" d="M' + m + ' 0H' + w + 'V' + hh + 'H' + m + '"/><path class="tr" pathLength="1" d="M' + m + ' 0H0V' + hh + 'H' + m + '"/>' +
          '<path class="bd" d="' + bd + '"/><path class="fw" pathLength="100" d="' + bd + '"/>';
        b.style.setProperty('--sx', ((w - 6) / w).toFixed(4));
        b.style.setProperty('--sy', ((hh - 6) / hh).toFixed(4));
      };
      var place = function () {
        var low = window.innerHeight < 520, bh = low ? 42 : 50;
        var y = window.innerHeight - (low ? 64 : 96) - bh / 2;   // 缺省：底部
        if (BV === 4) y = Math.min(window.innerHeight * 0.8, window.innerHeight - 60 - bh / 2);   // 方向 4：进度条的位置（同 boot_views.start_rect）
        if (dial && !(BV === 3 && window.innerHeight > window.innerWidth)) {
          y = dial.getBoundingClientRect().bottom + (BV === 3 ? 34 : 30) + bh / 2;
          y = Math.min(y, window.innerHeight - 30 - bh / 2 - (low ? 0 : 22));   // 让出页脚声明（矮屏不写下面那行英文）
        }
        b.style.top = Math.round(y - bh / 2) + 'px';
        frame();
      };
      (d.querySelector('.p4box') || d).appendChild(b);   // 方向 4：放进安全区框（left:50% 按安全区居中，top 由 p4Init 每帧对齐「认证通过」）
      if (BV !== 4) place(); else frame();
      var onResize = BV !== 4 ? place : frame;
      window.addEventListener('resize', onResize);
      d.classList.add('sy-ready');
      // 引线：从「接入完成」接触点（方向 3 钉在 180 方位）竖直落到按钮上沿，接触点上一个收拢的锁定框（横屏才拉，竖屏盘下是日志）
      var ct = d.querySelector('.sv-contacts');
      ct = ct && ct.lastElementChild;
      if (ct && !rm && window.innerWidth >= window.innerHeight) {
        var cr = ct.querySelector('rect').getBoundingClientRect(), br0 = b.getBoundingClientRect(), dr = d.getBoundingClientRect();
        var cx = cr.left + cr.width / 2 - dr.left, cy = cr.top + cr.height / 2 - dr.top;
        var ld = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
        ld.setAttribute('class', 'sy-lead');
        ld.innerHTML = '<line pathLength="1" x1="' + cx + '" y1="' + cy + '" x2="' + (br0.left + br0.width / 2 - dr.left) + '" y2="' + (br0.top - dr.top) + '"/>' +
          '<rect x="' + (cx - 6) + '" y="' + (cy - 6) + '" width="12" height="12"/>';
        d.appendChild(ld);
        var leadTimer = setTimeout(function () { ld.remove(); }, 1500);
      }
      // 字：先乱码、再从左到右逐个解出（0.45 秒起，每字隔 0.08 秒）
      if (!rm) {
        var ss = b.querySelectorAll('span s'), t0 = performance.now();
        var dec = setInterval(function () {
          var u = (performance.now() - t0) / 1000, all = true;
          for (var k = 0; k < ss.length; k++) {
            if (u >= 0.62 + 0.08 * k) { ss[k].textContent = LAB[k]; ss[k].className = ''; }
            else { all = false; if (u >= 0.45) { ss[k].textContent = SCR[Math.floor(Math.random() * SCR.length)]; ss[k].className = 'x'; } }
          }
          if (all) clearInterval(dec);
        }, 42);
      }
      var t1 = performance.now();
      var go = function (e) {
        if (performance.now() - t1 < 250) return;   // 读完那一刻正好按着键，不算
        if (e.type === 'keydown' && (e.ctrlKey || e.metaKey || e.altKey || /^F\d+$/.test(e.key))) return;   // 刷新 / 开发者工具之类的组合键放行
        e.preventDefault();
        e.stopPropagation();
        // 点按是用户手势：先把引擎的音频上下文唤醒（power.js 记下的实例），引擎读到 __syStart 时按下音效才放得出来
        // 触屏的 pointerdown 不算激活手势，这里唤醒在手机上不生效；真正的解锁在 power.js 的 pointerup / touchend / click 监听里（同一次点按紧接着就到）
        if (window.__syAudioKick) window.__syAudioKick(); else (window.__syAudioCtx || []).forEach(function (c) { try { c.resume(); } catch (err) {} });
        window.__syStart = 1;
        b.classList.add('on');
        // 按下：整屏一下压暗 + 三圈声呐脉冲从按钮扩到整屏（引擎 0.28 秒后揭开标题页）
        var r = b.getBoundingClientRect(), dr2 = d.getBoundingClientRect();
        var px = r.left + r.width / 2 - dr2.left, py = r.top + r.height / 2 - dr2.top;
        var dim = document.createElement('div');
        dim.className = 'sy-dim';
        d.appendChild(dim);   // 层级靠 z-index（压暗 19 < 按钮 20）；方向 4 的按钮不是 d 的直接子节点
        if (!rm) {
          var R = Math.hypot(Math.max(px, dr2.width - px), Math.max(py, dr2.height - py));
          for (var j = 0; j < 3; j++) {
            var pu = document.createElement('div');
            pu.className = 'sy-pulse p' + j;
            pu.style.cssText = 'left:' + (px - R) + 'px;top:' + (py - R) + 'px;width:' + 2 * R + 'px;height:' + 2 * R + 'px;--s0:' + (r.height / 2 / R).toFixed(4) + ';animation-delay:' + (j * 0.1) + 's';
            d.appendChild(pu);
          }
        }
        d.removeEventListener('pointerdown', go, true);
        window.removeEventListener('keydown', go, true);
      };
      d.addEventListener('pointerdown', go, true);
      window.addEventListener('keydown', go, true);
      unbindReady = function () {
        window.removeEventListener('resize', onResize);
        window.removeEventListener('keydown', go, true);
        d.removeEventListener('pointerdown', go, true);
        clearTimeout(leadTimer);
        clearInterval(dec);
      };
    };
    window.__syBootProgress = function (value, label) {
      if (closing || ready || !Number.isFinite(value)) return;
      bootProgress = Math.max(shownProgress, Math.min(1, value));
      bootLabel = String(label || '准备主菜单');
      upd();
    };
    window.__syBootDone = function () {
      if (closing) return;
      bootProgress = 1;
      bootLabel = '进入主菜单';
      upd();
      out();
    };
    var t = setInterval(function () {
      upd();   // 启动阶段没有字节进度：靠这里按时间推进
      if (++tick % 27 === 0) {
        ti = (ti + 1) % TIPS.length;
        el.tip.style.opacity = '0';
        tipTimer = setTimeout(function () { el.tip.textContent = TIPS[ti]; el.tip.style.opacity = '1'; }, 220);
      }
      var nt = document.getElementById('status-notice');
      if (nt && nt.style.display === 'block') out();
    }, 150);
  }
  if (document.body) build(); else document.addEventListener('DOMContentLoaded', build, {once: true});

  var hasDS = typeof DecompressionStream === 'function';

  // 把一片写进 out 的 [off, off + raw) 区间。gz 片：第一块带 1f 8b 时经 DecompressionStream 解开；否则（服务器已解压）原样写入。
  // 返回写入的字节数；写越界 / 不足都按出错处理（part 会重试）。
  // enc === 'lzma'（index.wasm，docs/187 §5）：不是 gzip 头时收齐压缩字节，用 syLzmaDecode（lzma_dec.js）直接解进 out 的这一段。
  async function once(url, bytes, out, off, raw, enc) {
    var r = await of(url, { cache: 'no-cache' });
    if (!r.ok) throw new Error(url + ' ' + r.status);
    var rd = r.body.getReader(), counted = 0, wrote = 0, gz = null, chunks = null, ds = null, w = null, pump = null, pumpErr = null;
    function sink(v) {   // 解开后的字节 → out
      if (wrote + v.length > raw) throw new Error(url + ' 解开后超过原始长度');
      out.set(v, off + wrote); wrote += v.length;
    }
    try {
      for (;;) {
        var x = await rd.read();
        if (x.done) break;
        var v = x.value;
        var add = Math.min(v.length, bytes - counted);
        if (add > 0) { counted += add; got += add; upd(); }
        if (gz === null) gz = (v.length > 1 && v[0] === 0x1f && v[1] === 0x8b);
        if (!gz && enc === 'lzma') { if (!chunks) chunks = []; chunks.push(v); continue; }
        if (!gz) { sink(v); continue; }
        if (hasDS) {
          if (!ds) {
            ds = new DecompressionStream('gzip'); w = ds.writable.getWriter();
            pump = (async function () {   // 与下载并行：解开的块一出来就写进 out，不在内存里攒
              var rr = ds.readable.getReader();
              for (;;) { var y = await rr.read(); if (y.done) break; sink(y.value); }
            })().catch(function (e2) { pumpErr = e2; });
          }
          await w.write(v);
        } else {
          if (!chunks) chunks = [];
          chunks.push(v);
        }
      }
      if (ds) { await w.close(); await pump; if (pumpErr) throw pumpErr; }
      else if (chunks && !gz) { var lz = cat(chunks); chunks = null; wrote = syLzmaDecode(lz, out.subarray(off, off + raw)); }
      else if (chunks) { sink(inflate(cat(chunks))); chunks = null; }
    } catch (e) {
      got -= counted; upd();
      if (w) { try { w.abort(); } catch (e2) {} }
      throw e;
    }
    got += bytes - counted; upd();
    if (wrote !== raw) throw new Error(url + ' 解开后大小不符：' + wrote + ' ≠ ' + raw);
    return wrote;
  }

  function cat(list) {
    var n = 0; list.forEach(function (b) { n += b.length; });
    var o = new Uint8Array(n), p = 0;
    list.forEach(function (b) { o.set(b, p); p += b.length; });
    return o;
  }

  async function part(url, bytes, out, off, raw, enc) {
    for (var i = 0; ; i++) {
      try { return await once(url, bytes, out, off, raw, enc); }
      catch (e) { if (i >= 2) throw e; await new Promise(function (r) { setTimeout(r, 800 * (i + 1)); }); }
    }
  }

  var pending = Object.keys(M).length;
  var of = window.fetch.bind(window);
  window.fetch = function (input, init) {
    var url = (typeof input === 'string') ? input : ((input && input.url) || '');
    var path = url.split('?')[0].split('#')[0];
    var name = path.split('/').pop();
    var e = M[name];
    if (!e) return of(input, init);
    var base = path.slice(0, path.length - name.length);
    var out = new Uint8Array(e.size), off = 0, jobs = [];
    e.parts.forEach(function (p) {
      var raw = p.length > 2 ? p[2] : e.size - off;   // 旧清单没有原始长度：只可能是单片
      jobs.push(part(base + p[0], p[1], out, off, raw, e.enc));
      off += raw;
    });
    if (off !== e.size) return Promise.reject(new Error(name + ' 清单分片长度之和不符：' + off + ' ≠ ' + e.size));
    return Promise.all(jobs).then(function () {
      if (--pending === 0) { done = true; upd(); }
      var resp = new Response(out, { status: 200, headers: { 'Content-Type': e.type, 'Content-Length': String(e.size) } });
      resp.__syBuf = out.buffer;
      if (/\.pck$/.test(name)) window.__syPckBytes = (window.__syPckBytes || 0) + e.size;   // 只算主包：wasm 编译完不留   // 崩溃前快照估 JS 堆（WebKit 没有 performance.memory，docs/319 §13）   // 引擎补丁（engine_patch.py §2）直接拿这块，不再 arrayBuffer() 拼一份、MEMFS 也不再 slice 一份（docs/319 §10）
      return resp;
    });
  };

  // ---------------------------------------------------------------- 后备：纯 JS gzip 解压（没有 DecompressionStream 的老浏览器）
  // 标准 inflate（RFC 1951），只处理 gzip 单成员；输出按 4 MiB 增长。正常浏览器走不到这里。
  function inflate(src) {
    var pos = 0;
    if (src[0] !== 0x1f || src[1] !== 0x8b || src[2] !== 8) throw new Error('不是 gzip');
    var flg = src[3]; pos = 10;
    if (flg & 4) { var xl = src[pos] | (src[pos + 1] << 8); pos += 2 + xl; }
    if (flg & 8) { while (src[pos++] !== 0); }
    if (flg & 16) { while (src[pos++] !== 0); }
    if (flg & 2) pos += 2;
    var out = new Uint8Array(4 << 20), op = 0;
    function grow(n) { if (op + n > out.length) { var o2 = new Uint8Array(Math.max(out.length * 2, op + n)); o2.set(out); out = o2; } }
    var bitbuf = 0, bitcnt = 0;
    function bits(n) {
      while (bitcnt < n) { bitbuf |= src[pos++] << bitcnt; bitcnt += 8; }
      var v = bitbuf & ((1 << n) - 1); bitbuf >>>= n; bitcnt -= n; return v;
    }
    function huff(lengths) {   // 码长表 → {count, symbol}（zlib puff 做法）
      var n = lengths.length, count = new Uint16Array(16), symbol = new Uint16Array(n), offs = new Uint16Array(16), i;
      for (i = 0; i < n; i++) count[lengths[i]]++;
      count[0] = 0;
      for (i = 1; i < 16; i++) offs[i] = offs[i - 1] + count[i - 1];
      for (i = 0; i < n; i++) if (lengths[i]) symbol[offs[lengths[i]]++] = i;
      return { count: count, symbol: symbol };
    }
    function decode(h) {
      var code = 0, first = 0, index = 0;
      for (var len = 1; len < 16; len++) {
        code |= bits(1);
        var c = h.count[len];
        if (code - c < first) return h.symbol[index + (code - first)];
        index += c; first += c; first <<= 1; code <<= 1;
      }
      throw new Error('inflate: 坏码');
    }
    var LB = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];
    var LE = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
    var DB = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577];
    var DE = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13];
    function codes(lh, dh) {
      for (;;) {
        var sym = decode(lh);
        if (sym < 256) { grow(1); out[op++] = sym; }
        else if (sym === 256) return;
        else {
          sym -= 257;
          var len = LB[sym] + bits(LE[sym]);
          var ds = decode(dh);
          var dist = DB[ds] + bits(DE[ds]);
          grow(len);
          for (var k = 0; k < len; k++) { out[op] = out[op - dist]; op++; }
        }
      }
    }
    var fixL = null, fixD = null;
    for (var last = 0; !last;) {
      last = bits(1);
      var type = bits(2);
      if (type === 0) {
        bitbuf = 0; bitcnt = 0;
        var len = src[pos] | (src[pos + 1] << 8); pos += 4;
        grow(len); out.set(src.subarray(pos, pos + len), op); op += len; pos += len;
      } else if (type === 1) {
        if (!fixL) {
          var l = new Uint8Array(288), i;
          for (i = 0; i < 144; i++) l[i] = 8;
          for (; i < 256; i++) l[i] = 9;
          for (; i < 280; i++) l[i] = 7;
          for (; i < 288; i++) l[i] = 8;
          fixL = huff(l);
          var d = new Uint8Array(30); for (i = 0; i < 30; i++) d[i] = 5;
          fixD = huff(d);
        }
        codes(fixL, fixD);
      } else if (type === 2) {
        var nlen = bits(5) + 257, ndist = bits(5) + 1, ncode = bits(4) + 4;
        var ORD = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];
        var lens = new Uint8Array(19), j;
        for (j = 0; j < ncode; j++) lens[ORD[j]] = bits(3);
        var ch = huff(lens);
        var all = new Uint8Array(nlen + ndist);
        for (j = 0; j < nlen + ndist;) {
          var s = decode(ch);
          if (s < 16) all[j++] = s;
          else {
            var rep = 0, val = 0;
            if (s === 16) { val = all[j - 1]; rep = 3 + bits(2); }
            else if (s === 17) rep = 3 + bits(3);
            else rep = 11 + bits(7);
            while (rep--) all[j++] = val;
          }
        }
        codes(huff(all.subarray(0, nlen)), huff(all.subarray(nlen)));
      } else throw new Error('inflate: 坏块类型');
    }
    return out.subarray(0, op);
  }
})();
