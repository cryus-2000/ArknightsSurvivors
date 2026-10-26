"""网页导出后给引擎 JS（index.js）打的小补丁（docs/50 §40）。发布包（tools/export_web.py）与测量副本（tools/perf_web.py）共用。

1. window.__syAudioFree(id)：释放一条网页样本（引擎把每段音频整段解码成 AudioBuffer 留在 GodotAudio.samples 里，
   脚本没有注销接口；sfx.gd 切曲后按流的 instance id 调这个，释放后引擎认为没注册，下次播放会重新解码注册）。
   挂在第一次建样本时（Sample.create 里），那时 GodotAudio 已经就绪。
"""

ANCHOR = "GodotAudio.samples.set(params.id,sample);"
LEGACY_INJECT = ("if(!window.__syAudioFree){window.__syAudioFree=function(id){const s=GodotAudio.Sample.getSampleOrNull(String(id));if(s){s.clear();}};"
          "window.__syAudioMB=function(){let b=0;for(const [k,s] of GodotAudio.samples){const a=s._audioBuffer;if(a){b+=a.length*a.numberOfChannels*4;}}return b/1048576;};}")
# AudioBuffer is immutable during playback; each source keeps its own cursor, pitch and bus.
# Godot 4.7.2 otherwise duplicates the entire PCM on every play / loop / resume.
COPY = "getAudioBuffer(){return this._duplicateAudioBuffer()}"
SHARE = "getAudioBuffer(){return this._audioBuffer}"
INJECT = ("if(!window.__syAudioFree){window.__syAudioFree=function(id){id=String(id);"
          "for(const n of GodotAudio.sampleNodes.values()){if(n.streamObjectId===id)return false;}"
          "const s=GodotAudio.Sample.getSampleOrNull(id);if(s)s.clear();return true;};"
          "window.__syAudioMB=function(){const buffers=new Set;"
          "for(const s of GodotAudio.samples.values()){if(s._audioBuffer)buffers.add(s._audioBuffer);}"
          "for(const n of GodotAudio.sampleNodes.values()){if(n._source&&n._source.buffer)buffers.add(n._source.buffer);}"
          "let b=0;for(const a of buffers){b+=a.length*a.numberOfChannels*4;}return b/1048576;};}")


def patch_index_js(path: str) -> None:
    with open(path, encoding="utf-8") as fh:
        s = fh.read()
    # Validate every anchor before writing, including when upgrading an older export.
    if s.count(ANCHOR) != 1 or (s.count(COPY) + s.count(SHARE)) != 1:
        raise SystemExit("index.js 音频补丁锚点不匹配（Godot 网页引擎变了？docs/50 §40）")
    s = s.replace(LEGACY_INJECT, "", 1)
    if INJECT not in s:
        if "window.__syAudioFree" in s:
            raise SystemExit("index.js 带有未知版本的音频补丁")
        s = s.replace(ANCHOR, ANCHOR + INJECT, 1)
    s = s.replace(COPY, SHARE, 1)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(s)
