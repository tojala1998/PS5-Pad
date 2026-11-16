[CmdletBinding()]
param(
    [string]$IosSdk,
    [string]$Distribution = 'Ubuntu-24.04',
    [switch]$Transfer
)
$ErrorActionPreference = 'Stop'
function Convert-ToWslPath([string]$Value) {
    if ($Value.StartsWith('/')) { return $Value }
    $converted = & wsl.exe --distribution $Distribution --exec wslpath -u $Value
    if ($LASTEXITCODE -ne 0) { throw 'Could not convert a build path for WSL.' }
    return ($converted | Out-String).Trim()
}
if (-not $IosSdk) {
    $candidates = @((Join-Path $PSScriptRoot 'work\ios-sdks\iPhoneOS16.5.sdk'), (Join-Path (Split-Path $PSScriptRoot -Parent) 'ios-sdks\iPhoneOS16.5.sdk'))
    $IosSdk = $candidates | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'SDKSettings.plist') } | Select-Object -First 1
    if (-not $IosSdk) { throw 'Pass -IosSdk with the path to your iPhoneOS SDK.' }
}
$linuxRoot = Convert-ToWslPath $PSScriptRoot
$linuxSdk = Convert-ToWslPath $IosSdk
& wsl.exe --distribution $Distribution --cd $linuxRoot --exec bash tools/build.sh $linuxSdk
if ($LASTEXITCODE -ne 0) { throw 'Build or verification failed.' }
if ($Transfer) {
    [xml]$info = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'app\Info.plist') -Raw
    $version = $info.SelectSingleNode('/plist/dict/key[text()="CFBundleShortVersionString"]/following-sibling::string[1]').InnerText
    & (Join-Path $PSScriptRoot 'Transfer-IPA.ps1') -Ipa (Join-Path $PSScriptRoot ('dist\PS5-Pad-'+$version+'-unsigned.ipa'))
}
