"""把原作萨米敌人特效预制体的层级 / 粒子参数 / 贴图提出来（参照用，输出到 F:/sami_enemy_fx_ref/prefabs/）。"""
import sys, os, re, json, glob
sys.path.insert(0, os.path.dirname(__file__))
import akup  # noqa
import UnityPy

ROOT = os.environ.get("SAMI_FX_REF", "F:/sami_enemy_fx_ref")
OUT = ROOT + '/prefabs'
PAT = re.compile(sys.argv[1] if len(sys.argv) > 1 else r'/enemy_(sm|snslime|icebrk|uamord|mhshep)')
os.makedirs(OUT, exist_ok=True)

env = UnityPy.load(*sorted(glob.glob(ROOT + '/ab/pkgrps/*.ab')) + sorted(glob.glob(ROOT + '/ab/extra/*.ab')))


def curve_val(c):
    """MinMaxCurve → 简短描述"""
    if not isinstance(c, dict):
        return c
    mode = c.get('minMaxState', 0)
    sc = c.get('scalar', 0)
    mn = c.get('minScalar', sc)
    if mode == 0:
        return round(sc, 3)
    if mode == 3:
        return [round(mn, 3), round(sc, 3)]
    # 曲线：取关键帧
    keys = c.get('maxCurve', {}).get('m_Curve', [])
    pts = [(round(k['time'], 2), round(k['value'] * sc, 3)) for k in keys]
    return {'curve': pts}


def col(cv):
    return [round(cv.get(k, 0), 2) for k in ('r', 'g', 'b', 'a')]


def grad(gr):
    if not gr:
        return None
    n = gr.get('m_NumColorKeys', 0)
    na = gr.get('m_NumAlphaKeys', 0)
    ck = [(round(gr.get('ctime%d' % i, 0) / 65535, 2), col(gr.get('key%d' % i, {}))[:3]) for i in range(n)]
    ak = [(round(gr.get('atime%d' % i, 0) / 65535, 2), round(gr.get('key%d' % i, {}).get('a', 0), 2)) for i in range(na)]
    return {'c': ck, 'a': ak}


def mmgrad(g):
    if not isinstance(g, dict):
        return None
    st = g.get('minMaxState', 0)
    if st == 0:
        return {'col': col(g.get('maxColor', {}))}
    if st == 1:
        return {'grad': grad(g.get('maxGradient'))}
    if st == 2:
        return {'between': [col(g.get('minColor', {})), col(g.get('maxColor', {}))]}
    return {'grads': [grad(g.get('minGradient')), grad(g.get('maxGradient'))]}


def resolve(af, ref):
    if not ref or not ref.get('m_PathID'):
        return None
    if ref.get('m_FileID', 0) == 0:
        return af.objects.get(ref['m_PathID'])
    try:
        ext = af.externals[ref['m_FileID'] - 1]
        nm = ext.path.split('/')[-1].lower()
        for k, f in env.files.items():
            for kk, ff in getattr(f, 'files', {}).items():
                if kk.lower() == nm and hasattr(ff, 'objects'):
                    return ff.objects.get(ref['m_PathID'])
    except Exception:
        pass
    return None


def mat_info(af, ref):
    m = resolve(af, ref)
    if m is None:
        return {'mat': 'ext'}
    tt = m.read_typetree()
    info = {'mat': tt.get('m_Name')}
    sh = resolve(m.assets_file, tt.get('m_Shader'))
    try:
        info['shader'] = sh.read_typetree().get('m_ParsedForm', {}).get('m_Name') if sh else 'ext'
    except Exception:
        info['shader'] = '?'
    texs = {}
    for name, te in tt.get('m_SavedProperties', {}).get('m_TexEnvs', []):
        t = resolve(m.assets_file, te.get('m_Texture'))
        if t is not None:
            try:
                texs[name] = t.read().m_Name
            except Exception:
                texs[name] = '?'
        elif te.get('m_Texture', {}).get('m_PathID'):
            texs[name] = 'ext'
    info['tex'] = texs
    info['col'] = {n: col(c) for n, c in tt.get('m_SavedProperties', {}).get('m_Colors', []) if 'olor' in n}
    info['f'] = {n: round(v, 3) for n, v in tt.get('m_SavedProperties', {}).get('m_Floats', []) if n in ('_SrcBlend', '_DstBlend', '_Intensity', '_Brightness', '_Mode', '_Cutoff')}
    return info


