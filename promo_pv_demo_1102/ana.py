import sys, subprocess, numpy as np, imageio_ffmpeg as I
FF=I.get_ffmpeg_exe()
def load(p, sr=22050):
    raw=subprocess.run([FF,"-v","error","-i",p,"-ac","1","-ar",str(sr),"-f","f32le","-"],capture_output=True).stdout
    return np.frombuffer(raw,np.float32), sr
def tempo(x,sr):
    hop=512; n=len(x)//hop
    fr=x[:n*hop].reshape(n,hop); e=np.sqrt((fr**2).mean(1)+1e-12)
    on=np.maximum(0,np.diff(np.log(e+1e-4))); on-=on.mean()
    ac=np.correlate(on,on,'full')[len(on)-1:]
    fps=sr/hop; best=None
    lags=np.arange(int(fps*60/200),int(fps*60/70))
    l=lags[np.argmax(ac[lags])]; return 60*fps/l
for p in (sys.argv[1:] if __name__=="__main__" else []):
    x,sr=load(p); d=len(x)/sr
    rms=[np.sqrt((x[int(i*sr):int((i+4)*sr)]**2).mean()) for i in np.arange(0,d-1,4)]
    m=max(rms)
    print("%-40s %.1fs bpm~%.1f"%(p.split('/')[-1][-40:],d,tempo(x,sr)))
    print("   "+"".join(" .:-=+*#%@"[min(9,int(r/m*9.99))] for r in rms))
