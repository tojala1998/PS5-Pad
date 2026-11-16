[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Ipa,
    [string]$Python = (Join-Path $env:LOCALAPPDATA 'Programs\iPhoneDeviceTools\pymobiledevice3\Scripts\python.exe')
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Python)) { throw 'Pass -Python with a Python environment that has pymobiledevice3 installed.' }
& $Python (Join-Path $PSScriptRoot 'tools\stage_ipa.py') (Resolve-Path -LiteralPath $Ipa).Path
if ($LASTEXITCODE -ne 0) { throw 'The IPA was not verified on the iPhone. Check USB connection and device trust.' }
