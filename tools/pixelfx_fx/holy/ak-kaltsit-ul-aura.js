// 凯尔希 / Mon3tr 常驻循环帧条（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：首尾无缝循环，侧视，原点见各 move。
// 原作参照（build/ark_ref/mon3tr）：S3 熔毁常驻 monstr_skill_03_buff_01（红点粒子 + 红黑流光贴身流动；原作 dspr 的火焰不要），
//   S1 外壳 kalts_skill_01_buff（护盾骨架，原作蓝色，本作骨白 + 黄绿）。
// move：melt（Mon3tr 熔毁期间贴身：几道细的暗绯红热流沿身体边缘往上飘、红点余烬、偶尔一粒白火星；原点 = Mon3tr 脚底）
//       shell（节点「结构加固」队长身上 3 秒外壳：几片骨白外壳片围着身体缓慢起伏、边上一格黄绿；原点 = 脚底；等宽 4 帧，游戏里 6 fps 循环）
//       blade（精二身侧骨刃：一片骨白弯刃轻微上下浮动；2 帧，游戏里 4 fps）
import { Rng, fit, clamp, noise, hex, TAU } from "../../core/index.js";
import { OP } from "../house.js";   // 色阶唯一来源（§11.1 #12）：OP.kaltsit 黄绿；熔毁红待样板把 OP.kaltsit_melt 换成组长 C 批的压暗版后改用，暂留本地 red

function solid(p) {   // 实色：a < 0.5 不画、否则画实（pixelfx 半透明是 Bayer 点阵抖动，§12 画面不能脏）
  if (p._solid) return;
  const f = p.put.bind(p);
  p.put = (sx, sy, c, a = 1) => { if (a < 0.999) { if (a < 0.5) return; a = 1; } f(sx, sy, c, a); };
  p._solid = 1;
}

export const meta = {
  name: "Kal'tsit / Mon3tr loops unleashed",
  desc: "Seamless loops: thin dark-crimson heat wisps and embers clinging to Mon3tr during Meltdown, bone-white shell plates bobbing around the protected leader, and Mon3tr's bone side blade.",
  tags: ["aura", "loop", "buff", "summon"],
  size: [100, 100],
  origin: [50, 92],
  duration: 1.0,
  loop: true,
  fps: 20,
  bg: "dark",
  options: {
    palette: OP.kaltsit,
    red: ["#120403", "#2e0806", "#560c0a", "#84120e", "#b01c16", "#d8443a", "#f6d8d4", "#ffffff"],
    bone: "#f3efd8",
    move: "melt",
    layer: "all",
    seed: 4,
  },
};

export function create(o) {
  const mv = o.move, G = fit(o.palette, 8), RD = fit(o.red, 8), Rg = new Rng(o.seed), BN = hex(o.bone);
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const D = mv === "shell" ? 4 / 6 : mv === "blade" ? 0.5 : 1.0;   // 循环时长 = 帧数 / 游戏 fps
  // 熔毁：热流（每条一个相位，沿身体边缘某一侧往上走，横向按 noise 扭）、余烬
  const wisps = [], embers = [];
  if (mv === "melt") {
    for (let i = 0; i < 5; i++) wisps.push({ x: Rg.range(-22, 22), ph: Rg.range(0, 1), h: Rg.range(26, 44), s: o.seed + i * 17 });
    for (let i = 0; i < 9; i++) embers.push({ x: Rg.range(-24, 24), y: -Rg.range(6, 44), ph: Rg.range(0, 1), vy: Rg.range(14, 28), white: i < 1 });
  }
  const plates = [];
  if (mv === "shell") {
    let a = Rg.range(0, TAU);
    for (let i = 0; i < 6; i++) { a += TAU / 6 * Rg.range(0.75, 1.25); plates.push({ a, r: Rg.range(11, 14), s: Rg.range(3.2, 4.4), rot: Rg.range(-0.5, 0.5), ph: Rg.range(0, 1) }); }
  }
  let t = 0;
  const plate = (p, cx, cy, s, rr, col, edge) => {
    const cs = Math.cos(rr), sn = Math.sin(rr);
    const pts = [[-s, -s * 0.5], [s, -s * 0.6], [s * 0.8, s * 0.6], [-s * 0.9, s * 0.5]].map(([a, b]) => [cx + a * cs - b * sn, cy + a * sn + b * cs]);
    p.poly(pts, col, 1);
    p.line(pts[0][0], pts[0][1], pts[1][0], pts[1][1], edge, 1);
  };
  return {
    update(dt) { t += dt; },
    drawBack(p) {},
    draw(p) {
      solid(p);
      const u = (t % D) / D;   // 0..1 循环相位
      if (mv === "melt") {
        if (core) for (const w of wisps) {   // 热流：一串点沿往上的扭曲路径，头亮尾暗，相位循环
          const q = (u + w.ph) % 1;
          for (let k = 0; k < 10; k++) {
            const v = q - k * 0.035;
            if (v < 0 || v > 1) continue;
            const y = -v * w.h - 4, x = w.x * (1 - v * 0.35) + 3 * noise(v * 3 + w.s, w.s);
            p.rect(x, y, 1, 1, RD[clamp(Math.round(5 - k * 0.45 - v * 2), 2, 5)], 1);
          }
        }
        if (deco) for (const e of embers) {
          const q = (u + e.ph) % 1, y = e.y - q * e.vy, x = e.x + 2 * noise(q * 2 + e.x, 3);
          if (q > 0.85) continue;
          p.rect(x, y, 1, 1, e.white && q < 0.3 ? RD[6] : RD[clamp(Math.round(5 - q * 3), 3, 5)], 1);
        }
      } else if (mv === "shell") {
        if (core) for (const pl of plates) {
          const b = Math.sin((u + pl.ph) * TAU) * 1.2, cx = Math.cos(pl.a) * pl.r * 0.8, cy = -26 + Math.sin(pl.a) * pl.r * 1.15 + b;
          plate(p, cx, cy, pl.s, pl.a + Math.PI / 2 + pl.rot, BN, G[5]);
        }
      } else if (mv === "blade") {
        const b = Math.round(Math.sin(u * TAU));   // 2 帧：上下差 1 格
        if (core) {
          p.poly([[0, -10 + b], [3, -5 + b], [2, 2 + b], [0, 5 + b], [-1, -2 + b]], BN, 1);
          p.line(0, -10 + b, 2, 2 + b, G[5], 1);
        }
      }
    },
  };
}
