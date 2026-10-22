'use strict';
const canvas=document.querySelector('canvas'),ctx=canvas.getContext('2d');
const sea=document.createElement('canvas');sea.width=282;sea.height=160;const s=sea.getContext('2d');
const C={bg:'#13171e',ink:'#111318',white:'#dfe2e6',mute:'#969ca6',cyan:'#38d6f0',line:'#39414e'};
const hard=[['敌人生命与伤害','+20%'],['Boss 生命','+15%'],['大群规模','+20%'],['Boss 预警时间','-15%'],['队长初始最大生命','-10%'],['受击灯火损失','+30%'],['灯油掉落','-40%'],['源石锭掉落','-25%'],['小怪控制开始','05:00'],['寒霜冻结层数','2 层'],['围猎时长／圈上海嗣生命','-15%'],['灯标刷新间隔','-20%']];
const extreme=[['敌人生命','+70%'],['敌人造成的伤害','+35%'],['Boss 生命','+35%'],['Boss 伤害额外提高','+15%'],['大群规模','+60%'],['Boss 预警时间','-20%'],['队长初始最大生命','-10%'],['受击灯火损失','+60%'],['灯油掉落','-60%'],['源石锭掉落','-25%'],['小怪控制开始','05:00'],['寒霜冻结层数','2 层'],['围猎时长／圈上海嗣生命','-30%'],['灯标刷新间隔','-40%'],['后期敌人伤害成长上限','+50%'],['终局新刷杂兵生命倍率','×1.00'],['Boss 在场时大群照常来袭',''],['自然溟痕常驻，灯标可驱散','']];
const tiers=[{cn:'标准',en:'STANDARD',color:'#38d6f0',water:'#17303d',factor:'×1.00',grade:'S',rules:[],count:'08',label:'海面 / SURFACE'}, {cn:'困难',en:'HARD',color:'#ffce00',water:'#132532',factor:'×1.25',grade:'SS',rules:hard,count:'03',label:'深水 / DEEP WATER'}, {cn:'极限',en:'EXTREME',color:'#ef727d',water:'#101b2a',factor:'×1.50',grade:'SSS',rules:extreme,count:'00',label:'海渊 / ABYSS'}];
let tier=1,depth=1,from=1,change=1,clock=0,paused=false,reduced=matchMedia('(prefers-reduced-motion: reduce)').matches,last=0,ready=false;
const images={};
function image(name){return new Promise((resolve,reject)=>{let im=new Image();im.onload=()=>{images[name]=im;resolve()};im.onerror=()=>reject(Error('Asset missing: '+name));im.src='assets/'+name+'.png'})}
function rect(x,y,w,h,col,c=ctx){c.fillStyle=col;c.fillRect(Math.round(x),Math.round(y),w,h)}
function line(points,col,w=1,c=ctx){c.beginPath();c.strokeStyle=col;c.lineWidth=w;points.forEach((p,i)=>i?c.lineTo(Math.round(p[0]),Math.round(p[1])):c.moveTo(Math.round(p[0]),Math.round(p[1])));c.stroke()}
function text(x,y,str,size=18,col=C.white,align='left'){ctx.font=size+'px px';ctx.fillStyle=col;ctx.textAlign=align;ctx.textBaseline='top';ctx.fillText(str,x,y)}
function choose(i){if(i===tier)return;from=depth;tier=Math.max(0,Math.min(2,i));change=0;document.querySelectorAll('[data-tier]').forEach(b=>b.setAttribute('aria-pressed',Number(b.dataset.tier)===tier));draw()}
document.querySelectorAll('[data-tier]').forEach(b=>b.onclick=()=>choose(Number(b.dataset.tier)));
document.querySelector('#pause').onclick=()=>{paused=!paused;document.querySelector('#pause').textContent=paused?'播放':'暂停'};
document.querySelector('#reduce').checked=reduced;
document.querySelector('#reduce').onchange=e=>{reduced=e.target.checked;depth=tier;draw()};
canvas.onkeydown=e=>{if(['ArrowUp','ArrowDown','1','2','3'].includes(e.key)){e.preventDefault();choose(e.key==='ArrowUp'?tier-1:e.key==='ArrowDown'?tier+1:Number(e.key)-1)}};
canvas.onclick=e=>{const b=canvas.getBoundingClientRect(),x=(e.clientX-b.left)*1280/b.width,y=(e.clientY-b.top)*720/b.height;if(x<267&&y>200&&y<580)choose(y<320?0:y<460?1:2)};
const silhouettes={};
const sourceBounds={e_skimmer:[42,66,92,66],e_path:[74,90,154,138],e_mother:[58,74,110,94]};
function buildSilhouettes(){for(const [name,im] of Object.entries(images)){const [x,y,w,h]=sourceBounds[name],c=document.createElement('canvas');c.width=w;c.height=h;const g=c.getContext('2d');g.drawImage(im,x,y,w,h,0,0,w,h);g.globalCompositeOperation='source-in';g.fillStyle='#080f1a';g.fillRect(0,0,w,h);silhouettes[name]=c}}
function shadow(name,x,y,width){const im=silhouettes[name];s.drawImage(im,Math.round(x),Math.round(y),width,Math.round(im.height*width/im.width))}
function fish(x,y,size,dir,col,tm,kind=0){
 x=Math.round(x);y=Math.round(y);s.save();s.translate(x,y);s.scale(dir,1);s.fillStyle=col;
 const h=kind===1?Math.max(2,Math.round(size*.65)):kind===2?1:Math.max(1,Math.round(size/3));
 s.beginPath();s.moveTo(0,0);s.lineTo(size,-h);s.lineTo(size+3,0);s.lineTo(size,h);s.closePath();s.fill();
 if(kind===1){line([[size-1,-h],[size-3,-h-2],[size-3,h+2],[size,h]],col,1,s)}
 if(kind===2){rect(size+2,0,4,1,col,s)}
 const wag=Math.floor(tm*3+x)%2;s.fillRect(-2,-1-wag,2,3+wag);if(size>5)rect(size,0,1,1,'#111c28',s);s.restore();
}
function whale(x,y,tm){
 s.save();s.translate(Math.round(x),Math.round(y));s.fillStyle='#294150';
 const tail=Math.round(Math.sin(tm*.35)*2);
 const p=[[0,3],[3,0],[10,-2],[22,-2],[33,1],[43,5],[51,6],[56,1+tail],[63,-1+tail],[60,6+tail],[55,9],[59,13+tail],[52,12+tail],[47,9],[37,10],[25,13],[11,12],[3,9]];
 s.beginPath();p.forEach(([a,b],i)=>i?s.lineTo(a,b):s.moveTo(a,b));s.closePath();s.fill();
 s.beginPath();s.moveTo(24,10);s.lineTo(35,19);s.lineTo(32,11);s.fill();
 line([[3,7],[10,9],[22,10]],'#344c58',1,s);rect(7,4,1,1,'#162b38',s);s.restore();
}
function octopus(x,y,tm){
 x=Math.round(x);y=Math.round(y);const col='#526578';
 rect(x+3,y-12,6,2,col,s);rect(x+1,y-10,10,7,col,s);rect(x+3,y-3,6,3,col,s);
 for(let j=0;j<4;j++){const sway=Math.round(Math.sin(tm*.7+j)*1);line([[x+3+j,y-1],[x-3+j*4,y+3],[x-4+j*4+sway,y+5],[x-6+j*5+sway,y+4]],col,1,s)}
}
function terrain(x,k=0){const u=x/282;return Math.round(25+90/(1+Math.exp(-(u-.46)*10))+Math.sin(u*19)*4+k*7)}
function ocean(){
 s.imageSmoothingEnabled=false;rect(0,0,282,160,tiers[tier].water,s);
 // Only discrete translations move. No brightness oscillation or full-screen effects.
 const tm=reduced?0:clock;const surface=5-Math.round(depth*3);
 for(let x=0;x<282;x++){const y=surface+Math.round(Math.sin(x/15+tm*.45));rect(x,y,1,1,'#6999a7',s)}
 // Shallow broad light contracts into narrow deep-water slits.
 s.fillStyle=depth<.5?'#203d49':depth<1.5?'#19303e':'#142533';
 const beamWidth=Math.round(56-depth*18),shift=Math.round(Math.sin(tm*.12)*3);
 s.beginPath();s.moveTo(176+shift,surface);s.lineTo(176+beamWidth+shift,surface);s.lineTo(144+beamWidth,91);s.lineTo(144,91);s.fill();
 // Distant whale sits behind all other wildlife: slow and lower contrast.
 whale(181+Math.round(Math.sin(tm*.07)*12),16+Math.round(Math.sin(tm*.16)),tm);
 const drift=Math.round(Math.sin(tm*.16)*7);
 if(depth<.5){shadow('e_skimmer',167+drift,53,23)}
 else if(depth<1.5){shadow('e_skimmer',157+drift,51,31);shadow('e_mother',226-drift,87,25)}
 else{shadow('e_path',197+drift,67,66);shadow('e_mother',143-drift,70,26);shadow('e_skimmer',218-drift,45,26)}
 // Three schools have independent drift and speed; fish remain above the seabed.
 for(let group=0;group<3;group++)for(let j=0;j<8-tier*2;j++){
   const dir=group===1?-1:1,base=group===0?58:group===1?135:217;
   const x=base+(j%4)*12+Math.round(Math.sin(tm*.17+group)*14),y=12+group*17+Math.floor(j/4)*7+Math.round(Math.sin(tm*.6+j)*1);
   if(y<terrain(x)-8)fish(x,y,group===1?4:2,dir,['#608b98','#4c7586','#365868'][group],tm,group);
 }
 for(const [x,y,size,kind] of [[138,39,6,1],[246,65,7,2],[187,80,5,0]]){const xx=x+Math.round(Math.sin(tm*.12+x)*9);if(y<terrain(xx)-6)fish(xx,y,size,-1,'#36566a',tm,kind)}
 // Foreground geology occludes the bottom of the creatures, anchoring them in the trench.
 for(let k=0;k<6;k++){s.beginPath();for(let x=0;x<=282;x++)x?s.lineTo(x,terrain(x,k)):s.moveTo(x,terrain(x,k));s.lineTo(282,160);s.lineTo(0,160);s.closePath();s.fillStyle=['#263744','#22303c','#1e2a35','#1a2530','#17212b','#141d26'][k];s.fill();s.strokeStyle=k?'#2d404e':'#496372';s.lineWidth=1;s.beginPath();for(let x=0;x<=282;x++)x?s.lineTo(x,terrain(x,k)):s.moveTo(x,terrain(x,k));s.stroke()}
 // Rock-anchored kelp, branching coral and small benthic colonies.
 for(const [x,height] of [[19,17],[58,20],[110,14],[206,23],[267,21]]){
   const y=terrain(x),sway=reduced?0:Math.round(Math.sin(tm*.5+x)*2);
   for(let k=-1;k<=1;k++)line([[x+k*3,y],[x+k*3+1,y-6],[x+k*4+sway,y-height+5],[x+k*4+sway+1,y-height]],k?'#365c65':'#48747a',1,s);
 }
 for(const x of [83,179,242]){const y=terrain(x);line([[x,y],[x,y-11],[x-5,y-16],[x-5,y-20]],'#596278',1,s);line([[x,y-5],[x+6,y-10],[x+6,y-17]],'#596278',1,s);line([[x,y-10],[x+2,y-17]],'#68758a',1,s)}
 for(let j=0;j<13;j++){const x=12+j*21,y=terrain(x);rect(x,y-2,4,2,j%3?'#364b5b':'#536476',s);if(j%3===0)rect(x+1,y-4,2,2,'#6d7c88',s)}
 octopus(92+Math.round(Math.sin(tm*.09)*2),terrain(92)-4,tm);
 octopus(223+Math.round(Math.sin(tm*.08+1)*2),terrain(223)-3,tm+2);
 // A few water particles translate continuously, never blink in brightness.
 for(let j=0;j<(tier+1)*6;j++){const x=100+(j*37+Math.floor(tm*(2+tier)))%175,y=12+(j*13)%63;if(y<terrain(x)-5)rect(x,y,1,1,'#395967',s)}
 // Pixel jellyfish provide a fixed scale cue across the three depths.
 for(const [x,y0] of [[194,27],[248,75]]){const y=y0+Math.round(Math.sin(tm*.8+x)*2);rect(x+2,y,8,2,'#628c9d',s);rect(x,y+2,12,5,'#456c80',s);for(let j=0;j<3;j++)line([[x+2+j*4,y+7],[x+2+j*4,y+10],[x+3+j*4,y+12]],'#3a6178',1,s)}
 // Follow the exact seabed edge; the locator travels down this same contour.
 const edge=Array.from({length:282},(_,x)=>[x,terrain(x)]);
 line(edge,tiers[tier].color,1,s);
 const px=Math.round(66+depth*84),py=terrain(px);
 // Horizontal depth reference intersects the locator on the seabed contour.
 rect(0,py,282,1,tiers[tier].color,s);
 // Integer rectangles avoid half-pixel strokes on the small pixel canvas.
 rect(px-5,py-5,11,11,'#101924',s);
 rect(px-5,py-5,11,1,tiers[tier].color,s);rect(px-5,py+5,11,1,tiers[tier].color,s);
 rect(px-5,py-5,1,11,tiers[tier].color,s);rect(px+5,py-5,1,11,tiers[tier].color,s);
 rect(px-1,py-1,3,3,tiers[tier].color,s);
 // Single short sampling sweep on switching, no looping radar rings.
 if(change<1&&!reduced){const sx=Math.floor(change*282);rect(sx,0,1,160,'#527686',s)}
 ctx.imageSmoothingEnabled=false;ctx.drawImage(sea,302,218,564,320);
}
function draw(){if(!ready)return;const t=tiers[tier];ctx.clearRect(0,0,1280,720);rect(0,0,1280,720,C.bg);rect(0,0,1280,48,C.ink);line([[28,46],[1252,46]],C.line);text(32,15,'‹   选择难度',18);text(212,20,'OPERATION / SURVEY',10,C.mute);text(1248,17,'返回  Esc',15,C.white,'right');
 rect(0,48,267,606,C.white);text(30,80,'探索深度',36,C.ink);text(32,132,'DEPTH / SELECT',12,'#5c616a');text(32,185,'难度档位',13,'#5c616a');line([[58,239],[58,559]],'#9da5ae',2);for(let y=239;y<560;y+=10)line([[48,y],[58,y]],'#9da5ae',2);
 tiers.forEach((q,i)=>{let y=251+i*135;if(i===tier){rect(20,y-35,230,96,C.ink);rect(20,y-35,4,96,q.color);text(38,y-17,'0'+(i+1),40,q.color);text(106,y-13,q.cn,29);text(108,y+26,q.en,11,q.color)}else{rect(51,y-4,14,14,i===2?'#887177':'#347e8a');text(90,y-18,q.cn,27,'#5c616a');text(92,y+20,q.en,10,'#7c828b')}});text(32,603,'↑ ↓  选择档位',13,'#5c616a');
 text(302,82,'0'+(tier+1),17,t.color);text(346,79,t.cn,33);text(304,130,t.en+' / OPERATION CONDITIONS',11,C.mute);text(838,75,'0'+(tier+1),88,'#2b3542','right');line([[302,169],[865,169]],C.line);text(305,189,'海域剖面',11,C.mute);text(862,189,t.label,10,C.mute,'right');ocean();
 text(305,562,tier===0?'没有额外规则。':tier===1?'通关「困难」后解锁极限':'自然溟痕常驻，灯标可驱散。',15,C.mute);text(305,602,'结算系数',13,C.mute);text(410,589,t.factor,29,t.color);text(628,602,'通关评级',13,C.mute);text(743,589,t.grade,29);
 rect(902,48,378,606,'#1b2029');rect(902,48,4,107,t.color);text(935,83,'行动条件',27);text(937,128,'CONDITIONS / ALL',11,C.mute);line([[935,169],[1244,169]],C.line);
 if(!t.rules.length){text(936,202,'没有额外规则。',21);text(936,250,'标准作战条件',14,C.mute)}
 const gap=tier===2?19:28;t.rules.forEach((r,i)=>{let y=190+i*gap;text(936,y,r[0],tier===2?13:14,C.mute);text(1238,y-1,r[1],tier===2?15:19,C.white,'right')});if(tier)text(936,540,'Boss 预警不低于 0.6 秒',12,C.mute);
 line([[935,565],[1244,565]],C.line);text(936,590,'本档通关',16,C.mute);text(1130,580,t.count,39);text(1200,608,'次',13,C.mute);
 rect(0,654,1280,66,C.ink);line([[28,654],[1252,654]],C.line);text(31,681,'返回  Esc',17,C.mute);text(304,681,'认知塑造',19);rect(915,668,337,40,C.cyan);text(942,678,'确认难度',22,C.ink);text(1214,685,'Enter  ›',12,C.ink,'right');
}
function frame(now){const dt=last?Math.min((now-last)/1000,.05):0;last=now;if(!paused){clock+=dt;change=Math.min(1,change+dt/.38);depth=reduced?tier:from+(tier-from)*(1-Math.pow(1-change,3))}draw();requestAnimationFrame(frame)}
window.preview={select:choose,freeze:(time=0)=>{paused=true;clock=time;change=1;depth=tier;draw()},state:()=>({ready,tier,depth,paused,reduced,clock})};
Promise.all([document.fonts.load('18px px'),image('e_skimmer'),image('e_path'),image('e_mother')]).then(()=>{buildSilhouettes();ready=true;requestAnimationFrame(frame)}).catch(e=>{document.querySelector('nav').append('预览加载失败：'+e.message);throw e});
