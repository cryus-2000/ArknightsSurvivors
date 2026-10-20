// 网页 WebGL 状态缓存（docs/50 §21，10-21）：Godot 网页模板固定用 emscripten 的 OFFSCREEN_FRAMEBUFFER + explicitSwapControl，
// 每帧 emscripten_webgl_commit_frame → blitOffscreenFramebuffer 先 gl.getParameter(SCISSOR_TEST) / getParameter(FRAMEBUFFER_BINDING)
// 记下当前状态再把离屏缓冲拷到画布。Chromium 里这两次查询是同步回读：渲染进程要等 GPU 进程把这一帧的命令全部做完才返回，
// CPU 与 GPU 进程没法流水并行（CDP 采样：后期满屏怪时整页 CPU 的 19% 停在这里）。
// 这里在建 WebGL2 上下文时包一层：enable / disable / bindFramebuffer 照常调用并顺手记下剪裁开关与绘制帧缓冲绑定，
// 这两项 getParameter 直接答记下的值（与真实状态相同：所有改它们的调用都经过这层），其余查询原样转发。不改引擎、不改画面。
// ?glsync=1：关掉（诊断用）；?glcheck=1：每次快答时再问一次真实值，不一致计数进 window.__syGlMismatch 并打印前几条
(function () {
  if (/[?&]glsync=1/.test(location.search)) return;
  var check = /[?&]glcheck=1/.test(location.search);
  var SCISSOR_TEST = 3089, FRAMEBUFFER = 36160, DRAW_FRAMEBUFFER = 36009, FRAMEBUFFER_BINDING = 36006;
  var orig = HTMLCanvasElement.prototype.getContext;
  window.__syGlMismatch = 0;
  HTMLCanvasElement.prototype.getContext = function (type, attrs) {
    var gl = orig.call(this, type, attrs);
    if (!gl || type !== 'webgl2' || gl.__syGlState) return gl;
    gl.__syGlState = true;
    var scissor = gl.isEnabled(SCISSOR_TEST), fbo = gl.getParameter(FRAMEBUFFER_BINDING);
    var en = gl.enable, dis = gl.disable, bind = gl.bindFramebuffer, get = gl.getParameter;
    gl.enable = function (cap) { if (cap === SCISSOR_TEST) scissor = true; return en.call(gl, cap); };
    gl.disable = function (cap) { if (cap === SCISSOR_TEST) scissor = false; return dis.call(gl, cap); };
    gl.bindFramebuffer = function (target, fb) {
      if (target === FRAMEBUFFER || target === DRAW_FRAMEBUFFER) fbo = fb;
      return bind.call(gl, target, fb);
    };
    gl.getParameter = function (p) {
      if (p !== SCISSOR_TEST && p !== FRAMEBUFFER_BINDING) return get.call(gl, p);
      var v = p === SCISSOR_TEST ? scissor : fbo;
      if (check) {
        var real = get.call(gl, p);
        if (real !== v) {
          window.__syGlMismatch++;
          if (window.__syGlMismatch <= 5) console.error('GLSTATE mismatch', p, real, v);
        }
      }
      return v;
    };
    return gl;
  };
})();
