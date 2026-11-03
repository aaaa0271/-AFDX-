param([string]$Python='', [string]$ResultsRoot='', [switch]$RequireConformance,
      [switch]$Demo, [switch]$ModelsimOnly, [ValidateRange(1,8)][int]$Workers=1)
$ErrorActionPreference='Stop'
$env:PYTHONDONTWRITEBYTECODE='1'
if(!$Python){$Python=$env:AFDX_PYTHON}
if(!$Python){$candidate=Get-Command python.exe -ErrorAction SilentlyContinue;if($candidate -and $candidate.Source -notlike '*WindowsApps*'){$Python=$candidate.Source}}
if(!$Python){$Python=Join-Path $env:LOCALAPPDATA 'Programs\Python\Python314\python.exe'}
if(!(Test-Path -LiteralPath $Python)){throw 'Pass -Python or set AFDX_PYTHON to a Python 3.10+ executable.'}
if(!$ResultsRoot){$ResultsRoot=$env:AFDX_RESULTS_ROOT}
if(!$ResultsRoot){$ResultsRoot=Join-Path $PSScriptRoot 'results'}
$sourcePath=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
$outputPath=[IO.Path]::GetFullPath($ResultsRoot).TrimEnd('\')
$allowedResults=Join-Path $sourcePath 'results'
if($outputPath.Equals($sourcePath,[StringComparison]::OrdinalIgnoreCase) -or ($outputPath.StartsWith($sourcePath+'\',[StringComparison]::OrdinalIgnoreCase) -and !($outputPath.Equals($allowedResults,[StringComparison]::OrdinalIgnoreCase) -or $outputPath.StartsWith($allowedResults+'\',[StringComparison]::OrdinalIgnoreCase)))){throw 'Use the results subdirectory or an external results directory.'}
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$log=Join-Path $outputPath "launcher_$stamp.log"
$err=Join-Path $outputPath "launcher_$stamp.stderr.log"
$arguments=@('-B','-u',('"'+(Join-Path $PSScriptRoot 'scripts\run_all.py')+'"'),'--output-root',('"'+$outputPath+'"'))
$arguments+=@('--workers', $Workers)
if($RequireConformance){$arguments+='--require-conformance'}
if($Demo){$arguments+=@('--hdl-only','--tests','tb_foundation_shared_joint','tb_integration_subvl_mac','tb_integration_multi_services')}
elseif($ModelsimOnly){$arguments+='--hdl-only'}
$p=Start-Process -FilePath $Python -ArgumentList $arguments -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $log -RedirectStandardError $err
Get-Content -LiteralPath $log
if($p.ExitCode -ne 0){Get-Content -LiteralPath $err;throw "Verification exit=$($p.ExitCode). See $log. Exit 2 indicates unresolved full-standard conformance."}
Write-Host "Verification records: $outputPath"
