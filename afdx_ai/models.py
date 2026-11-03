"""Plain JSON tree export and NumPy inference, without pickle/joblib loading."""
import hashlib,math
from pathlib import Path
import numpy as np
from .schema import InputError,strict_json

def average_path(n):
    n=np.asarray(n,dtype=float);out=np.zeros_like(n);out[n==2]=1
    mask=n>2;out[mask]=2*(np.log(n[mask]-1)+np.euler_gamma)-2*(n[mask]-1)/n[mask]
    return out

def export_forest(model,features,kind):
    result={'schema':1,'kind':kind,'features':features,'trees':[]}
    if kind=='classifier':result['classes']=[str(x) for x in model.classes_]
    if kind=='isolation':result['max_samples']=int(model.max_samples_)
    for estimator in model.estimators_:
        t=estimator.tree_;value=t.value[:,0,:]
        if kind=='classifier':value=value/value.sum(axis=1,keepdims=True)
        tree=dict(feature=t.feature.tolist(),threshold=t.threshold.tolist(),
                  left=t.children_left.tolist(),right=t.children_right.tolist(),
                  samples=t.n_node_samples.tolist())
        if kind!='isolation':tree['value']=value.tolist()
        result['trees'].append(tree)
    return result

class Forest:
    def __init__(self,d):
        if not isinstance(d,dict) or d.get('schema')!=1 or d.get('kind') not in ('classifier','regressor','isolation'):
            raise InputError('model schema')
        self.kind=d['kind'];self.features=d['features'];self.classes=d.get('classes',[])
        if not self.features or len(self.features)!=len(set(self.features)):raise InputError('model feature order')
        self.trees=[]
        if not 1<=len(d['trees'])<=256:raise InputError('model tree count')
        for raw in d['trees']:
            count=len(raw['feature'])
            if not 1<=count<=20000:raise InputError('tree node count')
            for key in ('threshold','left','right','samples'):
                if len(raw[key])!=count:raise InputError('tree array lengths')
            t={k:np.asarray(v) for k,v in raw.items()}
            depth=np.zeros(count,dtype=int);parents=np.zeros(count,dtype=int)
            if not np.all(np.isfinite(t['threshold'])):raise InputError('tree threshold')
            for i in range(count):
                if t['feature'][i]>=0:
                    if t['feature'][i]>=len(self.features):raise InputError('tree feature index')
                    for child in (int(t['left'][i]),int(t['right'][i])):
                        if not i<child<count:raise InputError('tree cycle/index')
                        parents[child]+=1;depth[child]=depth[i]+1
                elif t['left'][i]!=-1 or t['right'][i]!=-1:raise InputError('leaf children')
            if np.any(parents[1:]!=1) or depth.max()>32:raise InputError('tree shape/depth')
            if not np.all(t['samples']>=1):raise InputError('tree leaf samples')
            if self.kind!='isolation':
                values=np.asarray(raw['value'],dtype=float)
                expected=len(self.classes) if self.kind=='classifier' else 1
                if values.shape!=(count,expected) or not np.all(np.isfinite(values)):raise InputError('tree values')
                if self.kind=='classifier' and (np.any(values<0) or not np.allclose(values.sum(axis=1),1)):
                    raise InputError('class vote values')
                t['value']=values
            self.trees.append(t)
        self.max_samples=d.get('max_samples',256)
        if self.kind=='isolation' and not 2<=self.max_samples<=100000:raise InputError('isolation sample count')

    def predict(self,x):
        x=np.asarray(x,dtype=np.float32)
        if x.ndim!=2 or x.shape[1]!=len(self.features) or not np.all(np.isfinite(x)):raise InputError('inference matrix')
        if self.kind=='classifier':result=np.zeros((len(x),len(self.classes)))
        else:result=np.zeros(len(x))
        for tree in self.trees:
            nodes=np.zeros(len(x),dtype=int);depth=np.zeros(len(x))
            for _ in range(33):
                active=tree['feature'][nodes]>=0
                if not active.any():break
                ids=np.flatnonzero(active);f=tree['feature'][nodes[ids]].astype(int)
                go_left=x[ids,f]<=tree['threshold'][nodes[ids]]
                nodes[ids]=np.where(go_left,tree['left'][nodes[ids]],tree['right'][nodes[ids]])
                depth[ids]+=1
            if self.kind=='isolation':result+=depth+average_path(tree['samples'][nodes])
            elif self.kind=='regressor':result+=tree['value'][nodes,0]
            else:result+=tree['value'][nodes]
        result/=len(self.trees)
        if self.kind=='isolation':result=-np.power(2.0,-result/float(average_path([self.max_samples])[0]))
        return result

def load_models(directory):
    directory=Path(directory);registry=strict_json(directory/'registry.json')
    if registry.get('schema')!=1:raise InputError('registry version')
    models={}
    for name in ('diagnosis','anomaly','latency'):
        filename=name+'.json';path=directory/filename
        if path.stat().st_size>32*1024*1024:raise InputError('model too large')
        if hashlib.sha256(path.read_bytes()).hexdigest()!=registry['sha256'][filename]:raise InputError('model hash mismatch: '+name)
        models[name]=Forest(strict_json(path))
    return registry,models
