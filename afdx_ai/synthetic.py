"""Synthetic fault telemetry and an ABSTRACT shared-inspector queue simulator.

Not an RTL replacement or device timing proof. Injected cause is the label;
security reason flags, labels, group ids and future latency never enter X.
"""
import heapq,math
import numpy as np
from .schema import CLASSES,FEATURES
SEED=615665
WINDOWS=10
GROUPS={'train':64,'validation':20,'test':24,'ood':40}
FAMILIES={'train':['periodic','poisson','bursty'],
          'validation':['batched'], 'test':['chirp','alternating'], 'ood':['chirp','alternating']}

def arrivals(rng,n,mean_gap,cv,family):
    shape=1/max(cv*cv,0.01)
    gaps=rng.gamma(shape,mean_gap/shape,n)
    t=np.arange(n)
    if family=='bursty':gaps*=np.where((t//6)%2==0,0.35,1.65)
    if family=='batched':gaps*=np.where(t%7==0,3.5,0.6)
    if family=='chirp':gaps*=np.linspace(.45,1.55,n)
    if family=='alternating':gaps*=np.where((t//11)%2,1.7,.3)
    return gaps

def queue_window(rng,pps,size,size_cv,cv,sha,family,management,n=192):
    """4 independent 100Mb/s byte streams; 4 frame slots per input.

    Arrival is capture completion. Approximate service includes UDP scan,
    duplicate comparison, control overhead and occasional file hashing.
    """
    jobs=[];starts=[];sizes=[]
    for ch in range(4):
        count=n//4
        lens=np.clip(rng.normal(size,max(1,size*size_cv),count),64,1518).astype(int)
        gaps=arrivals(rng,count,12500000*4/max(pps,1),cv,family)
        last_end=0.0;time=0.0
        for length,gap in zip(lens,gaps):
            time=max(time+float(gap),last_end+12)
            wire=int(length)+8;last_end=time+wire
            jobs.append((last_end,ch,int(length),time));starts.append(time);sizes.append(length)
    jobs.sort();used=[0]*4;finishes=[];server=0.0;delays=[];dropped=0
    for arrival,ch,length,start in jobs:
        while finishes and finishes[0][0]<=arrival:
            _,done_ch=heapq.heappop(finishes);used[done_ch]-=1
        if used[ch]>=4:dropped+=1;continue
        service=24+max(0,length-42)/2
        if rng.random()<.48:service+=max(0,length-12)
        if rng.random()<management:service+=rng.uniform(4,60)
        if rng.random()<sha/1000:
            file_bytes=int(rng.choice([126,512,700,1024,2048,4096]))
            service+=math.ceil((file_bytes+9)/64)*130
        server=max(server,arrival)+service;used[ch]+=1;heapq.heappush(finishes,(server,ch))
        delays.append((server-start)*.08)
    span=max(starts)-min(starts)+float(np.mean(sizes))+20
    sorted_starts=np.sort(starts);gaps=np.diff(sorted_starts)
    return dict(observed_pps=n*12500000/span,mean_frame_bytes=float(np.mean(sizes)),
                frame_size_cv=float(np.std(sizes)/np.mean(sizes)),
                arrival_cv=float(np.std(gaps)/max(np.mean(gaps),1)),
                queue_overflow_ratio=dropped/n,
                latency_p95_us=float(np.quantile(delays,.95)))

def base_profile(rng):
    return dict(pps=float(np.exp(rng.uniform(np.log(700),np.log(12500)))) ,
                size=float(rng.uniform(80,1300)),size_cv=float(rng.uniform(.03,.45)),
                cv=float(rng.uniform(.15,1.1)),sha=float(rng.choice([0,0,1,3,8])),
                management=float(rng.uniform(0,.12)),active=float(rng.uniform(0,.55)),
                loss=float(rng.uniform(0,.015)),mismatch=float(rng.uniform(0,.001)),
                fcs=float(rng.uniform(0,.002)),rtt=float(rng.uniform(.1,4)),
                offset=float(rng.uniform(.001,.9)),step=float(rng.uniform(0,.08)),
                progress=float(rng.uniform(.08,.9)),retry=float(rng.uniform(0,.03)),
                orphan=float(rng.uniform(0,.015)))

def inject(profile,label,severity):
    p=dict(profile);s=severity
    if label=='congestion':p.update(pps=p['pps']*(2+5*s),cv=p['cv']+s*1.8,active=min(1,p['active']+.3*s),sha=p['sha']+12*s)
    if label=='link_degradation':p.update(loss=.015+.65*s,fcs=p['fcs']+s*.06,retry=p['retry']+.12*s)
    if label=='replica_divergence':p.update(mismatch=.002+.22*s,loss=p['loss']+.04*s)
    if label=='time_anomaly':p.update(offset=p['offset']+s**2*350,step=s**2*60,rtt=p['rtt']+s*10)
    if label=='loader_stall':p.update(progress=max(0,.05*(1-s)),retry=.025+.5*s,active=.4+.6*s)
    if label=='fragment_pressure':p.update(orphan=.02+.7*s,active=.55+.45*s,pps=p['pps']*(1+s),retry=p['retry']+.1*s)
    if label=='management_burst':p.update(management=.15+.8*s,pps=p['pps']*(1+2*s),cv=p['cv']+.5*s)
    p['pps']=min(p['pps'],4*100e6/(8*(p['size']+20))*.95)
    return p

def measured(rng,p,family):
    q=queue_window(rng,p['pps'],p['size'],p['size_cv'],p['cv'],p['sha'],family,p['management'])
    # Rates represent independent, noisy finite-window counts, not exact labels.
    n=4096
    rate=lambda key:float(rng.binomial(n,np.clip(p[key],0,1))/n)
    q.update(ab_unpaired_ratio=rate('loss'),ab_payload_mismatch_ratio=rate('mismatch'),
             fcs_error_ratio=rate('fcs'),ntp_rtt_ms=max(0,p['rtt']*rng.lognormal(0,.12)),
             ntp_offset_abs_ms=max(0,p['offset']*rng.lognormal(0,.17)),
             clock_step_abs_ms=max(0,p['step']*rng.lognormal(0,.2)),
             loader_progress_ratio=rate('progress'),loader_retry_ratio=rate('retry'),
             fragment_orphan_ratio=rate('orphan'),management_fraction=rate('management'),
             active_context_ratio=rate('active'),sha_jobs_per_1k_frames=max(0,p['sha']*rng.lognormal(0,.1)))
    return {f:q[f] for f in FEATURES}

def generate(split):
    rng=np.random.default_rng(SEED+list(GROUPS).index(split)*100003)
    labels=CLASSES if split!='ood' else ['unknown_compound']
    for class_index,label in enumerate(labels):
        for group in range(GROUPS[split]):
            family=FAMILIES[split][group%len(FAMILIES[split])]
            profile=base_profile(rng);severity=float(rng.uniform(.1,.95))
            faults=[label] if split!='ood' else list(rng.choice(CLASSES[1:],2,replace=False))
            for window in range(WINDOWS):
                p=dict(profile)
                # Smooth within-scenario drift; scenario never crosses a split.
                p['pps']*=float(np.clip(1+.10*np.sin(window*.7)+rng.normal(0,.03),.7,1.3))
                for fault in faults:p=inject(p,fault,severity)
                metrics=measured(rng,p,family)
                future=queue_window(rng,p['pps'],p['size'],p['size_cv'],p['cv'],p['sha'],family,p['management'])
                yield dict(scenario_id=f'{split}-{class_index:02d}-{group:04d}',window_index=window,
                           traffic_family=family,label=label,split=split,
                           **metrics,next_latency_p95_us=future['latency_p95_us'])
