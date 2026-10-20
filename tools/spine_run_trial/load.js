'use strict';
// 读原生 Spine（3.5 转出的 JSON 或 3.8 二进制），返回 spine 命名空间与 SkeletonData。只读，不改素材。
const fs = require('fs'), path = require('path'), vm = require('vm');
const { loadImage } = require('@napi-rs/canvas');
const REF = 'E:/ArknightsSurvivors/build/prts_ref';

async function load(cfg) {
  const runtime = `${REF}/_node/spine-canvas-${cfg.json ? '3.5.51' : '3.8'}.js`;
  const box = { console, Math, Float32Array, Int16Array, Uint16Array, Int32Array, Uint8Array, ArrayBuffer, DataView, setTimeout, clearTimeout };
  vm.createContext(box);
  vm.runInContext(fs.readFileSync(runtime, 'utf8') + '\n;this.api=spine;', box);
  const sp = box.api;
  const txt = fs.readFileSync(cfg.atlas, 'utf8'), pages = {};
  for (const line of txt.split(/\r?\n/)) {
    const p = line.trim();
    if (p.endsWith('.png') && !p.includes(':')) pages[p] = await loadImage(fs.readFileSync(path.join(path.dirname(cfg.atlas), p)));
  }
  const atlas = new sp.TextureAtlas(txt, p => new sp.canvas.CanvasTexture(pages[p]));
  const loader = new sp.AtlasAttachmentLoader(atlas);
  const data = cfg.json
    ? new sp.SkeletonJson(loader).readSkeletonData(fs.readFileSync(cfg.json, 'utf8'))
    : new sp.SkeletonBinary(loader).readSkeletonData(new Uint8Array(fs.readFileSync(cfg.skel)));
  function pose(anim = 'Idle', t = 0) {
    const sk = new sp.Skeleton(data); sk.setToSetupPose();
    const a = data.findAnimation(anim);
    if (sp.MixBlend) a.apply(sk, 0, t, false, null, 1, sp.MixBlend.setup, sp.MixDirection.mixIn);
    else a.apply(sk, 0, t, false, null, 1, true, false);
    sk.updateWorldTransform();
    return sk;
  }
  return { sp, data, pose };
}
module.exports = { load, REF };

if (require.main === module) {
  // node load.js <cfg.json>：列出骨骼层级与带附件的槽，用来写每人的 rig 配置
  (async () => {
    const cfg = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
    const { data, pose } = await load(cfg);
    const sk = pose();
    console.log('anims', data.animations.map(a => a.name).join(' '));
    console.log('ik', data.ikConstraints.map(c => c.name + ':' + c.bones.map(b => b.name).join('>') + '->' + c.target.name).join(' | '));
    console.log('tc', data.transformConstraints.map(c => c.name + ':' + c.bones.map(b => b.name).join(',') + '->' + c.target.name).join(' | '));
    const depth = b => { let d = 0; for (let p = b.parent; p; p = p.parent) d++; return d; };
    for (const b of sk.bones) console.log(' '.repeat(depth(b)) + b.data.name, Math.round(b.worldX), Math.round(b.worldY), 'len', Math.round(b.data.length), 'rot', Math.round(Math.atan2(b.c, b.a) * 180 / Math.PI));
    console.log('slots', sk.drawOrder.filter(s => s.getAttachment()).map(s => s.data.name + '@' + s.bone.data.name).join(' '));
  })().catch(e => { console.error(e); process.exit(1); });
}
