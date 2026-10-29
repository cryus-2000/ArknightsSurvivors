"""Independent checks on exported strips and exact native source placement."""
from pathlib import Path
from PIL import Image
import hashlib,json
import numpy as np

R=Path(__file__).resolve().parent
ROOT=R.parents[1]
def H(p):return hashlib.sha256(p.read_bytes()).hexdigest()
entries=json.loads((R/'entries.json').read_text(encoding='utf8'))
results=[]
for e in entries:
    p=Path(e['file']);im=Image.open(p).convert('RGBA');w,h=e['physical_size'];n=e['frame_count'];a=np.asarray(im)
    assert im.size==(w*n,h)
    assert set(np.unique(a[:,:,3]))<={0,255}
    assert not np.any(a[a[:,:,3]==0,:3])
    assert H(p)==e['sha256']
    assert e['rgba_mib']<=5
    for source in e['sourcehash']:assert H(Path(source['file']))==source['sha256']
    for span in e['segments'].values():assert len(span)==2 and 0<=span[0]<=span[1]<n
    frames=[im.crop((i*w,0,(i+1)*w,h)) for i in range(n)]
    extra={}
    if 'sword' in e['name']:
        src=Image.open(e['native_source']).convert('RGBA')
        for i in range(6):
            source_frame=min(i,4)
            delivery=np.asarray(frames[i].crop((20,148,44,228)))
            native=np.asarray(src.crop((24*source_frame,0,24*(source_frame+1),80)))
            visible=native[:,:,3]>0
            assert np.array_equal(delivery[:,:,3],native[:,:,3])
            assert np.array_equal(delivery[visible],native[visible])
        approved=Image.open(ROOT/'keyframes/fx_ult_texas_sword_front_f03@2x.png').convert('RGBA')
        assert frames[4].tobytes()==approved.tobytes()
        extra={'native_frames_0_through_4_visible_rgba_exact':True,'sixth_frame_native_rectangle_visible_rgba_exact':True,'native_alpha_exact':True,'transparent_native_rgb_normalized_to_zero':True,'old_f3_keyframe_equals_full_f4':True}
    if 'lock' in e['name']:assert frames[4].tobytes()==frames[5].tobytes()
    results.append({'name':e['name'],'size':list(im.size),'fps':e['fps'],'frame_count':n,'binary_alpha':True,'clear_transparent_rgb':True,'source_hashes':True,'output_hash':True,'rgba_mib':e['rgba_mib'],**extra})
out={'checks':results,'assets':len(results),'frames':sum(e['frame_count'] for e in entries),'rgba_mib':sum(e['rgba_mib'] for e in entries),'runtime_verified':False}
(R/'independent_qa.json').write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(out,ensure_ascii=False))
