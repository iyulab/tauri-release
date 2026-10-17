#!/usr/bin/env pwsh
# The bundler's sign hook (`bundle.windows.signCommand`) for bundling twice around a separate signing
# job. It signs nothing. The files the bundler hands it that are signed outside the bundle are:
#
#   - the uninstaller — the call `makensis` makes (it is among the hook's parents) for a file that is
#     not the installer; makensis gives a temporary name, so it is told by its caller, not its name;
#   - the NSIS plugins — the DLLs under `nsis\...\Plugins\` the bundler signs before compiling.
#
#   hook.ps1 collect <file>      copy such a file to $env:TAURI_RELEASE_EXTRAS (uninstall.exe, plugins/<name>)
#   hook.ps1 substitute <file>   replace such a file by its signed copy from $env:TAURI_RELEASE_SIGNED
#
# Every other file (the app executable, signed before bundling; the installer, signed after) is left
# alone. Each call is logged to $env:TAURI_RELEASE_EXTRAS/hook.log as one JSON object. `makensis`
# ignores the hook's exit code, so a file this hook missed shows up only in the installed-copy check
# that follows — which is why that check exists.
param(
    [Parameter(Mandatory)] [ValidateSet('collect', 'substitute')] [string] $Mode,
    [Parameter(Mandatory)] [string] $File
)

$ErrorActionPreference = 'Stop'
$extras = $env:TAURI_RELEASE_EXTRAS
New-Item -ItemType Directory -Force -Path $extras | Out-Null

function ProcessOf([int] $id) {
    Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue
}
$self = ProcessOf $PID
$parent = if ($self) { ProcessOf $self.ParentProcessId } else { $null }
$grandparent = if ($parent) { ProcessOf $parent.ParentProcessId } else { $null }
$chain = @($parent, $grandparent) | Where-Object { $_ } | ForEach-Object Name

$name = $null
if (($chain -contains 'makensis.exe') -and -not ($File -like '*-setup.exe')) {
    $name = 'uninstall.exe'
} elseif ($File -match '[\/]nsis[\/].*[\/]Plugins[\/][^\/]+\.dll$') {
    $name = 'plugins/' + (Split-Path -Leaf $File)
}

$action = 'none'
if ($name -and $Mode -eq 'collect') {
    $to = Join-Path $extras $name
    New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null
    Copy-Item -LiteralPath $File -Destination $to -Force
    $action = 'collected'
}
if ($name -and $Mode -eq 'substitute') {
    $from = Join-Path $env:TAURI_RELEASE_SIGNED $name
    if (-not (Test-Path -LiteralPath $from)) { throw "no signed copy of $name" }
    Copy-Item -LiteralPath $from -Destination $File -Force
    $action = 'substituted'
}

$entry = [ordered]@{
    mode   = $Mode
    file   = $File
    as     = $name
    sha256 = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
    chain  = $chain
    action = $action
}
Add-Content -LiteralPath (Join-Path $extras 'hook.log') -Value ($entry | ConvertTo-Json -Compress)
