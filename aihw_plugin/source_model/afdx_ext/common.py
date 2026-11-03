import hashlib,json,math,re
from pathlib import Path
import numpy as np

FEATURES=['observed_pps','mean_frame_bytes','frame_size_cv','arrival_cv','ab_unpaired_ratio','ab_payload_mismatch_ratio','fcs_error_ratio','queue_overflow_ratio','latency_p95_us','ntp_rtt_ms','ntp_offset_abs_ms','clock_step_abs_ms','loader_progress_ratio','loader_retry_ratio','fragment_orphan_ratio','management_fraction','active_context_ratio','sha_jobs_per_1k_frames']
CAUSES=['congestion','link_degradation','replica_divergence','time_anomaly','loader_stall','fragment_pressure','management_burst']
TOOLS=['inspect_queue','inspect_link','inspect_ab','inspect_time','inspect_loader','inspect_fragments','inspect_management']
ROOT=Path(__file__).resolve().parents[1]
class InputError(ValueError):pass
def canonical(d):return json.dumps(d,sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False).encode()
def sha(raw):return hashlib.sha256(raw).hexdigest()
def write_json(p,d):
 p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);temp=p.with_suffix(p.suffix+'.tmp');temp.write_text(json.dumps(d,indent=2,ensure_ascii=False,allow_nan=False)+'\n');temp.replace(p)
def read_json(p):
 def pairs(items):
  out={}
  for k,v in items:
   if k in out:raise InputError('duplicate JSON key')
   out[k]=v
  return out
 return json.loads(Path(p).read_bytes(),object_pairs_hook=pairs,parse_constant=lambda _:(_ for _ in ()).throw(InputError('nonfinite JSON')))
def finite_array(x,shape=None):
 a=np.asarray(x)
 if a.dtype.kind not in 'fi' or not np.isfinite(a).all() or shape is not None and a.shape!=shape:raise InputError('numeric array shape/type/range')
 with np.errstate(over='ignore'):out=a.astype(np.float32)
 if not np.isfinite(out).all():raise InputError('numeric conversion overflow')
 return out
def sigmoid(x):return 1/(1+np.exp(-np.clip(x,-40,40)))
def softmax(x):
 x=x-x.max(axis=-1,keepdims=True);v=np.exp(x);return v/v.sum(axis=-1,keepdims=True)
def transform(x):return np.log1p(np.maximum(x,0))
def save_npz(path,params,**extras):np.savez_compressed(path,**{k:np.asarray(v) for k,v in dict(params,**extras).items()})
def refresh_registry():
 p=ROOT/'models/registry.json'
 if p.exists():
  d=read_json(p);d['artifacts']={f.name:sha(f.read_bytes()) for f in (ROOT/'models').iterdir() if f.is_file() and f.name!='registry.json'};write_json(p,d)
def verify_models():
 d=read_json(ROOT/'models/registry.json')
 for name,h in d['artifacts'].items():
  if Path(name).name!=name or sha((ROOT/'models'/name).read_bytes())!=h:raise InputError('model registry integrity mismatch')
 return dict(status='PASS',artifacts=len(d['artifacts']),authenticated_signature=False)
def load_npz(path):
 path=Path(path)
 if path.parent.name=='models' and (path.parent/'registry.json').exists():
  expected=read_json(path.parent/'registry.json')['artifacts'].get(path.name)
  if expected is None or sha(path.read_bytes())!=expected:raise InputError('model checksum mismatch')
 with np.load(path,allow_pickle=False) as d:result={k:d[k].copy() for k in d.files}
 if any(v.dtype.kind not in 'fiu' or not np.isfinite(v).all() for v in result.values()):raise InputError('nonfinite/nonnumeric NPZ')
 return result
def thresholds(y,p):
 from sklearn.metrics import f1_score
 return np.asarray([max(np.linspace(.1,.9,33),key=lambda t:f1_score(y[:,i],p[:,i]>=t,zero_division=0)) for i in range(y.shape[1])],np.float32)
def bounded_int(value,lo,hi,name):
 if type(value) is not int or not lo<=value<=hi:raise InputError('invalid '+name)
 return value
