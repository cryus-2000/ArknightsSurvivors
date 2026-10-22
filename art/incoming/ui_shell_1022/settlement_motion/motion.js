/* Visual candidate: compositing the accepted still, never gameplay state. */
const canvas=document.querySelector('canvas'),ctx=canvas.getContext('2d');
ctx.imageSmoothingEnabled=false;
const reduce=document.querySelector('#reduce'),pause=document.querySelector('#pause');
const status=document.querySelector('#status'),source=new Image(),counts=new Image(),backdrop=new Image();
const squadCards=new Image();let offset=0,selected=0,drag=null,suppressClick=false;
const TEAM=['水月','斯卡蒂','流明','能天使','塞雷娅','凯尔希','德克萨斯'];
const VIEW={x:28,y:288,w:884,h:350}, MAX=224*TEAM.length-VIEW.w;
const DURATION=900;let elapsed=0,last=0,raf=0,paused=false,loaded=false;
const media=matchMedia('(prefers-reduced-motion: reduce)');reduce.checked=media.matches;
const clamp=n=>Math.max(0,Math.min(1,n));
const progress=(t,start,duration)=>clamp((t-start)/duration);
const cubic=p=>1-(1-p)**3;
function block(x,y,w,h,color){ctx.fillStyle=color;ctx.fillRect(x,y,w,h);}
function clearData(x,y,w,h){ctx.drawImage(backdrop,x,y,w,h,x,y,w,h);}
function draw(t){
  ctx.drawImage(source,0,0);
  drawSquad(t);
  if(t>=DURATION)return;
  // Short editorial reveal in the existing result field. No full-screen flash.
  const title=cubic(progress(t,0,220)), edge=Math.round(29+345*title);
  if(title<1)block(edge,84,374-edge,55,'#dfe2e6');
  // Counts are rasterised using the accepted frame's exact font and pixel mask.
  const rp=cubic(progress(t,120,380));
  if(rp<1){
    clearData(752,138,100,38);clearData(942,138,86,38);
    const a=Math.floor(28*rp),b=Math.floor(4*rp);
    ctx.drawImage(counts,0,a*40,100,40,754,140,100,40);
    ctx.drawImage(counts,100,b*40,80,40,944,140,80,40);
  }
  // Timeline enters as a single downward reveal, then the rating is archived.
  const timeline=progress(t,300,420);
  if(timeline<1){
    const y=294+Math.round(334*timeline);
    clearData(952,y,296,628-y);
  }
  const rating=progress(t,680,220);
  if(rating<1){
    clearData(1159,104,80,55);
    if(rating>0){
      ctx.globalAlpha=rating;
      const dy=Math.round(4*(1-cubic(rating)));
      ctx.drawImage(source,1159,104,80,55,1159,104+dy,80,55);
      ctx.globalAlpha=1;
    }
  }
}
function label(){status.textContent=elapsed>=DURATION?'归档完成':paused?'已暂停':'正在归档';pause.textContent=paused?'继续':'暂停';pause.disabled=elapsed>=DURATION;}
function tick(now){
  if(paused)return;
  if(last)elapsed=Math.min(DURATION,elapsed+now-last);
  last=now;draw(elapsed);label();
  if(elapsed<DURATION)raf=requestAnimationFrame(tick);
}
function finish(){cancelAnimationFrame(raf);elapsed=DURATION;paused=false;last=0;if(loaded)draw(elapsed);label();}
function replay(){
  if(!loaded)return;
  cancelAnimationFrame(raf);elapsed=0;last=0;paused=false;
  if(reduce.checked){finish();return;}
  draw(0);label();raf=requestAnimationFrame(tick);
}
document.querySelector('#replay').onclick=replay;
document.querySelector('#finish').onclick=finish;
pause.onclick=()=>{if(!loaded||elapsed>=DURATION)return;paused=!paused;cancelAnimationFrame(raf);last=0;label();if(!paused)raf=requestAnimationFrame(tick);};
reduce.onchange=()=>{if(reduce.checked)finish();};
media.addEventListener('change',e=>{reduce.checked=e.matches;if(e.matches)finish();});
canvas.onclick=()=>{if(!suppressClick)finish();suppressClick=false;};
document.addEventListener('keydown',e=>{if(e.key==='Enter'&&e.target===document.body){e.preventDefault();finish();}});
Promise.all([[source,'../settlement/settlement_desktop.png'],[counts,'counts.png'],[backdrop,'backdrop.png'],[squadCards,'squad_cards.png']].map(([img,url])=>new Promise((resolve,reject)=>{img.onload=resolve;img.onerror=reject;img.src=url;}))).then(()=>{loaded=true;replay();}).catch(()=>{status.textContent='素材载入失败';});
// Deterministic review hooks; never used by game code.
window.settlementReview={seek(t){cancelAnimationFrame(raf);elapsed=Math.max(0,Math.min(DURATION,t));paused=true;draw(elapsed);label();},get state(){return{elapsed,paused,loaded,reduced:reduce.checked,offset,selected,total:TEAM.length,maxOffset:MAX};}};

