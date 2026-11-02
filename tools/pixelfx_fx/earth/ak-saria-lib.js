// 塞雷娅钙晶画法（D 组共用小模块，不是特效）：钙质结晶是块状的菱面体 / 六棱柱，不是细针。
// prism(p, x, base, h, w, lean, C, o)：一根钙晶柱，柱身两面（左亮右暗）+ 顶部斜切面（最亮）+ 棱线高光；
// 顶面斜切角度、柱宽、倾斜都由调用方随机给，C 是 8 阶色阶（暗 → 亮）。o = { glint: 0..1 扫光高度或 -1, hot: 首帧提一档 }
export function prism(p, x, base, h, w, lean, C, o = {}) {
  if (h < 2) return;
  const hw = w / 2, cut = Math.min(h * 0.45, w * (o.cut ?? 0.7)), skew = o.skew ?? 0.35, up = o.hot ? 1 : 0;
  const top = base - h;
  // 柱身：底边 → 斜切面下沿；中棱偏左（受光面窄、背光面宽）
  const ridge = (u) => x + lean * u - hw * 0.2;
  for (let y = Math.floor(top); y <= base; y++) {
    if (y > base) break;
    const u = (base - y) / h, cx = x + lean * u, r = ridge(u);
    // 顶部斜切：一侧高一侧低
    const yl = top + cut * (0.5 + skew), yr = top + cut * (0.5 - skew);
    for (let px = Math.floor(cx - hw); px <= Math.ceil(cx + hw); px++) {
      const f = (px - (cx - hw)) / w;   // 0 左 → 1 右
      const yTop = yl + (yr - yl) * f;
      if (y < yTop) continue;
      let ci;
      if (y < yTop + Math.max(2, w * 0.18)) ci = 6;           // 斜切顶面（一条亮带）
      else if (Math.abs(px - r) < 0.6) ci = 6;                // 中棱高光
      else if (px < r) ci = f < 0.12 ? 4 : 5;                 // 受光面
      else ci = f > 0.88 ? 2 : 3;                             // 背光面，外缘再暗一阶
      if (o.glint >= 0 && px <= r + 0.5 && Math.abs(u - o.glint) < 0.05) ci = 7;
      if (Math.abs(px - (cx - hw)) < 0.6 || Math.abs(px - (cx + hw)) < 0.6) ci = Math.min(ci, 2);   // 轮廓
      p.px(px, y, C[Math.min(7, ci + up)]);
    }
  }
}
