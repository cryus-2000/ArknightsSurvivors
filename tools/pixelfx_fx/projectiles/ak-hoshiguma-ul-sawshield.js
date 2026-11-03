// 星熊精二「般若回旋」放开版：掷出的盾锯弹体（替 proj_hoshiguma_sawshield 程序 / Codex 弹体），循环；原点 = 盾心，俯视压扁 sy 0.6。
// 盾面 = PRTS 黑钢盾（#272727 / #1E1E1E 一带），盾心一道暗红般若纹（两只眼角 + 獠牙，随盾转）；外沿一圈参差锯齿，前进侧齿尖白热、其余钢灰，
// 精二般若：齿根透一点青绿。装饰层只画齿尖后面拖出的两三道切线向短弧（转速的残影），不画整圈光环（用户 11-04）、不画盾心圆光（§12.3）。
// 一个循环正好转一整圈（般若纹回到原位），8 帧 @24 = 每秒三圈，画面上靠残影弧读出转速。
import { fit, clamp, noise, noise2, TAU } from "../../core/index.js";

export const meta = {
  name: "Hoshiguma unleashed saw-shield",
  desc: "Spinning thrown shield-saw: a dark steel disc with a dark-red oni mark, ragged saw teeth white-hot on the leading side with teal at the roots, and short tangential after-image arcs behind the teeth.",
  tags: ["projectile", "saw", "shield", "loop"],
  size: [60, 44],
  origin: [30, 22],
  duration: 8 / 24,
  loop: true,
  fps: 24,
  bg: "dark",
  options: {
    palette: ["#121418", "#262a31", "#434a55", "#6d7684", "#a3acb8", "#d9dee6", "#ffffff"],   // 钢色 = PRTS 黑钢盾（不用金，§12.6）
    ember: ["#2a0a08", "#5e1410", "#9c2418", "#d8452a", "#ff7050"],
    jade: ["#081814", "#18584c", "#258a77", "#58c4ab", "#b4f0e2"],
    radius: 15,
    teeth: 9,
    layer: "all",
    seed: 3,
  },
};

const SY = 0.6;

export function draw(p, t, o) {
  const C = fit(o.palette, 7), E = fit(o.ember, 5), J = fit(o.jade, 5);
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const R = +o.radius, N = +o.teeth, rot = (t / meta.duration) * TAU;
  // 齿：高矮不一（按齿号固定），整圈随盾转
  const toothH = (i) => 3.2 + 1.6 * (0.5 + 0.5 * noise(i * 1.7, o.seed));
  if (deco) for (let i = 0; i < N; i += 3) {   // 残影：每三颗齿拖一道切线向短弧（逆转向，长 0.5 rad），越往后越淡
    const a0 = rot + (i / N) * TAU, rr = R + toothH(i) * 0.6;
    for (let s = 0; s < 0.5; s += 0.03) {
      const a = a0 - s, k = 1 - s / 0.5;
      p.blend(Math.cos(a) * rr, Math.sin(a) * rr * SY, C[k > 0.6 ? 5 : 4], 0.55 * k * k);
    }
  }
  if (!core) return;
  // 盾面：逐像素，边缘压暗、上半略受光；般若纹（两眼角 + 两颗獠牙）在盾面坐标里画，随 rot 转
  for (let y = -R * SY - 1; y <= R * SY + 1; y++) for (let x = -R - 1; x <= R + 1; x++) {
    const r = Math.hypot(x, y / SY);
    if (r > R) continue;
    const a = Math.atan2(y / SY, x) - rot, lx = Math.cos(a) * r, ly = Math.sin(a) * r;   // 盾面本地坐标
    let c = C[clamp(Math.round(2 - r / R * 1.4 + (y < 0 ? 0.6 : 0) + 0.4 * noise2(lx * 0.4, ly * 0.4, o.seed)), 0, 3)];
    const eye = Math.abs(Math.abs(lx) - 5) < 2.2 && ly > -5 && ly < -1.5 && ly < -1.5 - (Math.abs(lx) - 5) * 0.8;   // 斜挑的眼角
    const fang = Math.abs(Math.abs(lx) - 3.2) < 1 && ly > 2 && ly < 6 - Math.abs(lx - Math.sign(lx) * 3.2) * 2;     // 两颗獠牙往下
    if (eye || fang) c = E[eye ? 3 : 2];
    if (r > R - 1.2) c = C[3];   // 盾沿一圈钢灰硬边
    p.blend(x, y, c, 1);
  }
  // 锯齿：三角齿往外、略后掠；前进侧（画面右侧，x > 0）齿尖白热、齿根透青绿，其余齿根暗钢
  for (let i = 0; i < N; i++) {
    const a = rot + (i / N) * TAU, h = toothH(i), half = (TAU / N) * 0.32;
    const lead = Math.cos(a) > 0.3;
    for (let d = 0; d <= h; d += 0.5) {
      const v = d / h, w = half * (1 - v), ac = a - v * 0.25;   // 齿尖往转向后掠
      for (let e = -w; e <= w; e += 0.04) {
        const rr = R - 0.5 + d, x = Math.cos(ac + e) * rr, y = Math.sin(ac + e) * rr * SY;
        const c = v < 0.3 ? (lead ? J[3] : C[2]) : lead && v > 0.6 ? C[6] : C[clamp(Math.round(3 + v * 2), 3, 5)];   // 青绿只在前进侧齿根，不绕成一圈
        p.blend(x, y, c, 1);
      }
    }
  }
}
