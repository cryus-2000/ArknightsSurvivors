"""网页导出后给引擎 JS（index.js）打的小补丁（docs/50 §40）。发布包（tools/export_web.py）与测量副本（tools/perf_web.py）共用。

1. window.__syAudioFree(id)：释放一条网页样本（引擎把每段音频整段解码成 AudioBuffer 留在 GodotAudio.samples 里，
   脚本没有注销接口；sfx.gd 切曲后按流的 instance id 调这个，释放后引擎认为没注册，下次播放会重新解码注册）。
   挂在第一次建样本时（Sample.create 里），那时 GodotAudio 已经就绪。
"""

ANCHOR = "GodotAudio.samples.set(params.id,sample);"
INJECT = ("if(!window.__syAudioFree){window.__syAudioFree=function(id){const s=GodotAudio.Sample.getSampleOrNull(String(id));if(s){s.clear();}};"
          "window.__syAudioMB=function(){let b=0;for(const [k,s] of GodotAudio.samples){const a=s._audioBuffer;if(a){b+=a.length*a.numberOfChannels*4;}}return b/1048576;};}")


def patch_index_js(path: str) -> None:
    with open(path, encoding="utf-8") as fh:
        s = fh.read()
    if "window.__syAudioFree" in s:
        return
    if ANCHOR not in s:
        raise SystemExit("index.js 里找不到 %s（Godot 网页引擎变了？docs/50 §40）" % ANCHOR)
    s = s.replace(ANCHOR, ANCHOR + INJECT, 1)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(s)
