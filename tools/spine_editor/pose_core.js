(function(root) {
  'use strict';
  const rad=Math.PI/180;
  function makeBones(rows) {
    return Object.fromEntries(rows.map(b=>[b.name,{name:b.name,parentName:b.parent,
      worldX:b.world[0],worldY:b.world[1],a:b.matrix[0],b:b.matrix[1],c:b.matrix[2],d:b.matrix[3]}]));
  }
  function branch(bones,name) {
    return Object.values(bones).filter(b=>{for(let p=b;p;p=bones[p.parentName])if(p.name===name)return true;return false;});
  }
  function rotate(bones,name,degrees,pivot) {
    const b=bones[name], [x,y]=pivot||[b.worldX,b.worldY], c=Math.cos(degrees*rad),s=Math.sin(degrees*rad);
    for(const p of branch(bones,name)) {
      const dx=p.worldX-x,dy=p.worldY-y,{a,b,c:cc,d}=p;
      p.worldX=x+c*dx-s*dy;p.worldY=y+s*dx+c*dy;
      p.a=c*a-s*cc;p.b=c*b-s*d;p.c=s*a+c*cc;p.d=s*b+c*d;
    }
  }
  function translate(bones,name,dx,dy) {
    for(const b of branch(bones,name)){b.worldX+=dx;b.worldY+=dy;}
  }
  function solveIK(bones,chain,target,equipment=[]) {
    const [a,b,c]=chain.map(n=>bones[n]);
    const l1=Math.hypot(b.worldX-a.worldX,b.worldY-a.worldY),l2=Math.hypot(c.worldX-b.worldX,c.worldY-b.worldY);
    if(l1<1e-6||l2<1e-6)throw Error('关节长度为零，不能解算');
    const cross=(b.worldX-a.worldX)*(c.worldY-b.worldY)-(b.worldY-a.worldY)*(c.worldX-b.worldX);
    const bend=cross>=0?-1:1;
    const dx=target[0]-a.worldX,dy=target[1]-a.worldY;
    const dist=Math.max(Math.abs(l1-l2)+1e-5,Math.min(l1+l2-1e-5,Math.hypot(dx,dy)));
    const alpha=Math.hypot(dx,dy)<1e-8?Math.atan2(c.worldY-a.worldY,c.worldX-a.worldX):Math.atan2(dy,dx);
    const beta=Math.acos(Math.max(-1,Math.min(1,(l1*l1+dist*dist-l2*l2)/(2*l1*dist))));
    const saved=equipment.map(n=>[n,Math.atan2(bones[n].c,bones[n].a)]);
    rotate(bones,a.name,(alpha+bend*beta-Math.atan2(b.worldY-a.worldY,b.worldX-a.worldX))/rad);
    const tx=a.worldX+Math.cos(alpha)*dist,ty=a.worldY+Math.sin(alpha)*dist;
    rotate(bones,b.name,(Math.atan2(ty-b.worldY,tx-b.worldX)-Math.atan2(c.worldY-b.worldY,c.worldX-b.worldX))/rad);
    // Rotate equipment around the grip, not its own origin, to keep contact intact.
    for(const [n,angle] of saved)rotate(bones,n,(angle-Math.atan2(bones[n].c,bones[n].a))/rad,[c.worldX,c.worldY]);
  }
  function validatePatch(p,project) {
    const fail=()=>{throw Error('姿势文件不匹配，或包含无效关节 / 层序 / 数值');};
    if(!p||p.version!==1||p.source!==project.id||!Array.isArray(p.frames)||p.frames.length!==project.frames.length)fail();
    const finite=(v,max)=>typeof v==='number'&&Number.isFinite(v)&&Math.abs(v)<=max;
    for(const f of p.frames){
      if(!f||!Array.isArray(f.ops)||f.ops.length>500)fail();
      for(const op of f.ops){
        if(!op||!project.bones.includes(op.bone))fail();
        if(op.type==='rotate'){if(!finite(op.degrees,360))fail();}
        else if(op.type==='translate'){if(!finite(op.dx,2000)||!finite(op.dy,2000))fail();}
        else if(op.type==='ik'){if(!Array.isArray(op.target)||op.target.length!==2||!op.target.every(v=>finite(v,2000))||!project.chains?.[op.bone])fail();}
        else fail();
      }
      if(f.order!==null&&(!Array.isArray(f.order)||f.order.length!==project.slots.length||new Set(f.order).size!==project.slots.length||f.order.some(n=>!project.slots.includes(n))))fail();
    }
    return p;
  }
  function apply(bones,ops,chains,equipment) {
    for(const op of ops){
      if(op.type==='rotate')rotate(bones,op.bone,op.degrees);
      else if(op.type==='translate')translate(bones,op.bone,op.dx,op.dy);
      else solveIK(bones,chains[op.bone],op.target,equipment[op.bone]||[]);
    }
  }
  // Spine 3.5 / 3.8 运行库差异：动画混合参数与世界顶点接口不同。返回平铺 [x0,y0,x1,y1,…]。
  function applyAnimation(spine,anim,skeleton,t) {
    if(spine.MixBlend)anim.apply(skeleton,0,t,false,null,1,spine.MixBlend.setup,spine.MixDirection.mixIn);
    else anim.apply(skeleton,0,t,false,null,1,true,false);
  }
  function worldVertices(spine,slot,att) {
    if(att.updateWorldVertices){const v=att.updateWorldVertices(slot,false),out=[];for(let i=0;i<v.length;i+=8)out.push(v[i],v[i+1]);return out;}
    if(spine.RegionAttachment&&att instanceof spine.RegionAttachment){const out=new Array(8);att.computeWorldVertices(slot.bone,out,0,2);return out;}
    const out=new Array(att.worldVerticesLength);att.computeWorldVertices(slot,0,att.worldVerticesLength,out,0,2);return out;
  }
  const api={makeBones,rotate,translate,solveIK,validatePatch,apply,applyAnimation,worldVertices};
  if(typeof module!=='undefined')module.exports=api;else root.PoseCore=api;
})(globalThis);
