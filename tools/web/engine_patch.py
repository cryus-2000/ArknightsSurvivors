"""网页导出后给引擎 JS（index.js）打的小补丁（docs/50 §40）。发布包（tools/export_web.py）与测量副本（tools/perf_web.py）共用。

1. window.__syAudioFree(id)：释放一条网页样本（引擎把每段音频整段解码成 AudioBuffer 留在 GodotAudio.samples 里，
   脚本没有注销接口；sfx.gd 切曲后按流的 instance id 调这个，释放后引擎认为没注册，下次播放会重新解码注册）。
   挂在第一次建样本时（Sample.create 里），那时 GodotAudio 已经就绪。
2. 主包少两份拷贝（11-08 docs/319 §10）：引擎把 index.pck 下载成 ArrayBuffer（Response.arrayBuffer() 又拼一份），
   再 FS.writeFile(new Uint8Array(buf)) 让 MEMFS slice 出第三份常驻。改成：分片加载器（loader.js）在 Response 上挂 __syBuf，
   引擎直接拿这块；MEMFS 用 canOwn 直接持有它，不再 slice。启动峰值从 3 份主包降到 1 份，常驻仍是 1 份（引擎要从 MEMFS 读资源）。
4. 样本注册记录：每次注册网页样本记 [秒, 时长秒, 当时堆容量 MB] 到 window.__syAudioRegs（只读，测量用）。
3. WASM 堆增长记录：每次 emscripten_resize_heap 记 [秒, 原容量 MB, 请求 MB] 到 window.__syWasmGrows（崩溃前快照 / --memlog 读）。
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


FS_COPY = "FS.writeFile(path,new Uint8Array(buffer))}"
FS_OWN = "FS.writeFile(path,new Uint8Array(buffer),{canOwn:true})}"
FETCH_A = "const tr = getTrackedResponse(response, tracker[file]);"
FETCH_B = ("if (!raw && response.__syBuf) { const n = response.__syBuf.byteLength; tracker[file].total = n; tracker[file].loaded = n; "
           "tracker[file].done = true; return Promise.resolve(response.__syBuf); } " + FETCH_A)
GROW_A = "var _emscripten_resize_heap=requestedSize=>{"
REG_A = "const audioBuffer=GodotAudio.ctx.createBuffer(numberOfChannels,framesTotal,sampleRate);"
REG_B = ("(window.__syAudioRegs=window.__syAudioRegs||[]).push([Math.round(performance.now()/1000),Math.round(framesTotal/sampleRate),HEAPU8.length>>>20]);" + REG_A)
GROW_B = GROW_A + "(window.__syWasmGrows=window.__syWasmGrows||[]).push([Math.round(performance.now()/1000),HEAPU8.length>>>20,(requestedSize>>>0)>>>20]);"


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
    for a, b in ((FS_COPY, FS_OWN), (FETCH_A, FETCH_B), (GROW_A, GROW_B), (REG_A, REG_B)):
        if b in s:
            continue
        if s.count(a) != 1:
            raise SystemExit("index.js 主包 / 堆增长补丁锚点不匹配：%s（docs/319 §10）" % a[:40])
        s = s.replace(a, b, 1)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(s)
