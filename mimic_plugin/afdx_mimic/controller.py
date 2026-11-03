"""Stateless semantic adjudication with frame-boundary executor replacement.

This controller does not mutate any AFDX loading, fragmentation or time state.
Only the trusted integration caller may supply an original-engine decision.
"""
import concurrent.futures,copy,json,os,random,secrets,threading,time
from collections import Counter
from itertools import combinations
from .build import SPECS
from .contract import ContractError,canonical,policy,request,semantic,semantic_hash,sha

def adjudicate(records,active):
    if len(active)!=3 or len(set(active))!=3:raise ContractError('three distinct active executors required')
    seen=set();valid=[]
    for r in records:
        eid=r['executor_id']
        if eid not in active or eid in seen:continue
        seen.add(eid)
        if r['status']=='ok':valid.append(r)
    counts=Counter(semantic_hash(r['response']) for r in valid)
    winner=next((h for h,n in counts.items() if n>=2),None)
    winners=[r['executor_id'] for r in valid if semantic_hash(r['response'])==winner] if winner else []
    chosen=next((semantic(r['response']) for r in valid if semantic_hash(r['response'])==winner),None)
    return dict(status='quorum' if winner else 'no_quorum',semantic=chosen,semantic_sha256=winner,winners=winners,
      dissenters=[r['executor_id'] for r in valid if winner and r['executor_id'] not in winners],
      errors=[r['executor_id'] for r in records if r['executor_id'] in active and r['status']!='ok'])

def combine_gate(mode,quorum,baseline):
    if mode not in ('shadow','enforce') or baseline is not None and type(baseline) is not bool:raise ContractError('trusted baseline/mode')
    if baseline is None:return None
    if mode=='shadow':return baseline
    result=quorum.get('semantic')
    return baseline and result is not None and result.get('verdict')=='allow'

