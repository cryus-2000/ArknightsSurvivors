'use strict';
// 归溟幽灵鲨替身（_T 部件，骨骼名带 2 后缀）原作没有攻击轨：把本体 Attack 的骨骼局部动作（相对本体 Idle）
// 按「去掉 2 后缀同名」映射到替身骨骼上，替身部件不变，得到替身的原生环斩动作。
// 用法：node doll_retarget.js <out.png> [anim=Attack] [t0,t1,...]   —— 只出审阅图；像素化走 run_trial.js 的 dollRetarget 配置
const { load } = require('./load.js');
const { createCanvas } = require('@napi-rs/canvas');
const fs = require('fs');

async function dollPose(src, anim, t, base = ['Idle', 0], dollIdle = ['Idle_B', 0.3]) {
  const { data, pose, sp } = await load(src);
  return { data, sp, make: (tt) => retarget(pose, data, anim, tt, base, dollIdle) };
}

function retarget(pose, data, anim, t, base, dollIdle) {
  const a = pose(anim, t), b = pose(base[0], base[1]), d = pose(dollIdle[0], dollIdle[1]);
  const names = new Set(data.bones.map(x => x.name));
  for (const bone of d.bones) {
    const n = bone.data.name;
    if (!/2$/.test(n)) continue;
    const src = n.slice(0, -1);
    if (!names.has(src)) continue;
    const A = a.findBone(src), B = b.findBone(src);
    bone.rotation += A.rotation - B.rotation;
    bone.x += A.x - B.x; bone.y += A.y - B.y;
    bone.scaleX *= B.scaleX ? A.scaleX / B.scaleX : 1; bone.scaleY *= B.scaleY ? A.scaleY / B.scaleY : 1;
  }
  d.updateWorldTransform();
  return d;
}
module.exports = { retarget };

if (require.main === module) (async () => {
  const src = require('./cfg/specter_unchained.src.json');
  const { data, pose, sp } = await load(src);
  const anim = process.argv[3] || 'Attack';
  const times = (process.argv[4] || '0,0.15,0.3,0.45,0.6,0.75,0.9,1.1').split(',').map(Number);
  const cv = createCanvas(200 * times.length, 2 * 400), c = cv.getContext('2d'); c.fillStyle = '#303d4d'; c.fillRect(0, 0, cv.width, cv.height);
  times.forEach((t, k) => {
    for (const [row, sk] of [[0, pose(anim, t)], [1, retarget(pose, data, anim, t, ['Idle', 0], ['Idle_B', 0.3])]]) {
      c.save(); c.translate(100 + k * 200, 380 + row * 400); c.scale(0.4, -0.4);
      const r = new sp.canvas.SkeletonRenderer(c); r.triangleRendering = true; r.draw(sk); c.restore();
    }
  });
  fs.writeFileSync(process.argv[2], cv.toBuffer('image/png'));
})().catch(e => { console.error(e); process.exit(1); });
