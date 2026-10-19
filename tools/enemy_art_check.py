"""Enemy delivery checks. Candidate evidence is separate from runtime acceptance."""
from pathlib import Path
import argparse, hashlib, json
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]

def audit(manifest_path):
    path=Path(manifest_path);root=path.parent
    doc=json.loads(path.read_text(encoding='utf8'));errors=[];pending=[]
    if not doc.get('actions'):errors.append('empty animation delivery')
    seen=set()
    for entry in doc.get('actions',[]):
        if not isinstance(entry,dict) or not isinstance(entry.get('id'),str) or not isinstance(entry.get('action'),str):
            errors.append('action identity missing or invalid');continue
        tag=entry['id']+'/'+entry['action']
        if tag in seen:errors.append(tag+': duplicate action')
        seen.add(tag)
        if entry.get('status')=='missing_reference':
            pending.append(tag+': missing original/custom pose reference');continue
        try:
            strip=Image.open(root/entry['strip']).convert('RGBA')
            n=entry['frames'];w,h=entry['frame_size']
            if n<=0 or strip.size!=(n*w,h):errors.append(tag+': strip dimensions/frame count')
            if not set(strip.getchannel('A').getdata())<={0,255}:errors.append(tag+': nonbinary alpha')
            times=entry['sample_times']
            if len(times)!=n or any(b<=a for a,b in zip(times,times[1:])):errors.append(tag+': sample timeline')
            if entry['duration']<=0 or any(t<0 or t>entry['duration'] for t in times):errors.append(tag+': invalid duration')
            if not (0<=entry['anchor'][0]<=w and 0<=entry['anchor'][1]<=h):errors.append(tag+': anchor outside canvas')
            for i,frame in enumerate(entry['parts']):
                composed=Image.new('RGBA',(w,h));orders=[]
                for part in frame:
                    orders.append(part['draw_order'])
                    im=Image.open(root/part['file']).convert('RGBA')
                    if im.size!=(w,h):errors.append(tag+': part canvas mismatch');continue
                    composed.alpha_composite(im)
                if orders!=sorted(set(orders)):errors.append(tag+': invalid draw order')
                if composed.tobytes()!=strip.crop((i*w,0,(i+1)*w,h)).tobytes():errors.append(tag+': recomposition differs frame '+str(i))
            if len(entry['parts'])!=n:errors.append(tag+': missing per-frame parts')
            if entry.get('clipped_source_parts'):errors.append(tag+': clipped native attachment')
            if not entry.get('sources'):pending.append(tag+': source provenance missing')
            mapping=entry.get('runtime_mapping')
            if mapping and mapping.get('frames')!=n:errors.append(tag+': runtime frame count mismatch')
            evidence=entry.get('engine_evidence')
            if evidence:
                evidence_path=root/evidence
                if not evidence_path.exists():errors.append(tag+': missing render evidence')
                else:
                    captures=json.loads(evidence_path.read_text(encoding='utf8'))
                    required={'raw','pop','stunned','hit','raw_atlas'}
                    if not required.issubset({x.get('state') for x in captures.get('states',[])}):errors.append(tag+': incomplete render states')
                    if captures.get('strip_sha256')!=hashlib.sha256((root/entry['strip']).read_bytes()).hexdigest():pending.append(tag+': render evidence does not identify this strip')
                    if not captures.get('clean_exit',False):pending.append(tag+': clean engine exit unverified')
                    if not all((evidence_path.parent/x['file']).exists() for x in captures.get('states',[])):errors.append(tag+': missing captured state image')
            for source in entry['sources']:
                p=root/source['file']
                if hashlib.sha256(p.read_bytes()).hexdigest()!=source['sha256']:errors.append(tag+': source changed')
            if not entry.get('runtime_mapping'):pending.append(tag+': runtime timing/slot mapping pending')
            if not entry.get('engine_evidence'):pending.append(tag+': actual rendering pending')
            if not entry.get('visual_approved'):pending.append(tag+': visual approval pending')
        except (OSError,KeyError,TypeError,ValueError) as exc:errors.append(tag+': '+str(exc))
    for item in doc.get('coverage',[]):
        if item.get('status')!='rebuilt':pending.append(item['slot']+': '+item.get('status','unverified'))
    return {'errors':errors,'pending':pending,'actions':len(doc.get('actions',[])),'technical_pass':not errors,'ready_to_integrate':not errors and not pending}

def check():
    errors=[];count=0;pending=0
    for p in (ROOT/'art/incoming').glob('**/enemy_delivery.json'):
        result=audit(p);errors+=result['errors'];count+=result['actions'];pending+=len(result['pending'])
    return errors,f'{count} registered actions; {pending} pending acceptance items (not integration approved)'

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('manifest',nargs='?');ap.add_argument('--require-ready',action='store_true');args=ap.parse_args()
    if args.manifest:
        result=audit(args.manifest);print(json.dumps(result,ensure_ascii=False,indent=2));raise SystemExit(bool(result['errors']) or (args.require_ready and not result['ready_to_integrate']))
    errors,detail=check();print(detail);print('\n'.join(errors));raise SystemExit(bool(errors))
