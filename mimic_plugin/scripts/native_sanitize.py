"""Execute native parsers with GCC undefined-behavior/bounds instrumentation."""
import json,os,random,shutil,subprocess,sys
from pathlib import Path
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R));sys.path.insert(0,str(R/'scripts'))
from fixtures import POLICY,vectors
from afdx_mimic.contract import canonical,decode_response,request,semantic,sha

def check_native(output):
    out=Path(output).resolve()
    if out.exists():raise ValueError('new sanitizer output required')
    out.mkdir(parents=True);rows=[(n,raw,w) for n,raw,w in vectors()];rng=random.Random(167)
    for i in range(48):rows.append(('raw_'+str(i),rng.randbytes(rng.randrange(2049)),None))
    results=[];commands=[]
    for name,compiler,standard,source in [('c_offsets','gcc','c11','c_offsets.c'),('cpp_cursor','g++','c++17','cpp_cursor.cpp')]:
        tool=shutil.which(compiler)
        if not tool:raise RuntimeError('compiler unavailable for sanitizer')
        exe=out/name;argv=[tool,'-std='+standard,'-O1','-g','-fsanitize=undefined,bounds','-fno-sanitize-recover=all',str(R/'executors'/source),'-o',str(exe)]
        r=subprocess.run(argv,capture_output=True,text=True,timeout=45);(out/(name+'.compile.log')).write_text(r.stdout+r.stderr);commands.append(dict(argv=argv,exit_code=r.returncode))
        if r.returncode:raise RuntimeError('sanitizer compile failed')
        for i,(ident,raw,want) in enumerate(rows):
            data,meta=request(raw,POLICY,i+1,1);r=subprocess.run([str(exe)],input=data,capture_output=True,timeout=2)
            if r.returncode or r.stderr:raise RuntimeError('native sanitizer finding: '+name+'/'+ident+': '+r.stderr.decode(errors='replace')[:200])
            d=decode_response(r.stdout,meta,len(raw))
            if want is not None and semantic(d)!=want:raise RuntimeError('golden mismatch under sanitizer')
            results.append(dict(executor=name,vector=ident,input_sha256=sha(raw),response_sha256=sha(r.stdout),reason=d['reason'],status='PASS'))
    result=dict(status='PASS',native_executors=2,executions=len(results),instrumentation='GCC undefined,bounds with no recovery; not exhaustive memory-safety proof',results=results,commands=commands)
    (out/'summary.json').write_text(json.dumps(result,indent=2)+'\n');return result