function drawSquad(t){
  ctx.save();ctx.beginPath();ctx.rect(VIEW.x,VIEW.y,VIEW.w,VIEW.h);ctx.clip();
  block(VIEW.x,VIEW.y,VIEW.w,VIEW.h,'#13171e');
  ctx.drawImage(squadCards,Math.round(offset),0,VIEW.w,VIEW.h,VIEW.x,VIEW.y,VIEW.w,VIEW.h);
  for(let i=0;i<4;i++){
    const p=cubic(progress(t,240+i*60,300)),x=36+224*i-offset;
    const width=Math.round(186*[.561,.290,.060,.089][i])+1;
    if(p<1)block(x+Math.round(width*p),539,width-Math.round(width*p),5,'#2a313d');
  }
  block(VIEW.x+selected*224-offset+16,288,40,2,'#38d6f0');ctx.restore();
  block(140,230,280,32,'#13171e');ctx.fillStyle='#969ca6';ctx.font='12px system-ui';
  const first=Math.floor(offset/224)+1,last=Math.min(TEAM.length,Math.ceil((offset+VIEW.w)/224));
  ctx.fillText(`${first}–${last} / 共 ${TEAM.length} 名`,140,248);
  block(28,638,884,12,'#13171e');block(64,642,812,2,'#2a313d');
  const thumb=812*VIEW.w/(224*TEAM.length);
  block(64+(812-thumb)*offset/MAX,641,thumb,3,'#38d6f0');
  ctx.fillStyle=offset>0?'#38d6f0':'#566171';ctx.fillText('‹',32,649);
  ctx.fillStyle=offset<MAX?'#38d6f0':'#566171';ctx.fillText('›',895,649);
  canvas.setAttribute('aria-label',`结算样例，本局编队共七名，当前选择${TEAM[selected]}。方向键切换干员。`);
}
function moveTo(value){offset=Math.max(0,Math.min(MAX,value));if(loaded)draw(elapsed);}
function select(index){selected=Math.max(0,Math.min(TEAM.length-1,index));
  const left=selected*224,right=left+212;
  moveTo(left<offset?left:right>offset+VIEW.w?right-VIEW.w:offset);
}
function point(e){const r=canvas.getBoundingClientRect();return{x:(e.clientX-r.left)*1280/r.width,y:(e.clientY-r.top)*720/r.height};}
function inside(p){return p.x>=28&&p.x<=912&&p.y>=280&&p.y<=650;}
canvas.addEventListener('wheel',e=>{if(!inside(point(e)))return;e.preventDefault();moveTo(offset+(Math.abs(e.deltaX)>Math.abs(e.deltaY)?e.deltaX:e.deltaY));},{passive:false});
canvas.addEventListener('pointerdown',e=>{const p=point(e);if(!inside(p))return;
  canvas.focus({preventScroll:true});canvas.setPointerCapture(e.pointerId);
  drag={x:p.x,start:offset,moved:false};
  if(p.y>=638){moveTo(offset+(p.x<470?-224:224));drag.moved=true;}
});
canvas.addEventListener('pointermove',e=>{if(!drag)return;const dx=point(e).x-drag.x;
  if(Math.abs(dx)>5)drag.moved=true;if(drag.moved)moveTo(drag.start-dx);
});
canvas.addEventListener('pointerup',e=>{if(!drag)return;
  if(!drag.moved)select(Math.floor((point(e).x-28+offset)/224));
  suppressClick=true;drag=null;if(canvas.hasPointerCapture(e.pointerId))canvas.releasePointerCapture(e.pointerId);
});
canvas.addEventListener('pointercancel',()=>{drag=null;suppressClick=true;});
canvas.addEventListener('keydown',e=>{
  if(!['ArrowLeft','ArrowRight','Home','End','Enter'].includes(e.key))return;e.preventDefault();
  if(e.key==='Enter'){finish();return;}
  select(e.key==='Home'?0:e.key==='End'?TEAM.length-1:selected+(e.key==='ArrowLeft'?-1:1));
});
