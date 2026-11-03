import json,os,signal,subprocess,sys,tempfile,time
from pathlib import Path
from .build import SPECS,source_files
from .contract import ContractError,MAX_OUTPUT,decode_response,sha

FAULTS={'crash','timeout','oversize','malformed','stale_epoch','stale_generation','wrong_input','wrong_semantics','forged_allow'}
class WorkerPool:
    def __init__(self,root,build_dir):
        self.root=Path(root).resolve();self.build=Path(build_dir).resolve();self.info=json.loads((self.build/'build.json').read_text());self.lab_faults={}
        self.temp=self.build/'worker_tmp';self.temp.mkdir(exist_ok=True);self.verify()
    def verify(self):
        now={str(p.relative_to(self.root)):sha(p.read_bytes()) for p in source_files(self.root)}
        if now!=self.info['source_hashes']:raise ContractError('worker source trust check failed; rebuild from trusted release')
        if set(self.info['binary_hashes'])!={'c_offsets','cpp_cursor'}:raise ContractError('native inventory')
        for name,h in self.info['binary_hashes'].items():
            if sha((self.build/(name+('.exe' if os.name=='nt' else ''))).read_bytes())!=h:raise ContractError('worker executable trust check failed')
        for name,h in self.info.get('runtime_hashes',{}).items():
            if Path(name).name!=name or sha((self.build/name).read_bytes())!=h:raise ContractError('worker runtime trust check failed')
    def set_lab_fault(self,eid,mode):
        if eid not in SPECS or mode is not None and mode not in FAULTS:raise ContractError('laboratory fault allowlist')
        if mode is None:self.lab_faults.pop(eid,None)
        else:self.lab_faults[eid]=mode
    def execute(self,eid,data,meta,wire_length,deadline):
        start=time.monotonic();record=dict(executor_id=eid,status='error',response=None,stdout='',stderr='',seconds=0.0,lab_injection=self.lab_faults.get(eid))
        proc=None;job=None
        try:
            if eid not in SPECS:raise ContractError('executor allowlist')
            self.verify();kind,relative=SPECS[eid];program=self.root/relative if kind=='python' else self.build/(relative+('.exe' if os.name=='nt' else ''))
            if eid in self.lab_faults:
                argv=[sys.executable,'-I',str(self.root/'afdx_mimic/launch.py'),str(self.root/'executors/lab_proxy.py'),'python',kind,str(program),self.lab_faults[eid]]
            else:argv=[sys.executable,'-I',str(self.root/'afdx_mimic/launch.py'),str(program),kind]
            if os.name=='nt':
                if eid in self.lab_faults:argv=[sys.executable,'-I',str(self.root/'executors/lab_proxy.py'),kind,str(program),self.lab_faults[eid]]
                else:argv=[sys.executable,'-I',str(program)] if kind=='python' else [str(program)]
            remaining=deadline-time.monotonic()
            if remaining<=0:raise subprocess.TimeoutExpired(argv,0)
            env={'PATH':os.defpath,'LANG':'C','PYTHONHASHSEED':'0','PYTHONDONTWRITEBYTECODE':'1','PYTHONNOUSERSITE':'1'}
            if os.name=='nt':
                from .windows_limits import WorkerJob
                env.update({k:os.environ[k] for k in ('SystemRoot','WINDIR','TEMP','TMP') if k in os.environ})
            # Immutable bounded input files avoid cross-worker inherited pipe
            # writers delaying EOF on Windows. Each process owns its handle.
            with tempfile.TemporaryFile(dir=self.temp) as stdin,tempfile.TemporaryFile(dir=self.temp) as stdout,tempfile.TemporaryFile(dir=self.temp) as stderr:
                stdin.write(data);stdin.seek(0)
                proc=subprocess.Popen(argv,stdin=stdin,stdout=stdout,stderr=stderr,cwd=self.temp,env=env,start_new_session=True,close_fds=True,creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
                if os.name=='nt':job=WorkerJob(proc)
                try:
                    while proc.poll() is None:
                        remaining=deadline-time.monotonic()
                        if remaining<=0:raise subprocess.TimeoutExpired(argv,0)
                        if os.fstat(stdout.fileno()).st_size>MAX_OUTPUT or os.fstat(stderr.fileno()).st_size>4096:
                            raise ContractError('worker output budget exceeded')
                        try:proc.wait(timeout=min(.01,remaining))
                        except subprocess.TimeoutExpired:pass
                except subprocess.TimeoutExpired:
                    if job is not None:job.kill()
                    elif os.name=='posix':os.killpg(proc.pid,signal.SIGKILL)
                    else:proc.kill()
                    proc.wait();raise
                stdout.seek(0);raw=stdout.read(MAX_OUTPUT+1);stderr.seek(0);errors=stderr.read(4096)
                record.update(stdout=raw.decode('utf8',errors='replace'),stderr=errors.decode('utf8',errors='replace'),exit_code=proc.returncode)
                if time.monotonic()>deadline:raise subprocess.TimeoutExpired(argv,0)
                if proc.returncode:raise ContractError('worker process exit '+str(proc.returncode))
                response=decode_response(raw,meta,wire_length);record.update(status='ok',response=response)
        except subprocess.TimeoutExpired:record.update(status='timeout',reason='shared request deadline exceeded')
        except Exception as e:record.update(status='error',reason=type(e).__name__+': '+str(e)[:240])
        finally:
            if proc is not None and proc.poll() is None:
                if job is not None:job.kill()
                elif os.name=='posix':os.killpg(proc.pid,signal.SIGKILL)
                else:proc.kill()
                proc.wait()
            if job is not None:job.close()
            if proc is not None and proc.stdin is not None and not proc.stdin.closed:proc.stdin.close()
            record['seconds']=time.monotonic()-start
        return record
