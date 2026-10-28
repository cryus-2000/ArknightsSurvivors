(() => {
  const defaults = JSON.parse(document.getElementById('initial-layout').textContent);
  const svg = document.querySelector('svg');
  const groups = [...svg.querySelectorAll('g')].filter(g => g.querySelector(':scope > title'));
  const fields = Object.fromEntries(['x','y','radius'].map(k => [k,document.getElementById(k)]));
  const status = document.getElementById('status');
  const storageKey = 'deep-blue-medal-layout-v1';
  const motionButton=document.getElementById('motion');
  let motionPaused=false;
  const reducedMotion=window.matchMedia('(prefers-reduced-motion: reduce)');
  function updateMotion(){
    if(motionPaused||document.hidden||reducedMotion.matches)svg.pauseAnimations();
    else svg.unpauseAnimations();
  }
  if(motionButton)motionButton.onclick=()=>{motionPaused=!motionPaused;motionButton.textContent=motionPaused?'播放背景':'暂停背景';updateMotion();};
  document.addEventListener('visibilitychange',updateMotion);
  reducedMotion.addEventListener('change',updateMotion);
  updateMotion();
  let state = structuredClone(defaults), selected = 3, drag = null, history = [];
  const A=Math.sqrt(3)/2, clearance=0.8;
  const axes=[[1,0],[.5,A],[.5,-A]];
  function overlaps(a,b) {
    return axes.every(([nx,ny])=>Math.abs((a.center[0]-b.center[0])*nx+(a.center[1]-b.center[1])*ny)<A*(a.radius+b.radius)+clearance-1e-7);
  }
  function valid(value, expected=defaults.medals) {
    return value && Array.isArray(value.medals) && value.medals.length === expected.length &&
      expected.every(d => value.medals.filter(m => m.id === d.id).length === 1) &&
      value.medals.every(m => Array.isArray(m.center) && m.center.length === 2 &&
        m.center.every(Number.isFinite) && Number.isFinite(m.radius) && m.radius >= 35 && m.radius <= 220 &&
        m.center[0] >= 0 && m.center[0] <= 1672 && m.center[1] >= 0 && m.center[1] <= 941) &&
      value.medals.every((m,i)=>value.medals.slice(i+1).every(n=>!overlaps(m,n)));
  }
  function migrate(value) {
    if(valid(value))return value;
    if(!value||!Array.isArray(value.medals))return null;
    // Remove retired medals from older exports without moving survivors.
    value={...value,medals:value.medals.filter(m=>m&&m.id!==6&&m.id!==9)};
    if(valid(value))return value;
    const legacy=defaults.medals.filter(m=>m.id<=9);
    if(!valid(value,legacy))return null;
    const migrated=structuredClone(value);
    for(const base of defaults.medals.filter(m=>m.id>9)){
      const m=structuredClone(base);
      if(migrated.medals.some(n=>overlaps(m,n))){
        let best=null,score=Infinity;
        for(let x=560+m.radius;x<=1672-m.radius;x+=8){
          for(let y=m.radius+40;y<=880-m.radius;y+=8){
            const candidate={...m,center:[x,y]},cost=Math.hypot(x-base.center[0],y-base.center[1]);
            if(cost<score&&migrated.medals.every(n=>!overlaps(candidate,n))){best=candidate;score=cost;}
          }
        }
        if(!best)return null;m.center=best.center;
      }
      migrated.medals.push(m);
    }
    return migrated;
  }
  function upgradeEnding(value){
    if(!value||value.styleRevision===2)return value;
    value=structuredClone(value);
    const m=value.medals.find(n=>n.id===1);
    if(m.radius<112){
      const origin=[...m.center];m.radius=112;
      if(value.medals.some(n=>n.id!==1&&overlaps(m,n))){
        let best=null,score=Infinity;
        for(let x=560+112;x<=1672-112;x+=4)for(let y=152;y<=768;y+=4){
          const candidate={...m,center:[x,y]},cost=Math.hypot(x-origin[0],y-origin[1]);
          if(cost<score&&value.medals.every(n=>n.id===1||!overlaps(candidate,n))){best=candidate;score=cost;}
        }
        if(!best)return null;m.center=best.center;
      }
    }
    value.styleRevision=2;return value;
  }
  try { const saved=upgradeEnding(migrate(JSON.parse(localStorage.getItem(storageKey))));if(saved)state=saved; } catch {}
  const medal = () => state.medals.find(m => m.id === selected);
  function checkpoint() { history.push(JSON.stringify(state)); if(history.length>80) history.shift(); }
  function persist() {
    try { localStorage.setItem(storageKey,JSON.stringify(state)); status.textContent='已保存在此浏览器；定稿后请导出布局文件。'; }
    catch { status.textContent='浏览器未允许本地保存，请导出布局文件保留修改。'; }
  }
  function render() {
    state.medals.forEach(m => {
      const index=defaults.medals.findIndex(d=>d.id===m.id), base=defaults.medals[index], g=groups[index];
      g.setAttribute('transform',`translate(${m.center[0]} ${m.center[1]}) scale(${m.radius/base.radius})`);
      g.classList.toggle('selected',m.id===selected);
    });
    const m=medal(); fields.x.value=m.center[0].toFixed(1); fields.y.value=m.center[1].toFixed(1); fields.radius.value=m.radius.toFixed(1);
    document.getElementById('chosen').value=String(selected);
    document.getElementById('undo').disabled=!history.length;
  }
  function point(e) { return new DOMPoint(e.clientX,e.clientY).matrixTransform(svg.getScreenCTM().inverse()); }
  function move(x,y) {
    const m=medal(),dx=Math.max(0,Math.min(1672,x))-m.center[0],dy=Math.max(0,Math.min(941,y))-m.center[1];
    let travel=1;
    // Swept hexagon SAT: stop at the first contact, even if a pointer event
    // jumps all the way past another medal.
    for(const other of state.medals){
      if(other.id===m.id)continue;
      const extent=A*(m.radius+other.radius)+clearance;
      let enter=-Infinity,exit=Infinity;
      for(const [nx,ny] of axes){
        const start=(m.center[0]-other.center[0])*nx+(m.center[1]-other.center[1])*ny,velocity=dx*nx+dy*ny;
        if(Math.abs(velocity)<1e-10){if(Math.abs(start)>=extent-1e-7){exit=-Infinity;break;}continue;}
        const t1=(-extent-start)/velocity,t2=(extent-start)/velocity;
        enter=Math.max(enter,Math.min(t1,t2));exit=Math.min(exit,Math.max(t1,t2));
      }
      if(enter<exit-1e-9&&exit>1e-9&&enter<travel)travel=Math.max(0,enter-1e-6);
    }
    m.center=[m.center[0]+dx*travel,m.center[1]+dy*travel];render();
  }
  function resize(value){
    const m=medal();let radius=Math.max(35,Math.min(220,value));
    for(const other of state.medals){
      if(other.id===m.id)continue;
      const separation=Math.max(...axes.map(([nx,ny])=>Math.abs((m.center[0]-other.center[0])*nx+(m.center[1]-other.center[1])*ny)));
      radius=Math.min(radius,(separation-clearance)/A-other.radius);
    }
    m.radius=radius;
  }
  groups.forEach((g,i)=>{
    const id=defaults.medals[i].id;g.classList.add('medal');
    g.addEventListener('pointerdown',e=>{
      if(e.button!==0)return;
      e.preventDefault();selected=id;checkpoint();const p=point(e),m=medal();
      drag={id:e.pointerId,x:p.x,y:p.y,origin:[...m.center]};svg.setPointerCapture(e.pointerId);render();
    });
  });
  svg.addEventListener('pointermove',e=>{
    if(!drag||drag.id!==e.pointerId)return;const p=point(e);
    move(drag.origin[0]+p.x-drag.x,drag.origin[1]+p.y-drag.y);
  });
  function end(e){if(drag&&drag.id===e.pointerId){drag=null;persist();}}
  svg.addEventListener('pointerup',end);svg.addEventListener('pointercancel',end);
  document.getElementById('chosen').addEventListener('change',e=>{selected=Number(e.target.value);render();});
  Object.entries(fields).forEach(([k,input])=>input.addEventListener('change',()=>{
    const v=Number(input.value);if(!Number.isFinite(v)||input.value===''){render();return;}
    checkpoint();if(k==='radius')resize(v);
    else {const m=medal();move(k==='x'?v:m.center[0],k==='y'?v:m.center[1]);}render();persist();
  }));
  function undo(){if(history.length){state=JSON.parse(history.pop());render();persist();}}
  document.getElementById('undo').onclick=undo;
  document.addEventListener('keydown',e=>{
    if(/INPUT|SELECT|TEXTAREA/.test(e.target.tagName))return;
    if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='z'){e.preventDefault();undo();return;}
    const delta={ArrowLeft:[-1,0],ArrowRight:[1,0],ArrowUp:[0,-1],ArrowDown:[0,1]}[e.key];
    if(!delta)return;e.preventDefault();if(!e.repeat)checkpoint();const step=e.shiftKey?10:1,m=medal();
    move(m.center[0]+delta[0]*step,m.center[1]+delta[1]*step);persist();
  });
  document.getElementById('reset').onclick=()=>{checkpoint();state=structuredClone(defaults);render();persist();};
  document.getElementById('clean').onclick=()=>svg.classList.toggle('clean');
  document.getElementById('export').onclick=()=>{
    const result={version:1,styleRevision:2,canvas:[1672,941],medals:state.medals};
    const url=URL.createObjectURL(new Blob([JSON.stringify(result,null,2)],{type:'application/json'}));
    const a=document.createElement('a');a.href=url;a.download='深蓝之下-章组布局.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
    status.textContent='已发起布局文件下载；把文件发回即可按你的排版继续。';
  };
  document.getElementById('import').onchange=async e=>{
    const file=e.target.files[0];if(!file)return;
    try{const incoming=upgradeEnding(migrate(JSON.parse(await file.text())));if(!incoming)throw Error();checkpoint();state={styleRevision:2,canvas:[1672,941],medals:incoming.medals};render();persist();}
    catch{status.textContent='文件格式不正确或徽章重叠，原布局未更改。';}e.target.value='';
  };
  render();status.textContent='拖动任意章。方向键移动 1px，Shift + 方向键移动 10px。';
})();
