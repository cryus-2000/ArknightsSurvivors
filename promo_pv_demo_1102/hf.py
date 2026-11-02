import sys, glob, os
import numpy as np
from PIL import Image
HERE=os.path.dirname(os.path.abspath(__file__))
def hf(d):
    fs=sorted(glob.glob(os.path.join(d,"f*.jpg"))); out=[]
    for i,f in enumerate(fs):
        a=np.asarray(Image.open(f).reduce(8).convert("L"),np.float32)
        out.append(a.mean())
    out=np.array(out); w=[i for i in range(len(out)) if out[i]>140 and (i==0 or out[i-1]<=140)]
    return w, len(fs)
for run in sys.argv[1:]:
    for d in sorted(glob.glob(os.path.join(HERE,"raw",run,"rec_*_ult_*"))):
        print(run, os.path.basename(d), *hf(d))
