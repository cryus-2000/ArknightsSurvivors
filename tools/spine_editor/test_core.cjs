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
console.log('PASS hierarchy, fixed-length IK, grip, unreachable/zero target, patch identity and validation, 3.5/3.8 animation and vertex compatibility');
