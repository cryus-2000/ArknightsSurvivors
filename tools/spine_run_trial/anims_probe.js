'use strict';
// 列出各干员骨骼的动画轨与时长（入场 Start 轨排查用）
const { load } = require('./load.js');
(async () => {
  for (const id of process.argv.slice(2)) {
    try {
      const { data } = await load(require(`./cfg/${id}.src.json`));
      console.log(id, data.animations.map(a => `${a.name}:${a.duration.toFixed(2)}`).join(' '));
    } catch (e) { console.log(id, 'ERR', e.message); }
  }
})();
