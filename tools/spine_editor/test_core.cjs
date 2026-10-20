const assert = require('node:assert/strict');
const P = require('./pose_core.js');
function rig() {
  const bones = [
    {name:'root',world:[0,0],matrix:[1,0,0,1]},
    {name:'arm',parent:'root',world:[0,0],matrix:[1,0,0,1]},
    {name:'elbow',parent:'arm',world:[4,0],matrix:[1,0,0,1]},
    {name:'hand',parent:'elbow',world:[4,3],matrix:[1,0,0,1]},
    {name:'weapon',parent:'hand',world:[5,3],matrix:[1,0,0,1]},
    {name:'other',parent:'root',world:[-2,0],matrix:[1,0,0,1]}
  ];
  return P.makeBones(bones);
}
const near = (a,b) => assert.ok(Math.abs(a-b)<1e-7, `${a} != ${b}`);
let b=rig();P.rotate(b,'arm',90);near(b.hand.worldX,-3);near(b.hand.worldY,4);near(b.other.worldX,-2);
b=rig();P.solveIK(b,['arm','elbow','hand'],[3,4],['weapon']);
near(Math.hypot(b.elbow.worldX,b.elbow.worldY),4);
near(Math.hypot(b.hand.worldX-b.elbow.worldX,b.hand.worldY-b.elbow.worldY),3);
near(b.hand.worldX,3);near(b.hand.worldY,4);
near(b.weapon.a,1);near(b.weapon.c,0); // weapon angle preserved when dragging grip
near(b.weapon.worldX-b.hand.worldX,1);near(b.weapon.worldY-b.hand.worldY,0);
P.solveIK(b,['arm','elbow','hand'],[100,0],['weapon']);
assert.ok(b.hand.worldX<=7);assert.ok(Number.isFinite(b.hand.worldY));
P.solveIK(b,['arm','elbow','hand'],[0,0],['weapon']);assert.ok(Number.isFinite(b.hand.worldX));
const project={id:'abc',frames:[{}],bones:['root','arm'],slots:['face','hand']};
const patch={version:1,source:'abc',frames:[{ops:[{type:'rotate',bone:'arm',degrees:10}],order:null}]};
P.validatePatch(patch,project);
for(const change of [p=>p.source='wrong',p=>p.frames[0].ops[0].degrees=Infinity,p=>p.frames[0].ops[0].bone='missing',p=>p.frames[0].order=['face','face']]) {
 const p=structuredClone(patch);change(p);assert.throws(()=>P.validatePatch(p,project));
}
// Spine 3.5 / 3.8 compatibility helpers
{
  const calls=[];const anim={apply:(...a)=>calls.push(a)};
  P.applyAnimation({MixBlend:{setup:'S'},MixDirection:{mixIn:'I'}},anim,'sk',0.5);
  P.applyAnimation({},anim,'sk',0.25);
  assert.deepEqual(calls[0].slice(2),[0.5,false,null,1,'S','I']);
  assert.deepEqual(calls[1].slice(2),[0.25,false,null,1,true,false]);
  const v35={updateWorldVertices:()=>[1,2,0,0,0,0,0,0,3,4,0,0,0,0,0,0]};
  assert.deepEqual(P.worldVertices({},{},v35),[1,2,3,4]);
  class Region{computeWorldVertices(bone,out,o,s){assert.equal(bone,'bone');assert.equal(s,2);for(let i=0;i<8;i++)out[i]=i;}}
  class Mesh{constructor(){this.worldVerticesLength=4;}computeWorldVertices(slot,start,n,out,o,s){assert.equal(n,4);out.splice(0,4,9,8,7,6);}}
  const sp38={RegionAttachment:Region};
  assert.deepEqual(P.worldVertices(sp38,{bone:'bone'},new Region()),[0,1,2,3,4,5,6,7]);
  assert.deepEqual(P.worldVertices(sp38,{},new Mesh()),[9,8,7,6]);
}
// Real Spine 3.8 skeleton (local only; skipped when the runtime or PRTS reference is absent)
{
  const fs=require('fs'),vm=require('vm'),path=require('path');
  const root=['../..','../../../..','../../../../..'].map(p=>path.resolve(__dirname,p)).find(p=>fs.existsSync(path.join(p,'build/prts_ref/_node/spine-canvas-3.8.js')));
  const raw=root&&path.join(root,'build/prts_ref/_raw');
  for(const id of ['mizuki','suzuran','wisadel']){
    const dir=raw&&path.join(raw,id);if(!dir||!fs.existsSync(dir)){console.log('SKIP 3.8',id);continue;}
    const box={console,Math,Float32Array,Int16Array,Uint16Array,Int32Array,Uint8Array,ArrayBuffer,DataView,setTimeout};vm.createContext(box);
    vm.runInContext(fs.readFileSync(path.join(root,'build/prts_ref/_node/spine-canvas-3.8.js'),'utf8')+'\n;this.api=spine;',box);const sp=box.api;
    const file=ext=>path.join(dir,fs.readdirSync(dir).find(f=>f.endsWith(ext)));
    const stub={setFilters(){},setWraps(){},getImage(){return{width:1,height:1};}};
    const atlas=new sp.TextureAtlas(fs.readFileSync(file('.atlas'),'utf8'),()=>stub);
    const data=new sp.SkeletonBinary(new sp.AtlasAttachmentLoader(atlas)).readSkeletonData(new Uint8Array(fs.readFileSync(file('.skel'))));
    assert.ok(data.version.startsWith('3.8'));
    const s=new sp.Skeleton(data);s.setToSetupPose();P.applyAnimation(sp,data.findAnimation('Idle'),s,0);s.updateWorldTransform();
    let n=0;for(const slot of s.slots){const att=slot.getAttachment();if(!(att instanceof sp.MeshAttachment||att instanceof sp.RegionAttachment))continue;
      const v=P.worldVertices(sp,slot,att);assert.equal(v.length%2,0);assert.ok(v.every(Number.isFinite));n++;}
    assert.ok(n>20);
    const bones=P.makeBones(s.bones.map(b=>({name:b.data.name,parent:b.parent?.data.name,world:[b.worldX,b.worldY],matrix:[b.a,b.b,b.c,b.d]})));
    const leg=id==='wisadel'?['F_L_Leg_01','F_L_Calf_01_01','F_L_Foot_01']:['F_L_Leg','F_L_Calf','F_L_Foot'];
    const len=(a,b)=>Math.hypot(bones[a].worldX-bones[b].worldX,bones[a].worldY-bones[b].worldY),l1=len(leg[0],leg[1]),l2=len(leg[1],leg[2]);
    const foot=bones[leg[2]],target=[foot.worldX+15,foot.worldY+20];
    P.solveIK(bones,leg,target);
    near(len(leg[0],leg[1]),l1);near(len(leg[1],leg[2]),l2);
    assert.ok(Math.hypot(bones[leg[2]].worldX-target[0],bones[leg[2]].worldY-target[1])<1e-6);
  }
}
console.log('PASS hierarchy, fixed-length IK, grip, unreachable/zero target, patch identity and validation, 3.5/3.8 animation and vertex compatibility, real 3.8 skeletons (mizuki / suzuran / wisadel)');
