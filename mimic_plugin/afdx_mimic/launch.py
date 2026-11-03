"""Resource limits for known worker programs; this is not an OS security sandbox."""
import os,sys
if os.name=='posix':
 import resource
 resource.setrlimit(resource.RLIMIT_CPU,(2,2))
 resource.setrlimit(resource.RLIMIT_AS,(256*1024*1024,256*1024*1024))
 resource.setrlimit(resource.RLIMIT_FSIZE,(1024*1024,1024*1024))
 resource.setrlimit(resource.RLIMIT_NOFILE,(32,32))
 resource.setrlimit(resource.RLIMIT_CORE,(0,0))
program=sys.argv[1]
args=[sys.executable,'-I',program,*sys.argv[3:]] if sys.argv[2]=='python' else [program,*sys.argv[3:]]
if os.name=='nt':
 import subprocess
 raise SystemExit(subprocess.run(args,creationflags=subprocess.CREATE_NO_WINDOW).returncode)
else:os.execv(args[0],args)
