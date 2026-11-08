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
		watch(c);
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
	// 11-07 用户 iPhone B站 App 实测：从别的 App 切回来以后没声音。iOS / WebKit 会把上下文挂起（suspended）或中断（interrupted，来电 / 切 App），
	// 回到前台不会自己恢复，非手势里的 resume() 也常常不生效。所以：回到前台（visibilitychange 可见、pageshow、focus）先试一次 resume；
	// 仍不是 running（或之后 statechange 掉回非 running）就重新挂上手势监听，下一次 touchstart / pointerdown / 点按 / 按键里再 resume。
	// resume 不改各总线音量（Godot 的总线增益在音频图里，挂起只是停时钟），不会爆音
	var GEST = ["pointerup", "touchend", "click", "mousedown", "keydown", "touchstart", "pointerdown"];
	var armed = false;
	function arm() {
		if (armed) return;
		armed = true;
		GEST.forEach(function (t) { document.addEventListener(t, gesture, true); });
	}
	function disarm() {
		if (!armed) return;
		armed = false;
		GEST.forEach(function (t) { document.removeEventListener(t, gesture, true); });
	}
	// 11-08 协调人：iOS 26.6 上上面这套仍不够——切出 App 再切回，仍然没声音。WebKit 回前台后常见两种坏法：
	// ① 非手势里的 resume() 让 state 变回 running，第一下手势看到全 running 就撤了监听，但音频输出其实没接回（state 说 running、时钟不走或没声）；
	// ② 系统中断（interrupted）不一定发 statechange。所以回前台后记 stale：之后 STALE_N 下手势里每个上下文都在手势内同步「suspend() 再 resume()」
	// 重启输出、重放一段静音缓冲，再播一个静音 <audio> 元素（让 WebKit 重新激活媒体音频会话）；另有 1 秒一次的看门狗：可见时状态不是 running、
	// 或 running 但 currentTime 不走，就重新挂手势监听并记 stale
	var STALE_N = 2, stale = 0, silentEl = null;
	function silentAudio() {
		try {
			if (!silentEl) {
				// 0.05 秒 8 kHz 单声道静音 WAV
				var n = 400, b = new Uint8Array(44 + n), v = new DataView(b.buffer);
				var w = function (o, t) { for (var k = 0; k < t.length; k++) b[o + k] = t.charCodeAt(k); };
				w(0, "RIFF"); v.setUint32(4, 36 + n, true); w(8, "WAVEfmt "); v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 1, true);
				v.setUint32(24, 8000, true); v.setUint32(28, 8000, true); v.setUint16(32, 1, true); v.setUint16(34, 8, true); w(36, "data"); v.setUint32(40, n, true);
				for (var k = 0; k < n; k++) b[44 + k] = 128;
				silentEl = document.createElement("audio");
				silentEl.setAttribute("playsinline", "");
				silentEl.preload = "auto";
				silentEl.src = URL.createObjectURL(new Blob([b], { type: "audio/wav" }));
			}
			silentEl.currentTime = 0;
			var pr = silentEl.play();
			if (pr && pr.catch) pr.catch(function () {});
		} catch (e) {}
	}
	function gesture() {
		window.__syGesture = 1;
		var all = list.length > 0;
		var restart = stale > 0;
		if (restart) {
			stale--;
			silentAudio();
		}
		for (var i = 0; i < list.length; i++) {
			var c = list[i];
			if (restart) {
				try { if (c.state === "running") c.suspend(); c.resume(); } catch (e) {}   // 同一手势里同步排队：先停再起，重新接上输出
				c.__syKicked = 0;
			}
			kick(c);
			if (c.state !== "running") all = false;
		}
		window.__syAudioRestarts = (window.__syAudioRestarts || 0) + (restart ? 1 : 0);
		if (all && stale <= 0) disarm();
	}
	function watch(c) {
		if (c.__syWatch || !c.addEventListener) return;
		c.__syWatch = 1;
		c.addEventListener("statechange", function () {
			if (c.state !== "running" && !document.hidden) arm();   // 被系统挂起 / 中断（interrupted）：等下一下手势
		});
	}
	function back(re) {   // 回到前台（re：真从后台回来——visibilitychange / pageshow；窗口 focus 只补 resume，不重启输出）
		if (re) stale = STALE_N;
		for (var i = 0; i < list.length; i++) {
			watch(list[i]);
			try { if (list[i].state !== "running") list[i].resume(); } catch (e) {}
		}
		arm();   // 先挂上：resume 是异步的，没恢复的话下一下手势接着唤醒；都 running 了下一下手势自己撤掉
	}
	arm();
	setInterval(function () {   // 看门狗（见上）
		if (document.hidden) return;
		for (var i = 0; i < list.length; i++) {
			var c = list[i], t = c.currentTime;
			if (c.state !== "running") arm();
			else if (c.__syLastT !== undefined && t === c.__syLastT && c.__syKicked) { if (stale <= 0) stale = 1; arm(); }
			c.__syLastT = t;
		}
	}, 1000);
	window.__syAudioKick = gesture;
	window.__syAudioState = function () { return list.map(function (c) { return c.state; }).join(","); };   // 自测 / 日志用
	document.addEventListener("visibilitychange", function () {
		if (document.hidden) {
			for (var i = 0; i < list.length; i++) { try { list[i].suspend(); } catch (e) {} }
		} else back(true);
	});
	window.addEventListener("pageshow", function () { if (!document.hidden) back(true); });
	window.addEventListener("focus", function () { if (!document.hidden) back(); });
})();
