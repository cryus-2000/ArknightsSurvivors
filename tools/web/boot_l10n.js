// 网页加载页的语言（11-16，docs/22「加载链路」）：export_web.py 把它作为 head 里第一个自有 script 内联（在 boot_err.js 之前），
// 首帧壳 / 诊断卡 / 加载页画出来之前选好语言。只用 ES5；这一段出错时什么都不设，壳按中文显示（boot_shell.html 缺省就是中文）。
// 判定顺序：Toy 包（导出时写 LOCK = 1）一律中文 → 游戏存的界面语言 localStorage sy_lang（settings.gd apply_lang 写）→ navigator.language
//   （zh* 中文 / ja* 日语 / ko* 韩语 / 其余英语）。网址 ?sylang=en|ja|ko|zh 临时指定（截图测试用）。
// 结果：window.__syL；<html data-sylang>（壳里四种语言的文字靠 CSS 选一种显示）。
// window.__syT(zh, a, b)：按中文原文查译文（字典 D 导出时从 game/l10n/ui.csv 与 tools/web/loader_l10n.json 生成，Toy 包为空），
//   {0} / {1} 换成 a / b；查不到返回中文原文。
(function () {
  var LOCK = /*SY_LOCK_ZH*/0;
  var D = /*SY_L10N*/{};
  var IDX = { en: 0, ja: 1, ko: 2 };
  var L = 'zh';
  try {
    if (!LOCK) {
      var q = /[?&]sylang=(zh|en|ja|ko)\b/.exec(location.search);
      var s = '';
      try { s = localStorage.getItem('sy_lang') || ''; } catch (e) {}
      if (q) L = q[1];
      else if (/^(zh|en|ja|ko)$/.test(s)) L = s;
      else {
        var n = String(navigator.language || (navigator.languages && navigator.languages[0]) || '').toLowerCase();
        L = n.indexOf('zh') === 0 ? 'zh' : n.indexOf('ja') === 0 ? 'ja' : n.indexOf('ko') === 0 ? 'ko' : 'en';
      }
    }
  } catch (e) { L = 'zh'; }
  window.__syL = L;
  try {
    document.documentElement.setAttribute('data-sylang', L);
    document.documentElement.lang = { zh: 'zh-CN', en: 'en', ja: 'ja', ko: 'ko' }[L];
  } catch (e) {}
  window.__syT = function (zh, a, b) {
    var s = zh, r = L !== 'zh' && D[zh];
    if (r && r[IDX[L]]) s = r[IDX[L]];
    if (a !== undefined) s = s.split('{0}').join(String(a));
    if (b !== undefined) s = s.split('{1}').join(String(b));
    return s;
  };
})();
