import glob, numpy as np, soundfile as sf, subprocess, imageio_ffmpeg as I
FF=I.get_ffmpeg_exe(); SR=48000
P=60/145.99; O=0.111; B=4*P
import os
STEMS="E:/ArknightsSurvivors/art/incoming/music_suno/swarm_theme/"
def load(p):
    raw=subprocess.run([FF,"-v","error","-i",p,"-ac","2","-ar",str(SR),"-f","f32le","-"],capture_output=True).stdout
    return np.frombuffer(raw,np.float32).reshape(-1,2)
def song():
    """11 条 Suno 分轨直接相加（主仓库 art/incoming/music_suno/swarm_theme，未入 git；内部小样用，授权待用户确认）"""
    st=[load(f) for f in sorted(glob.glob(STEMS+"*.mp3"))]
    n=min(len(s) for s in st); return sum(s[:n].astype(np.float64) for s in st)
# (song bar start, n bars) 依次拼接；None = 静默 n 拍
SEGS=[(48,1),(52,1),(22,7),(59,9),(68,4),("rest",2),(125,3.9)]
def build(out="music.wav"):
    s=song(); parts=[]; marks=[]; t=0.0
    for a,n in SEGS:
        if a=="rest":
            L=int(round(n*P*SR)); parts.append(np.zeros((L,2))); marks.append(("rest",t)); t+=L/SR; continue
        s0=int(round((O+a*B)*SR)); L=int(round(n*B*SR))
        x=s[s0:s0+L].copy()
        f=int(0.006*SR); x[:f]*=np.linspace(0,1,f)[:,None]; x[-f:]*=np.linspace(1,0,f)[:,None]
        parts.append(x); marks.append((a,t)); t+=L/SR
    m=np.concatenate(parts)
    tail=int(1.6*SR); m[-tail:]*=np.linspace(1,0,tail)[:,None]**1.5
    pk=np.abs(m).max(); m*=0.89/pk
    sf.write(out,m.astype(np.float32),SR); print(out,"%.3fs"%(len(m)/SR), [(a,round(t,3)) for a,t in marks])
if __name__=="__main__": build()
