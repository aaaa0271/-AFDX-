"""Explicit laboratory response faults; unreachable from untrusted case input.

The real selected executor runs first. These faults simulate compromised output
or process failure; they are not exploits or evidence of a real compromise.
"""
import hashlib,json,os,subprocess,sys,time

def main():
    kind,program,mode=sys.argv[1:4];raw=sys.stdin.buffer.read(4097)
    if mode=='crash':os._exit(23)
    if mode=='timeout':time.sleep(10);return
    argv=[sys.executable,'-I',program] if kind=='python' else [program]
    r=subprocess.run(argv,input=raw,capture_output=True,timeout=5 if os.name=='nt' else 1,creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
    if r.returncode:sys.exit(r.returncode)
    sys.stderr.write('LAB_INJECTION='+mode+' BASE_RESULT_SHA256='+hashlib.sha256(r.stdout).hexdigest()+'\n')
    if mode=='oversize':sys.stdout.write('X'*9000);return
    if mode=='malformed':sys.stdout.write('{invalid');return
    d=json.loads(r.stdout)
    if mode=='stale_epoch':d['epoch']^=1
    elif mode=='stale_generation':d['generation']^=1
    elif mode=='wrong_input':d['input_hash']='0'*64
    elif mode=='wrong_semantics':d['fields'][2]^=1
    elif mode=='forged_allow':
        count=raw[29];wire=raw[96+33*count:];get=lambda p,n:int.from_bytes(wire[p:p+n],'big')
        total=get(24,2);payload=wire[50:22+total]
        d.update(verdict='allow',reason='OK',rule_id=int.from_bytes(raw[96:98],'big'),fields=[get(8,6),get(14,6),get(34,4),get(38,4),get(26,2),wire[-5],get(42,2),get(44,2),len(payload)+8],payload_hex=payload.hex())
    else:raise ValueError('unknown laboratory fault')
    print(json.dumps(d,separators=(',',':')))

if __name__=='__main__':main()
