import os, sys, json, time
WT=os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace(os.sep,"/")
sys.path.insert(0, WT+"/tools")
import godot_runner as gr
HERE=os.path.dirname(os.path.abspath(__file__))
RUNS={
 "A": ["--seed=1","--op=mizuki","--squad=texas,skadi","--forceending=deep","--wheelplan=open@75,sel@0.35:1,ok@1.3"],
 "B": ["--seed=2","--op=texas","--squad=mizuki,saria","--forceending=resolve"],
 "C": ["--seed=3","--op=mizuki","--squad=texas,saria","--forceending=standard"],
}
def launch(name, extra, maxt):
    gr.ensure_imported(WT+"/game")
    out=os.path.join(HERE,"raw",name).replace(os.sep,"/"); os.makedirs(out,exist_ok=True)
    args=[gr.find_godot(),"--path",WT+"/game","--audio-driver","Dummy","--fixed-fps","30","--resolution","1920x1080",
          "-s",HERE.replace(os.sep,"/")+"/pv_mon.gd","--","--balance","--realtime","--nodeath","--bot=master","--diff=4"]+RUNS[name[0]]+["--pv_out="+out,"--pv_maxt=%s"%maxt]+extra
    t0=time.time(); o,e,to=gr.run_godot(args, 7200)
    open(os.path.join(out,"run.log"),"w",encoding="utf-8").write(" ".join(args)+"\n\n"+o+"\n----\n"+e)
    print(name,"wall %ds"%(time.time()-t0),"timeout" if to else "", gr.script_errors(o,e)[:3], flush=True)
if __name__=="__main__":
    name=sys.argv[1]; maxt=float(sys.argv[2]); extra=sys.argv[3:]
    launch(name, extra, maxt)
