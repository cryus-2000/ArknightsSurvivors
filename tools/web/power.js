// 页面隐藏时挂起音频（docs/50 §33 手机发烫）：切到别的标签 / 回桌面后浏览器会停 requestAnimationFrame（引擎主循环跟着停），
// 但 Web Audio 的 AudioContext 照转——网页版配乐 / 音效是解码好的样本，留在音频图里继续播放、音频线程一直醒着。
// 引擎建 AudioContext 之前把构造函数包一层记下实例，visibilitychange 时 suspend / resume。放在 gl_state.js 后面、引擎脚本之前
(function () {
	var A = window.AudioContext || window.webkitAudioContext;
	if (!A) return;
	var list = [];
	// 手机网页的音频上下文采样率（docs/50 §40）：引擎把每段样本按「上下文采样率 × 双声道 × float32」整段解码进内存，48 kHz 时 15 秒一句 5.5 MB；
	// 手机上按 24 kHz 建上下文，样本内存约减半（外放听不出）。网址带 ?sr=<Hz> 可覆盖（0 = 不改）
	var q = new URLSearchParams(location.search).get("sr");
	var phone = (navigator.maxTouchPoints > 1 || "ontouchstart" in window) && Math.min(screen.width, screen.height) <= 600;
	var want = q !== null ? Number(q) : (phone ? 24000 : 0);
	window.__sySampleRate = want;
	function Wrapped(opts) {
		if (want > 0) {
			opts = Object.assign({}, opts || {}, { sampleRate: want });
		}
		var c = opts === undefined ? new A() : new A(opts);
		list.push(c);
		if (window.__syGesture) kick(c);   // 加载中已经点过屏幕：引擎晚建的上下文也立刻试着唤醒（Chrome 认粘性激活；Safari 不认就等下一下点按）
		return c;
	}
	Wrapped.prototype = A.prototype;
	window.AudioContext = Wrapped;
	if (window.webkitAudioContext) window.webkitAudioContext = Wrapped;
	window.__syAudioCtx = list;   // 自测用（tools/probes/power_web.py --hidecheck）
	// 手机要点一下才有声音（11-07 用户「点击了之后才会有声音，就算在加载页也没有声音」）：浏览器只认「激活手势」里唤醒的音频上下文，
	// 而触屏的 pointerdown 不算激活（HTML 规范：触屏只有 pointerup / touchend / click 算，鼠标是 mousedown / pointerdown，键盘 keydown），
	// 加载页「开始游戏」原来只在 pointerdown 里 resume，手机上白调——要等进标题页后点某个按钮（touchend）才出声。
	// 这里从页面一开始就在捕获阶段听这几种手势：每一下都唤醒全部上下文，并在每个上下文里放一段 1 帧静音缓冲（老版 iOS WebKit 要真起一个音源才解锁）；
	// 全部 running 后撤掉监听。加载中点过屏幕的话，加载完直接有声音
	function kick(c) {
		try { if (c.state !== "running" && !document.hidden) c.resume(); } catch (e) {}
		if (c.__syKicked) return;
		try {
			var b = c.createBuffer(1, 1, c.sampleRate), s = c.createBufferSource();
			s.buffer = b;
			s.connect(c.destination);
			s.start(0);
			c.__syKicked = 1;
		} catch (e) {}
	}
	var GEST = ["pointerup", "touchend", "click", "mousedown", "keydown"];
	function gesture() {
		window.__syGesture = 1;
		var all = list.length > 0;
		for (var i = 0; i < list.length; i++) {
			kick(list[i]);
			if (list[i].state !== "running") all = false;
		}
		if (all) GEST.forEach(function (t) { document.removeEventListener(t, gesture, true); });
	}
	GEST.forEach(function (t) { document.addEventListener(t, gesture, true); });
	window.__syAudioKick = gesture;
	document.addEventListener("visibilitychange", function () {
		for (var i = 0; i < list.length; i++) {
			try {
				if (document.hidden) list[i].suspend();
				else list[i].resume();
			} catch (e) {}
		}
	});
})();
