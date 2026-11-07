// 方舟幸存者羁绊技概念动画（docs/314）的共用小件：怪群（被打飞 / 溶掉）、干员占位小人、地面长沟。只用于出 GIF 给用户看方向。
import { hex, clamp, smooth, mix, scale, WHITE } from "../../core/index.js";

const BODY = hex("#3b3152"), RIM = hex("#8f7cb8"), DARK = hex("#141019"), EYE = hex("#ff3f5f");
export const SHADOW = DARK;

// 一群怪：{x, y, s(大小), th(被打时刻), vx, vy}；被打后白一拍 → 被推开（带阻力）→ 抖散
export class Foes {
  constructor(R, n, cx, cy, rx, ry) {
    this.list = [];
    for (let i = 0; i < n; i++) {
      const a = R.range(0, Math.PI * 2), d = Math.sqrt(R.range(0, 1));
      this.list.push({ x: cx + Math.cos(a) * rx * d, y: cy + Math.sin(a) * ry * d, s: R.range(0.8, 1.25), th: -1, vx: 0, vy: 0, ph: R.range(0, 6.28), life: R.range(0.3, 0.5), hold: null });
    }
  }
  alive() { return this.list.filter((f) => f.th < 0); }
  hit(f, t, vx = 0, vy = 0) { if (f.th < 0) { f.th = t; f.vx = vx; f.vy = vy; } }
  update(dt, t) {
    for (const f of this.list) {
      if (f.hold) { const q = f.hold(f); f.x = q[0]; f.y = q[1]; continue; }
      if (f.th >= 0) { f.x += f.vx * dt; f.y += f.vy * dt; const k = Math.pow(0.03, dt); f.vx *= k; f.vy *= k; }
    }
  }
  draw(p, t) {
    for (const f of [...this.list].sort((a, b) => a.y - b.y)) {
      const age = f.th < 0 || f.hold ? -1 : t - f.th;
      if (age > f.life) continue;
      const a = age < 0 ? 1 : 1 - smooth(f.life * 0.3, f.life, age), w = 4 * f.s, h = 3 * f.s;
      const bob = age < 0 ? Math.round(Math.sin(t * 7 + f.ph) * 0.6) : 0, white = age >= 0 && age < 0.07;
      p.ellipse(f.x, f.y + 1, w + 1, 1.5, DARK, 0.45 * a);
      p.ellipse(f.x, f.y - h + bob, w, h, white ? WHITE : BODY, a);
      if (!white) {
        p.line(f.x - w + 1.5, f.y - 2 * h + 1 + bob, f.x + w - 1.5, f.y - 2 * h + 1 + bob, RIM, a);
        p.dot(Math.round(f.x + w * 0.45), Math.round(f.y - h - 1 + bob), EYE, a);
      }
    }
  }
}

// 干员占位小人（约 16 px 高）：身体主色、头发副色；pose 1 出手（前倾）
export function op(p, x, y, body, hair, pose = 0, face = 1) {
  const l = pose ? face : 0;
  p.ellipse(x, y + 1, 5, 1.5, DARK, 0.45);
  p.rect(x - 2 + l, y - 9, 5, 9, body);
  p.rect(x - 2 + l, y - 9, 5, 1, scale(body, 1.4));
  p.rect(x - 2 + l * 2, y - 14, 5, 5, hex("#f0dccb"));
  p.rect(x - 3 + l * 2, y - 15, 7, 3, hair);
  p.rect(face > 0 ? x - 3 + l * 2 : x + 3 + l * 2, y - 13, 1, 5, hair);
}

// 地上划开的一道沟：沿 (x0,y0)→(x1,y1) 显现到 u1；新划的一段热，往回冷成暗痕
export function groove(p, x0, y0, x1, y1, u1, hot, cold, fade = 1) {
  const n = Math.ceil(Math.hypot(x1 - x0, y1 - y0));
  for (let i = 0; i <= n * u1; i++) {
    const u = i / n, x = x0 + (x1 - x0) * u, y = y0 + (y1 - y0) * u, heat = 1 - smooth(0, 0.35, u1 - u);
    const j = Math.round(Math.sin(i * 0.9) * 0.7 + Math.sin(i * 0.31) * 0.8);
    p.dot(x, y + j, heat > 0.6 ? hot : mix(cold, hot, heat), fade);
    if (i % 2 === 0) p.dot(x, y + j + 1, DARK, fade);
    if (heat > 0.6) p.glow(x, y + j, 3, hot, 0.15 * fade);
  }
}
