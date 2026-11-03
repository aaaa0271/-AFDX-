"""Small actual trainable NumPy networks; inference needs no ML framework."""
import numpy as np
from .common import sigmoid,softmax

class Adam:
 def __init__(self,params,lr=.002):self.m={k:np.zeros_like(v) for k,v in params.items()};self.v={k:np.zeros_like(v) for k,v in params.items()};self.t=0;self.lr=lr
 def step(self,p,g):
  self.t+=1;norm=np.sqrt(sum(float(np.square(v).sum()) for v in g.values()));scale=min(1,5/max(norm,1e-9))
  for k in p:
   grad=g[k]*scale;self.m[k]=.9*self.m[k]+.1*grad;self.v[k]=.999*self.v[k]+.001*grad*grad
   p[k]-=self.lr*(self.m[k]/(1-.9**self.t))/(np.sqrt(self.v[k]/(1-.999**self.t))+1e-8)

def init_mlp(inputs,outputs,hidden=32,seed=7):
 r=np.random.default_rng(seed)
 return dict(W1=(r.normal(size=(inputs,hidden))*np.sqrt(2/inputs)).astype('f'),b1=np.zeros(hidden,'f'),W2=(r.normal(size=(hidden,outputs))*.1).astype('f'),b2=np.zeros(outputs,'f'))
def mlp(p,x):return np.maximum(x@p['W1']+p['b1'],0)@p['W2']+p['b2']
def mlp_grad(p,x,y,kind='mse'):
 z=x@p['W1']+p['b1'];h=np.maximum(z,0);out=h@p['W2']+p['b2'];b=len(x)
 if kind=='bce':
  loss=np.mean(np.logaddexp(0,out)-y*out);d=(sigmoid(out)-y)/out.size
 elif kind=='ce':
  pr=softmax(out);loss=-np.log(np.maximum(pr[np.arange(b),y],1e-9)).mean();d=pr;d[np.arange(b),y]-=1;d/=b
 else:loss=np.mean((out-y)**2);d=2*(out-y)/out.size
 dh=d@p['W2'].T;dz=dh*(z>0)
 return float(loss),dict(W2=h.T@d,b2=d.sum(0),W1=x.T@dz,b1=dz.sum(0))
def train_mlp(x,y,vx,vy,outputs,epochs=80,kind='mse',hidden=32,seed=7):
 p=init_mlp(x.shape[1],outputs,hidden,seed);opt=Adam(p);rng=np.random.default_rng(seed);history=[];best=None;bestloss=float('inf');patience=0
 for epoch in range(epochs):
  for ids in np.array_split(rng.permutation(len(x)),max(1,(len(x)+127)//128)):
   _,g=mlp_grad(p,x[ids],y[ids],kind);opt.step(p,g)
  loss,_=mlp_grad(p,vx,vy,kind);history.append(loss)
  if loss<bestloss-1e-5:bestloss=loss;best={k:v.copy() for k,v in p.items()};patience=0
  else:patience+=1
  if patience>=14:break
 return best,dict(epochs=len(history),validation_loss=bestloss,loss_history=history)

def conv(x,w,b,dilation):
 out=np.broadcast_to(b,(x.shape[0],x.shape[1],len(b))).copy()
 for k in range(len(w)):
  offset=k*dilation
  if offset==0:out+=x@w[k]
  else:out[:,offset:]+=x[:,:-offset]@w[k]
 return out
def conv_back(x,w,dout,dilation):
 dx=np.zeros_like(x);dw=np.zeros_like(w)
 for k in range(len(w)):
  offset=k*dilation;xx=x if offset==0 else x[:,:-offset];dd=dout if offset==0 else dout[:,offset:]
  dw[k]=np.einsum('btf,btc->fc',xx,dd)
  if offset==0:dx+=dd@w[k].T
  else:dx[:,:-offset]+=dd@w[k].T
 return dx,dw,dout.sum((0,1))
def init_tcn(features=18,channels=16,outputs=9,seed=99):
 r=np.random.default_rng(seed)
 return dict(K1=(r.normal(size=(3,features,channels))*np.sqrt(2/(features*3))).astype('f'),b1=np.zeros(channels,'f'),K2=(r.normal(size=(3,channels,channels))*np.sqrt(2/(channels*3))).astype('f'),b2=np.zeros(channels,'f'),W=(r.normal(size=(channels*2,outputs))*.1).astype('f'),b=np.zeros(outputs,'f'))
def tcn(p,x,cache=False):
 a=conv(x,p['K1'],p['b1'],1);h=np.maximum(a,0);b=conv(h,p['K2'],p['b2'],2);z=np.maximum(b,0);rep=np.concatenate([z[:,-1],z.mean(1)],axis=1);out=rep@p['W']+p['b']
 return (out,(a,h,b,z,rep)) if cache else out
def tcn_grad(p,x,y,regression):
 out,(a,h,b,z,rep)=tcn(p,x,True);d=np.zeros_like(out)
 bce=np.mean(np.logaddexp(0,out[:,:8])-y*out[:,:8]);mse=np.mean((out[:,8]-regression)**2)
 d[:,:8]=(sigmoid(out[:,:8])-y)/y.size;d[:,8]=.6*(out[:,8]-regression)/len(x)
 g=dict(W=rep.T@d,b=d.sum(0));dr=d@p['W'].T;c=z.shape[-1];dz=np.broadcast_to(dr[:,None,c:]/z.shape[1],z.shape).copy();dz[:,-1]+=dr[:,:c]
 dh,g['K2'],g['b2']=conv_back(h,p['K2'],dz*(b>0),2)
 _,g['K1'],g['b1']=conv_back(x,p['K1'],dh*(a>0),1)
 return float(bce+.3*mse),g
