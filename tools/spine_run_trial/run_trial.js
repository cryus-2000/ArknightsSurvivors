'use strict';
// 跑步试做：在原生 Spine 骨骼上按步态表摆 8 帧跑步，逐附件像素化后合成 128 画布 @2x。
// 只读原生 skel / atlas / 贴图与 bz_18 部件包的映射和调色板；不生成像素、不挪平图。
// 用法：node run_trial.js cfg/<id>.json [--out build/spine_run_trial/<id>] [--editor-ops <Codex Run raw 目录>]
const fs = require('fs'), path = require('path');
const { createCanvas } = require('@napi-rs/canvas');
const { load } = require('./load.js');

const cfgPath = process.argv[2];
const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
const src = JSON.parse(fs.readFileSync(path.join(path.dirname(cfgPath), cfg.src), 'utf8'));
const arg = k => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : null; };
const OUT = path.resolve(arg('--out') || `build/spine_run_trial/${cfg.id}/frames`);
const BZ = 'E:/ArknightsSurvivors/.worktrees/codex-art/art/incoming/bz_18_native_spine_parts_1017';
const BT = 'E:/ArknightsSurvivors/.worktrees/codex-art/art/incoming/bt_18_complete_parts_1017';
const D = 180 / Math.PI;

// 像素映射与 bz_18 静态部件包一致：px = mapped_root + bz_scale × source_scale × 世界坐标
const manifest = JSON.parse(fs.readFileSync(`${BZ}/${cfg.id}/manifest.json`, 'utf8'));
const catalog = JSON.parse(fs.readFileSync(`${BT}/${cfg.id}/source/catalog.json`, 'utf8'));
const SCALE = manifest.global_transform.scale * Number(catalog.scale);
const ANCHOR = manifest.global_transform.mapped_root.slice();
const SIZE = 128, CUT = manifest.alpha_cutoff || 96;

const P = Object.assign({ lean: 9, chestLean: 3, headKeep: 0.6, stride: 1, lift: 1, bob: 1, armAmp: 38, elbow: 75, elbowAmp: 25,
  holdAmp: 8, holdElbowAmp: 6, weaponSway: 3, weaponLean: 0.5, hairDrag: 5, hairAmp: 3, facing: 1 }, cfg.params || {});

// 每条腿 8 相位：脚踝相对髋关节的水平位置 fx、离地高度 fy（以腿长 L 为单位），脚掌转角（+ = 脚尖上翘）
// 0 触地 1 下压承重 2 经过 3 后蹬 4 离地后踢 5 屈膝回收 6 前摆 7 前伸
const GAIT = [[0.30, 0, 8], [0.10, 0, 0], [-0.12, 0, 0], [-0.32, 0, -22], [-0.38, 0.20, -40], [-0.14, 0.36, -30], [0.18, 0.30, -8], [0.33, 0.11, 4]];
// 身体起伏（腿长单位）：触地中位、下压最低、后蹬腾空最高
const BOB = [-0.05, -0.10, -0.06, 0.01, -0.05, -0.10, -0.06, 0.01];
// 摆动腿离地高度（@2x 像素，按相位 4–7）：10-20 用户按推进之王旧 run 条定的口径，后踢 13、回收 8、前摆 3、前伸 2
const LIFT_PX = [null, null, null, null, 13, 8, 3, 2];

function verts(sp, slot, att) {
  if (att.updateWorldVertices) {                         // 3.5：步长 8
    const v = att.updateWorldVertices(slot, false), out = [];
    for (let i = 0; i < v.length; i += 8) out.push(v[i], v[i + 1]);
    return out;
  }
  const n = att instanceof sp.RegionAttachment ? 8 : att.worldVerticesLength, out = new Array(n);
  if (att instanceof sp.RegionAttachment) att.computeWorldVertices(slot.bone, out, 0, 2);
  else att.computeWorldVertices(slot, 0, n, out, 0, 2);
  return out;
}

