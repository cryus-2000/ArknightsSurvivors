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
const OUT = path.resolve(arg('--out') || `build/spine_run_trial/${cfg.id}/${cfg.action ? cfg.action + '/' : ''}frames`);
const BZ = 'E:/ArknightsSurvivors/.worktrees/codex-art/art/incoming/bz_18_native_spine_parts_1017';
const BT = 'E:/ArknightsSurvivors/.worktrees/codex-art/art/incoming/bt_18_complete_parts_1017';
const D = 180 / Math.PI;

// 像素映射与 bz_18 静态部件包一致：px = mapped_root + bz_scale × source_scale × 世界坐标
// cfg.pack：没有 bz_18 部件包的新干员（拉普兰德 / 歌蕾蒂娅）——直接给 {scale, root: [x, y], alpha_cutoff, palette_png}
const manifest = cfg.pack ? { global_transform: { scale: cfg.pack.scale, mapped_root: cfg.pack.root || [64, 120] }, alpha_cutoff: cfg.pack.alpha_cutoff || 96 }
  : JSON.parse(fs.readFileSync(`${BZ}/${cfg.id}/manifest.json`, 'utf8'));
const catalog = cfg.pack ? { scale: 1 } : JSON.parse(fs.readFileSync(`${BT}/${cfg.id}/source/catalog.json`, 'utf8'));
const SCALE = (manifest.global_transform.scale * Number(catalog.scale)) * (cfg.scaleMul || 1);   // scaleMul：召唤物等按自己的显示尺度（归溟替身沿用 Codex 召唤物管线尺度）
const ANCHOR = manifest.global_transform.mapped_root.slice();
// 画布：跑步 128；动作可加大（cfg.canvas），原点随之平移到中心，保持 (64,120) 相对位置
const SIZE = cfg.canvas || 128, PAD = (SIZE - 128) / 2, CUT = manifest.alpha_cutoff || 96;

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
  const { sp, pose, data } = await load(src);
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
  let BACKV = false, SAVED = null;   // move_attack：攻击里转到背面的帧（斯卡蒂回旋）改用 B_ 腿
  const footSlots = side => BACKV ? data.slots.filter(s => cfg.legs[side].slice(2).includes(s.boneData.name)).map(s => s.name) : base.slots.filter(s => s.getAttachment() && cfg.legs[side].slice(2).concat(cfg.footExtra?.[side] || []).includes(s.bone.data.name)).map(s => s.data.name);
  const bottom = (sk, side) => {
    let y = Infinity;
    for (const n of footSlots(side)) { const s = sk.findSlot(n), a = s.getAttachment(); if (!a) continue; const v = verts(sp, s, a); for (let i = 1; i < v.length; i += 2) y = Math.min(y, v[i]); }
    return y;
  };
  const ground = Math.min(bottom(base, 'L'), bottom(base, 'R'));
  // 鞋底贴原点：地面映射到 y=120（最后一行 119），与游戏原点 (64,120) 和旧 run 条一致。
  // bz_18 的 mapped_root 按整身包围盒放置，推进之王因锤头垂到脚下会让鞋底悬空约 4 像素。
  ANCHOR[0] += PAD; ANCHOR[1] = 120 + PAD + ground * SCALE;
  const legInfo = {};
  for (const side of ['L', 'R']) {
    const [a, b, c] = cfg.legs[side].map(n => get(base, n));
    legInfo[side] = { L: dist(a, b) + dist(b, c), foot: ang(c), hipToAnkle: a.worldY - c.worldY, ankleAbove: c.worldY - bottom(base, side) };
  }
  const L = (legInfo.L.L + legInfo.R.L) / 2;
  const hold = cfg.hold;
  const weaponBase = cfg.weapon ? ang(get(base, cfg.weapon)) : 0;
  console.log(cfg.id, 'scale', SCALE.toFixed(4), 'leg L', L.toFixed(1), 'ground', ground.toFixed(1), 'px leg', (L * SCALE).toFixed(1));

  // sample.flatten = k（0–1）：把采样动画的髋部起伏压到 k 倍（绕全部采样帧的平均高度），脚踝 IK 回原位、脚掌角不变。
  // 安洁莉娜 dl 跑步借乌尔比安步态，髋部起伏约 3 个 1x 像素且带腾空，像素尺度下读成一跳一跳（10-20 用户）。
  const hipMean = cfg.sample?.flatten != null
    ? cfg.sample.times.reduce((m, t) => m + get(pose(cfg.sample.anim, t), cfg.body.hip).worldY, 0) / cfg.sample.times.length : 0;
  function flatten(sk) {
    const hip = get(sk, cfg.body.hip), keep = {};
    for (const side of ['L', 'R']) { const c = get(sk, cfg.legs[side][2]); keep[side] = [c.worldX, c.worldY, ang(c)]; }
    move(sk, hip, 0, (hipMean - hip.worldY) * (1 - cfg.sample.flatten));
    for (const side of ['L', 'R']) {
      const [a, b, c] = cfg.legs[side].map(n => get(sk, n)), [x, y, r] = keep[side];
      ik(sk, a, b, c, [x, y], P.facing); move(sk, c, x - c.worldX, y - c.worldY); rotate(sk, c, r - ang(c));
    }
  }

  // sample.carry：在采样动画上重摆双臂与武器（安洁莉娜跑步，10-20 用户「按最自然的办法」）。
  //   side / upper / fore / weapon：持杖臂上臂、前臂与杖的世界角（度，朝右）；swing：持杖臂随步小摆幅度。
  //   grip: 'native' → 握点、手与杖的相对角取原生 Idle t=0（原作握法），否则只让杖跟手平移。
  //   slide：沿杖身平移（调握在杖的哪一段）；front：把杖的槽挪到该槽之下（近侧手持杖时杖在身前）。
  //   free {amp, elbow, elbowAmp}：另一只手按双脚前后自然摆（同侧腿在前时手在后）。
  // 摆动相位取自本帧双脚前后差，不假设采样动画的起步腿。
  const under = (x, anc) => { for (let p = x; p; p = p.parent) if (p === anc) return true; return false; };
  let nativeGrip = null;
  function carry(sk, i) {
    const c = cfg.sample.carry, f = P.facing;
    const fl = get(sk, cfg.legs.L[2]), fr = get(sk, cfg.legs.R[2]), legLen = (L * 0.6) || 1;
    const stride = Math.max(-1, Math.min(1, (fl.worldX - fr.worldX) * f / legLen));     // +1 = 左脚在前
    const fwd = side => (side === 'L' ? -stride : stride);                                // 手与同侧腿反向
    const [a, b, h] = cfg.arms[c.side].map(n => get(sk, n)), w = get(sk, cfg.weapon), h0 = [h.worldX, h.worldY];
    const sw = (c.swing || 0) * fwd(c.side);
    aim(sk, a, b, c.upper + f * sw); aim(sk, b, h, c.fore + f * sw);
    if (c.grip === 'native') {
      if (!nativeGrip) {
        const n = pose('Idle', 0), nh = get(n, cfg.arms[c.side][2]), nw = get(n, cfg.weapon);
        const det = nw.a * nw.d - nw.b * nw.c, dx = nh.worldX - nw.worldX, dy = nh.worldY - nw.worldY;
        nativeGrip = { local: [(nw.d * dx - nw.b * dy) / det, (-nw.c * dx + nw.a * dy) / det], rel: ang(nw) - ang(nh) };
      }
      rotate(sk, h, c.weapon - nativeGrip.rel - ang(h));
      rotate(sk, w, c.weapon - ang(w));
      const g = nativeGrip.local;
      move(sk, w, h.worldX - (w.worldX + w.a * g[0] + w.b * g[1]), h.worldY - (w.worldY + w.c * g[0] + w.d * g[1]));
    } else {
      if (!under(w, a)) move(sk, w, h.worldX - h0[0], h.worldY - h0[1]);
      rotate(sk, w, c.weapon - ang(w), [h.worldX, h.worldY]);
    }
    if (c.slide) move(sk, w, Math.cos(c.weapon / D) * c.slide, Math.sin(c.weapon / D) * c.slide);
    if (c.front) {
      const ws = sk.drawOrder.filter(x => under(x.bone, w));
      sk.drawOrder = sk.drawOrder.filter(x => !ws.includes(x));
      sk.drawOrder.splice(sk.drawOrder.findIndex(x => x.data.name === c.front), 0, ...ws);
    }
    if (c.free) {
      const side = c.side === 'L' ? 'R' : 'L', [fa, fb, fc] = cfg.arms[side].map(n => get(sk, n)), k = fwd(side);
      const upper = -90 + f * (c.free.base ?? 0) + f * c.free.amp * k;
      aim(sk, fa, fb, upper); aim(sk, fb, fc, upper + f * (c.free.elbow + (c.free.elbowAmp || 0) * Math.max(0, k)));
    }
  }

  function frame(i) {
    if (cfg.keys?.[i]?.from) return deltaFrame(i, cfg.keys[i]);
    if (cfg.keys?.[i]?.view === 'B') return backFrame(i, cfg.keys[i]);
    // sample：直接按时间采样现成的 Spine 动画（如 Codex 交来的候选动画），只做像素化
    // retarget：把本体动画的骨骼局部动作转到替身骨骼（名字带 2 后缀）上，只显示替身部件（归溟替身，doll_retarget.js）
    if (cfg.retarget) { const R = cfg.retarget; return finish(require('./doll_retarget.js').retarget(pose, data, R.anim, R.times[i], R.base || ['Idle', 0], R.doll || ['Idle_B', 0.3]), [{ t: R.times[i] }]); }
    // sample.anims：逐帧换轨（终结技一条横跨掷出 / 冲锋 / 落地几条原作轨）；sample.hide：逐帧按槽名前缀隐藏（离手的锚由游戏特效画）
    if (cfg.sample && cfg.mode !== 'move_attack') {
      const an = cfg.sample.anims?.[i] || cfg.sample.anim, sk = pose(an, cfg.sample.times[i]);
      if (cfg.sample.flatten != null) flatten(sk);
      if (cfg.sample.carry) carry(sk, i);
      // sample.pinX：该帧把髋骨水平拉回待机位置（原作冲锋轨自带根位移，游戏里位移由代码做）
      if (cfg.sample.pinX?.[i]) { const dx = get(base, cfg.body.hip).worldX - get(sk, cfg.body.hip).worldX; for (const b of sk.bones) b.worldX += dx; }
      const hp = cfg.sample.hide?.[i];
      if (hp) for (const s of sk.slots) if (hp.some(x => s.data.name.startsWith(x))) s.attachment = null;
      return finish(sk, [{ anim: an, t: cfg.sample.times[i] }]);
    }
    // base：起始姿势（缺省原生 Idle t=0；如安洁莉娜浮空移动用 Skill2_Loop 举杖姿势）
    const MA = cfg.mode === 'move_attack';
    if (SAVED) { cfg.legs = SAVED.legs; cfg.body = SAVED.body; SAVED = null; BACKV = false; }
    const sk = MA ? (cfg.poses ? posedFrame(i, cfg.poses[i], true) : pose(cfg.sample.anim, cfg.sample.times[i])) : pose(cfg.base?.anim || 'Idle', cfg.base?.t || 0), f = P.facing, phi = i / 8 * 2 * Math.PI;
    if (MA && bottom(sk, 'L') === Infinity && bottom(sk, 'R') === Infinity) {
      const bk = n => n.replace(/^F_/, 'B_');
      if (sk.findBone(bk(cfg.legs.L[0])) && sk.findBone(bk(cfg.body.hip))) {
        SAVED = { legs: cfg.legs, body: cfg.body };
        cfg.legs = { L: cfg.legs.L.map(bk), R: cfg.legs.R.map(bk) }; cfg.body = Object.assign({}, cfg.body, { hip: bk(cfg.body.hip), head: cfg.body.head && bk(cfg.body.head) });
        BACKV = true;
      }
    }
    const hip = get(sk, cfg.body.hip);
    if (cfg.mode === 'float') return floatFrame(sk, i, phi);
    if (cfg.poses && !MA) return posedFrame(i, cfg.poses[i]);
    if (cfg.keys) return keyedFrame(sk, i, cfg.keys[i], phi);
    // 1) 躯干：前倾 + 起伏；胸再前倾一点，头部回正一部分（保持脸可读）
    // crouch：整体压低髋（腿长单位），支撑腿膝盖随之更弯
    if (MA) { move(sk, hip, 0, (get(base, cfg.body.hip).worldY - hip.worldY) * (P.hipKeep ?? 0.5) + BOB[i % 8] * L * P.bob); const ml = P.maLean ?? P.lean * 0.7; rotate(sk, hip, -f * ml); if (cfg.body.head) rotate(sk, get(sk, cfg.body.head), f * ml * (P.maHeadKeep ?? 0.5)); }
    else { move(sk, hip, 0, BOB[i % 8] * L * P.bob - (P.crouch || 0) * L);
    rotate(sk, hip, -f * P.lean); }
    // carry：不挂在身体骨链上、但该跟着身体走的部件（维什戴尔四件浮游武器挂在 Front 下）——随起伏 / 前倾绕髋转，
    // 再按配置抬起 / 后收 / 转角，[dx, dy, 度] 像素单位（@2x），带一点滞后摆动
    for (const [n, off] of Object.entries(MA ? (cfg.maCarry || {}) : (cfg.carry || {}))) {   // maCarry：移动攻击 / 技能跑动里也带着浮游部件走（维什戴尔 S2 跑动，武器别挡腿）
      const b = get(sk, n); move(sk, b, 0, BOB[i % 8] * L * P.bob - (P.crouch || 0) * L); rotate(sk, b, -f * P.lean * (P.carryLean ?? 1), [hip.worldX, hip.worldY]);
      move(sk, b, f * (off[0] || 0) / SCALE, (off[1] || 0) / SCALE + (off[3] || 1.5) / SCALE * Math.sin(2 * phi - 1.2));
      if (off[2]) rotate(sk, b, f * off[2]);
    }
    if (!MA && cfg.body.chest) rotate(sk, get(sk, cfg.body.chest), -f * (P.chestLean + 1.5 * Math.cos(2 * phi)));
    if (!MA && cfg.body.head) rotate(sk, get(sk, cfg.body.head), f * (P.lean + P.chestLean) * P.headKeep + 1.5 * Math.sin(2 * phi - 0.6));
    // 2) 腿：按相位放脚踝，支撑相把鞋底贴地
    const contacts = runLegs(sk, i, f);
    // legDepth：按脚踝前后排两腿层序——靠后的腿整条放到靠前那条腿的最底层部件之前（靴筒翻边不压到另一条小腿上）
    if (cfg.legDepth && !(cfg.swingTop === 'back' && contacts.some(c => c.phase === 4 || c.phase === 5))) {
      const slotsOf = side => { const root = get(sk, cfg.legs[side][0]); return sk.drawOrder.filter(sl => { for (let p = sl.bone; p; p = p.parent) if (p === root) return true; return false; }); };
      const ax = side => f * get(sk, cfg.legs[side][2]).worldX;
      const [back, front] = ax('L') < ax('R') ? ['L', 'R'] : ['R', 'L'];
      const bs = slotsOf(back), fs = slotsOf(front);
      if (bs.length && fs.length) {
        const rest = sk.drawOrder.filter(sl => !bs.includes(sl)), at = rest.indexOf(fs[0]);
        sk.drawOrder = rest.slice(0, at).concat(bs, rest.slice(at));
      }
    }
    const fol = followStart(sk);
    if (!MA) arms(sk, i, phi);
    followEnd(sk, fol);
    secondary(sk, phi);
    return finish(sk, contacts);
  }

  // follow：[[随动骨, 目标骨]]——原作用变换约束把道具挂在手上（艾丽妮提灯、流明提包），世界空间改手臂后约束不会重算，这里按目标的位移和转角整枝带过去
  function followStart(sk) { return (cfg.follow || []).map(([b, t, mode]) => { const tb = get(sk, t); return { b, t, hang: mode === 'hang', x: tb.worldX, y: tb.worldY, r: ang(tb) }; }); }
  function followEnd(sk, fol) {
    for (const f of fol) { const b = get(sk, f.b), t = get(sk, f.t); move(sk, b, t.worldX - f.x, t.worldY - f.y); if (!f.hang) rotate(sk, b, ang(t) - f.r, [t.worldX, t.worldY]); }
  }

  // 姿势关键帧（新动作）：每帧取一条原生动画的某一时刻（可再叠第二条动画按比例混合），再在骨骼局部量上加转角 / 位移 / 缩放，
  // 最后 updateWorldTransform（IK、变换约束照常生效，道具跟手）。rot / x / y / sx 均为相对原值的增量；单位：度 / 骨骼局部单位
  // raw：只返回摆好的骨架（move_attack 模式拿它当上半身底稿，再接跑步腿；10-24 塞雷娅跑动拳击）
  function posedFrame(i, k, raw) {
    const sk = new sp.Skeleton(data); sk.setToSetupPose();
    const apply = (name, t, alpha, first) => {
      const a = data.findAnimation(name); if (!a) throw Error('缺动画 ' + name);
      if (sp.MixBlend) a.apply(sk, 0, t, false, null, alpha, first ? sp.MixBlend.setup : sp.MixBlend.replace, sp.MixDirection.mixIn);
      else a.apply(sk, 0, t, false, null, alpha, first, false);
    };
    apply(k.anim || 'Idle', k.t || 0, 1, true);
    if (k.mix) apply(k.mix.anim, k.mix.t || 0, k.mix.alpha ?? 0.5, false);
    // take：只从另一条动画的某一时刻抄这些骨（含子骨）的局部量，其余（表情、附件）保留底稿，如流明举伞瞄准时眼睛仍睁着
    for (const tk of [].concat(k.take || [])) {
      const o = new sp.Skeleton(data); o.setToSetupPose();
      const a = data.findAnimation(tk.anim);
      if (sp.MixBlend) a.apply(o, 0, tk.t || 0, false, null, 1, sp.MixBlend.setup, sp.MixDirection.mixIn); else a.apply(o, 0, tk.t || 0, false, null, 1, true, false);
      const roots = tk.bones.map(n => o.findBone(n));
      for (const b of o.bones) {
        if (!roots.some(r => { for (let p = b; p; p = p.parent) if (p === r) return true; return false; })) continue;
        const d = sk.findBone(b.data.name); d.x = b.x; d.y = b.y; d.rotation = b.rotation; d.scaleX = b.scaleX; d.scaleY = b.scaleY; d.shearX = b.shearX; d.shearY = b.shearY;
      }
      for (const n of tk.slots || []) { const so = o.findSlot(n), sd = sk.findSlot(n); sd.setAttachment(so.getAttachment()); }
    }
    // copy：把一根骨的局部位置 / 转角抄给同父的另一根（换用原作的另一套手部附件时，让它落在原来的手位上）
    for (const [n, from] of Object.entries(k.copy || {})) { const b = get(sk, n), f = get(sk, from); b.x = f.x; b.y = f.y; b.rotation = f.rotation; }
    for (const [n, v] of Object.entries(k.rot || {})) get(sk, n).rotation += v;
    for (const [n, v] of Object.entries(k.pos || {})) { const b = get(sk, n); b.x += v[0]; b.y += v[1]; }
    for (const [n, v] of Object.entries(k.scale || {})) { const b = get(sk, n); b.scaleX *= v[0]; b.scaleY *= v[1] ?? v[0]; }
    for (const [n, v] of Object.entries(k.attach || {})) { const s = sk.findSlot(n); s.setAttachment(v ? sk.getAttachment(s.data.index, v) : null); }
    // opaque：原作这段把正面部件淡出（艾丽妮 S3 连射期间整个人透明），强制不透明看姿势
    if (k.opaque) for (const s of sk.slots) if (!s.data.name.startsWith('B_')) s.color.a = 1;
    sk.updateWorldTransform();
    // pin：这些骨（含子骨）回到 Idle t=0 的世界位置（流明举灯时提包仍挂在髋侧）
    if (k.pin) { const ref = pose('Idle', 0); for (const n of k.pin) { const b = get(sk, n), r = get(ref, n); rotate(sk, b, ang(r) - ang(b)); move(sk, b, r.worldX - b.worldX, r.worldY - b.worldY); } }
    // carry：{骨: [手骨, dx, dy]} 把道具（含子骨）挂到手上，保持竖直下垂（dx / dy 为世界单位偏移）
    // tip：{骨: [槽, 手骨, dx, dy]} 挂到某附件离手最远的顶点（流明把提灯挂在伞尖）
    for (const [n, [sl, h, dx, dy]] of Object.entries(k.tip || {})) {
      const b = get(sk, n), hb = get(sk, h), s = sk.findSlot(sl), v = verts(sp, s, s.getAttachment()); let best = null, far = -1;
      // 有 tipDir 时取沿该方向最远的顶点（伞尖朝前上），否则取离手最远的顶点
      const td = k.tipDir;
      for (let q = 0; q < v.length; q += 2) { const d = td ? (v[q] - hb.worldX) * td[0] + (v[q + 1] - hb.worldY) * td[1] : Math.hypot(v[q] - hb.worldX, v[q + 1] - hb.worldY); if (d > far) { far = d; best = [v[q], v[q + 1]]; } }
      rotate(sk, b, (k.carryAngle ?? -90) - ang(b)); move(sk, b, best[0] + (dx || 0) - b.worldX, best[1] + (dy || 0) - b.worldY);
    }
    for (const [n, [h, dx, dy, an]] of Object.entries(k.carry || {})) { const b = get(sk, n), hb = get(sk, h); rotate(sk, b, (an ?? k.carryAngle ?? -90) - ang(b)); move(sk, b, hb.worldX + (dx || 0) - b.worldX, hb.worldY + (dy || 0) - b.worldY); }
    if (k.lift) move(sk, get(sk, cfg.body.root || 'Front'), (k.dx || 0), k.lift);
    else if (k.dx) move(sk, get(sk, cfg.body.root || 'Front'), k.dx, 0);
    for (const n of k.top || []) { const t = sk.findSlot(n); sk.drawOrder = sk.drawOrder.filter(x => x !== t); sk.drawOrder.push(t); }
    for (const [n, before] of k.order || []) {
      const s = sk.findSlot(n); sk.drawOrder = sk.drawOrder.filter(x => x !== s);
      sk.drawOrder.splice(sk.drawOrder.findIndex(x => x.data.name === before), 0, s);
    }
    for (const n of k.hide || []) { const s = sk.findSlot(n); if (s) s.attachment = null; }
    // only：只画这些槽（量道具像素位置用）
    if (k.only || process.env.ONLY) { const keep = k.only || process.env.ONLY.split(','); for (const s of sk.slots) if (!keep.includes(s.data.name)) s.attachment = null; }
    if (raw) return sk;
    // mark：记录某骨在 @2x 画布上的像素位置（核对道具 / 炮口与游戏出手点）
    const marks = {}; for (const n of k.mark || []) { const b = get(sk, n); marks[n] = [+(ANCHOR[0] + b.worldX * SCALE).toFixed(1), +(ANCHOR[1] - b.worldY * SCALE).toFixed(1)]; }
    return finish(sk, [{ pose: k.anim || 'Idle', t: k.t || 0, marks }]);
  }

  // 关键帧动作（跳劈等）：每帧给髋位移、前倾、两脚（着地 = 贴地放脚；空中 = 相对髋的脚踝位置）、两臂绝对角、武器角
  // 位移单位：腿长 L；角度：世界角（度），朝向 +x 时 0 = 向前、90 = 向上、-90 = 向下
  function runLegs(sk, i, f) {
    const contacts = [];
    for (const side of ['L', 'R']) {
      const k = (i + (side === cfg.leadLeg ? 0 : 4)) % 8, g = GAIT[k];
      const [a, b, c] = cfg.legs[side].map(n => get(sk, n)), info = legInfo[side];
      const tx = a.worldX + f * (cfg.gaitX?.[k] ?? g[0]) * L * P.stride;   // gaitX：按相位覆盖脚踝前后位置
      const setFoot = () => rotate(sk, c, info.foot + f * g[2] * (P.footRot ?? 1) - ang(c));   // footRot：脚掌转角比例（靴筒挂在小腿上的干员转多了会脱开）
      // gaitLiftPx：按像素指定各相位离地高度（对齐已批准的旧条），否则用步态表 × lift
      const liftPx0 = (cfg.gaitLiftPx === undefined ? LIFT_PX : cfg.gaitLiftPx || [])[k], liftPx = liftPx0 == null ? liftPx0 : liftPx0 * (cfg.scaleMul || 1);
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
      // swingTop：抬起的腿（相位 4–7）整条移到最前绘制，免得高抬的膝 / 鞋被衣摆、武器挡住（维什戴尔）
      if (cfg.swingTop && !stance && (cfg.swingTop !== 'back' || k <= 5)) {   // 'back' 只在后踢相位（4–5）压底
        const root = get(sk, cfg.legs[side][0]);
        const mine = sk.drawOrder.filter(sl => { for (let p = sl.bone; p; p = p.parent) if (p === root) return true; return false; });
        sk.drawOrder = cfg.swingTop === 'back' ? mine.concat(sk.drawOrder.filter(sl => !mine.includes(sl))) : sk.drawOrder.filter(sl => !mine.includes(sl)).concat(mine);   // 'back' = 抬起的腿压到最底层（后踢在身后）
      }
    }
    return contacts;
  }

  function keyedFrame(sk, i, k, phi) {
    const f = P.facing, hip = get(sk, cfg.body.hip);
    const RUN = cfg.runLegs;   // runLegs：上半身按关键帧，腿走跑步步态（移动攻击，10-23 斯卡蒂前向斩）
    move(sk, hip, f * (k.hipX || 0) * L, (k.hipY || 0) * L + (RUN ? BOB[i % 8] * L * P.bob : 0));
    rotate(sk, hip, -f * (k.lean || 0));
    if (cfg.body.chest && k.chest) rotate(sk, get(sk, cfg.body.chest), -f * k.chest);
    if (cfg.body.head) rotate(sk, get(sk, cfg.body.head), f * (k.lean || 0) * (k.headKeep ?? P.headKeep) + (k.head || 0));
    const contacts = RUN ? runLegs(sk, i, f) : [];
    for (const side of RUN ? [] : ['L', 'R']) {
      const [a, b, c] = cfg.legs[side].map(n => get(sk, n)), info = legInfo[side], leg = k.legs[side];
      const setFoot = () => rotate(sk, c, info.foot + f * (leg.foot || 0) - ang(c));
      if (leg.ground) {
        const tx = a.worldX + f * leg.x * L; let ty = ground + info.ankleAbove;
        ik(sk, a, b, c, [tx, ty], f); setFoot();
        for (let n = 0; n < 6; n++) { const err = bottom(sk, side) - ground; if (Math.abs(err) < 0.05) break; ty -= err; ik(sk, a, b, c, [tx, ty], f); setFoot(); }
      } else { ik(sk, a, b, c, [a.worldX + f * leg.x * L, a.worldY + leg.y * L], f); setFoot(); }
      contacts.push({ side, ground: !!leg.ground, gap: +(bottom(sk, side) - ground).toFixed(2) });
    }
    for (const side of ['L', 'R']) {
      const [a, b, c] = cfg.arms[side].map(n => get(sk, n)), arm = k.arms[side];
      const up = f > 0 ? arm[0] : 180 - arm[0], fore = f > 0 ? arm[1] : 180 - arm[1];
      aim(sk, a, b, up); aim(sk, b, c, fore);
    }
    if (cfg.weapon && hold) {
      const w = get(sk, cfg.weapon), grip = get(sk, cfg.arms[hold][2]), wa = f > 0 ? k.weapon : 180 - k.weapon;
      rotate(sk, w, wa - ang(w), [grip.worldX, grip.worldY]);
      const g = cfg.grip || cfg.holdPose?.grip;
      if (g) move(sk, w, grip.worldX - (w.worldX + w.a * g[0] + w.b * g[1]), grip.worldY - (w.worldY + w.c * g[0] + w.d * g[1]));
      foreshorten(sk, w, grip, k.weaponScale);
    }
    secondary(sk, phi);
    // front：武器挥到身前时改到持武器手之前绘制（手指仍压在握把上）
    if (k.front && cfg.weaponSlot) {
      const ws = sk.findSlot(cfg.weaponSlot), hs = sk.findSlot(cfg.handSlot);
      sk.drawOrder = sk.drawOrder.filter(x => x !== ws); sk.drawOrder.splice(sk.drawOrder.indexOf(hs), 0, ws);
    }
    // top：这些槽按给定顺序移到最前（持剑手靠近大头时，原层序会被头 / 帽子挡住）
    for (const n of k.top || []) { const t = sk.findSlot(n); sk.drawOrder = sk.drawOrder.filter(x => x !== t); sk.drawOrder.push(t); }
    return finish(sk, contacts);
  }

  // 增量关键帧（10-20，德克萨斯 / 星熊）：以原作动画某时刻的姿势为底稿（from: [动画, 秒]），只在上面做增量——
  //   hipX / hipY（腿长单位）、lean（前倾度数）、chest / head（度）、legs（同 keyedFrame：着地放脚 / 空中相对髋）、
  //   arms {侧: [上臂, 前臂]}（世界角，同 keyedFrame）、armRot {侧: [上臂, 前臂, 手]}（相对转角，度，+ = 向前上挥）、
  //   rot {骨: 度}（相对转角，+ = 逆时针，朝右时即向后仰）、weapon（武器世界角，同 keyedFrame）/ weaponRot（绕握点相对转角）/ weaponScale（沿剑身压短，透视）、plant（整体平移让最低的鞋底贴地）、
  //   hide [槽]、top [槽]、flip（整帧镜像）、sec（加次级摆动）。
  //   cfg.attach {武器骨: 跟随骨}：武器不是手的子骨（德克萨斯的剑挂在髋上、由约束跟手）时，按底稿里的相对变换重新贴到跟随骨上
  const affine = b => [b.a, b.b, b.c, b.d, b.worldX, b.worldY];
  const mul = (M, N) => [M[0] * N[0] + M[1] * N[2], M[0] * N[1] + M[1] * N[3], M[2] * N[0] + M[3] * N[2], M[2] * N[1] + M[3] * N[3],
    M[0] * N[4] + M[1] * N[5] + M[4], M[2] * N[4] + M[3] * N[5] + M[5]];
  const inv = M => { const d = M[0] * M[3] - M[1] * M[2], a = M[3] / d, b = -M[1] / d, c = -M[2] / d, e = M[0] / d;
    return [a, b, c, e, -(a * M[4] + b * M[5]), -(c * M[4] + e * M[5])]; };
  function applyAffine(sk, root, D) {
    for (const p of branch(sk, root)) { const n = mul(D, affine(p)); [p.a, p.b, p.c, p.d, p.worldX, p.worldY] = n; }
  }
  // cfg.attach 在跑步 / 关键帧模式下按待机 t=0 的相对变换贴回
  const relBase = {};
  for (const [w, t] of Object.entries(cfg.attach || {})) relBase[w] = mul(inv(affine(get(base, t))), affine(get(base, w)));
  function reattach(sk) {
    for (const [w, t] of Object.entries(cfg.attach || {})) { const W = get(sk, w); applyAffine(sk, W, mul(mul(affine(get(sk, t)), relBase[w]), inv(affine(W)))); }
  }
  function deltaFrame(i, k) {
    const sk = pose(k.from[0], k.from[1]), f = P.facing, hip = get(sk, cfg.body.hip);
    const rel = {};
    for (const [w, t] of Object.entries(cfg.attach || {})) rel[w] = mul(inv(affine(get(sk, t))), affine(get(sk, w)));
    if (k.hipX || k.hipY) move(sk, hip, f * (k.hipX || 0) * L, (k.hipY || 0) * L);
    if (k.lean) rotate(sk, hip, -f * k.lean);
    if (k.chest && cfg.body.chest) rotate(sk, get(sk, cfg.body.chest), -f * k.chest);
    if (k.head && cfg.body.head) rotate(sk, get(sk, cfg.body.head), f * k.head);
    for (const [n, d] of Object.entries(k.rot || {})) rotate(sk, get(sk, n), f * d);
    const contacts = [];
    for (const side of ['L', 'R']) {
      const leg = k.legs?.[side];
      if (!leg) continue;
      const [a, b, c] = cfg.legs[side].map(n => get(sk, n)), info = legInfo[side];
      const setFoot = () => rotate(sk, c, info.foot + f * (leg.foot || 0) - ang(c));
      if (leg.ground) {
        const tx = a.worldX + f * leg.x * L; let ty = ground + info.ankleAbove;
        ik(sk, a, b, c, [tx, ty], f); setFoot();
        for (let n = 0; n < 6; n++) { const err = bottom(sk, side) - ground; if (Math.abs(err) < 0.05) break; ty -= err; ik(sk, a, b, c, [tx, ty], f); setFoot(); }
      } else { ik(sk, a, b, c, [a.worldX + f * leg.x * L, a.worldY + leg.y * L], f); setFoot(); }
      contacts.push({ side, ground: !!leg.ground, gap: +(bottom(sk, side) - ground).toFixed(2) });
    }
    for (const side of ['L', 'R']) {
      const [a, b, c] = cfg.arms[side].map(n => get(sk, n));
      const arm = k.arms?.[side];
      if (arm) { aim(sk, a, b, f > 0 ? arm[0] : 180 - arm[0]); aim(sk, b, c, f > 0 ? arm[1] : 180 - arm[1]); }
      const r = k.armRot?.[side];
      if (r) { rotate(sk, a, f * (r[0] || 0)); rotate(sk, b, f * (r[1] || 0)); if (r[2]) rotate(sk, c, f * r[2]); }
    }
    for (const [w, t] of Object.entries(cfg.attach || {})) {
      const W = get(sk, w); applyAffine(sk, W, mul(mul(affine(get(sk, t)), rel[w]), inv(affine(W))));
    }
    if (k.weapon != null && cfg.weapon) { const g = get(sk, cfg.arms[hold][2]), w = get(sk, cfg.weapon); rotate(sk, w, (f > 0 ? k.weapon : 180 - k.weapon) - ang(w), [g.worldX, g.worldY]); }
    if (k.weaponRot && cfg.weapon) { const g = get(sk, cfg.arms[hold][2]); rotate(sk, get(sk, cfg.weapon), f * k.weaponRot, [g.worldX, g.worldY]); }
    if (k.weaponScale && cfg.weapon) { const g = get(sk, cfg.arms[hold][2]); foreshorten(sk, get(sk, cfg.weapon), g, k.weaponScale); }
    if (k.sec) secondary(sk, i / (cfg.keys.length) * 2 * Math.PI);
    if (k.plant) {
      const dy = ground - Math.min(bottom(sk, 'L'), bottom(sk, 'R')) + (k.lift || 0) / SCALE;
      move(sk, sk.bones[0], 0, dy);
    }
    for (const n of k.hide || []) { const s = sk.findSlot(n); if (s) s.attachment = null; }
    for (const n of k.top || []) { const t = sk.findSlot(n); sk.drawOrder = sk.drawOrder.filter(x => x !== t); sk.drawOrder.push(t); }
    return finish(sk, contacts);
  }

  // 背面视角（原作骨架自带 B_* 背面部件，Idle 里隐藏）：用 setup 姿势，只显示 B_ 槽，鞋底贴地；可转持剑臂与剑
  function backFrame(i, k) {
    const sk = new sp.Skeleton(data); sk.setToSetupPose(); sk.updateWorldTransform();
    for (const s of sk.slots) if (!s.data.name.startsWith('B_')) s.attachment = null;
    const bk = cfg.back, hip = get(sk, bk.hip);
    const bBottom = () => { let y = Infinity; for (const s of sk.slots) { const a = s.getAttachment(); if (!a || !bk.feet.includes(s.data.name)) continue; const v = verts(sp, s, a); for (let n = 1; n < v.length; n += 2) y = Math.min(y, v[n]); } return y; };
    move(sk, hip, (k.hipX || 0) * L, ground - bBottom() + (k.hipY || 0) * L);
    if (k.lean) rotate(sk, hip, k.lean);
    if (k.arm) { const [a, b, c] = bk.arm.map(n => get(sk, n)); aim(sk, a, b, k.arm[0]); aim(sk, b, c, k.arm[1]); }
    if (k.weapon != null) { const w = get(sk, bk.weapon), h = get(sk, bk.arm[2]); rotate(sk, w, k.weapon + (bk.bladeFlip ? 180 : 0) - ang(w), [h.worldX, h.worldY]); foreshorten(sk, w, h, k.weaponScale); }
    for (const n of k.top || []) { const t = sk.findSlot(n); sk.drawOrder = sk.drawOrder.filter(x => x !== t); sk.drawOrder.push(t); }
    return { sk, contacts: [{ view: 'B' }] };
  }

  // 透视缩短：把武器骨（及子骨）沿剑身方向的轴按比例压短，绕握点；表现剑指向镜头 / 远离镜头
  function foreshorten(sk, w, grip, sc) {
    if (sc == null || sc === 1) return;
    const ux = w.a, uy = w.c, n = Math.hypot(ux, uy), ex = ux / n, ey = uy / n, [gx, gy] = [grip.worldX, grip.worldY];
    // 世界空间沿剑轴的缩放矩阵 S = I + (sc-1)·e·eᵀ，作用在位置（相对握点）和骨骼基向量上
    const S = (x, y) => { const d = (x * ex + y * ey) * (sc - 1); return [x + d * ex, y + d * ey]; };
    for (const b of branch(sk, w)) {
      const [px, py] = S(b.worldX - gx, b.worldY - gy); b.worldX = gx + px; b.worldY = gy + py;
      const [a, c] = S(b.a, b.c), [bb, d] = S(b.b, b.d); b.a = a; b.c = c; b.b = bb; b.d = d;
    }
  }

  // 刀光示意：剑贴图离手最远的顶点当剑尖（像素坐标），供预览叠一道拖影，不进帧条
  function swordLine(sk, i) {
    const k = cfg.keys?.[i] || {}, back = k.view === 'B';
    if (!(back ? cfg.back?.weaponSlot : cfg.weaponSlot) || !hold) return null;
    const slot = sk.findSlot(back ? cfg.back.weaponSlot : cfg.weaponSlot), att = slot?.getAttachment();
    if (!att) return null;
    const hand = get(sk, back ? cfg.back.arm[2] : cfg.arms[hold][2]), v = verts(sp, slot, att);
    let best = null, far = -1;
    for (let n = 0; n < v.length; n += 2) { const d = Math.hypot(v[n] - hand.worldX, v[n + 1] - hand.worldY); if (d > far) { far = d; best = [v[n], v[n + 1]]; } }
    const px = p => [ANCHOR[0] + p[0] * SCALE, ANCHOR[1] - p[1] * SCALE];
    let h = px([hand.worldX, hand.worldY]), t = px(best);
    if (k.flip) { h = [SIZE - h[0], h[1]]; t = [SIZE - t[0], t[1]]; }
    return { hand: h, tip: t };
  }

  // 悬浮飘行（浊心斯卡蒂）：不踩地；身体缓慢上下浮动并前倾，两腿向后拖、交替轻摆，衣摆和头发大幅向后飘
  function floatFrame(sk, i, phi) {
    const f = P.facing, hip = get(sk, cfg.body.hip);
    move(sk, hip, 0, ((P.floatLift ?? 0) + (P.floatBob ?? 2) * Math.sin(phi)) / SCALE);   // floatLift：整体离地（@2x 像素）
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
        // relOffset：在原姿势上先整体抬臂 [上臂, 前臂]（度，+ = 朝面向方向抬），如流明提包离地
        const ro = cfg.relOffset?.[side] || [0, 0];
        rotate(sk, a, f * ro[0] + f * (P.relAmp ?? 6) * fwd); rotate(sk, b, f * ro[1] + f * (P.relElbowAmp ?? 3) * fwd);
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
    if (cfg.attach && !(cfg.weapon && hold)) reattach(sk);   // 双持（拉普兰德两把剑挂在髋上、由约束跟手）：两只手都摆，剑各自贴回手上
    // attachRot {武器骨: 度}：贴回后再绕跟随骨（手）转，跑步时剑尖拖在身后，不插地
    for (const [w, d] of Object.entries(cfg.attachRot || {})) { const h = get(sk, cfg.attach[w]); rotate(sk, get(sk, w), P.facing * d, [h.worldX, h.worldY]); }
    if (cfg.weapon && hold) {
      reattach(sk);
      const w = get(sk, cfg.weapon), grip = get(sk, cfg.arms[hold][2]);
      rotate(sk, w, (cfg.holdPose?.weapon ?? weaponBase) - f * P.lean * P.weaponLean + P.weaponSway * Math.sin(2 * phi - 1.0) - ang(w), [grip.worldX, grip.worldY]);
      // grip：武器局部坐标里的握把点；原姿势手不在握把上时（斯卡蒂大剑立在身后），把握把点移到手上
      const g = cfg.holdPose?.grip || cfg.grip;
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
        // gravity：链根抵消身体前倾的比例（0–1），让衣摆仍大致朝下垂，不随前倾翘成水平
        const hang = depth === 0 ? f * P.lean * (rule.gravity ?? 0) : 0;
        const wave = (rule.amp ?? P.hairAmp) * Math.sin((rule.freq ?? 2) * phi - (rule.lag ?? 0.9) - 0.7 * depth);
        rotate(sk, b, down * f * drag + wave + hang);
      }
    }
  }

  function finish(sk, contacts) {
    // Approved 1x face treatment; opt-in so other density exports are unchanged.
    for (const slot of sk.slots) {
      const n = slot.data.name;
      if (cfg.noMouth && (/mouth/i.test(n) || (cfg.id === 'suzuran' && /^F_Face_(Default_g|Stun_c)$/.test(n)))) slot.attachment = null;
      if (cfg.pixelEyes && ((cfg.id === 'wisadel' && /_Eye_0[1-4]$/.test(n)) || (cfg.id === 'specter_unchained' && /_Eye_Light$/.test(n)) || (cfg.id === 'skalter' && /_Eye_[CDE]$/.test(n)))) slot.attachment = null;
    }
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
      // 入场 Start 轨里有缩到 0 / 透明 / 飞出画面很远的部件（登场光效之类）：跳过，否则读像素失败
      if (!(w > 0 && h > 0 && w < SIZE * 4 && h < SIZE * 4) || slot.color.a <= 0.004) continue;
      if (cfg.skipAdditive && slot.data.blendMode) continue;   // 入场：叠加 / 滤色的登场光效像素化后成白块，不画（特效另做）
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
      // 嘴：沿用 bz_18 mouth_sampling 的光学取样——按列覆盖率取 ≥ 18% 峰值的列（至少两格成线），每列取覆盖最高的一行，
      // 墨色按覆盖率（夹 0.30–0.65）与下层脸色混合；否则亚像素嘴二值化后只剩一个黑点或碎点
      const iris = cfg.pixelEyes && ((cfg.id==='wisadel' && /_Eye_05$/.test(slot.data.name)) || (cfg.id==='specter_unchained' && /_Eyeball$/.test(slot.data.name)) || (cfg.id==='skalter' && /_Eye_B$/.test(slot.data.name)));
      const lash = cfg.pixelEyes && ((cfg.id==='wisadel' && /_Eyelash_/.test(slot.data.name)) || (cfg.id==='specter_unchained' && /_[LR]_Eye$/.test(slot.data.name)) || (cfg.id==='skalter' && /_Eye_A$/.test(slot.data.name)));
      if ((iris || lash) && max>0) {
        // Eye cells follow each native attachment's deformed source footprint.
        // Hand-selected two-tone iris, one-row upper lid per covered column.
        for(let x=0;x<w;x++) {
          let best=-1,peak=0;
          for(let y=0;y<h;y++){const al=acc[(y*w+x)*4+3];if(al>peak){peak=al;best=y;}}
          if(peak<th)continue;
          if(lash){const q=(best*w+x)*4;const under=oc.getImageData(x0+x,y0+best,1,1).data;const wt=Math.min(.8,peak/255);for(let k=0;k<3;k++)a[q+k]=Math.round([47,36,42][k]*wt+under[k]*(1-wt));a[q+3]=255;}
          else {
            const ys=[];for(let y=0;y<h;y++)if(acc[(y*w+x)*4+3]>=th)ys.push(y);
            const top=ys[0],bottom=ys[ys.length-1];
            for(const y of ys){const q=(y*w+x)*4;let c;
              if(cfg.id==='wisadel')c=y===top&&top!==bottom?[157,65,32]:[239,157,59];
              else if(cfg.id==='specter_unchained')c=y===top&&top!==bottom?[119,36,48]:[214,89,98];
              else c=y===top&&top!==bottom?[128,29,44]:[203,53,70];
              a[q]=c[0];a[q+1]=c[1];a[q+2]=c[2];a[q+3]=255;
            }
          }
        }
      } else if (/mouth/i.test(slot.data.name) && max > 0 && x0 >= 0 && y0 >= 0 && x0 + w <= SIZE && y0 + h <= SIZE) {
        const cols = new Float64Array(w);
        for (let x = 0; x < w; x++) for (let y = 0; y < h; y++) cols[x] += acc[(y * w + x) * 4 + 3] / 255;
        const peak = Math.max(...cols); let xs = [];
        for (let x = 0; x < w; x++) if (cols[x] >= peak * 0.18) xs.push(x);
        if (xs.length < 2) { const x = cols.indexOf(peak), nb = [x - 1, x + 1].filter(n => n >= 0 && n < w); xs = [x, nb.reduce((m, n) => cols[n] > cols[m] ? n : m, nb[0])].sort((p, q) => p - q); }
        const under = oc.getImageData(x0, y0, w, h).data;
        for (const x of xs) {
          let y = 0; for (let yy = 1; yy < h; yy++) if (acc[(yy * w + x) * 4 + 3] > acc[(y * w + x) * 4 + 3]) y = yy;
          const q = (y * w + x) * 4, wt = Math.min(0.65, Math.max(0.30, acc[q + 3] / 255));
          for (let k = 0; k < 3; k++) a[q + k] = Math.round(acc[q + k] * wt + under[q + k] * (1 - wt));
          a[q + 3] = 255;
        }
      } else
      for (let q = 0; q < acc.length; q += 4) {
        if (acc[q + 3] < th) continue;
        const c = nearest(palette, acc[q], acc[q + 1], acc[q + 2]);
        a[q] = c[0]; a[q + 1] = c[1]; a[q + 2] = c[2]; a[q + 3] = 255;
        const px = x0 + (q / 4) % w, py = y0 + Math.floor(q / 4 / w);
        if (px < 2 || py < 2 || px >= SIZE - 2 || py >= SIZE - 2) problems.push(slot.data.name);
        if (process.env.BELOW && py >= 120 + PAD) problems.push('below:' + slot.data.name);
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

  // --clean：先删旧的逐帧图（帧数变少时不留上一版的尾帧）
  if (process.argv.includes('--clean') && fs.existsSync(OUT)) for (const f of fs.readdirSync(OUT)) if (/^(hires_)?f\d\d\.png$/.test(f)) fs.unlinkSync(path.join(OUT, f));
  fs.mkdirSync(OUT, { recursive: true });
  const report = [];
  const frames = [];
  const N = cfg.poses?.length || cfg.keys?.length || cfg.sample?.times.length || cfg.retarget?.times.length || 8, lines = [];
  for (let i = 0; i < N; i++) {
    const { sk, contacts } = frame(i), { canvas: px, clipped } = pixelize(sk);
    // flip：回旋类动作转到背面的帧整帧水平镜像（原点在画布中线，镜像后脚下位置不变）
    let canvas = px;
    if (cfg.keys?.[i]?.flip) { canvas = createCanvas(SIZE, SIZE); const m = canvas.getContext('2d'); m.translate(SIZE, 0); m.scale(-1, 1); m.drawImage(px, 0, 0); }
    fs.writeFileSync(path.join(OUT, `f${String(i).padStart(2, '0')}.png`), canvas.toBuffer('image/png'));
    frames.push(sk);
    if (cfg.keys) { lines.push(swordLine(sk, i)); if (process.env.SWORD_DEBUG) console.log(i, JSON.stringify(lines[i])); }
    report.push({ frame: i, contacts, clipped_near_edge: clipped });
  }
  const idle = pixelize(base).canvas;
  fs.writeFileSync(path.join(OUT, 'idle_t0.png'), idle.toBuffer('image/png'));
  // 头骨原点在待机首帧（idle_t0.png）里的像素位置：1 倍头像素替换（docs/128 §3）的对位锚点
  const hb = cfg.body?.head && base.findBone(cfg.body.head);
  const idleHead = hb ? [+(ANCHOR[0] + hb.worldX * SCALE).toFixed(2), +(ANCHOR[1] - hb.worldY * SCALE).toFixed(2)] : null;
  fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify({ id: cfg.id, scale: SCALE, anchor: ANCHOR, idle_head_px: idleHead, params: P, gait: GAIT, bob: BOB, frames: report }, null, 1));
  if (arg('--editor-ops')) writeEditorOps(frames, arg('--editor-ops'));
  if (N === 8) writePack(frames); else console.log('帧数', N, '≠ 8：不写编辑台数据包');
  // 透视缩短：把武器骨（及子骨）沿剑身方向的轴按比例压短，绕握点；表现剑指向镜头 / 远离镜头
  function foreshorten(sk, w, grip, sc) {
    if (sc == null || sc === 1) return;
    const ux = w.a, uy = w.c, n = Math.hypot(ux, uy), ex = ux / n, ey = uy / n, [gx, gy] = [grip.worldX, grip.worldY];
    // 世界空间沿剑轴的缩放矩阵 S = I + (sc-1)·e·eᵀ，作用在位置（相对握点）和骨骼基向量上
    const S = (x, y) => { const d = (x * ex + y * ey) * (sc - 1); return [x + d * ex, y + d * ey]; };
    for (const b of branch(sk, w)) {
      const [px, py] = S(b.worldX - gx, b.worldY - gy); b.worldX = gx + px; b.worldY = gy + py;
      const [a, c] = S(b.a, b.c), [bb, d] = S(b.b, b.d); b.a = a; b.c = c; b.b = bb; b.d = d;
    }
  }

  // 刀光示意帧：smear 帧在角色身后填一道上一帧剑身到这一帧剑身之间的浅色扇面
  if (cfg.keys && cfg.keys.some(k => k.smear)) {
    const fxDir = path.join(path.dirname(OUT), 'fx_preview'); fs.mkdirSync(fxDir, { recursive: true });
    const { loadImage } = require('@napi-rs/canvas');
    for (let i = 0; i < N; i++) {
      const cv = createCanvas(SIZE, SIZE), c = cv.getContext('2d'), a = lines[i], b = lines[(i + N - 1) % N];
      if (cfg.keys[i].smear && a && b) {
        c.fillStyle = 'rgb(214,236,246)'; c.beginPath();
        // 上一帧剑身到这一帧剑身之间的带状拖影（四边形）
        const r = q => [Math.round(q[0]), Math.round(q[1])];
        c.moveTo(...r(b.hand)); c.lineTo(...r(b.tip)); c.lineTo(...r(a.tip)); c.lineTo(...r(a.hand)); c.closePath(); c.fill();
      }
      c.drawImage(await loadImage(fs.readFileSync(path.join(OUT, `f${String(i).padStart(2, '0')}.png`))), 0, 0);
      fs.writeFileSync(path.join(fxDir, `f${String(i).padStart(2, '0')}.png`), cv.toBuffer('image/png'));
    }
  }
  // --hires：原生网格 4 倍直出（不像素化），用来检查部件接缝和遮挡
  if (process.argv.includes('--hires')) for (let i = 0; i < N; i++) {
    const cv = createCanvas(SIZE * 4, SIZE * 4), c = cv.getContext('2d');
    c.translate(ANCHOR[0] * 4, ANCHOR[1] * 4); c.scale(SCALE * 4, -SCALE * 4);
    const r = new sp.canvas.SkeletonRenderer(c); r.triangleRendering = true; r.draw(frames[i]);
    fs.writeFileSync(path.join(OUT, `hires_f${String(i).padStart(2, '0')}.png`), cv.toBuffer('image/png'));
  }
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
      skeleton: src.json || src.skel, atlas: src.atlas, fps: cfg.fps || 40 / 3, scale: SCALE, palette,
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
  const dir = cfg.pack ? null : `${BZ}/${cfg.id}/parts`;
  // cfg.pack.palette_png：调色板取自 Codex 交付的帧条（风格对齐它的配色）
  for (const f of cfg.pack ? [path.resolve(cfg.pack.palette_png)] : fs.readdirSync(dir).map(n => path.join(dir, n))) {
    const img = await loadImage(fs.readFileSync(f));
    const c = createCanvas(img.width, img.height), x = c.getContext('2d'); x.drawImage(img, 0, 0);
    const d = x.getImageData(0, 0, img.width, img.height).data;
    for (let i = 0; i < d.length; i += 4) if (d[i + 3] > 0) set.set((d[i] << 16) | (d[i + 1] << 8) | d[i + 2], [d[i], d[i + 1], d[i + 2]]);
  }
  // paletteAdd：部件包调色板缺的原作色（乌尔比安锚上铜轮只在技能轨里露出，部件包里没有铜色，像素化后发灰）
  for (const c of cfg.paletteAdd || []) set.set((c[0] << 16) | (c[1] << 8) | c[2], c);
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
