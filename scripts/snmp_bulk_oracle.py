"""Independent RFC3416 GetBulk reference using PySNMP response encoding."""
from pathlib import Path
import sys
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R/'vendor'))
from pysnmp.proto.api import v2c
from pyasn1.codec.ber import encoder
BASE=(1,3,6,1,4,1,32473,1,1);KNOWN=[BASE+(i,) for i in range(1,26)]

def expected_message(vector,values,snapshot_count):
 response=v2c.ResponsePDU();v2c.apiPDU.set_defaults(response);v2c.apiPDU.set_request_id(response,vector['rid'])
 message=v2c.Message();v2c.apiMessage.set_defaults(message);v2c.apiMessage.set_community(message,vector['community']);v2c.apiMessage.set_pdu(message,response)
 def successor(q):
  q=tuple(q);wanted=next((oid for oid in KNOWN if oid>q),None)
  if wanted is None:return q,v2c.EndOfMibView('')
  index=wanted[-1];value=snapshot_count if index==2 else values[index-1]
  typed=v2c.Integer(value) if index in (1,4,5) else v2c.TimeTicks(value) if index==3 else v2c.Counter32(value)
  return wanted,typed
 queries=[tuple(q) for q in vector['oids']];n=min(max(0,vector['nonrepeaters']),len(queries));m=max(0,vector['repetitions'])
 def bindings():
  for q in queries[:n]:yield successor(q)
  columns=queries[n:]
  # A 512-byte PDU cannot encode more than512 nonempty bindings. This is a
  # resource bound on the oracle, not a substitution for the wire max-repetitions.
  for _ in range(min(m,512)):
   for j,q in enumerate(columns):
    binding=successor(q);columns[j]=binding[0];yield binding
 accepted=[]
 for binding in bindings():
  trial=accepted+[binding];v2c.apiPDU.set_varbinds(response,trial)
  if len(encoder.encode(message))>512:break
  accepted=trial
 v2c.apiPDU.set_varbinds(response,accepted)
 return encoder.encode(message)