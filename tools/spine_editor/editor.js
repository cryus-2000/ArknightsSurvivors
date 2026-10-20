'use strict';
(async function() {
  const $=id=>document.getElementById(id), P=PoseCore;
  const message=(s,error=false)=>{$('message').textContent=s;$('message').classList.toggle('error',error);};
  try {
    const get=async url=>{const r=await fetch(url);if(!r.ok)throw Error(`读取失败 ${url}`);return r;};
    const project=await (await get('/project.json')).json();
    const atlasText=await (await get('/native.atlas')).text();
    const image=new Image();await new Promise((ok,fail)=>{image.onload=ok;image.onerror=()=>fail(Error('读取失败 /texture.png'));image.src='/texture.png';});
    const atlas=new spine.TextureAtlas(atlasText,()=>new spine.canvas.CanvasTexture(image));
    const loader=new spine.AtlasAttachmentLoader(atlas);
    // 3.5 用转出的 JSON，3.8 直接读二进制 .skel（服务端按文件头版本选运行库）
    const data=project.format==='skel'
      ?new spine.SkeletonBinary(loader).readSkeletonData(new Uint8Array(await (await get('/native.skel')).arrayBuffer()))
      :new spine.SkeletonJson(loader).readSkeletonData(await (await get('/native.json')).json());
    if(project.base==='native')nativeBase();
    // --operator 原生底稿：八帧骨骼由运行库算出（动画 t=0 或八等分），地面（脚部附件最低点）平移到 y=0。
    function nativeBase() {
      const anim=data.findAnimation(project.anim);
      if(!anim)throw Error(`骨架没有动画 ${project.anim}；可用：${data.animations.map(a=>a.name).join(' ')}`);
      const pose=t=>{const s=new spine.Skeleton(data);s.setToSetupPose();P.applyAnimation(spine,anim,s,t);s.updateWorldTransform();return s;};
      const names=data.bones.map(b=>b.name);
      if(names.join('\n')!==project.bones.join('\n'))throw Error('服务端读出的骨骼表与运行库不一致');
      const first=pose(0),visible=new Set(first.slots.filter(s=>s.getAttachment()).map(s=>s.bone.data.name));
      // 同名多套骨骼：换成底稿里有可见附件的那套，标签随之移过去
      for(const [primary,cands] of Object.entries(project.alternates||{})){
        const pick=Object.keys(cands).find(c=>project.chains[c].some(n=>visible.has(n)))||primary;
        if(pick===primary)continue;
        for(const n of Object.keys(cands[primary]))delete project.labels[n];
        Object.assign(project.labels,cands[pick]);
      }
      const ends=Object.keys(project.chains).filter(c=>project.labels[c]);
      if(!project.labels[project.default_bone])project.default_bone=ends.find(c=>project.equipment[c])||ends[0];
      const feet=new Set(ends.filter(c=>project.labels[c].includes('腿')).flatMap(c=>{const out=[];for(const b of first.bones)for(let p=b;p;p=p.parent)if(p.data.name===c){out.push(b.data.name);break;}return out;}));
      let ground=Infinity,any=Infinity;
      for(const slot of first.slots){
        const att=slot.getAttachment();if(!(att instanceof spine.MeshAttachment||att instanceof spine.RegionAttachment))continue;
        const v=P.worldVertices(spine,slot,att);
        for(let n=1;n<v.length;n+=2){any=Math.min(any,v[n]);if(feet.has(slot.bone.data.name))ground=Math.min(ground,v[n]);}
      }
      if(!Number.isFinite(ground))ground=any;
      const dx=(project.origin_shift||0)/project.scale;
      project.frames.forEach((row,i)=>{
        row.t=row.t??row.phase*anim.duration;const s=pose(row.t);
        row.bones=s.bones.map(b=>({name:b.data.name,parent:b.parent?b.parent.data.name:undefined,world:[b.worldX+dx,b.worldY-ground],matrix:[b.a,b.b,b.c,b.d]}));
        row.order=s.drawOrder.map(slot=>slot.data.name);
      });
    }
    const base=()=>({version:1,source:project.id,frames:project.frames.map(()=>({ops:[],order:null}))});
    let patch=base(),frame=0,playing=false,lastTick=0,drag=null,model=null,sk=null;
    let history=[],future=[],dirty=false,renderPending=false,hidden=null;
    const cache=new Map(),native=$('native'),pixel=$('pixel'),ctx=native.getContext('2d');
    const span=160,left=48,top=64,k=native.width/span;
    pixel.width=span;pixel.height=span;
    const labels=Object.keys(project.labels||{}).length?project.labels:{F_Hip:'髋部 / 整体',F_Waist:'腰部',F_Chest:'胸部',F_Head:'头部',F_Weapon:'锤子',
      F_R_Arm:'持锤侧 · 肩',F_R_Shoulder:'持锤侧 · 肘',F_R_Hand:'持锤手 · 手腕',
      F_L_Arm:'摆臂侧 · 肩',F_L_Shoulder:'摆臂侧 · 肘',F_L_Hand:'摆臂手 · 手腕',
      F_R_Leg:'近侧 · 髋',F_R_Calf:'近侧 · 膝',F_R_Foot:'近侧 · 脚踝',
      F_L_Leg:'远侧 · 髋',F_L_Calf:'远侧 · 膝',F_L_Foot:'远侧 · 脚踝'};
    const major=Object.keys(labels).filter(n=>project.bones.includes(n));
    const names=[...major,...project.bones.filter(n=>!major.includes(n))];
    for(const name of names){const o=document.createElement('option');o.value=name;o.textContent=labels[name]||name;$('bone').append(o);}
    $('bone').value=project.default_bone||major[0];
    function worldToView(b){return [(128+b.worldX*project.scale-left)*k,(180-b.worldY*project.scale-top)*k];}
    function eventWorld(e){const r=native.getBoundingClientRect();return [((e.clientX-r.left)/r.width*span+left-128)/project.scale,(180-((e.clientY-r.top)/r.height*span+top))/project.scale];}
    function skeleton(i,fp) {
      const source=project.frames[i],s=new spine.Skeleton(data);s.setToSetupPose();
      P.applyAnimation(spine,data.findAnimation(source.anim),s,source.t);s.updateWorldTransform();
      const b=P.makeBones(source.bones);P.apply(b,fp.ops,project.chains,project.equipment);
      for(const node of s.bones){const v=b[node.data.name];for(const key of ['worldX','worldY','a','b','c','d'])node[key]=v[key];}
      s.drawOrder=(fp.order||source.order).map(n=>s.findSlot(n));
      for(const name of source.hidden){const slot=s.findSlot(name);if(slot)slot.attachment=null;}
      return {s,b};
    }
    function drawNative(s,opacity=1) {
      const saved=hidden?s.findSlot(hidden)?.attachment:null;
      if(hidden)s.findSlot(hidden).attachment=null;
      ctx.save();ctx.globalAlpha=opacity;ctx.translate((128-left)*k,(180-top)*k);ctx.scale(project.scale*k,-project.scale*k);
      const renderer=new spine.canvas.SkeletonRenderer(ctx);renderer.triangleRendering=true;renderer.draw(s);ctx.restore();
      if(hidden)s.findSlot(hidden).attachment=saved;
    }
    // Pixelize each attachment before composing. Never downscale the flattened character.
    function pixels(s,inspectHidden=null,enforceBounds=false) {
      const out=document.createElement('canvas');out.width=out.height=256;const oc=out.getContext('2d');
      const saved=s.drawOrder.map(slot=>slot.getAttachment());let clip=null;
      const high=document.createElement('canvas'),low=document.createElement('canvas');
      try {
        for(let i=0;i<saved.length;i++) {
          const att=saved[i],slot=s.drawOrder[i];
          if(!att)continue;
          // 3.8 剪裁附件：记录多边形，按层序裁到 endSlot
          if(spine.ClippingAttachment&&att instanceof spine.ClippingAttachment){clip={end:att.endSlot&&att.endSlot.name,v:P.worldVertices(spine,slot,att)};continue;}
          if(slot.data.name===inspectHidden||!(att instanceof spine.MeshAttachment||att instanceof spine.RegionAttachment)){if(clip&&clip.end===slot.data.name)clip=null;continue;}
          for(let j=0;j<saved.length;j++)s.drawOrder[j].attachment=j===i?saved[j]:null;
          const vertices=P.worldVertices(spine,slot,att),xs=[],ys=[];
          for(let n=0;n<vertices.length;n+=2){xs.push(128+vertices[n]*project.scale);ys.push(180-vertices[n+1]*project.scale);}
          const x=Math.floor(Math.min(...xs))-1,y=Math.floor(Math.min(...ys))-1;
          const w=Math.ceil(Math.max(...xs))-x+1,h=Math.ceil(Math.max(...ys))-y+1;
          if(!Number.isFinite(w)||w<=0||w>1024||h<=0||h>1024)throw Error('部件超出编辑范围');
          high.width=w*4;high.height=h*4;const hc=high.getContext('2d');
          hc.save();hc.translate((128-x)*4,(180-y)*4);hc.scale(project.scale*4,-project.scale*4);
          if(clip){hc.beginPath();for(let n=0;n<clip.v.length;n+=2)hc[n?'lineTo':'moveTo'](clip.v[n],clip.v[n+1]);hc.closePath();hc.clip();}
          const renderer=new spine.canvas.SkeletonRenderer(hc);renderer.triangleRendering=true;renderer.draw(s);hc.restore();
          if(clip&&clip.end===slot.data.name)clip=null;
          low.width=w;low.height=h;const lc=low.getContext('2d',{willReadFrequently:true});lc.drawImage(high,0,0,w,h);
          const id=lc.getImageData(0,0,w,h),a=id.data;let max=0;
          for(let n=3;n<a.length;n+=4)max=Math.max(max,a[n]);
          const threshold=Math.max(1,Math.min(96,max)),colors=new Map();
          for(let n=0;n<a.length;n+=4){
            if(a[n+3]<threshold){a[n]=a[n+1]=a[n+2]=a[n+3]=0;continue;}
            const key=a[n]*65536+a[n+1]*256+a[n+2];let rgb=colors.get(key);
            if(!rgb){let best=Infinity;for(const c of project.palette){const d=(c[0]-a[n])**2+(c[1]-a[n+1])**2+(c[2]-a[n+2])**2;if(d<best){best=d;rgb=c;}}colors.set(key,rgb);}
            a[n]=rgb[0];a[n+1]=rgb[1];a[n+2]=rgb[2];a[n+3]=255;
            const px=x+(n/4)%w,py=y+Math.floor(n/4/w);
            if(enforceBounds&&(px<0||py<0||px>=256||py>=256))throw Error(`部件 ${slot.data.name} 超出 256 场景，已停止导出，请缩小移动幅度`);
          }
          lc.putImageData(id,0,0);
          oc.globalCompositeOperation=['source-over','lighter','multiply','screen'][slot.data.blendMode]||'source-over';oc.drawImage(low,x,y);
        }
      } finally {for(let i=0;i<saved.length;i++)s.drawOrder[i].attachment=saved[i];}
      return out;
    }
    function refreshLayers() {
      const value=$('layers').value,order=patch.frames[frame].order||project.frames[frame].order;
      $('layers').replaceChildren();for(const n of [...order].reverse()){const o=document.createElement('option');o.value=n;o.textContent=n;$('layers').append(o);}
      $('layers').value=order.includes(value)?value:order[order.length-1];
    }
    function render(fp=patch.frames[frame]) {
      ({s:sk,b:model}=skeleton(frame,fp));ctx.clearRect(0,0,native.width,native.height);
      ctx.strokeStyle='#6a7c8a';ctx.lineWidth=1;const floor=(180-top)*k;ctx.beginPath();ctx.moveTo(0,floor);ctx.lineTo(native.width,floor);ctx.stroke();
      if($('onion').checked)drawNative(skeleton((frame+7)%8,patch.frames[(frame+7)%8]).s,.18);
      drawNative(sk);
      if($('bones').checked){
        for(const n of new Set([...major,$('bone').value])){
          const b=model[n],[x,y]=worldToView(b);let parent=model[b.parentName];while(parent&&!major.includes(parent.name))parent=model[parent.parentName];
          if(parent){const [px,py]=worldToView(parent);ctx.beginPath();ctx.moveTo(px,py);ctx.lineTo(x,y);ctx.strokeStyle='#78c7dba0';ctx.lineWidth=2;ctx.stroke();}
          ctx.beginPath();ctx.arc(x,y,n===$('bone').value?8:5,0,Math.PI*2);ctx.fillStyle=n===$('bone').value?'#fff39c':'#6ce4e5';ctx.fill();ctx.strokeStyle='#153240';ctx.stroke();
        }
      }
      const key=JSON.stringify([frame,fp,hidden]);let result=cache.get(key);
      if(!result){result=pixels(sk,hidden);if(cache.size>40)cache.clear();cache.set(key,result);}
      const pc=pixel.getContext('2d');pc.clearRect(0,0,span,span);pc.drawImage(result,-left,-top);
      $('clock').textContent=`第 ${frame+1} / 8 帧 · ${(8/project.fps).toFixed(3)} 秒`;
      for(const b of $('frames').children)b.classList.toggle('active',Number(b.dataset.index)===frame);
      $('undo').disabled=!history.length;$('redo').disabled=!future.length;
    }
    function safeRender(fp){try{render(fp);}catch(e){stop();message(e.message,true);}}
    function stop(){playing=false;$('play').textContent='播放';}
    function remember(){history.push(structuredClone(patch));if(history.length>60)history.shift();future=[];}
    function changed(){dirty=true;refreshLayers();safeRender();message('已修改当前帧。点击「保存姿势」写入本地；导出不会覆盖原始素材。');}
    function commit(op){stop();const candidate=structuredClone(patch);candidate.frames[frame].ops.push(op);P.validatePatch(candidate,project);remember();patch=candidate;changed();}
    function selectFrame(i){stop();frame=(i+8)%8;hidden=null;$('hide').checked=false;refreshLayers();safeRender();}
    for(let i=0;i<8;i++){const b=document.createElement('button');b.textContent=String(i+1).padStart(2,'0');b.dataset.index=i;b.onclick=()=>selectFrame(i);$('frames').append(b);}
    $('prev').onclick=()=>selectFrame(frame-1);$('next').onclick=()=>selectFrame(frame+1);
    $('play').onclick=()=>{playing=!playing;$('play').textContent=playing?'暂停':'播放';lastTick=performance.now();};
    function tick(now){if(playing){const dt=1000/project.fps/Number($('speed').value);if(now-lastTick>=dt){frame=(frame+Math.floor((now-lastTick)/dt))%8;lastTick=now;refreshLayers();safeRender();}}requestAnimationFrame(tick);}
    $('bone').onchange=()=>{stop();safeRender();};$('bones').onchange=()=>safeRender();$('onion').onchange=()=>safeRender();
    function operation(e,d){
      const target=eventWorld(e),b=d.model[d.bone];
      if(d.mode==='rotate')return {type:'rotate',bone:d.bone,degrees:(Math.atan2(target[1]-b.worldY,target[0]-b.worldX)-Math.atan2(d.start[1]-b.worldY,d.start[0]-b.worldX))*180/Math.PI};
      const dx=target[0]-d.start[0],dy=target[1]-d.start[1];
      return d.mode==='ik'?{type:'ik',bone:d.bone,target:[b.worldX+dx,b.worldY+dy]}:{type:'translate',bone:d.bone,dx,dy};
    }
    native.onpointerdown=e=>{
      stop();const r=native.getBoundingClientRect(),x=(e.clientX-r.left)/r.width*native.width,y=(e.clientY-r.top)/r.height*native.height;
      let best=22,hit=null;for(const n of new Set([...major,$('bone').value])){const [px,py]=worldToView(model[n]),d=Math.hypot(px-x,py-y);if(d<best){best=d;hit=n;}}
      const [sx,sy]=worldToView(model[$('bone').value]);
      if(Math.hypot(sx-x,sy-y)<22)hit=$('bone').value;
      // Rotation may start away from the joint to give a usable lever arm.
      if(hit)$('bone').value=hit;else if($('mode').value!=='rotate')return;
      const bone=$('bone').value,mode=$('mode').value;
      if(mode==='ik'&&!project.chains[bone]){message('此关节不是手腕或脚踝。请选旋转模式，或使用「移动整支骨骼」。');safeRender();return;}
      drag={bone,mode,start:eventWorld(e),model:structuredClone(model),original:structuredClone(patch.frames[frame]),op:null};
      native.setPointerCapture(e.pointerId);safeRender();
    };
    native.onpointermove=e=>{if(!drag)return;drag.op=operation(e,drag);if(!renderPending){renderPending=true;requestAnimationFrame(()=>{renderPending=false;if(drag)safeRender({...drag.original,ops:[...drag.original.ops,drag.op]});});}};
    native.onpointerup=e=>{if(!drag)return;const op=drag.op;drag=null;if(native.hasPointerCapture(e.pointerId))native.releasePointerCapture(e.pointerId);if(op){try{commit(op);}catch(err){message(err.message,true);safeRender();}}else safeRender();};
    native.onpointercancel=()=>{drag=null;safeRender();};
    function nudge(dx,dy){const n=$('bone').value,b=model[n];try{if(project.chains[n])commit({type:'ik',bone:n,target:[b.worldX+dx/project.scale,b.worldY+dy/project.scale]});else if($('mode').value==='move')commit({type:'translate',bone:n,dx:dx/project.scale,dy:dy/project.scale});else message('请选择手腕 / 脚踝，或切换整支骨骼移动模式。');}catch(e){message(e.message,true);}}
    $('left').onclick=()=>nudge(-1,0);$('right').onclick=()=>nudge(1,0);$('up').onclick=()=>nudge(0,1);$('down').onclick=()=>nudge(0,-1);
    $('rotate').onclick=()=>{try{commit({type:'rotate',bone:$('bone').value,degrees:Number($('angle').value)});$('angle').value=0;}catch(e){message(e.message,true);}};
    function reorder(delta){stop();const order=[...(patch.frames[frame].order||project.frames[frame].order)],i=order.indexOf($('layers').value),j=i+delta;if(j<0||j>=order.length)return;remember();[order[i],order[j]]=[order[j],order[i]];patch.frames[frame].order=order;changed();}
    $('front').onclick=()=>reorder(1);$('back').onclick=()=>reorder(-1);
    $('hide').onchange=()=>{hidden=$('hide').checked?$('layers').value:null;safeRender();};
    $('layers').onchange=()=>{hidden=$('hide').checked?$('layers').value:null;safeRender();};
    $('reset').onclick=()=>{stop();remember();patch.frames[frame]={ops:[],order:null};changed();};
    $('undo').onclick=()=>{if(!history.length)return;stop();future.push(structuredClone(patch));patch=history.pop();changed();};
    $('redo').onclick=()=>{if(!future.length)return;stop();history.push(structuredClone(patch));patch=future.pop();changed();};
    async function post(url,body){const r=await fetch(url,{method:'POST',headers:{'Content-Type':'application/json','X-Editor-Token':project.token},body:JSON.stringify(body)});const data=await r.json();if(!r.ok)throw Error(data.error);return data;}
    $('save').onclick=async()=>{stop();const snapshot=structuredClone(patch);try{const result=await post('/save',{patch:snapshot});dirty=JSON.stringify(patch)!==JSON.stringify(snapshot);message(`已保存：${result.path}`);}catch(e){message(e.message,true);}};
    $('download').onclick=()=>{const url=URL.createObjectURL(new Blob([JSON.stringify(patch,null,2)],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download=(project.character||'operator')+'_run_pose.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);};
    $('import').onchange=async()=>{stop();try{const f=$('import').files[0];if(!f)return;if(f.size>1_000_000)throw Error('姿势文件过大');const p=JSON.parse(await f.text());P.validatePatch(p,project);remember();patch=p;changed();message('姿势已载入。原生骨架来源指纹匹配。');}catch(e){message(e.message,true);}finally{$('import').value='';}};
    $('export').onclick=async()=>{
      stop();const snapshot=structuredClone(patch);$('export').disabled=true;
      try{const frames=[];for(let i=0;i<8;i++){message(`正在逐附件像素化并导出 ${i+1} / 8…`);await new Promise(r=>setTimeout(r,0));const c=pixels(skeleton(i,snapshot.frames[i]).s,null,true);frames.push(c.toDataURL('image/png').split(',')[1]);}
        const result=await post('/export',{patch:snapshot,frames});const div=$('exports');div.replaceChildren();const p=document.createElement('p');p.textContent=`导出位置：${result.path}`;div.append(p);
        for(const [label,url] of [['查看 GIF',result.url],['下载 PNG 帧条',result.strip]]){const a=document.createElement('a');a.textContent=label;a.href=url;a.target='_blank';a.rel='noopener';div.append(a);}message('八帧导出完成。姿势 JSON 随图保存；尚未进行游戏接入验收。');
      }catch(e){message(e.message,true);}finally{$('export').disabled=false;safeRender();}
    };
    window.addEventListener('beforeunload',e=>{if(dirty){e.preventDefault();e.returnValue='';}});
    const draft=await (await get('/draft.json')).json();let draftWarning='';
    if(draft){try{P.validatePatch(draft,project);patch=draft;}catch(e){draftWarning='旧草稿来源已变化，未自动应用；旧文件仍保留。';}}
    document.querySelectorAll('button,select,input').forEach(el=>el.disabled=false);
    $('source').textContent=`${project.title} · Spine ${project.spine||''} · 八帧 · ${(8/project.fps).toFixed(3)} 秒 · 原始素材只读`;
    refreshLayers();render();requestAnimationFrame(tick);
    message(draftWarning||'已就绪。选中持武器手或脚踝，拖动圆点或点击方向键微调；修改只作用于当前帧。');
  } catch(e) {message(`载入失败：${e.message}`,true);console.error(e);}
})();
