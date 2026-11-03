import os
os.environ['OPENBLAS_NUM_THREADS']='1';os.environ['OMP_NUM_THREADS']='1'
import sys,time,copy
from pathlib import Path
import numpy as np
from sklearn.ensemble import RandomForestClassifier,RandomForestRegressor
from sklearn.metrics import f1_score,average_precision_score,roc_auc_score,mean_absolute_error
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R))
from afdx_ext.common import transform,load_npz,save_npz,write_json,sigmoid,thresholds,sha,refresh_registry
from afdx_ext.nn import init_tcn,tcn,tcn_grad,Adam

def metrics(y,p,threshold,reg,target):
 binary=p>=threshold
 return dict(multilabel_macro_f1=float(f1_score(y[:,:7],binary[:,:7],average='macro',zero_division=0)),compound_exact_match=float(np.all(binary[:,:7]==y[:,:7],axis=1).mean()),warning_f1=float(f1_score(y[:,7],binary[:,7],zero_division=0)),warning_average_precision=float(average_precision_score(y[:,7],p[:,7])),warning_recall=float(binary[y[:,7]==1,7].mean()) if (y[:,7]==1).any() else 0,warning_false_positive_rate=float(binary[y[:,7]==0,7].mean()),latency_mae_us=float(mean_absolute_error(np.expm1(target),np.expm1(np.clip(reg,0,20)))))
def main():
 start=time.monotonic();a=load_npz(R/'data/train.npz');v=load_npz(R/'data/validation.npz');x=transform(a['X']);vx=transform(v['X']);mean=x.reshape(-1,18).mean(0);scale=np.maximum(x.reshape(-1,18).std(0),.03);x=(x-mean)/scale;vx=(vx-mean)/scale
 rm=a['future_log_latency'].mean();rs=max(.1,a['future_log_latency'].std());ry=(a['future_log_latency']-rm)/rs;vry=(v['future_log_latency']-rm)/rs
 p=init_tcn();opt=Adam(p,.002);rng=np.random.default_rng(19);bestloss=float('inf');best=None;history=[];stale=0
 for epoch in range(90):
  for ids in np.array_split(rng.permutation(len(x)),max(1,len(x)//96)):
   _,g=tcn_grad(p,x[ids],a['Y'][ids],ry[ids]);opt.step(p,g)
  loss,_=tcn_grad(p,vx,v['Y'],vry);history.append(loss)
  if loss<bestloss-1e-5:bestloss=loss;best=copy.deepcopy(p);stale=0
  else:stale+=1
  if epoch%10==0:print('epoch',epoch,'validation_loss',round(loss,5),flush=True)
  if stale>=14:break
 p=best;vp=tcn(p,vx);th=thresholds(v['Y'],sigmoid(vp[:,:8]));errors=np.abs(vp[:,8]*rs+rm-v['future_log_latency']);blocks=[errors[v['group']==i].max() for i in np.unique(v['group'])];rank=min(len(blocks),int(np.ceil((len(blocks)+1)*.9)));radius=float(np.sort(blocks)[rank-1])
 save_npz(R/'models/temporal.npz',p,mean=mean,scale=scale,reg_mean=rm,reg_scale=rs,thresholds=th,radius=radius)
 refresh_registry()
 # Strong same-data single-window baseline. It cannot read future or history.
 forest=RandomForestClassifier(n_estimators=80,max_depth=10,min_samples_leaf=4,random_state=21,n_jobs=2).fit(x[:,-1],a['Y'])
 reg=RandomForestRegressor(n_estimators=64,max_depth=10,min_samples_leaf=4,random_state=22,n_jobs=2).fit(x[:,-1],a['future_log_latency'])
 fp=np.column_stack([d[:,list(c).index(1)] if 1 in c else np.zeros(len(vx)) for d,c in zip(forest.predict_proba(vx[:,-1]),forest.classes_)]);fth=thresholds(v['Y'],fp)
 report=dict(domain='scenario-held-out synthetic packet-service traces',epochs=len(history),validation_loss_history=history,threshold_source='validation only',baseline='random forest with identical training groups, current window only',splits={})
 for split in ('validation','test','ood'):
  d=load_npz(R/'data'/(split+'.npz'));xx=(transform(d['X'])-mean)/scale;out=tcn(p,xx);prob=sigmoid(out[:,:8]);bp=np.column_stack([q[:,list(c).index(1)] if 1 in c else np.zeros(len(xx)) for q,c in zip(forest.predict_proba(xx[:,-1]),forest.classes_)])
  forecast=out[:,8]*rs+rm;base_reg=reg.predict(xx[:,-1]);report['splits'][split]=dict(tcn=metrics(d['Y'],prob,th,forecast,d['future_log_latency']),current_window_forest=metrics(d['Y'],bp,fth,base_reg,d['future_log_latency']))
  # Early-detection subset excludes windows where queue loss is already present.
  early=(d['X'][:,-1,7]==0)&(d['Y'][:,7]==1);below=(d['X'][:,-1,7]<.04)&(d['Y'][:,7]==1)
  report['splits'][split]['early_warning_recall_before_any_loss']=float((prob[early,7]>=th[7]).mean()) if early.any() else None;report['splits'][split]['zero_current_loss_risk_windows']=int(early.sum())
  report['splits'][split]['warning_recall_before_4pct_loss_threshold']=float((prob[below,7]>=th[7]).mean()) if below.any() else None;report['splits'][split]['below_4pct_risk_windows']=int(below.sum())
  covered=np.abs(forecast-d['future_log_latency'])<=radius;report['splits'][split]['interval_window_coverage']=float(covered.mean());report['splits'][split]['interval_whole_group_coverage']=float(np.mean([covered[d['group']==g].all() for g in np.unique(d['group'])]))
  np.savez_compressed(R/'reports'/('temporal_'+split+'_predictions.npz'),probabilities=prob,targets=d['Y'],predicted_log_latency=forecast,baseline_probabilities=bp,baseline_log_latency=base_reg,groups=d['group'])
 report['seconds']=time.monotonic()-start;report['model_sha256']=sha((R/'models/temporal.npz').read_bytes());write_json(R/'reports/temporal_evaluation.json',report);print('TEMPORAL_TRAINING_PASS',report['splits']['test'],flush=True)
if __name__=='__main__':main()
