"""网页导出后给引擎 JS（index.js）打的小补丁（docs/50 §40）。发布包（tools/export_web.py）与测量副本（tools/perf_web.py）共用。

1. window.__syAudioFree(id)：释放一条网页样本（引擎把每段音频整段解码成 AudioBuffer 留在 GodotAudio.samples 里，
   脚本没有注销接口；sfx.gd 切曲后按流的 instance id 调这个，释放后引擎认为没注册，下次播放会重新解码注册）。
   挂在第一次建样本时（Sample.create 里），那时 GodotAudio 已经就绪。
2. 主包少两份拷贝（11-08 docs/319 §10）：引擎把 index.pck 下载成 ArrayBuffer（Response.arrayBuffer() 又拼一份），
   再 FS.writeFile(new Uint8Array(buf)) 让 MEMFS slice 出第三份常驻。改成：分片加载器（loader.js）在 Response 上挂 __syBuf，
   引擎直接拿这块；MEMFS 用 canOwn 直接持有它，不再 slice。启动峰值从 3 份主包降到 1 份，常驻仍是 1 份（引擎要从 MEMFS 读资源）。
4. 样本注册记录：每次注册网页样本记 [秒, 时长秒, 当时堆容量 MB] 到 window.__syAudioRegs（只读，测量用）。
7. window.__syLiveMB()：测量用，堆里实际在用的 MB（容量 − 1 MB 块能放下的空闲）；__syNoGrow 置位时堆增长直接失败。
6. window.__syFsSync()：把 user://（IDBFS）立刻写回 IndexedDB，返回 Promise（引擎自己的同步在进行中就先等它）。
   手机网页局与局之间整页重载（core/run_reload.gd，docs/319 §14）重载前等它，存档一定落盘。
3. WASM 堆增长记录：每次 emscripten_resize_heap 记 [秒, 原容量 MB, 请求 MB, 阶段] 到 window.__syWasmGrows（崩溃前快照 / --memlog 读；阶段 = window.__syPhase，游戏在开机 / 标题 / 建局各段写）。
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
# 5. 注册样本时引擎先把 WASM 堆里的左右声道各 new Float32Array 拷一份再 copyToChannel（无线程版堆不是 SharedArrayBuffer，
#    copyToChannel 直接收堆视图即可）：200 秒一首在 24 kHz 下是 2 × 18 MB 的 JS 临时拷贝，换曲那一刻正好叠在新旧两首上（docs/319 §10）
CH_A = "audioBuffer.copyToChannel(new Float32Array(subLeft),0,0);audioBuffer.copyToChannel(new Float32Array(subRight),1,0);"
CH_B = ("if(typeof SharedArrayBuffer!=='undefined'&&HEAPF32.buffer instanceof SharedArrayBuffer){" + CH_A + "}"
        "else{audioBuffer.copyToChannel(subLeft,0,0);audioBuffer.copyToChannel(subRight,1,0);}")
REG_A = "const audioBuffer=GodotAudio.ctx.createBuffer(numberOfChannels,framesTotal,sampleRate);"
REG_B = ("(window.__syAudioRegs=window.__syAudioRegs||[]).push([Math.round(performance.now()/1000),Math.round(framesTotal/sampleRate),HEAPU8.length>>>20]);" + REG_A)
FSS_A = "_syncing:false,_mount_points:[],"
FSS_B = ("_syncing:false,_syFs:(window.__syFsSync=function(){return Promise.resolve(GodotOS._fs_sync_promise).catch(function(){})"
         ".then(function(){return GodotFS._idbfs?GodotFS.sync():null})}),"
         # 7. 测量用：堆里现在实际在用多少（WASM 容量只涨不缩，看不出谁在占）。暂时禁止增长，按 1 MB 一块 malloc 到失败，
         #    能放下的块数 ≈ 容量里的空闲；容量 − 空闲 ≈ 在用（含 < 1 MB 的碎片）。随即全部 free。只在 --memlog 下由 frame_rec / art.mark 调
         "_syLive:(window.__syLiveMB=function(){var p=[],c=HEAPU8.length>>>20;window.__syNoGrow=1;try{for(var i=0;i<4096;i++){var a=_malloc(1048576);if(!a)break;p.push(a)}}"
         "finally{window.__syNoGrow=0}for(var j=0;j<p.length;j++)_free(p[j]);return c-p.length}),_mount_points:[],")
GROW_B = GROW_A + "if(window.__syNoGrow)return false;(window.__syWasmGrows=window.__syWasmGrows||[]).push([Math.round(performance.now()/1000),HEAPU8.length>>>20,(requestedSize>>>0)>>>20,String(window.__syPhase||'')]);"   # 第 4 项：当时的阶段（crash_box.phase 写）


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
    for a, b in ((FS_COPY, FS_OWN), (FETCH_A, FETCH_B), (GROW_A, GROW_B), (REG_A, REG_B), (CH_A, CH_B), (FSS_A, FSS_B)):
        if b in s:
            continue
        if s.count(a) != 1:
            raise SystemExit("index.js 主包 / 堆增长补丁锚点不匹配：%s（docs/319 §10）" % a[:40])
        s = s.replace(a, b, 1)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(s)