def ps_info(ps_tt):
    i = ps_tt.get('InitialModule', {})
    d = {
        'dur': round(ps_tt.get('lengthInSec', 0), 2), 'loop': ps_tt.get('looping'), 'delay': curve_val(ps_tt.get('startDelay')),
        'life': curve_val(i.get('startLifetime')), 'spd': curve_val(i.get('startSpeed')),
        'size': curve_val(i.get('startSize')), 'rot': curve_val(i.get('startRotation')),
        'color': mmgrad(i.get('startColor')), 'max': i.get('maxNumParticles'),
        'grav': curve_val(i.get('gravityModifier')),
    }
    em = ps_tt.get('EmissionModule', {})
    if em.get('enabled'):
        d['rate'] = curve_val(em.get('rateOverTime'))
        bs = em.get('m_Bursts', [])
        if bs:
            d['bursts'] = [(round(b.get('time', 0), 2), curve_val(b.get('countCurve'))) for b in bs]
    sh = ps_tt.get('ShapeModule', {})
    if sh.get('enabled'):
        d['shape'] = {'type': sh.get('type'), 'r': round(sh.get('radius', {}).get('value', 0) if isinstance(sh.get('radius'), dict) else sh.get('radius', 0), 2),
                      'angle': round(sh.get('angle', 0), 1), 'arc': round(sh.get('arc', {}).get('value', 360) if isinstance(sh.get('arc'), dict) else sh.get('arc', 360), 1)}
    for mod, key, fn in (('ColorModule', 'gradient', mmgrad), ('SizeModule', 'curve', curve_val), ('RotationModule', 'curve', curve_val)):
        m = ps_tt.get(mod, {})
        if m.get('enabled'):
            d[mod.replace('Module', '').lower() + '_ol'] = fn(m.get(key))
    vm = ps_tt.get('VelocityModule', {})
    if vm.get('enabled'):
        d['vel'] = [curve_val(vm.get(k)) for k in ('x', 'y', 'z')]
    tm = ps_tt.get('UVModule', {})
    if tm.get('enabled'):
        d['sheet'] = [tm.get('tilesX'), tm.get('tilesY')]
    tr = ps_tt.get('TrailModule', {})
    if tr.get('enabled'):
        d['trail'] = True
    return d


rows = {}
for path, obj in env.container.items():
    if not PAT.search(path):
        continue
    go = obj.read()
    name = os.path.basename(path).replace('.prefab', '')
    nodes = []

    def walk(g, depth):
        tt = g.read_typetree()
        ent = {'n': tt.get('m_Name'), 'd': depth, 'active': tt.get('m_IsActive')}
        tr = None
        for comp in tt.get('m_Component', []):
            ref = comp['component']
            try:
                c = g.assets_file.objects[ref['m_PathID']]
            except KeyError:
                continue
            tn = c.type.name
            if tn == 'Transform':
                tr = c
                ctt = c.read_typetree()
                ent['pos'] = [round(ctt['m_LocalPosition'][k], 2) for k in 'xyz']
                ent['scl'] = [round(ctt['m_LocalScale'][k], 2) for k in 'xyz']
            elif tn == 'ParticleSystem':
                ent['ps'] = ps_info(c.read_typetree())
            elif tn == 'ParticleSystemRenderer':
                rt = c.read_typetree()
                ent['rmode'] = rt.get('m_RenderMode')
                ent['vscale'] = round(rt.get('m_VelocityScale', 0), 2)
                ent['lscale'] = round(rt.get('m_LengthScale', 0), 2)
                mats = rt.get('m_Materials', [])
                ent['mats'] = [mat_info(c.assets_file, m) for m in mats]
            elif tn == 'MeshRenderer':
                ent['mesh_mats'] = [mat_info(c.assets_file, m) for m in c.read_typetree().get('m_Materials', [])]
            elif tn == 'MeshFilter':
                mm = resolve(c.assets_file, c.read_typetree().get('m_Mesh'))
                ent['mesh'] = mm.read().m_Name if mm else 'ext'
            elif tn == 'Animator':
                ent['anim'] = True
            elif tn == 'MonoBehaviour':
                try:
                    mt = c.read_typetree()
                    ent.setdefault('mono', []).append({k: v for k, v in mt.items() if isinstance(v, (int, float)) and k not in ('m_Enabled',)})
                except Exception:
                    pass
        nodes.append(ent)
        if tr is not None:
            for ch in tr.read_typetree().get('m_Children', []):
                try:
                    ctr = tr.assets_file.objects[ch['m_PathID']].read_typetree()
                    walk(tr.assets_file.objects[ctr['m_GameObject']['m_PathID']], depth + 1)
                except KeyError:
                    pass

    try:
        walk(go.assets_file.objects[go.object_reader.path_id] if hasattr(go, 'object_reader') else obj, 0)
    except Exception as ex:
        nodes.append({'err': repr(ex)})
    rows[name] = nodes

json.dump(rows, open(OUT + '/prefabs.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print(len(rows))
