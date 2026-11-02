import numpy as np, glob, os
from ana import load
P=60/145.99; O=0.111; B=4*P
D="E:/ArknightsSurvivors/art/incoming/music_suno/swarm_theme/"   # 分轨只在本机主仓库（未入库）；云端用 music/ 里的整曲
st={}
for f in sorted(glob.glob(D+"*.mp3")):
    x,sr=load(f,22050); st[os.path.basename(f)[:6]]=x
mix=sum(v[:min(map(len,st.values()))] for v in st.values()); st["MIX"]=mix
nb=int((len(mix)/sr-O)/B)
for k,x in st.items():
    r=np.array([np.sqrt((x[int((O+i*B)*sr):int((O+(i+1)*B)*sr)]**2).mean()) for i in range(nb)])
    print("%-7s"%k+"".join(" .:-=+*#%@"[min(9,int(v/r.max()*9.99))] for v in r))
print("bar    "+"".join(str((i//10)%10) if i%10==0 else " " for i in range(nb)))
print("bar len %.4f  nb %d"%(B,nb))
