"""Render silent 30fps original-speed black/actual-ground review videos."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json, math, subprocess, hashlib
import imageio_ffmpeg

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'animation_previews'
OUT.mkdir(exist_ok=True)
FONT=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',16)
GROUND=Path('E:/ArknightsSurvivors/art/incoming/tiles.png')

def render(row):
    name=row['name']; w,h=row['physical_size']; n=row['frame_count']
    sheet=Image.open(ROOT/row['file']).convert('RGBA')
    assert sheet.size==(w*n,h)
    frames=[sheet.crop((i*w,0,(i+1)*w,h)) for i in range(n)]
    guide=None
    if row.get('pose_guide_strip'):
        guide=Image.open(ROOT/row['pose_guide_strip']).convert('RGBA')
    fps=row.get('fps') or 12
    # Integer presentation preserves original animation timing on a 30fps video clock.
    # Three complete repeats on each background; loops remain at their source FPS.
    cycles=max(3,math.ceil(2*fps/n))
    ticks=math.ceil(n/fps*30*cycles)
    angle_mode=row.get('fps') is None
    if angle_mode:ticks=60
    W,H=960,640
    ground=Image.new('RGBA',(W,H),(16,25,30,255))
    tile=Image.open(GROUND).convert('RGBA')
    for y in range(0,H,tile.height):
        for x in range(0,W,tile.width):ground.alpha_composite(tile,(x,y))
    backgrounds=[Image.new('RGBA',(W,H),'black'),ground]
    path=OUT/(name+'.mp4')
    cmd=[imageio_ffmpeg.get_ffmpeg_exe(),'-y','-loglevel','error','-f','rawvideo','-vcodec','rawvideo','-pix_fmt','rgb24','-s',f'{W}x{H}','-r','30','-i','-','-an','-c:v','libx264','-preset','fast','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(path)]
    proc=subprocess.Popen(cmd,stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    for bg_index,bg in enumerate(backgrounds):
        for tick in range(ticks):
            idx=int(tick*fps/30)%n
            canvas=bg.copy(); im=frames[idx]
            if angle_mode:
                im=frames[0].rotate(tick*180/30,Image.Resampling.NEAREST)
            if guide is not None and idx in row.get('pose_guide_visible_frames',range(n)):
                gw,gh=row['pose_guide_frame_size_2x'];gi=row['pose_guide_frame_mapping'][idx]
                g=guide.crop((gi*gw,0,(gi+1)*gw,gh))
                ox,oy=row['origin_px_2x'];gx,gy=row['pose_guide_origin_px_2x']
                canvas.alpha_composite(g,(round((W-w)/2+ox-gx),round((H-h)/2+oy-gy)))
            if row.get('tile_axis')=='x':
                canvas.alpha_composite(im,((W-w)//2,150))
                copies=min(4,800//w)
                for k in range(copies):canvas.alpha_composite(im,((W-copies*w)//2+k*w,400))
            else:
                canvas.alpha_composite(im,((W-w)//2,(H-h)//2))
            d=ImageDraw.Draw(canvas)
            d.text((24,18),name,fill='white',font=FONT)
            label='Angle atlas / program rotation demo 180 deg/s' if angle_mode else f'{fps:g} source fps / 30 fps video / original speed'
            d.text((24,44),label+' / '+('BLACK' if bg_index==0 else 'GAME GROUND'),fill='#aabbc5',font=FONT)
            proc.stdin.write(canvas.convert('RGB').tobytes())
    proc.stdin.close(); error=proc.stderr.read();code=proc.wait()
    assert code==0,error.decode(errors='replace')
    assert path.stat().st_size<=5_000_000,(name,path.stat().st_size)
    return {'file':path.relative_to(ROOT).as_posix(),'video_fps':30,'source_fps':fps,'frames':ticks*2,'duration_seconds':ticks*2/30,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'background_source':str(GROUND),'background_sha256':hashlib.sha256(GROUND.read_bytes()).hexdigest()}

if __name__=='__main__':
    manifest=json.loads((ROOT/'manifest.json').read_text(encoding='utf8'))
    results={row['name']:render(row) for row in manifest['assets']}
    (OUT/'videos.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf8')
