'use strict';
// 原作 Spine 高清参照联排：按动画轨等分采样，整只骨架原样渲染（不像素化），供挑动作 / 三列对照用。
// 用法：node ref_sheet.js cfg/<id>.src.json <输出 png> <动画>[:t0-t1] [...更多动画] [--n 8] [--px 220]
//       --times a,b,c  显式时间点（只用于单个动画）；--frames <目录>  另存逐帧 png（f00.png…）
const fs = require('fs'), path = require('path');
const { createCanvas } = require('@napi-rs/canvas');
const { load } = require('./load.js');
const argv = process.argv.slice(2), opt = k => { const i = argv.indexOf(k); return i >= 0 ? argv.splice(i, 2)[1] : null; };
const N = +(opt('--n') || 8), PX = +(opt('--px') || 220), TIMES = opt('--times'), FR = opt('--frames');
const [srcPath, out, ...anims] = argv;
(async () => {
  const { sp, pose, data } = await load(JSON.parse(fs.readFileSync(srcPath, 'utf8')));
  const rows = anims.map(spec => {
    const [name, rng] = spec.split(':'), a = data.findAnimation(name);
    const [t0, t1] = rng ? rng.split('-').map(Number) : [0, a.duration];
    const ts = TIMES ? TIMES.split(',').map(Number) : Array.from({ length: N }, (_, i) => t0 + (t1 - t0) * i / Math.max(1, N - 1));
    return { name, ts };
  });
  // 统一比例：取 Idle t=0 包围盒高度 → 人高约 PX*0.62
  const bb = sk => { const o = new sp.Vector2(), s = new sp.Vector2(); sk.getBounds(o, s, []); return [o.x, o.y, s.x, s.y]; };
  const b0 = bb(pose('Idle', 0)), K = PX * 0.62 / b0[3];
  const cols = Math.max(...rows.map(r => r.ts.length));
  const cv = createCanvas(cols * PX, rows.length * (PX + 18)), c = cv.getContext('2d');
  c.fillStyle = '#303d4d'; c.fillRect(0, 0, cv.width, cv.height);
  if (FR) fs.mkdirSync(FR, { recursive: true });
  rows.forEach((r, ri) => r.ts.forEach((t, ci) => {
    const sk = pose(r.name, t), x = ci * PX, y = ri * (PX + 18) + 18;
    const draw = (ctx, ox, oy) => { ctx.save(); ctx.translate(ox + PX / 2, oy + PX * 0.86); ctx.scale(K, -K);
      const rr = new sp.canvas.SkeletonRenderer(ctx); rr.triangleRendering = true; rr.draw(sk); ctx.restore(); };
    c.save(); c.beginPath(); c.rect(x, y, PX, PX); c.clip(); draw(c, x, y); c.restore();
    c.fillStyle = '#ddd'; c.font = '12px sans-serif'; c.fillText(`${r.name} ${t.toFixed(3)}`, x + 4, y - 4);
    if (FR) { const f = createCanvas(PX, PX); draw(f.getContext('2d'), 0, 0); fs.writeFileSync(path.join(FR, `f${String(ci).padStart(2, '0')}.png`), f.toBuffer('image/png')); }
  }));
  fs.writeFileSync(out, cv.toBuffer('image/png'));
  console.log('ok', out, rows.map(r => r.name + ':' + r.ts.length).join(' '));
})();
