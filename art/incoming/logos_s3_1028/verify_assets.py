from pathlib import Path
import json, hashlib, importlib.util, sys
import numpy as np
from PIL import Image
R=Path(__file__).resolve().parent
M=json.loads((R/'manifest.json').read_text())
palette={tuple(bytes.fromhex(x[1:])) for x in M['palette']}
checks=[];images={}
for a in M['assets']:
    p=R/a['file'];im=Image.open(p).convert('RGBA');q=np.array(im);w,h=a['frame_size']
    assert im.size==(w*a['frames'],h)
    assert set(np.unique(q[:,:,3]))<={0,255}
    assert set(map(tuple,q[:,:,:3][q[:,:,3]>0]))<=palette
    assert np.array_equal(q[::2,::2],q[1::2,::2]) and np.array_equal(q[::2,::2],q[::2,1::2])
    assert hashlib.sha256(p.read_bytes()).hexdigest()==a['sha256']
    frames=[q[:,i*w:(i+1)*w] for i in range(a['frames'])];images[a['file']]=frames
    if 'fan_' in a['file']:
        yy,xx=np.mgrid[:h//2,:w//2];dx=xx+.5-4;dy=yy+.5-132
        bounds=(np.hypot(dx,dy)<=170)&(dx>=0)&(np.abs(np.arctan2(dy,dx))<=np.deg2rad(50))
        for frame in frames:
            assert np.array_equal(frame,frame[::-1])
            assert not np.any((frame[::2,::2,3]>0)&~bounds)
        if 'ground' in a['file']:
            interior=(np.hypot(dx,dy)<155)&(np.hypot(dx,dy)*np.sin(np.deg2rad(50)-np.abs(np.arctan2(dy,dx)))>14)&(np.hypot(dx,dy)>25)
            for f in frames:assert set(map(tuple,f[::2,::2,:3][interior&(f[::2,::2,3]>0)]))<=palette.intersection({tuple(bytes.fromhex(s)) for s in ['080e18']})
    elif "slow" in a["file"]:
        yy,xx=np.mgrid[:48,:48];center=(xx-23.5)**2+(yy-23.5)**2<9**2
        for f in frames:assert not np.any(f[:,:,3][center])
    checks.append({'file':a['file'],'pass':True,'opaque_fraction':round(float(np.mean(q[:,:,3]>0)),4),'bytes':p.stat().st_size})
g=images['fx_logos_s3_fan_ground@2x.png'][0]
assert np.array_equal(g,images['fx_logos_s3_fan_open@2x.png'][-1])
assert np.array_equal(g,images['fx_logos_s3_fan_close@2x.png'][0])
assert sum(c['bytes'] for c in checks)<600000
report={'checks':checks,'seams_exact':True,'runtime_bytes':sum(c['bytes'] for c in checks),'pixel_grid':'2x2 exact','geometry':'100 degrees, radius <=340, mirrored at y264','runtime_verified':False}
if len(sys.argv)>1:
    tools=Path(sys.argv[1]);sys.path.insert(0,str(tools));import px_lint,asset_lint
    reports=[]
    for a in M['assets']:
        key=a['file'].removeprefix('fx_logos_s3_').removesuffix('@2x.png')
        for i in range(a['frames']):
            p=R/'preview'/f'{key}_{i:02}.png'
            r=px_lint.analyze(px_lint.Layer(str(p)),tuple(a['origin']),2)
            reports.append({'file':str(p),'report':r})
            assert r['alpha_binary'] and not r['single_highlight']
    (R/'px_lint_report.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
    rep=asset_lint.Report();ops,ens=asset_lint.load_ids()
    asset_lint.check_runtime_names(rep,[str(R/a['file']) for a in M['assets']],ops,ens)
    findings=[{'rule':k[0],'level':k[1],'title':k[2],'items':v} for k,v in rep.items.items()]
    assert not any(f['level']=='ERROR' for f in findings)
    report['asset_lint']=findings
    report['px_lint_note']='Binary alpha and single highlights checked. Character foot/single-component/black-outline criteria are inapplicable to an open glyph field with pale borders and intentional stipple.'
(R/'qa.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report))
