// 拉普兰德 S2「狼魂」法术剑气（docs/242 放开版，代表招式）：俯视，原点 = 剑气出手点（拉普兰德身前 off），正右为飞行方向，游戏里按瞄准方向旋转。
// 原作 S2 的弹体是一颗侧面朝前、张口咆哮的低多边形灰白狼首，双耳竖起、脑后鬃毛碎成细长菱形晶片（build/ark_ref/lappland/langtou_02.png、suikuai.png，
// 只作参照、不描进帧条）。本作照这个外形写成「低多边形狼首 + 窄长剑气」：
//   - 形状读判定（docs/242 §9.1）：半宽 hw = blade_w ÷ 2 ÷ PX，飞行距离 dist = blade_dist ÷ PX（lappland.json base，targets 里 judge 传入），
//     核心层不超出 hw；用户 11-03「纵深感拉远一点，半角有点太大」：剑气是窄长的一根，不是扇形。
//   - 起手信号：出手点先有几道细光从四周收拢、一道竖向亮缝（和普攻月牙完全不同的主形）。
//   - elite（docs/242 §10，docs/91 / lappland.json progression）：
//       E0 克制：单颗狼首 + 剑痕，余韵短、光小；
//       E1 加「精神摧毁」封印（精一天赋）：狼首身后拖两层残影，剑气走过处留一串大封印符，终点烙一个大歪十字；
//       E2「双生刃」（精二）：整只晶体狼（头颈、躯干、前后腿、尾）奔出来，两柄长刃在身上交叉成 X，亮芯带原作狼首贴图里的淡蓝高光，
//          终点碎成更多晶片 —— 和 E1 不是一个外形。
//   11-03 用户「像哥斯拉」：狼的辨识点放在尖长吻部 + 两只竖起的尖三角耳；额到吻一条直斜线；鬃毛往后拖成流线；晶面少而大，剪影优先。
// 分层（docs/242 §8）：core = 狼首、剑刃、剑痕两条边线、起手亮缝、封印纹；deco = 光晕、晶片、雾、余韵闪点。
import { Rng, fit, hex, clamp, ease, noise } from "../../core/index.js";
import { jitterSteps, jitterAngles } from "../house.js";

export const meta = {
  name: "Lappland wolf-spirit blade",
  desc: "A low-poly grey wolf head, jaws open, streaks forward on a narrow blade trail, gathering light first; seals at elite 1, twin crossed blades at elite 2; it shatters into drifting shards.",
  tags: ["projectile", "blade", "wolf", "crystal", "topdown", "one-shot"],
  size: [200, 80],
  origin: [20, 40],
  duration: 1.1,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#2b3036", "#52565a", "#868c8e", "#a9aeb3", "#c9ced3", "#e6eaee", "#ffffff"],   // 取自原作 langtou_02.png 亮度分位（冷灰白），不用紫：避开侵蚀 / 溟痕紫（docs/242 §12.6）
    hw: 12.5,         // 判定半宽（1x 像素），由 targets judge 覆盖
    dist: 100,        // 飞行距离（1x 像素），由 targets judge 覆盖
    elite: 2,
    quick: 0,         // 1 = 队友版（余韵减半）
    layer: "all",
    seed: 3,
  },
};



// 狼首（局部坐标，鼻尖朝 +x、侧面）：吻尖 → 额（直斜线）→ 前耳（高尖三角）→ 后耳 → 脑后 → 三缕往后拖的鬃毛 → 腮 → 下巴 → 张口缺口 → 上颌下沿。
// 高度按判定半宽缩放（耳尖 13 × HS ≤ hw）
const HEAD = [[16, -1], [10, -3.2], [4, -5.4], [2, -6], [-0.5, -13], [-3.5, -6.6], [-6, -12], [-8.5, -6.2], [-12, -5.2], [-21, -3.6], [-15, -1.6],
  [-24, 0.4], [-15, 2.2], [-20, 4.6], [-10, 5.2], [-3, 6.6], [8, 6.2], [13, 4.6], [9, 3.2], [2, 2], [14, 1]];
// E2 躯干（接在狼首后面）：颈背 → 背 → 臀 → 两缕尾 → 后腿往后蹬 → 腹 → 前腿往前伸到下巴下面
const BODY = [[-6, -6], [-16, -5.4], [-26, -4.6], [-32, -4], [-45, -7], [-37, -2.2], [-50, -0.8], [-35, 0.8], [-32, 3], [-41, 8], [-52, 11.2],
  [-50, 12.6], [-38, 10.6], [-27, 5.6], [-17, 5.8], [-9, 6.2], [0, 9.4], [11, 12], [12.5, 10.6], [2.5, 7], [-4, 5]];