class MimicPlugin:
    def __init__(self,pool,initial_policy,mode='shadow',deadline_ms=None,rotation_interval=4,lab_seed=None):
        if deadline_ms is None:deadline_ms=5000 if os.name=='nt' else 500
        if mode not in ('shadow','enforce') or type(deadline_ms) is not int or not 20<=deadline_ms<=5000:raise ContractError('mode/deadline bounds')
        if type(rotation_interval) is not int or not 1<=rotation_interval<=1000:raise ContractError('rotation interval')
        self.pool=pool;self.policy=policy(initial_policy);self.mode=mode;self.deadline_ms=deadline_ms;self.interval=rotation_interval
        self.random=secrets.SystemRandom() if lab_seed is None else random.Random(lab_seed)
        self.lab_seed=lab_seed;self.lock=threading.Lock();self.generation=1;self.next_id=1 if lab_seed is not None else secrets.randbelow(2**62)+1;self.strikes={e:0 for e in SPECS};self.quarantined=set();self.events=[]
        self.active=['python_struct','c_offsets','cpp_cursor'];self.completed=0;self.decisions={};self.recovery_tests=[]
        self._initialize()

    def _selftest(self,eid):
        fixtures=json.loads((self.pool.root/'trusted_selftests.json').read_text());records=[]
        # Distinct startup challenges; these results never enter a live quorum.
        for i,item in enumerate(fixtures['vectors']):
            raw=bytes.fromhex(item['raw_hex']);data,meta=request(raw,fixtures['policy'],2**63+i,0,0,0)
            result=self.pool.execute(eid,data,meta,len(raw),time.monotonic()+(5 if os.name=='nt' else 1))
            passed=result['status']=='ok' and semantic(result['response'])==item['expected']
            records.append(dict(vector=item['id'],passed=passed,result=result))
            if not passed:break
        return dict(executor_id=eid,status='passed' if len(records)==len(fixtures['vectors']) and all(r['passed'] for r in records) else 'failed',vectors=records)

    def _initialize(self):
        self.pool.verify()
        if not hasattr(self.pool,'startup_certificates'):
            with concurrent.futures.ThreadPoolExecutor(max_workers=4) as workers:
                self.pool.startup_certificates=list(workers.map(self._selftest,SPECS))
        self.startup=copy.deepcopy(self.pool.startup_certificates)
        for r in self.startup:
            if r['status']!='passed':self.quarantined.add(r['executor_id'])
        if len(set(SPECS)-self.quarantined)<3:raise RuntimeError('not enough independently self-tested executors')
        if any(e in self.quarantined for e in self.active):self._select('startup_selftest')

    def _select(self,reason,rotate=False):
        healthy=[e for e in SPECS if e not in self.quarantined]
        choices=[list(c) for c in combinations(healthy,3)]
        alternatives=[c for c in choices if set(c)!=set(self.active)]
        if rotate and alternatives:choices=alternatives
        if not choices:
            old=list(self.active);self.active=[]
            self.events.append(dict(kind='pool_exhausted',after_request=self.completed,generation=self.generation,old_active=old,active=[],reason=reason));return
        chosen=self.random.choice(choices)
        if set(chosen)!=set(self.active):
            if self.generation==0xffffffff:raise ContractError('generation exhausted')
            old=list(self.active);self.generation+=1;self.active=chosen
            self.events.append(dict(kind='executor_switch',after_request=self.completed,generation=self.generation,old_active=old,active=list(chosen),reason=reason))

    def evaluate(self,raw,channel=0,capture_ticks=0,baseline=None):
        if not self.lock.acquire(blocking=False):raise ContractError('one in-flight frame per plugin instance')
        try:
            if self.next_id>=2**63:raise ContractError('request id exhausted')
            rid=self.next_id;self.next_id+=1;start=time.monotonic();snapshot=list(self.active)
            data,meta=request(raw,self.policy,rid,self.generation,channel,capture_ticks)
            deadline=start+self.deadline_ms/1000;records=[]
            if len(snapshot)==3:
                with concurrent.futures.ThreadPoolExecutor(max_workers=3) as workers:
                    futures=[workers.submit(self.pool.execute,e,data,meta,len(raw),deadline) for e in snapshot]
                    records=[f.result() for f in futures]
                quorum=adjudicate(records,snapshot)
            else:quorum=dict(status='no_quorum',semantic=None,semantic_sha256=None,winners=[],dissenters=[],errors=[],reason='healthy_executor_pool_exhausted')
            final=combine_gate(self.mode,quorum,baseline)
            result=dict(schema=1,meta=meta,channel=channel,capture_ticks=capture_ticks,active=snapshot,mode=self.mode,deadline_ms=self.deadline_ms,
              quorum=quorum,worker_results=records,baseline_allow=baseline,final_allow=final,
              online_device_action=False,state_commit_scope='local investigation record only',seconds=time.monotonic()-start,
              lab_faults={e:self.pool.lab_faults[e] for e in snapshot if e in self.pool.lab_faults})
            # Exactly one local result is committed for each newly assigned id.
            if rid in self.decisions:raise RuntimeError('duplicate local commit')
            self.decisions[rid]=result;self.completed+=1
            for e in set(quorum['errors']+quorum['dissenters']):
                self.strikes[e]+=1;self.quarantined.add(e)
                self.events.append(dict(kind='executor_quarantined',executor_id=e,request_id=rid,generation=meta['generation'],reason='process_or_binding_failure' if e in quorum['errors'] else 'semantic_minority',confirmed_compromise=False))
            if any(e in self.quarantined for e in self.active):self._select('quarantine')
            elif self.completed%self.interval==0:self._select('bounded_periodic_rotation',rotate=True)
            result['next_active']=list(self.active);result['next_generation']=self.generation
            return copy.deepcopy(result)
        finally:self.lock.release()

    def recover(self,eid):
        if eid not in SPECS:raise ContractError('executor identity')
        if not self.lock.acquire(blocking=False):raise ContractError('recovery requires no in-flight frame')
        try:
            self.pool.verify();test=self._selftest(eid);self.recovery_tests.append(test)
            if test['status']=='passed':
                self.quarantined.discard(eid);self.strikes[eid]=0
                self.events.append(dict(kind='executor_requalified',executor_id=eid,generation=self.generation,restoration='fresh process from unchanged trusted executable plus full golden selftest',confirmed_clean_of_all_vulnerabilities=False))
                if len(self.active)!=3:self._select('recovery')
            return copy.deepcopy(test)
        finally:self.lock.release()

    def update_policy(self,value):
        p=policy(value)
        if not self.lock.acquire(blocking=False):raise ContractError('policy update requires no in-flight frame')
        try:
            if p['epoch']!=self.policy['epoch']+1:raise ContractError('monotonic policy epoch required')
            self.policy=p;self.events.append(dict(kind='local_policy_update',epoch=p['epoch'],online_device_action=False))
        finally:self.lock.release()
