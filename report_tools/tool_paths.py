"""Locate tools without another developer's project paths."""
import os
import shutil
from pathlib import Path
def tool(name, env, candidates=()):
    value=os.environ.get(env) or shutil.which(name)
    if value:return Path(value)
    for candidate in candidates:
        if Path(candidate).is_file():return Path(candidate)
    return Path(name)
def modelsim():
    return tool('vsim','AFDX_MODELSIM',('C:/modeltech64_2020.4/win64/vsim.exe',))
def elinx():
    return tool('quartus_map','AFDX_ELINX',('D:/eLinx3.0/bin/Passkey/bin/quartus_map.exe',))
