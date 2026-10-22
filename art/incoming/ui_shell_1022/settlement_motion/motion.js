/* Visual candidate: compositing the accepted still, never gameplay state. */
const canvas=document.querySelector('canvas'),ctx=canvas.getContext('2d');
ctx.imageSmoothingEnabled=false;
const reduce=document.querySelector('#reduce'),pause=document.querySelector('#pause');
const status=document.querySelector('#status'),source=new Image(),counts=new Image(),backdrop=new Image();
const DURATION=900;let elapsed=0,last=0,raf=0,paused=false,loaded=false;
const media=matchMedia('(prefers-reduced-motion: reduce)');reduce.checked=media.matches;
const clamp=n=>Math.max(0,Math.min(1,n));
const progress=(t,start,duration)=>clamp((t-start)/duration);
const cubic=p=>1-(1-p)**3;
function block(x,y,w,h,color){ctx.fillStyle=color;ctx.fillRect(x,y,w,h);}
function clearData(x,y,w,h){ctx.drawImage(backdrop,x,y,w,h,x,y,w,h);}
function draw(t){
  ctx.drawImage(source,0,0);
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
  // Damage fills, preserving the approved track lengths and final shares.
  for(let i=0;i<4;i++){
    const p=cubic(progress(t,240+i*60,300)),x=36+224*i;
    const width=Math.round(186*[.561,.290,.060,.089][i])+1;
    if(p<1)block(x+Math.round(width*p),539,width-Math.round(width*p),5,'#2a313d');
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
canvas.onclick=finish;
document.addEventListener('keydown',e=>{if(e.key==='Enter'&&e.target===document.body){e.preventDefault();finish();}});
Promise.all([[source,'../settlement/settlement_desktop.png'],[counts,'counts.png'],[backdrop,'backdrop.png']].map(([img,url])=>new Promise((resolve,reject)=>{img.onload=resolve;img.onerror=reject;img.src=url;}))).then(()=>{loaded=true;replay();}).catch(()=>{status.textContent='素材载入失败';});
// Deterministic review hooks; never used by game code.
window.settlementReview={seek(t){cancelAnimationFrame(raf);elapsed=Math.max(0,Math.min(DURATION,t));paused=true;draw(elapsed);label();},get state(){return{elapsed,paused,loaded,reduced:reduce.checked};}};
