from pathlib import Path
from PIL import Image
import json,hashlib,numpy as np
import imageio_ffmpeg
R=Path(__file__).resolve().parent
m=json.loads((R/'manifest.json').read_text(encoding='utf8'))
old=json.loads((R/'animation_keyframe_manifest.json').read_text(encoding='utf8'))
spec={a['name']:a for a in old['assets']}
videos=json.loads((R/'animation_previews/videos.json').read_text(encoding='utf8'))
report=[];total=0
assert len(m['assets'])==16
for a in m['assets']:
    name=a['name'];w,h=a['physical_size'];n=a['frame_count'];p=R/a['file']
    assert a['physical_size']==spec[name]['physical_size']
    assert n==spec[name]['frame_count']
    im=Image.open(p);assert im.mode=='RGBA' and im.size==(w*n,h)
    ar=np.array(im);assert not np.any(ar[ar[:,:,3]==0,:3])
    size=w*h*n*4;assert size<=5*1048576;total+=size
    frames=[ar[:,i*w:(i+1)*w] for i in range(n)]
    hashes=[hashlib.sha256(f.tobytes()).hexdigest() for f in frames]
    assert len(set(hashes))>=2,(name,'static strip')
    assert hashlib.sha256(p.read_bytes()).hexdigest()==a['sha256']
    seams=[]
    if a.get('tile_axis')=='x':
        for f in frames:
            seams.append(bool(np.array_equal(f[:,0],f[:,-1])))
        assert all(seams),(name,'seam')
    v=videos[name];vp=R/v['file'];assert vp.stat().st_size<=5_000_000
    reader=imageio_ffmpeg.read_frames(str(vp));meta=next(reader)
    assert meta['fps']==30,meta
    decoded=sum(1 for _ in reader)
    assert decoded==v['frames'],(name,decoded,v['frames'])
    report.append({'name':name,'frames':n,'unique_frames':len(set(hashes)),
                   'rgba_mib':size/1048576,'seams_all_frames':all(seams) if seams else None,
                   'video_decoded_frames':decoded,'video_fps':meta['fps'],'video_bytes':vp.stat().st_size})
assert total<=30*1048576
result={'status':'PASS','assets':16,'rgba_mib':total/1048576,'checks':report,
        'runtime_verified':False,'scope':'full strips and original-speed dual-background MP4s'}
(R/'animation_qa.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
print('PASS',16,'full strips and videos;',total/1048576,'MiB RGBA')
