"""Reassemble target-emitted TFTP bytes independently of the HDL test peer."""
import csv
import hashlib
import json
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'host'))
from download615a import DownloadReceiver,parse_directory


def audit(path):
    receiver=DownloadReceiver();duplicates=0;unknown=0;completed=[]
    for row in csv.DictReader(Path(path).open(encoding='ascii')):
        if int(row['sport'])!=44001:continue
        packet=bytes.fromhex(row['payload_hex'])
        if len(packet)!=int(row['length']):raise ValueError('capture length')
        op=int.from_bytes(packet[:2],'big')
        if op==5:
            if packet!=b'\0\5\0\5\0':raise ValueError('unknown-TID error')
            unknown+=1;continue
        before=receiver.block
        _,event=receiver.receive(packet)
        if op==3 and receiver.block==before:duplicates+=1
        if event:completed.append(event)
    data=[e for e in completed if e['name'] in ('A.LUP','B.LUP')]
    if [e['name'] for e in data]!=['A.LUP','B.LUP','A.LUP']:raise ValueError('selected transfer order')
    for event in data:
        if event['data']!=(ROOT/'tb'/event['name']).read_bytes():raise ValueError('downloaded file content')
    lists=[e for e in completed if e['name']=='TARGET.LNL']
    if len(lists)!=1 or [r['name'] for r in parse_directory(lists[0]['data'])]!=['A.LUP','B.LUP']:raise ValueError('LNL directory')
    statuses=[e['status'] for e in completed if 'status' in e]
    if [s['code'] for s in statuses]!=[1,2,2,3,1,2,3]:raise ValueError('LNS lifecycle')
    for status in (s for s in statuses if s['code']==3):
        if status['ratio']!=100 or any(f['code']!=3 for f in status['files']):raise ValueError('premature completion')
    if duplicates<1 or unknown!=1:raise ValueError('retry/TID coverage missing')
    return dict(status='PASS',source='captured_target_UDP_bytes',
                download_modes=['operator_defined','media_defined'],
                files=[dict(name=e['name'],length=len(e['data']),sha256=hashlib.sha256(e['data']).hexdigest()) for e in data],
                duplicate_blocks=duplicates,unknown_tid_errors=unknown,status_codes=[s['code'] for s in statuses])


if __name__=='__main__':
    result=audit(sys.argv[1]);print(json.dumps(result,indent=2))
    Path(sys.argv[1]).with_name('download_audit.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
