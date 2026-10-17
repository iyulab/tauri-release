#!/usr/bin/env pwsh
# The bundler's sign hook (`bundle.windows.signCommand`) for the two-pass measurement. It signs
# nothing. Every call is logged — which file, which process ran the hook — so the measurement shows
# which call is the uninstaller's. The call `makensis` makes for a file that is not the installer is
# taken as the uninstaller:
#
#   hook.ps1 collect <file>      copy that uninstaller to $env:TWO_PASS_DIR/uninstall.exe
#   hook.ps1 substitute <file>   replace that uninstaller by $env:TWO_PASS_DIR/uninstall.signed.exe
#
# Log: $env:TWO_PASS_DIR/hook.log (one JSON object per call).
param(
    [Parameter(Mandatory)] [ValidateSet('collect', 'substitute')] [string] $Mode,
    [Parameter(Mandatory)] [string] $File
)

$ErrorActionPreference = 'Stop'
$dir = $env:TWO_PASS_DIR
New-Item -ItemType Directory -Force -Path $dir | Out-Null

function NameOf([int] $id) {
    (Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue)
}
$self = NameOf $PID
$parent = if ($self) { NameOf $self.ParentProcessId } else { $null }
$grandparent = if ($parent) { NameOf $parent.ParentProcessId } else { $null }
$chain = @($parent, $grandparent) | Where-Object { $_ } | ForEach-Object Name
$fromMakensis = $chain -contains 'makensis.exe'
$installer = $File -like '*-setup.exe'
$uninstaller = $fromMakensis -and -not $installer

$action = 'none'
if ($uninstaller -and $Mode -eq 'collect') {
    Copy-Item -LiteralPath $File -Destination (Join-Path $dir 'uninstall.exe') -Force
    $action = 'collected'
}
if ($uninstaller -and $Mode -eq 'substitute') {
    Copy-Item -LiteralPath (Join-Path $dir 'uninstall.signed.exe') -Destination $File -Force
    $action = 'substituted'
}

$entry = [ordered]@{
    mode = $Mode
    file = $File
    size = (Get-Item -LiteralPath $File).Length
    sha256 = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
    chain = $chain
    uninstaller = $uninstaller
    action = $action
}
Add-Content -LiteralPath (Join-Path $dir 'hook.log') -Value ($entry | ConvertTo-Json -Compress)