const inPoly = (pts, x, y) => {
  let c = false;
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    const [xi, yi] = pts[i], [xj, yj] = pts[j];
    if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) c = !c;
  }
  return c;
};

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), el = clamp(Math.round(+o.elite), 0, 2), quick = +o.quick > 0;
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const hw = +o.hw, dist = +o.dist, HS = Math.min(1, hw / 13);   // 竖向缩放：耳尖 13 × HS ≤ hw
  const T0 = 0.07, TF = 0.36, T1 = T0 + TF;                       // 起手 / 飞行时长（≈ 判定速度：dist ÷ (blade_spd ÷ PX) = 0.4 s）
  const DL = [0.25, 0.4, 0.62][el] * (quick ? 0.5 : 1), GK = [0.25, 0.4, 0.55][el];
  const head = HEAD.map(([x, y]) => [x, y * HS]), body = BODY.map(([x, y]) => [x, y * HS]);
  const polys = el >= 2 ? [head, body] : [head];
  // 低多边形晶面：撒少量种子点、每个像素归最近的种子（Voronoi），面少而大；每面一个明暗偏移
  const seeds = Array.from({ length: 6 }, () => [Rg.range(-18, 14), Rg.range(-10, 6) * HS, Rg.range(-1, 1)])
    .concat(el >= 2 ? Array.from({ length: 6 }, () => [Rg.range(-46, -8), Rg.range(-6, 11) * HS, Rg.range(-1, 1)]) : []);
  const BLUE = hex("#d6ebf6");   // 淡蓝高光：原作 langtou_02 亮部色相约 0.56（极淡的冷蓝），只给 E2 的亮芯和眼
  const sealRot = () => [Rg.range(4, 5.5), Rg.range(-0.5, 0.5)];
  const gather = jitterAngles(Rg, 5, 0, Math.PI * 2, 0.45).map((a) => [a, Rg.range(9, 16)]);
  // 剑气走过的路径上：晶片脱落位置（随机步长）、封印符位置（E1+）
  const chips = jitterSteps(Rg, dist, 5, 13).map((x) => ({ x, y: Rg.range(-hw * 0.6, hw * 0.6), vx: Rg.range(-10, 25), vy: Rg.range(-22, 22), r: Rg.range(0, 6.28), s: Rg.range(1, 2.2), t0: T0 + (x / dist) * TF, life: Rg.range(0.3, 0.6) * (0.6 + DL) }));
  const seals = el >= 1 ? jitterSteps(Rg, dist - 10, 18, 30).map((x) => ({ x: x + 6, y: Rg.range(-2, 2), sz: sealRot(), t0: T0 + (x / dist) * TF })) : [];
  const burst = Array.from({ length: [7, 10, 16][el] }, () => ({ a: Rg.range(-1.1, 1.1) + (Rg.chance(0.25) ? Math.PI : 0), sp: Rg.range(30, 110), r: Rg.range(0, 6.28), s: Rg.range(1.2, 3), life: Rg.range(0.25, 0.55) * (0.6 + DL) }));
  const flick = jitterSteps(Rg, dist, 7, 18).map((x) => ({ x, y: Rg.range(-hw, hw), ph: Rg.range(0, 6.28), t0: T1 + Rg.range(0, 0.15) }));
  const mist = jitterSteps(Rg, dist, 12, 26).map((x) => [x, Rg.range(-hw * 0.5, hw * 0.5), Rg.range(8, 18)]);
  let t = 0;

  const hx = () => dist * ease.outQuad(clamp((t - T0) / TF));     // 狼首位置
  const shard = (p, x, y, r, s, c, a) => {   // 一片细长菱形晶片（原作 suikuai：长约宽的 2.5 倍）
    const pts = [[s * 1.4, 0], [0, s * 0.5], [-s * 1.2, 0], [0, -s * 0.55]].map(([px, py]) => [x + px * Math.cos(r) - py * Math.sin(r), y + px * Math.sin(r) + py * Math.cos(r)]);
    if (a > 0.3) p.poly(pts, a > 0.65 ? c : C[2]);   // 实心晶片，淡出靠降阶（不用抖动半透明）
  };
  const seal = (p, x, y, s, c, r = 0) => {   // 封印纹：一长一短的歪十字（不对称，每枚大小、歪角不同）
    const cs = Math.cos(r), sn = Math.sin(r), L = (a, b) => [x + a * cs - b * sn, y + a * sn + b * cs];
    p.line(...L(-s, -s * 0.8), ...L(s * 1.1, s * 0.9), c);
    p.line(...L(-s * 0.7, s), ...L(s * 0.6, -s * 0.7), c);
  };

  return {
    update(dt) { t += dt; },
    draw(p) {
      // ---- 起手：细光收拢 + 竖向亮缝
      if (t < T0 + 0.05) {
        const g = clamp(t / T0);
        if (core) for (const [a, r0] of gather) {
          const r = r0 * (1 - g) + 1.5, L = 4 + 3 * g;
          p.line(Math.cos(a) * r, Math.sin(a) * r, Math.cos(a) * (r + L), Math.sin(a) * (r + L), C[g > 0.6 ? 6 : 5]);
        }
        if (core && t > T0 * 0.5) p.line(0, -hw * 0.7, 0, hw * 0.7, C[t < T0 ? 6 : 4]);
        if (deco) p.glow(0, 0, 10, C[4], GK * g);
      }
      const x = hx(), fly = t >= T0 && t < T1, hot = t < T0 + 0.06 ? 2 : t < T0 + 0.12 ? 1 : 0;
      // ---- 剑痕：从出手点到狼首后方的两条细边线（核心），中间半透明填充（装饰），收尾时从后往前收
      if (t >= T0 && t < T1 + DL * 0.6) {
        const back = Math.max(0, dist * clamp((t - T0 - 0.12) / (TF + DL * 0.5)));   // 尾端追上来
        const front = Math.max(back, x - (el >= 2 ? 44 : 18));
        for (let px = back; px < front; px += 1) {
          const u = (px - back) / Math.max(1, front - back);           // 0 尾 → 1 头
          const wv = hw * 0.55 * Math.pow(u, 0.7) * (1 + 0.15 * noise(px * 0.21, o.seed));
          if (core && u > 0.12 && t < T1 + 0.1) {   // 狼首碎掉后边线 0.1 秒内收掉，余下交给装饰层
            const ci = u > 0.75 && hot ? 6 : u > 0.5 ? 5 : u > 0.28 ? 4 : 3;
            p.dot(px, -wv, C[ci]); p.dot(px, wv, C[ci - 1]);
            if (u > 0.45 && fly) p.dot(px, 0, C[u > 0.8 ? 6 : 4]);   // 剑脊：中线一格亮线，飞行中才有
          }
          if (deco) for (let y = -wv + 1; y < wv; y += 1) p.blend(px, y, C[3], 0.22 * u * (1 - Math.abs(y) / (wv + 1)));
        }
      }
      // ---- E2 双生刃：两柄长刃从狼的前胸伸到身后，在躯干上交叉成 X（核心，画在狼下面，两端露出来）
      if (core && el >= 2 && fly) {
        const L = Math.min(62, x + 6);
        for (const sg of [-1, 1]) {
          const x0 = x + 6, y0 = sg * hw * 0.92, x1 = x - L, y1 = -sg * hw;
          p.line(x0, y0, x1, y1, C[hot ? 6 : 5]);
          p.line(x0 - 1, y0 - sg, x1 + 2, y1 + sg, C[4]);   // 刃身第二格（2 格宽、外亮内暗）
          p.dot(x0 + 1, y0, hot ? C[6] : BLUE);              // 刃尖亮点
        }
      }
      // ---- E1 残影：狼首身后一层平涂剪影（核心层，降三阶），不看说明也能看出「多了一截」
      if (core && el === 1 && fly) for (const [d, ci] of [[17, 1]]) {
        const gx = x - d;
        if (gx < 4) continue;
        p.shade(gx - 25, -14, gx + 17, 14, (px, py, out) => { if (px >= -2 && inPoly(head, px - gx, py)) out.c = C[ci]; });
      }
      // ---- 狼（核心）：晶面明暗 + 上沿亮边 + 眼；从出手点的亮缝里钻出来（出手点后面不画），飞完之后一块块碎开
      if (core && t >= T0 && t < T1 + 0.05) {
        const brk = clamp((t - T1) / 0.05);   // 0 完整 → 1 碎散（碎片交给下面的终点晶片）
        p.shade(x - 50, -14, x + 18, 14, (px, py, out) => {
          if (px < -2) return;
          const lx = (px - x) / (1 + brk * 0.5), ly = py / (1 + brk * 0.5);   // 碎开时整体往外胀
          if (!polys.some((pl) => inPoly(pl, lx, ly))) return;
          let best = 1e9, sd = seeds[0];
          for (const q of seeds) { const d = (q[0] - lx) ** 2 + (q[1] - ly) ** 2; if (d < best) { best = d; sd = q; } }
          if (brk > 0 && ((sd[2] * 7) % 1 + 1) % 1 < brk) return;           // 碎开：晶面一块块掉
          const lit = -sd[1] / 4.5 + sd[0] / 40 + sd[2];                    // 上沿受光、晶面明暗跳一阶
          const ci = clamp(Math.round(3.1 + lit + hot * 2 + (lx < -10 ? 0.6 : 0)), 1, hot ? 6 : 4);   // 平时晶面封顶第 4 阶（近白只给白热帧和亮边），躯干提半阶
          out.c = el >= 2 && ci >= 4 && !hot && sd[2] > 0.4 ? BLUE : C[ci];   // E2：最亮的几面带原作的淡蓝
        });
        if (brk < 0.5) for (const [i, j] of [[0, 1], [1, 2], [2, 3], [3, 4], [5, 6]]) {   // 上沿 1 格亮边：吻 → 额 → 两只耳尖（轮廓优先）
          const a = head[i], b = head[j];
          if (x + Math.min(a[0], b[0]) >= -2) p.line(x + a[0], a[1], x + b[0], b[1], C[hot ? 6 : 5]);
        }
        if (brk < 0.3) p.dot(x + 6, -3.4 * HS, el >= 2 ? BLUE : C[6]);      // 眼
        if (el >= 1 && brk < 0.3) seal(p, x - 4, -1 * HS, 2.6, C[6]);      // E1+ 额后封印纹
      }
      // ---- E1+ 封印符：剑气走过处一串断续歪十字，亮一下后变暗淡出；终点烙一个大的
      if (el >= 1) for (const s of seals) {
        const u = t - s.t0;
        if (u < 0 || u > 0.18 + DL * 0.5) continue;
        const k = u < 0.08 ? 6 : u < 0.18 ? 5 : 3;
        if (core) { seal(p, s.x, s.y, s.sz[0], C[k], s.sz[1]); if (u < 0.08) p.dot(s.x, s.y, C[6]); }
        if (deco) p.glow(s.x, s.y, 5, C[4], 0.35 * (1 - u / (0.18 + DL * 0.5)));
      }
      if (el >= 1 && core && t >= T1 && t < T1 + 0.15 + DL * 0.4) seal(p, dist + 4, 0, 4.5, C[t < T1 + 0.06 ? 6 : t < T1 + 0.18 ? 5 : 3]);
      // ---- 装饰：狼首光晕
      if (deco && fly) for (let k = 0; k < 4 + el; k++) p.glow(x + 6 - k * 9, 0, 7 + 2 * el - k, C[3], GK * (hot ? 1.3 : 1) * (1 - k * 0.15));   // 光晕沿剑气拉长（不是一个圆）
      // ---- 装饰：路上脱落的晶片（往后飘、慢慢转、淡出）
      if (deco) for (const c of chips) {
        const u = t - c.t0;
        if (u < 0 || u > c.life) continue;
        const k = 1 - u / c.life;
        shard(p, c.x + c.vx * u, c.y + c.vy * u, c.r + u * 4, c.s, C[k > 0.6 ? 4 : 3], Math.min(1, 1.6 * k));
      }
      // ---- 终点碎散：晶片顺着飞行方向迸出（不是圆形爆点：多数朝前、少数回弹）
      if (t >= T1) for (const b of burst) {
        const u = t - T1;
        if (u > b.life) continue;
        const k = 1 - u / b.life, d = b.sp * u * (1 - u * 0.8);
        const bx = dist + Math.cos(b.a) * d, by = Math.sin(b.a) * d * 0.8;
        if (core && u < 0.1) shard(p, bx, by, b.r + u * 6, b.s, C[u < 0.05 ? 6 : 5], 1);
        else if (deco) shard(p, bx, by, b.r + u * 6, b.s * 0.8, C[4], 0.9 * k);
      }
      if (deco && t >= T1 && t < T1 + 0.2) for (let k = 0; k < 3; k++) p.glow(dist + 4 + k * 8, 0, 10 + 3 * el - 2 * k, C[4], GK * (1 - (t - T1) / 0.2));   // 终点光顺着飞行方向冲出去
      // ---- 装饰余韵：路上零星闪点、淡雾
      if (deco) for (const f of flick) {
        const u = t - f.t0;
        if (u < 0 || u > DL) continue;
        const k = (1 - u / DL) * (0.5 + 0.5 * Math.sin(f.ph + u * 40));
        if (k > 0.15) p.blend(f.x, f.y, C[k > 0.6 ? 5 : 4], Math.min(1, k));
      }
      if (deco && t >= T0 + 0.1 && t < T1 + DL) {
        const m = clamp((t - T0 - 0.1) / (TF + DL));
        for (const [mx, my, ml] of mist) for (let k = 0; k < ml; k++) p.blend(mx + k + 8 * m, my, C[2], 0.2 * (1 - m) * (1 - k / ml));   // 淡雾：顺着剑气的几缕长短不一的横丝
      }
    },
  };
}
