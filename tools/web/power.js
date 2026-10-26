// 页面隐藏时挂起音频（docs/50 §33 手机发烫）：切到别的标签 / 回桌面后浏览器会停 requestAnimationFrame（引擎主循环跟着停），
// 但 Web Audio 的 AudioContext 照转——网页版配乐 / 音效是解码好的样本，留在音频图里继续播放、音频线程一直醒着。
// 引擎建 AudioContext 之前把构造函数包一层记下实例，visibilitychange 时 suspend / resume。放在 gl_state.js 后面、引擎脚本之前
(function () {
	var A = window.AudioContext || window.webkitAudioContext;
	if (!A) return;
	var list = [];
	function Wrapped(opts) {
		var c = opts === undefined ? new A() : new A(opts);
		list.push(c);
		return c;
	}
	Wrapped.prototype = A.prototype;
	window.AudioContext = Wrapped;
	if (window.webkitAudioContext) window.webkitAudioContext = Wrapped;
	window.__syAudioCtx = list;   // 自测用（tools/probes/power_web.py --hidecheck）
	document.addEventListener("visibilitychange", function () {
		for (var i = 0; i < list.length; i++) {
			try {
				if (document.hidden) list[i].suspend();
				else list[i].resume();
			} catch (e) {}
		}
	});
})();
