"""Typed register encoding shared by examples/host tools, not RTL oracle."""
from dataclasses import dataclass
def require(condition):
 if not condition:raise ValueError('invalid policy field')
@dataclass
class Rule:
 peer_ip:int
 local_ip:int
 rx_mac:int
 peer_mac:int
 kind:int=0
 source_port:int=0
 destination_port:int=0
 tx_mac:int=0
 fragments:bool=False
 signed_loading:bool=False
 strict_initial_time:bool=False
 min_gap:int=0
 max_mac:int=1518
 max_contexts:int=4
 timeout:int=12500000
 window:int=0
 max_frames:int=0
 def words(self):
  values=[self.peer_ip,self.local_ip,self.rx_mac,self.peer_mac,self.tx_mac]
  require(all(type(x) is int and x>=0 for x in values))
  require(self.peer_ip<2**32 and self.local_ip<2**32 and self.rx_mac<2**48 and self.peer_mac<2**48 and self.tx_mac<2**48)
  require(self.kind in range(4) and 64<=self.max_mac<=1518 and 0<=self.max_contexts<=16 and 1<=self.timeout<=0xffffffff)
  require(0<=self.source_port<=65535 and 0<=self.destination_port<=65535)
  w=[0]*16;w[0]=1|(self.kind<<2)|(int(self.fragments)<<5)|(int(self.kind==2)<<6)|(int(self.signed_loading)<<7)|(int(self.strict_initial_time)<<9)
  w[1]=self.peer_ip;w[2]=self.local_ip;w[3]=self.source_port<<16|self.destination_port;w[4]=self.rx_mac&0xffffffff;w[5]=self.rx_mac>>32;w[6]=self.peer_mac&0xffffffff;w[7]=self.peer_mac>>32;w[8]=self.min_gap;w[9]=self.max_mac;w[10]=self.max_contexts;w[11]=self.timeout;w[12]=self.window;w[13]=self.max_frames;w[14]=self.tx_mac&0xffffffff;w[15]=self.tx_mac>>32
  require(all(type(x) is int and 0<=x<=0xffffffff for x in w))
  return w
 def writes(self,index):
  require(0<=index<16)
  return [(0x100+index*64+4*k,v) for k,v in enumerate(self.words())]
COMMIT=(0x10,0x53454331)
ROLLBACK=(0x14,0x524f4c4c)
def decode_event(value):
 return dict(epoch=(value>>128)&0xffffffff,cycle=(value>>64)&0xffffffffffffffff,flags=(value>>48)&65535,rule=(value>>44)&15,channel=(value>>42)&3,allow=bool(value&(1<<41)),duplicate=bool(value&(1<<40)),phase=(value>>33)&7,length=(value>>16)&65535,sequence=(value>>8)&255,mode=value&3)
FLAGS={1:'format',2:'acl',4:'ab_content',8:'phase',16:'rate',32:'quota',64:'authorization',128:'tid_or_replay',256:'time',512:'orphan_fragment',1024:'sha256_or_length',2048:'fragment_overlap'}
