param([string]$Python='',[string]$ResultsRoot='')
& (Join-Path $PSScriptRoot 'run_all.ps1') -Python $Python -ResultsRoot $ResultsRoot -Demo