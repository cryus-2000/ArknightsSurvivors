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
      f = 0.6 + 0.2 * (1 - Math.exp(-s / 6));   // 引擎启动：拿不到真实进度，按已等秒数向 80% 渐近；之后游戏内启动页（boot_screen.gd）从 80% 接着走
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

  function buildV(d) {
    var segs = '';
    for (var i = 0; i < 50; i++) segs += '<i></i>';
    var h = '';
    if (BV === 1) {
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
    d.innerHTML = h + FOOT;
    var q = function (s) { return d.querySelector(s); };
    return { root: d, lines: q('.sv-lines'), tip: q('.sv-tip .bd'), code: q('.sv-code'), segs: d.querySelectorAll('.sv-segs i'), pct: q('.sv-pct'),
      what: q('.sv-what'), ruler: q('.sv-ruler'), depth: q('.sv-depth'), sync: q('.sv-sync'), deep: q('.sv-deep'), jelly: q('.sv-jwrap'),
      ticks: d.querySelectorAll('.sv-ticks line'), num: q('.sv-num'), rows: q('.sv-rows'), contacts: q('.sv-contacts'), build: q('.sv-build'), dark: q('.sv-dark'), net: d.querySelectorAll('.sv-net line') };
  }

  // 每次 upd() 调：f = 进度 0–1，stage = {key, text, ok}，n / total = 编译到第几个（Godot 回传后才有）
  function updV(v, f, stage) {
    logStep(stage.key, stage.text, stage.ok);
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
        var x = (Math.cos(ang) * rad).toFixed(1), y = (Math.sin(ang) * rad).toFixed(1);
        var hit = (ang / (2 * Math.PI)) * 3.2, dl = (((hit - el3) % 3.2) + 3.2) % 3.2 - 3.2;
        ch += '<g class="' + (logs[ci].ok ? 'dn' : 'go') + '" transform="translate(' + x + ' ' + y + ')">' +
          '<circle class="pg" r="6" style="animation-delay:' + dl.toFixed(2) + 's"/>' +
          (logs[ci].ok ? '<rect x="-3" y="-3" width="6" height="6"/>' : '<rect class="bx" x="-4" y="-4" width="8" height="8"/><rect x="-1.5" y="-1.5" width="3" height="3"/>') +
          '<text x="8" y="-5">' + ('0' + ci).slice(-2) + '</text></g>';
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

  function finish(d) {
    var ti = Math.floor(Math.random() * TIPS.length);
    el.tip.textContent = TIPS[ti];
    upd();
    var tick = 0, closing = false, tipTimer = 0;
    var out = function () {
      if (closing) return;
      closing = true;
      clearInterval(t);
      clearTimeout(tipTimer);
      d.classList.add('sy-out');
      setTimeout(function () { d.remove(); }, 400);
    };
    // One visual owner: download, engine and Godot warm-up update this same page.
    window.__syBootUp = function () {
      bootProgress = Math.max(shownProgress, 0.6);
      bootLabel = '准备主菜单';
      upd();
    };
    window.__syBootProgress = function (value, label) {
      if (closing || !Number.isFinite(value)) return;
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
  if (document.body) build(); else document.addEventListener('DOMContentLoaded', build);

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
      return new Response(out, { status: 200, headers: { 'Content-Type': e.type, 'Content-Length': String(e.size) } });
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