async function main() {
  const { sp, pose } = await load(src);
  const branch = (sk, b) => sk.bones.filter(x => { for (let p = x; p; p = p.parent) if (p === b) return true; return false; });
  function rotate(sk, b, deg, pivot) {
    const t = deg / D, c = Math.cos(t), s = Math.sin(t), [x, y] = pivot || [b.worldX, b.worldY];
    for (const p of branch(sk, b)) {
      const dx = p.worldX - x, dy = p.worldY - y, a = p.a, bb = p.b, cc = p.c, d = p.d;
      p.worldX = x + c * dx - s * dy; p.worldY = y + s * dx + c * dy;
      p.a = c * a - s * cc; p.b = c * bb - s * d; p.c = s * a + c * cc; p.d = s * bb + c * d;
    }
  }
  function move(sk, b, dx, dy) { for (const p of branch(sk, b)) { p.worldX += dx; p.worldY += dy; } }
  const ang = b => Math.atan2(b.c, b.a) * D;
  const dir = (a, b) => Math.atan2(b.worldY - a.worldY, b.worldX - a.worldX) * D;
  const dist = (a, b) => Math.hypot(b.worldX - a.worldX, b.worldY - a.worldY);
  const aim = (sk, a, b, deg) => rotate(sk, a, deg - dir(a, b));
  // 双节 IK：保持骨长；两解中取膝 / 肘朝 bendDir（+1 = 朝面向方向）的那一个
  function ik(sk, a, b, c, target, bendDir) {
    const l1 = dist(a, b), l2 = dist(b, c);
    let dx = target[0] - a.worldX, dy = target[1] - a.worldY, d = Math.hypot(dx, dy);
    const cl = Math.max(Math.abs(l1 - l2) + 0.1, Math.min(l1 + l2 - 0.1, d)); dx *= cl / d; dy *= cl / d; d = cl;
    const alpha = Math.atan2(dy, dx), beta = Math.acos(Math.max(-1, Math.min(1, (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d))));
    let best = null;
    for (const sign of [1, -1]) {
      // 膝相对「髋→目标」连线的侧向（叉积）：腿朝下时正值 = 膝朝 +x
      const kx = Math.cos(alpha + sign * beta), ky = Math.sin(alpha + sign * beta);
      const score = (dx * ky - dy * kx) * bendDir;
      if (!best || score > best.score) best = { sign, score };
    }
    aim(sk, a, b, (alpha + best.sign * beta) * D);
    aim(sk, b, c, Math.atan2(a.worldY + dy - b.worldY, a.worldX + dx - b.worldX) * D);
  }
  const get = (sk, n) => { const b = sk.findBone(n); if (!b) throw Error('缺骨骼 ' + n); return b; };

  // 待机 t=0 作为基础姿势：量地面、腿长、脚掌角、武器角
  const base = pose('Idle', 0);
  const footSlots = side => base.slots.filter(s => s.getAttachment() && cfg.legs[side].slice(2).concat(cfg.footExtra?.[side] || []).includes(s.bone.data.name)).map(s => s.data.name);
  const bottom = (sk, side) => {
    let y = Infinity;
    for (const n of footSlots(side)) { const s = sk.findSlot(n), a = s.getAttachment(); if (!a) continue; const v = verts(sp, s, a); for (let i = 1; i < v.length; i += 2) y = Math.min(y, v[i]); }
    return y;
  };
  const ground = Math.min(bottom(base, 'L'), bottom(base, 'R'));
  // 鞋底贴原点：地面映射到 y=120（最后一行 119），与游戏原点 (64,120) 和旧 run 条一致。
  // bz_18 的 mapped_root 按整身包围盒放置，推进之王因锤头垂到脚下会让鞋底悬空约 4 像素。
  ANCHOR[1] = 120 + ground * SCALE;
  const legInfo = {};
  for (const side of ['L', 'R']) {
    const [a, b, c] = cfg.legs[side].map(n => get(base, n));
    legInfo[side] = { L: dist(a, b) + dist(b, c), foot: ang(c), hipToAnkle: a.worldY - c.worldY, ankleAbove: c.worldY - bottom(base, side) };
  }
  const L = (legInfo.L.L + legInfo.R.L) / 2;
  const hold = cfg.hold;
  const weaponBase = cfg.weapon ? ang(get(base, cfg.weapon)) : 0;
  console.log(cfg.id, 'scale', SCALE.toFixed(4), 'leg L', L.toFixed(1), 'ground', ground.toFixed(1), 'px leg', (L * SCALE).toFixed(1));

  function frame(i) {
    const sk = pose('Idle', 0), f = P.facing, phi = i / 8 * 2 * Math.PI;
    const hip = get(sk, cfg.body.hip);
    if (cfg.mode === 'float') return floatFrame(sk, i, phi);
    // 1) 躯干：前倾 + 起伏；胸再前倾一点，头部回正一部分（保持脸可读）
    move(sk, hip, 0, BOB[i] * L * P.bob);
    rotate(sk, hip, -f * P.lean);
    if (cfg.body.chest) rotate(sk, get(sk, cfg.body.chest), -f * (P.chestLean + 1.5 * Math.cos(2 * phi)));
    if (cfg.body.head) rotate(sk, get(sk, cfg.body.head), f * (P.lean + P.chestLean) * P.headKeep + 1.5 * Math.sin(2 * phi - 0.6));
    // 2) 腿：按相位放脚踝，支撑相把鞋底贴地
    const contacts = [];
    for (const side of ['L', 'R']) {
      const k = (i + (side === cfg.leadLeg ? 0 : 4)) % 8, g = GAIT[k];
      const [a, b, c] = cfg.legs[side].map(n => get(sk, n)), info = legInfo[side];
      const tx = a.worldX + f * g[0] * L * P.stride;
      const setFoot = () => rotate(sk, c, info.foot + f * g[2] - ang(c));
      // gaitLiftPx：按像素指定各相位离地高度（对齐已批准的旧条），否则用步态表 × lift
      const liftPx = (cfg.gaitLiftPx === undefined ? LIFT_PX : cfg.gaitLiftPx || [])[k];
      let ty = ground + info.ankleAbove + (liftPx != null ? liftPx / SCALE : g[1] * L * P.lift);
      ik(sk, a, b, c, [tx, ty], f); setFoot();
      const stance = k <= 3;
      for (let n = 0; n < 6; n++) {
        const err = bottom(sk, side) - ground;
        const want = !stance && liftPx != null ? liftPx / SCALE : 0;
        if (stance || liftPx != null ? Math.abs(err - want) < 0.05 : err >= -0.05) break;
        if (liftPx != null && !stance) { ty -= err - want; ik(sk, a, b, c, [tx, ty], f); setFoot(); continue; }
        ty -= err; ik(sk, a, b, c, [tx, ty], f); setFoot();
      }
      contacts.push({ side, phase: k, support: stance, gap: +(bottom(sk, side) - ground).toFixed(2) });
    }
    arms(sk, i, phi);
    secondary(sk, phi);
    return finish(sk, contacts);
  }

  // 悬浮飘行（浊心斯卡蒂）：不踩地；身体缓慢上下浮动并前倾，两腿向后拖、交替轻摆，衣摆和头发大幅向后飘
  function floatFrame(sk, i, phi) {
    const f = P.facing, hip = get(sk, cfg.body.hip);
    move(sk, hip, 0, (P.floatBob ?? 2) / SCALE * Math.sin(phi));
    rotate(sk, hip, -f * P.lean);
    if (cfg.body.head) rotate(sk, get(sk, cfg.body.head), f * P.lean * P.headKeep + 1.2 * Math.sin(phi - 0.8));
    for (const side of ['L', 'R']) {
      const [a, b] = cfg.legs[side].map(n => get(sk, n)), off = side === cfg.leadLeg ? 0 : Math.PI;
      rotate(sk, a, -f * (P.floatTrail ?? 14) + f * (P.floatKick ?? 6) * Math.sin(phi + off));
      rotate(sk, b, -f * (P.floatKnee ?? 10) * (0.6 + 0.4 * Math.sin(phi + off - 0.9)));
    }
    arms(sk, i, phi);
    secondary(sk, phi);
    return finish(sk, [{ mode: 'float', bob_px: +((P.floatBob ?? 2) * Math.sin(phi)).toFixed(2) }]);
  }

  function arms(sk, i, phi) {
    const f = P.facing;
    // 3) 手臂：与同侧腿反向摆；持武器手只小幅摆动，武器绕握点保持角度
    for (const side of ['L', 'R']) {
      const [a, b, c] = cfg.arms[side].map(n => get(sk, n));
      const k = (i + (side === cfg.leadLeg ? 0 : 4)) % 8;
      const fwd = -Math.cos(k / 8 * 2 * Math.PI);           // 同侧腿在前时手在后
      if ((cfg.relativeArms || []).includes(side)) {
        // 原姿势就握着东西（挂在髋上的武器 / 盾）：只在原姿势上小幅摆，不改握持关系
        rotate(sk, a, f * (P.relAmp ?? 6) * fwd); rotate(sk, b, f * (P.relElbowAmp ?? 3) * fwd);
      } else if (side === hold && cfg.holdPose) {
        // 扛 / 端武器：上臂、前臂给绝对角，再小幅随步摆动
        const hp = cfg.holdPose, up = hp.upper + f * P.holdAmp * fwd;
        aim(sk, a, b, up); aim(sk, b, c, up + hp.fore + f * P.holdElbowAmp * fwd);
      } else if (side === hold) {
        rotate(sk, a, f * P.holdAmp * fwd + f * (cfg.holdArmLean ?? P.lean * 0.6));
        rotate(sk, b, f * P.holdElbowAmp * Math.max(0, fwd));
      } else {
        const upper = -90 + f * (cfg.armBase ?? 5) + f * P.armAmp * fwd;
        aim(sk, a, b, upper);
        aim(sk, b, c, upper + f * (P.elbow + P.elbowAmp * Math.max(0, fwd)));
      }
    }
    if (cfg.weapon && hold) {
      const w = get(sk, cfg.weapon), grip = get(sk, cfg.arms[hold][2]);
      rotate(sk, w, (cfg.holdPose?.weapon ?? weaponBase) - f * P.lean * P.weaponLean + P.weaponSway * Math.sin(2 * phi - 1.0) - ang(w), [grip.worldX, grip.worldY]);
      // grip：武器局部坐标里的握把点；原姿势手不在握把上时（斯卡蒂大剑立在身后），把握把点移到手上
      const g = cfg.holdPose?.grip;
      if (g) move(sk, w, grip.worldX - (w.worldX + w.a * g[0] + w.b * g[1]), grip.worldY - (w.worldY + w.c * g[0] + w.d * g[1]));
    }
  }

  function secondary(sk, phi) {
    const f = P.facing;
    // 4) 次级：头发 / 尾 / 衣摆 / 绳带按链深度滞后摆动，整体向后拖
    for (const rule of cfg.secondary || []) {
      const re = new RegExp(rule.match);
      const chain = sk.bones.filter(b => re.test(b.data.name));
      for (const b of chain) {
        let depth = 0; for (let p = b.parent; p; p = p.parent) if (re.test(p.data.name)) depth++;
        const down = Math.sin(ang(b) / D) < 0 ? -1 : 1;           // 朝下的骨向后拖需顺时针
        const drag = depth === 0 ? (rule.drag ?? P.hairDrag) : 0;
        const wave = (rule.amp ?? P.hairAmp) * Math.sin((rule.freq ?? 2) * phi - (rule.lag ?? 0.9) - 0.7 * depth);
        rotate(sk, b, down * f * drag + wave);
      }
    }
  }

  function finish(sk, contacts) {
    for (const n of cfg.hide || []) { const s = sk.findSlot(n); if (s) s.attachment = null; }
    if (cfg.order) for (const [slot, before] of cfg.order) {
      const s = sk.findSlot(slot); sk.drawOrder = sk.drawOrder.filter(x => x !== s);
      sk.drawOrder.splice(sk.drawOrder.findIndex(x => x.data.name === before), 0, s);
    }
    return { sk, contacts };
  }

  // 逐附件：4 倍渲染 → 4×4 BOX 平均 → 二值透明（低于阈值的细件保留最大覆盖）→ 映射调色板 → 按层序合成
  const palette = await loadPalette();
  function pixelize(sk) {
    const out = createCanvas(SIZE, SIZE), oc = out.getContext('2d');
    const saved = sk.drawOrder.map(s => s.getAttachment()), problems = [];
    let clip = null;
    for (let i = 0; i < saved.length; i++) {
      const att = saved[i], slot = sk.drawOrder[i];
      if (!att) continue;
      if (sp.ClippingAttachment && att instanceof sp.ClippingAttachment) { clip = { end: att.endSlot?.name, v: verts(sp, slot, att) }; continue; }
      if (!(att instanceof sp.MeshAttachment || att instanceof sp.RegionAttachment)) continue;
      for (let j = 0; j < saved.length; j++) sk.drawOrder[j].attachment = j === i ? saved[j] : null;
      const v = verts(sp, slot, att), xs = [], ys = [];
      for (let n = 0; n < v.length; n += 2) { xs.push(ANCHOR[0] + v[n] * SCALE); ys.push(ANCHOR[1] - v[n + 1] * SCALE); }
      const x0 = Math.floor(Math.min(...xs)) - 1, y0 = Math.floor(Math.min(...ys)) - 1;
      const w = Math.ceil(Math.max(...xs)) - x0 + 1, h = Math.ceil(Math.max(...ys)) - y0 + 1;
      const hi = createCanvas(w * 4, h * 4), hc = hi.getContext('2d');
      hc.translate((ANCHOR[0] - x0) * 4, (ANCHOR[1] - y0) * 4); hc.scale(SCALE * 4, -SCALE * 4);
      if (clip) { hc.beginPath(); for (let n = 0; n < clip.v.length; n += 2) hc[n ? 'lineTo' : 'moveTo'](clip.v[n], clip.v[n + 1]); hc.closePath(); hc.clip(); }
      const r = new sp.canvas.SkeletonRenderer(hc); r.triangleRendering = true; r.draw(sk);
      const src4 = hc.getImageData(0, 0, w * 4, h * 4).data, img = oc.createImageData(w, h), a = img.data;
      let max = 0;
      const acc = new Float64Array(w * h * 4);
      for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
        let R = 0, G = 0, B = 0, A = 0;
        for (let yy = 0; yy < 4; yy++) for (let xx = 0; xx < 4; xx++) {
          const p = ((y * 4 + yy) * w * 4 + x * 4 + xx) * 4, al = src4[p + 3];
          R += src4[p] * al; G += src4[p + 1] * al; B += src4[p + 2] * al; A += al;
        }
        const q = (y * w + x) * 4; acc[q] = A ? R / A : 0; acc[q + 1] = A ? G / A : 0; acc[q + 2] = A ? B / A : 0; acc[q + 3] = A / 16;
        max = Math.max(max, A / 16);
      }
      const th = Math.max(1, Math.min(CUT, max));
      for (let q = 0; q < acc.length; q += 4) {
        if (acc[q + 3] < th) continue;
        const c = nearest(palette, acc[q], acc[q + 1], acc[q + 2]);
        a[q] = c[0]; a[q + 1] = c[1]; a[q + 2] = c[2]; a[q + 3] = 255;
        const px = x0 + (q / 4) % w, py = y0 + Math.floor(q / 4 / w);
        if (px < 2 || py < 2 || px >= SIZE - 2 || py >= SIZE - 2) problems.push(slot.data.name);
      }
      const low = createCanvas(w, h); low.getContext('2d').putImageData(img, 0, 0);
      oc.globalCompositeOperation = ['source-over', 'lighter', 'multiply', 'screen'][slot.data.blendMode] || 'source-over';
      oc.drawImage(low, x0, y0);
      if (clip && clip.end === slot.data.name) clip = null;
    }
    for (let i = 0; i < saved.length; i++) sk.drawOrder[i].attachment = saved[i];
    oc.globalCompositeOperation = 'source-over';
    // 合成后再二值一次（lighter / screen 叠加可能留下半透明）
    const id = oc.getImageData(0, 0, SIZE, SIZE);
    for (let q = 3; q < id.data.length; q += 4) id.data[q] = id.data[q] >= 128 ? 255 : 0;
    oc.putImageData(id, 0, 0);
    return { canvas: out, clipped: [...new Set(problems)] };
  }

  fs.mkdirSync(OUT, { recursive: true });
  const report = [];
  const frames = [];
  for (let i = 0; i < 8; i++) {
    const { sk, contacts } = frame(i), { canvas, clipped } = pixelize(sk);
    fs.writeFileSync(path.join(OUT, `f${String(i).padStart(2, '0')}.png`), canvas.toBuffer('image/png'));
    frames.push(sk);
    report.push({ frame: i, contacts, clipped_near_edge: clipped });
  }
  const idle = pixelize(base).canvas;
  fs.writeFileSync(path.join(OUT, 'idle_t0.png'), idle.toBuffer('image/png'));
  fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify({ id: cfg.id, scale: SCALE, anchor: ANCHOR, params: P, gait: GAIT, bob: BOB, frames: report }, null, 1));
  if (arg('--editor-ops')) writeEditorOps(frames, arg('--editor-ops'));
  writePack(frames);
  console.log('ok', OUT, report.map(r => r.contacts.map(c => c.side + c.phase + ':' + c.gap).join(',')).join(' | '));

  // 编辑台通用数据包：八帧世界骨骼（地面平移到 y=0，对齐编辑台地线）+ 层序 + 链 / 武器 / 标签 + 调色板
  function writePack(sks) {
    const dir = path.join(path.dirname(OUT), 'editor_pack');
    const chains = {}, labels = {};
    const sideName = { L: cfg.nearSide === 'L' ? '近侧' : '远侧', R: cfg.nearSide === 'L' ? '远侧' : '近侧' };
    for (const side of ['L', 'R']) {
      const leg = cfg.legs[side], arm = cfg.arms[side];
      chains[leg[2]] = leg; chains[arm[2]] = arm;
      const who = side === hold ? '持武器侧' : sideName[side];
      [['髋', leg[0]], ['膝', leg[1]], ['脚踝', leg[2]]].forEach(([t, n]) => labels[n] = `${sideName[side]}腿 · ${t}`);
      [['肩', arm[0]], ['肘', arm[1]], ['手腕', arm[2]]].forEach(([t, n]) => labels[n] = `${who}手 · ${t}`);
    }
    labels[cfg.body.hip] = '髋部 / 整体';
    if (cfg.body.chest) labels[cfg.body.chest] = '胸部';
    if (cfg.body.head) labels[cfg.body.head] = '头部';
    if (cfg.weapon) labels[cfg.weapon] = '武器';
    const frames = [];
    for (let i = 0; i < 8; i++) {
      const name = `Run_0${i}`; fs.mkdirSync(path.join(dir, 'frames', name), { recursive: true });
      fs.writeFileSync(path.join(dir, 'frames', name, 'bones.json'), JSON.stringify(sks[i].bones.map(b => ({
        name: b.data.name, parent: b.parent ? b.parent.data.name : undefined, world: [b.worldX, b.worldY - ground], matrix: [b.a, b.b, b.c, b.d] }))));
      frames.push({ name, anim: 'Idle', t: 0, order: sks[i].drawOrder.map(s => s.data.name), hidden: (cfg.hide || []).filter(n => sks[i].findSlot(n)) });
    }
    fs.writeFileSync(path.join(dir, 'pack.json'), JSON.stringify({ version: 1, character: cfg.id, title: `${cfg.name || cfg.id} · 跑步（步态脚本底稿）`,
      skeleton: src.json || src.skel, atlas: src.atlas, fps: 40 / 3, scale: SCALE, palette,
      bones: sks[0].bones.map(b => b.data.name), slots: sks[0].slots.map(s => s.data.name), chains,
      equipment: hold && cfg.weapon ? { [cfg.arms[hold][2]]: [cfg.weapon] } : {}, labels,
      default_bone: hold ? cfg.arms[hold][2] : cfg.legs.L[2], frames, generator: { cfg: path.basename(cfgPath), params: P } }, null, 1));
  }

  // 推进之王：把本脚本的世界姿势换算成编辑台的修正操作（相对 Codex Run 已烘焙骨骼），可在编辑台继续手调
  function writeEditorOps(sks, rawDir) {
    const core = require('../spine_editor/pose_core.js');
    const patch = { version: 1, source: null, frames: [] };
    for (let i = 0; i < 8; i++) {
      const rows = JSON.parse(fs.readFileSync(path.join(rawDir, `Run_0${i}`, 'bones.json'), 'utf8'));
      const work = core.makeBones(rows), ops = [];
      for (const b of sks[i].bones) {
        const name = b.data.name, w = work[name];
        const dx = b.worldX + (cfg.editorShift?.[0] || 0) - w.worldX, dy = b.worldY + (cfg.editorShift?.[1] || 0) - w.worldY;
        if (Math.hypot(dx, dy) > 1e-3) { core.translate(work, name, dx, dy); ops.push({ type: 'translate', bone: name, dx, dy }); }
        let r = Math.atan2(b.c, b.a) * D - Math.atan2(w.c, w.a) * D; r = ((r + 540) % 360) - 180;
        if (Math.abs(r) > 1e-3) { core.rotate(work, name, r); ops.push({ type: 'rotate', bone: name, degrees: r }); }
      }
      const order = sks[i].drawOrder.map(s => s.data.name);
      patch.frames.push({ ops, order });
    }
    fs.writeFileSync(path.join(OUT, 'editor_patch.json'), JSON.stringify(patch, null, 1));
  }
}

async function loadPalette() {
  const { loadImage } = require('@napi-rs/canvas');
  const set = new Map();
  const dir = `${BZ}/${cfg.id}/parts`;
  for (const f of fs.readdirSync(dir)) {
    const img = await loadImage(fs.readFileSync(path.join(dir, f)));
    const c = createCanvas(img.width, img.height), x = c.getContext('2d'); x.drawImage(img, 0, 0);
    const d = x.getImageData(0, 0, img.width, img.height).data;
    for (let i = 0; i < d.length; i += 4) if (d[i + 3] > 0) set.set((d[i] << 16) | (d[i + 1] << 8) | d[i + 2], [d[i], d[i + 1], d[i + 2]]);
  }
  return [...set.values()];
}
const memo = new Map();
function nearest(pal, r, g, b) {
  const key = ((r | 0) << 16) | ((g | 0) << 8) | (b | 0);
  let hit = memo.get(key); if (hit) return hit;
  let best = Infinity;
  for (const c of pal) { const d = (c[0] - r) ** 2 + (c[1] - g) ** 2 + (c[2] - b) ** 2; if (d < best) { best = d; hit = c; } }
  memo.set(key, hit); return hit;
}

main().catch(e => { console.error(e); process.exit(1); });
