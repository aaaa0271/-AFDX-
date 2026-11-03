import json,os,shutil,subprocess
from pathlib import Path
from .contract import canonical,sha

SPECS={'python_struct':('python','executors/python_struct.py'),'c_offsets':('native','c_offsets'),
       'cpp_cursor':('native','cpp_cursor'),'python_table':('python','executors/python_table.py')}
def source_files(root):
    return sorted([*root.joinpath('executors').glob('*.py'),*root.joinpath('executors').glob('*.c'),*root.joinpath('executors').glob('*.cpp'),root/'afdx_mimic/launch.py',root/'afdx_mimic/windows_limits.py',root/'trusted_selftests.json'])
def build(root,output,cc=None,cxx=None):
    root=Path(root).resolve();output=Path(output).resolve()
    if output.exists():raise ValueError('choose a new build directory')
    cc=cc or shutil.which('gcc');cxx=cxx or shutil.which('g++')
    if not cc or not cxx:raise RuntimeError('gcc and g++ required; no executor will be silently omitted')
    output.mkdir(parents=True)
    sources={str(p.relative_to(root)):sha(p.read_bytes()) for p in source_files(root)};commands=[]
    for name,compiler,flags,source in [('c_offsets',cc,['-std=c11'],'executors/c_offsets.c'),('cpp_cursor',cxx,['-std=c++17'],'executors/cpp_cursor.cpp')]:
        binary=name+('.exe' if os.name=='nt' else '')
        argv=[compiler,*flags,'-O2','-Wall','-Wextra','-Werror',*(['-fstack-protector-strong'] if os.name=='posix' else []),*(['-static'] if os.name=='nt' else []),str(root/source),'-o',str(output/binary)]
        r=subprocess.run(argv,capture_output=True,text=True,timeout=45,creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        (output/(name+'.compile.log')).write_text(r.stdout+r.stderr)
        commands.append(dict(argv=argv,exit_code=r.returncode))
        if r.returncode:raise RuntimeError('native compile failed: '+name+'; inspect compile.log')
    runtimes={}
    binaries={name:sha((output/(name+('.exe' if os.name=='nt' else ''))).read_bytes()) for name in ('c_offsets','cpp_cursor')}
    if sources!={str(p.relative_to(root)):sha(p.read_bytes()) for p in source_files(root)}:raise RuntimeError('sources changed during build')
    info=dict(schema=1,source_hashes=sources,binary_hashes=binaries,runtime_hashes=runtimes,commands=commands,executors=list(SPECS),compiler_versions={})
    for name,tool in [('cc',cc),('cxx',cxx)]:
        info['compiler_versions'][name]=subprocess.run([tool,'--version'],capture_output=True,text=True,timeout=10,creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0).stdout.splitlines()[0]
    (output/'build.json').write_text(json.dumps(info,indent=2)+'\n');return info
