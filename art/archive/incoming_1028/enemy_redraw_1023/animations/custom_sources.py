"""No-Spine exceptions: original chest layers and reference-authored crystal rays.
Never labelled as original Spine. No approved f0 pixels are used.
"""
import json,math
from PIL import Image,ImageDraw

def prepare(j,root,build):
    ident=j['id'];out=build/ident;out.mkdir(parents=True,exist_ok=True);size=32;ss=4
    defs=[('idle',4,1.6,True),('move',4,.8,True),('attack',6,.8,False),('wound',1,.12,False),('death',6,.8,False)] if ident=='tear' else [('idle',1,1,True),('wound',1,.12,False),('reveal',4,.64,False)]
    actions=[];frames=[]
    ref=root/j['reference'];chest=Image.open(ref).convert('RGBA') if ident!='tear' else None
    def add_frame(name,action,index,n):
        parts=[];full=Image.new('RGBA',(size*ss,size*ss));phase=index*math.tau/max(1,n);glow=None
        if ident=='tear':
            center=(16,20);bob=math.sin(phase)*.65 if action=='move' else 0
            tips=[(-3,-25),(23,-14),(18,21),(-5,17),(-24,-6),(-14,-18)]
            for k,(tx,ty) in enumerate(tips):
                # Each original-reference ray articulates about its core.
                angle=math.sin(phase+k)*.025 if action in ('idle','move') else 0
                stretch=1
                if action=='attack':stretch=[1,.85,.9,1.22,1.08,1][index]
                if action=='wound':angle=.16*(1 if k%2 else -1);stretch=.84
                spread=(index/max(1,n-1))*1.5 if action=='death' else 0
                length=math.hypot(tx,ty);ux,uy=tx/length,ty/length
                cx=center[0]+ux*spread;cy=center[1]+bob+uy*spread+(index*.15 if action=='death' else 0)
                xx=(tx*math.cos(angle)-ty*math.sin(angle))*18/46*stretch
                yy=(tx*math.sin(angle)+ty*math.cos(angle))*18/46*stretch
                nx,ny=-uy*.9,ux*.9
                pts=[(cx+nx,cy+ny),(cx+xx,cy+yy),(cx-nx,cy-ny)]
                im=Image.new('RGBA',full.size);d=ImageDraw.Draw(im)
                cv=lambda ps:[(round(x*ss),round(y*ss)) for x,y in ps]
                d.polygon(cv(pts),fill='#6C7B91');d.polygon(cv([pts[0],pts[1],(cx,cy)]),fill='#DED6C5');d.line(cv([(cx,cy),pts[1]]),fill='#C3C3BC',width=1)
                parts.append(('ray_'+str(k),im))
            im=Image.new('RGBA',full.size);d=ImageDraw.Draw(im);cx,cy=center[0],center[1]+bob
            if action!='death' or index<4:d.polygon([(int(cx*ss),int((cy-1)*ss)),(int((cx+1)*ss),int(cy*ss)),(int(cx*ss),int((cy+1)*ss)),(int((cx-1)*ss),int(cy*ss))],fill='#C3C3BC')
            parts.append(('core',im));glow=[cx,cy] if action!='death' or index<4 else None
        else:
            # The supplied reference is the original 14x11 chest, not a f0 cutout.
            ox=16-chest.width//2;oy=28-chest.height;split=4
            base=Image.new('RGBA',full.size);low=chest.crop((0,split,chest.width,chest.height)).resize((chest.width*ss,(chest.height-split)*ss),Image.Resampling.NEAREST);base.paste(low,(ox*ss,(oy+split)*ss));parts.append(('chest_base',base))
            lid=chest.crop((0,0,chest.width,split)).resize((chest.width*ss,split*ss),Image.Resampling.NEAREST)
            rotation=-8 if action=='wound' else -index*7 if action=='reveal' else 0
            lift=1 if action=='wound' else index if action=='reveal' else 0
            lid=lid.rotate(rotation,Image.Resampling.NEAREST,expand=True);im=Image.new('RGBA',full.size);im.paste(lid,(ox*ss,(oy-lift)*ss),lid);parts.append(('chest_lid',im))
        rows=[]
        for z,(part,im) in enumerate(parts):
            filename=name+'_'+part+'.png';im.save(out/filename);full.alpha_composite(im)
            rows.append({'slot':part,'attachment':part,'bone':None,'parent':'core' if ident=='tear' else None,'draw_order':z,'file':filename,'construction':'authored original-reference component; no Spine'})
        full.save(out/(name+'.png'));frames.append({'name':name,'anim':'authored_'+action,'t':0,'parts':rows,'glow':glow})
    add_frame('reference','idle',0,1)
    for action,n,duration,loop in defs:
        names=[];times=[]
        for i in range(n):
            name=f'{action}_{i:02}';names.append(name);times.append(duration*i/(n if loop else max(1,n-1)));add_frame(name,action,i,n)
        actions.append({'action':action,'source_animation':None,'construction':'original-reference authored components; no Spine','frames':n,'duration_seconds':duration,'sample_times':times,'source_events':[],'event_frames':[],'loop':loop,'frame_names':names,'release_frame':3 if action=='attack' else None})
    cat={'id':ident,'source':'original-reference authored components; no standalone Spine','anims':{},'scale':1,'frame_size':[32,32],'origin':[16,28],'glow_binding':{'component':'core'} if ident=='tear' else None,'frames':frames}
    (out/'catalog.json').write_text(json.dumps(cat),encoding='utf-8')
    (build/(ident+'_job.json')).write_text(json.dumps({'art_source':str(ref),'construction':cat['source']}),encoding='utf-8')
    return actions,[]
