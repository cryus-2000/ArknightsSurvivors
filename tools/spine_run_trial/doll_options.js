'use strict';
// 归溟替身环斩候选审阅图：① 本体 Skill_3_Attack 身体动作重定向到替身；③ ① + 现版镜像旋身（每两帧左右翻转）。
// 输出逐帧 PNG 到 <out>/opt1、<out>/opt3（原生网格，未像素化，只供挑方向）
const fs = require('fs'), path = require('path');
const { load } = require('./load.js');
const { retarget } = require('./doll_retarget.js');
const { createCanvas } = require('@napi-rs/canvas');

(async () => {
  const out = process.argv[2];
  const src = require('./cfg/specter_unchained.src.json');
  const { data, pose, sp } = await load(src);
  const times = [0, 0.27, 0.55, 0.82, 1.1, 1.37, 1.65, 1.9];
  for (const opt of ['opt1', 'opt3']) {
    fs.mkdirSync(path.join(out, opt), { recursive: true });
    times.forEach((t, i) => {
      const sk = retarget(pose, data, 'Skill_3_Attack', t, ['Idle', 0], ['Idle_B', 0.3]);
      const cv = createCanvas(240, 240), c = cv.getContext('2d');
      const flip = opt === 'opt3' && (i % 4 === 1 || i % 4 === 2);
      c.translate(120, 225); c.scale(flip ? -0.42 : 0.42, -0.42);
      const r = new sp.canvas.SkeletonRenderer(c); r.triangleRendering = true; r.draw(sk);
      fs.writeFileSync(path.join(out, opt, `f${String(i).padStart(2, '0')}.png`), cv.toBuffer('image/png'));
    });
  }
})().catch(e => { console.error(e); process.exit(1); });
