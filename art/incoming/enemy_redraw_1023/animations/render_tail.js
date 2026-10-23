  // Native attachment geometry is the only pose source. No candidate f0 input.
  const frames=job.frames;
  const off=new spine.Vector2(),sz=new spine.Vector2();
  const ref=pose(frames[0].anim,0);
  ref.getBounds(off,sz,[]);
  let scale=400/Math.max(sz.x,sz.y), rx=32-off.x*scale, ry=432+off.y*scale;
  const probe=createCanvas(512,512),pc=probe.getContext('2d');
  pc.translate(rx,ry);pc.scale(scale,-scale);
  const pr=new spine.canvas.SkeletonRenderer(pc);pr.triangleRendering=true;pr.draw(ref);
  const pixels=pc.getImageData(0,0,512,512).data;
  let bx=512,by=512,ex=0,ey=0;
  for(let y=0;y<512;y++)for(let x=0;x<512;x++)if(pixels[(y*512+x)*4+3]>=128){bx=Math.min(bx,x);by=Math.min(by,y);ex=Math.max(ex,x+1);ey=Math.max(ey,y+1);}
  if(ey<=by)throw Error('Empty reference '+job.id);
  const ground=(ry-ey)/scale, center=((bx+ex)/2-rx)/scale;
  scale=job.height/((ey-by)/scale);
  let l=-job.canvas[0]/2,r=job.canvas[0]/2,t=-(job.canvas[1]-4),b=4;
  for(const f of frames){const sk=pose(f.anim,f.t,f.bones,f.seed_anim);sk.getBounds(off,sz,[]);l=Math.min(l,(off.x-center)*scale-3);r=Math.max(r,(off.x+sz.x-center)*scale+3);t=Math.min(t,-(off.y+sz.y-ground)*scale-3);b=Math.max(b,-(off.y-ground)*scale+3);}
  l=Math.floor(l);r=Math.ceil(r);t=Math.floor(t);b=Math.ceil(b);
  const W=r-l,H=b-t,origin=[-l,-t],SS=4;
  fs.mkdirSync(job.out_dir,{recursive:true});
  const catalog={id:job.id,anims,scale,frame_size:[W,H],origin,reference_alpha_bounds:[bx,by,ex,ey],source:'original Spine attachments',frames:[]};
  let glow=null;
  for(const f of frames){
    const sk=pose(f.anim,f.t,f.bones,f.seed_anim),cv=createCanvas(W*SS,H*SS),ctx=cv.getContext('2d');
    ctx.translate((origin[0]-center*scale)*SS,(origin[1]+ground*scale)*SS);ctx.scale(scale*SS,-scale*SS);
    const renderer=new spine.canvas.SkeletonRenderer(ctx);renderer.triangleRendering=true;
    let registrationY=0;
    if(f.name.startsWith('death_') && /Die/.test(f.anim)){
      // Original death clips may fall below their idle projection floor.
      // Register their landing to the shared floor without changing scale or
      // internal bone motion. This is recorded separately from authored poses.
      renderer.draw(sk);const a=ctx.getImageData(0,0,W*SS,H*SS).data;let bottom=0;
      for(let y=0;y<H*SS;y++)for(let x=0;x<W*SS;x++)if(a[(y*W*SS+x)*4+3]>=128)bottom=Math.max(bottom,y+1);
      registrationY=Math.min(0,origin[1]-bottom/SS);
      ctx.save();ctx.setTransform(1,0,0,1,0,0);ctx.clearRect(0,0,cv.width,cv.height);ctx.restore();
      ctx.translate(0,-registrationY/scale);
    }
    const slots=sk.drawOrder,states=slots.map(s=>s.getAttachment()),rows=[];
    for(let j=0;j<slots.length;j++){
      const slot=slots[j],at=states[j];if(!at)continue;
      // setAttachment clears mesh deformation in Spine. Isolate only the render
      // attachment pointer, keeping the original pose's deformation untouched.
      for(let k=0;k<slots.length;k++)slots[k].attachment=k===j?states[k]:null;
      renderer.draw(sk);
      const filename=f.name+'_slot_'+j+'.png';fs.writeFileSync(path.join(job.out_dir,filename),cv.toBuffer('image/png'));
      const bone=slot.bone;
      rows.push({slot:slot.data.name,attachment:at.name,bone:bone.data.name,parent:bone.parent?bone.parent.data.name:null,draw_order:j,file:filename,matrix:[bone.a,bone.b,bone.c,bone.d,bone.worldX,bone.worldY],mesh:!!at.triangles,vertices:at.vertices?Array.from(at.vertices):null,triangles:at.triangles?Array.from(at.triangles):null,deform:Array.from(slot.deform||slot.attachmentVertices||[])});
      if(!glow && f.name==='reference' && slot.data.name===job.glow_slot){
        const p=ctx.getImageData(0,0,W*SS,H*SS).data;let x0=W*SS,y0=H*SS,x1=0,y1=0;
        for(let y=0;y<H*SS;y++)for(let x=0;x<W*SS;x++)if(p[(y*W*SS+x)*4+3]>=128){x0=Math.min(x0,x);y0=Math.min(y0,y);x1=Math.max(x1,x+1);y1=Math.max(y1,y+1);}
        const uv=job.glow_uv||[0.65,0.45],px=(x0+(x1-x0)*uv[0])/SS,py=(y0+(y1-y0)*uv[1])/SS;
        const wx=(px-origin[0])/scale+center,wy=(origin[1]-py)/scale+ground;
        const det=bone.a*bone.d-bone.b*bone.c;
        glow={bone:bone.data.name,local:[(bone.d*(wx-bone.worldX)-bone.b*(wy-bone.worldY))/det,(-bone.c*(wx-bone.worldX)+bone.a*(wy-bone.worldY))/det],slot:slot.data.name};
      }
      ctx.save();ctx.setTransform(1,0,0,1,0,0);ctx.clearRect(0,0,cv.width,cv.height);ctx.restore();
    }
    for(let k=0;k<slots.length;k++)slots[k].attachment=states[k];
    renderer.draw(sk);fs.writeFileSync(path.join(job.out_dir,f.name+'.png'),cv.toBuffer('image/png'));
    let gp=null;if(glow){const bn=sk.findBone(glow.bone),[x,y]=glow.local;gp=[origin[0]+(bn.a*x+bn.b*y+bn.worldX-center)*scale,origin[1]-(bn.c*x+bn.d*y+bn.worldY-ground)*scale+registrationY];}
    catalog.frames.push({...f,registration_y_1x:registrationY,parts:rows,glow:gp});
  }
  catalog.glow_binding=glow;
  fs.writeFileSync(path.join(job.out_dir,'catalog.json'),JSON.stringify(catalog));
  process.stdout.write(JSON.stringify({id:job.id,frame_size:[W,H],frames:frames.length})+'\n');
}
main().catch(e=>{console.error(e.stack||e);process.exit(1);});
