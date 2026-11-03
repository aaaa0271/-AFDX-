"""Continuous abstract packet-service traces, with actual interacting injections.

Labels describe controlled injections, not physical diagnoses. No label,
scenario id, future metric or security reason flag is placed in model inputs.
"""
import heapq,math
import numpy as np
from .common import FEATURES,CAUSES
HISTORY=8;HORIZON=3;WINDOWS=24
TRAIN_PAIRS=[(0,1),(3,4),(5,6),(1,2)]
TEST_PAIRS=[(0,6),(1,3),(1,4),(2,3),(0,5)]

class PacketLab:
 def __init__(self):self.time=0.;self.server=0.;self.finishes=[];self.used=[0]*4
 def window(self,rng,p,family,n=128):
  jobs=[];starts=[];sizes=[]
  for ch in range(4):
   lens=np.clip(rng.normal(p['size'],p['size']*p['size_cv'],n//4),64,1518).astype(int)
   gaps=rng.gamma(1/max(p['cv']**2,.03),12500000*4/max(p['pps'],1)*max(p['cv']**2,.03),n//4)
   if family=='bursty':gaps*=np.where(np.arange(n//4)%6<3,.4,1.6)
   if family=='alternating':gaps*=np.where(np.arange(n//4)%9<4,.2,1.8)
   if family=='chirp':gaps*=np.linspace(.3,1.7,n//4)
   if family=='batched':gaps*=np.where(np.arange(n//4)%7==0,3.5,.6)
   time=self.time;last=self.time
   for length,gap in zip(lens,gaps):
    time=max(time+float(gap),last+12);last=time+int(length)+8
    jobs.append((last,ch,int(length),time));starts.append(time);sizes.append(length)
  jobs.sort();delays=[];drops=0
  for arrival,ch,length,start in jobs:
   while self.finishes and self.finishes[0][0]<=arrival:
    _,old=heapq.heappop(self.finishes);self.used[old]-=1
   if self.used[ch]>=4:drops+=1;continue
   service=24+(length-42)/2
   if rng.random()<.48:service+=length-12
   if rng.random()<p['management']:service+=rng.uniform(4,100)
   if rng.random()<p['sha']/1000:service+=math.ceil((rng.choice([512,1024,2048,4096])+9)/64)*130
   self.server=max(self.server,arrival)+service;self.used[ch]+=1;heapq.heappush(self.finishes,(self.server,ch));delays.append((self.server-start)*.08)
  span=max(x[0] for x in jobs)-self.time;self.time+=span;gaps=np.diff(np.sort(starts));m=float(np.mean(sizes))
  return dict(observed_pps=n*12500000/max(span,1),mean_frame_bytes=m,frame_size_cv=float(np.std(sizes)/m),arrival_cv=float(np.std(gaps)/max(np.mean(gaps),1)),queue_overflow_ratio=drops/n,latency_p95_us=float(np.quantile(delays,.95)) if delays else max(0,(self.server-self.time)*.08)),span/12500000

def trajectory(seed,index,split):
 rng=np.random.default_rng(seed);lab=PacketLab()
 if index%4==0:faults=[]
 elif index%4 in (1,2):faults=[index%7]
 elif split=='ood':faults=list(rng.choice(7,3,replace=False))
 else:faults=list((TEST_PAIRS if split=='test' else TRAIN_PAIRS)[index%len(TEST_PAIRS if split=='test' else TRAIN_PAIRS)])
 if split=='ood' and index%4:faults=list(rng.choice(7,3,replace=False))
 family={'train':['periodic','poisson','bursty'],'validation':['batched'],'test':['chirp','alternating'],'ood':['chirp','alternating']}[split]
 family=family[index%len(family)];base=dict(pps=float(rng.uniform(2200,16000)),size=float(rng.uniform(90,1350)),size_cv=float(rng.uniform(.05,.35)),cv=float(rng.uniform(.2,1.1)),management=float(rng.uniform(.005,.1)),sha=float(rng.choice([0,1,3])),active=float(rng.uniform(.05,.35)))
 starts={j:int(rng.integers(3,12)) for j in faults};slopes={j:float(rng.uniform(.06,.18)) for j in faults};peak={j:float(rng.uniform(.5,1.)) for j in faults}
 pattern=index%3;xs=[];ys=[];durations=[]
 for t in range(WINDOWS):
  severity=np.zeros(7)
  for j in faults:
   s=np.clip((t-starts[j])*slopes[j],0,peak[j])
   if pattern==1 and t>starts[j]+6:s=max(0,s-(t-starts[j]-6)*slopes[j]*1.2)
   if pattern==2:s*=.7+.3*np.sin(t*.45)**2
   severity[j]=s
  c,l,a,nt,load,frag,mg=severity;p=dict(base)
  p.update(pps=base['pps']*(1+5*c+2*mg+.8*frag),cv=base['cv']+1.8*c+.8*mg,management=min(.95,base['management']+.8*mg),sha=base['sha']+16*c+8*load,active=min(1,base['active']+.5*load+.6*frag+.2*c))
  p['pps']*=float(np.clip(1+.08*np.sin(t*.6)+rng.normal(0,.025),.7,1.3));p['pps']=min(p['pps'],4*100e6/(8*(p['size']+20))*.9,150000)
  q,duration=lab.window(rng,p,family)
  sample=lambda prob:float(rng.binomial(2048,np.clip(prob,0,1))/2048)
  q.update(ab_unpaired_ratio=sample(.004+.55*l+.03*a),ab_payload_mismatch_ratio=sample(.0004+.2*a),fcs_error_ratio=sample(.0007+.065*l),
    ntp_rtt_ms=float((.4+9*nt+2*c)*rng.lognormal(0,.18)),ntp_offset_abs_ms=float((.08+280*nt**2)*rng.lognormal(0,.18)),clock_step_abs_ms=float((.02+45*nt**2)*rng.lognormal(0,.2)),
    loader_progress_ratio=sample(np.clip(.65*(1-.95*load)*(1-.55*l)*(1-.35*c),0,1)),loader_retry_ratio=sample(.008+.4*load+.16*l+.1*c),fragment_orphan_ratio=sample(.004+.65*frag),management_fraction=sample(p['management']),active_context_ratio=sample(p['active']),sha_jobs_per_1k_frames=float(p['sha']*rng.lognormal(0,.1)))
  xs.append([q[f] for f in FEATURES]);ys.append((severity>.22).astype(int));durations.append(duration)
 return np.asarray(xs,'f'),np.asarray(ys,'f'),np.asarray(durations,'f'),dict(seed=seed,split=split,scenario_id=split+'-'+str(index),family=family,injected_causes=[CAUSES[j] for j in faults],pattern=pattern)

def generate_split(split,count):
 base={'train':410000,'validation':510000,'test':610000,'ood':710000}[split];hist=[];labels=[];reg=[];groups=[];current=[];raw=[];rawlabels=[];metadata=[];times=[]
 for i in range(count):
  x,y,d,m=trajectory(base+i,i,split);raw.append(x);rawlabels.append(y);times.append(d);metadata.append(m)
  for t in range(HISTORY-1,WINDOWS-HORIZON):
   hist.append(x[t-HISTORY+1:t+1]);labels.append(np.r_[y[t],float(np.max(x[t+1:t+1+HORIZON,7])>=.04)]);reg.append(np.log1p(np.max(x[t+1:t+1+HORIZON,8])));groups.append(i);current.append(t)
 return dict(X=np.asarray(hist,'f'),Y=np.asarray(labels,'f'),future_log_latency=np.asarray(reg,'f'),group=np.asarray(groups,'i'),window=np.asarray(current,'i'),raw=np.asarray(raw,'f'),raw_labels=np.asarray(rawlabels,'f'),duration=np.asarray(times,'f')),metadata
