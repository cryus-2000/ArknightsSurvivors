"""prefabs.json → 精简文字摘要（每个预制体每个启用粒子一行）。"""
import json, sys
d = json.load(open('F:/sami_enemy_fx_ref/prefabs/prefabs.json', encoding='utf-8'))
flt = sys.argv[1] if len(sys.argv) > 1 else ''
RM = {0: 'bill', 1: 'stretch', 2: 'hbill', 3: 'vbill', 4: 'mesh'}
SH = {0: 'sphere', 4: 'cone', 5: 'box', 10: 'circle', 12: 'edge', 13: 'mesh', 16: 'donut', 17: 'rect'}


def blend(m):
    f = m.get('f', {})
    s, dd = f.get('_SrcBlend'), f.get('_DstBlend')
    if dd == 1.0:
        return 'add'
    if dd == 10.0:
        return 'alpha'
    if s == 1.0 and dd == 0.0:
        return 'opaque?'
    return '%s/%s' % (s, dd)


def gtxt(g):
    if not g:
        return ''
    if 'col' in g:
        return 'c%s' % g['col']
    if 'grad' in g and g['grad']:
        gg = g['grad']
        return 'g[%s | a%s]' % (' '.join('%s:%s' % (t, c) for t, c in gg['c']), [a for _, a in gg['a']])
    if 'between' in g:
        return 'rnd%s' % g['between']
    return str(g)[:80]


out = []
for name in sorted(d):
    if flt and flt not in name:
        continue
    out.append('## ' + name)
    for n in d[name]:
        if 'err' in n:
            out.append('  ERR ' + n['err'])
            continue
        if 'ps' not in n and 'mesh_mats' not in n:
            continue
        mats = n.get('mats') or n.get('mesh_mats') or []
        m = mats[0] if mats else {}
        tex = ','.join(str(v) for v in m.get('tex', {}).values())
        line = '  %s%s [%s %s %s]' % ('  ' * n['d'], n['n'], tex, blend(m) if m else '', RM.get(n.get('rmode'), n.get('rmode', '')) if 'ps' in n else 'MESH:' + str(n.get('mesh')))
        if not n.get('active'):
            line += ' (off)'
        p = n.get('ps')
        if p:
            line += ' dly%s life%s spd%s size%s' % (p['delay'], p['life'], p['spd'], p['size'])
            if 'bursts' in p:
                line += ' burst%s' % p['bursts']
            if p.get('rate'):
                line += ' rate%s' % p['rate']
            if 'shape' in p:
                s = p['shape']
                line += ' shape:%s r%s a%s' % (SH.get(s['type'], s['type']), s['r'], s['angle'])
            line += ' col:' + gtxt(p.get('color'))
            if 'color_ol' in p:
                line += ' ol:' + gtxt(p['color_ol'])
            if 'size_ol' in p:
                line += ' sz_ol:%s' % (p['size_ol'] if not isinstance(p['size_ol'], dict) else [v for _, v in p['size_ol']['curve']][:5])
            if 'sheet' in p:
                line += ' sheet%s' % p['sheet']
            if p.get('grav'):
                line += ' grav%s' % p['grav']
            if n.get('scl') != [1.0, 1.0, 1.0]:
                line += ' scl%s' % n['scl']
            if n.get('lscale') and n.get('rmode') == 1:
                line += ' len%s' % n['lscale']
        mc = m.get('col', {}).get('_TintColor') or m.get('col', {}).get('_Color')
        if mc and mc != [1.0, 1.0, 1.0, 1.0]:
            line += ' tint%s' % mc
        out.append(line)
print('\n'.join(out))
