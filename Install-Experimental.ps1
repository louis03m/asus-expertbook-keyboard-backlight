[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Assert-Compatibility.ps1')
Assert-AsusKeyboardCompatibility
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Use Windows PowerShell 5.1 as administrator, under your own Windows account.' }
if (-not [Environment]::Is64BitProcess) { throw 'Use 64-bit Windows PowerShell.' }
foreach ($name in @('Codex-ASUS-KeyboardMaximum','Codex-ASUS-KeyboardCycle')) {
    if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) { throw ('Task already exists; nothing installed: ' + $name) }
}
$destination = Join-Path $env:ProgramFiles 'AsusKeyboardBacklight-Experimental'
if (Test-Path -LiteralPath $destination) { throw 'Destination already exists; nothing overwritten. Review it before installing.' }
$files = @('Assert-Compatibility.ps1','Check-Compatibility.ps1','Install-Experimental.ps1','Remove-Experimental.ps1','Invoke-AsusKeyboardHotkey.ps1','KeyboardStateStore.ps1','Manage-AsusKeyboardMaximum.ps1','Manage-AsusKeyboardMode.ps1','Restore-AsusKeyboardMaximum.ps1','Set-AsusKeyboardState.ps1','Watch-AsusKeyboardCycle.ps1','Watch-AsusKeyboardMaximum.ps1','Wmi-Maximum-OneShot.ps1','README-IT-EN.txt','AI-adaptation-IT-EN.txt')
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $file) -PathType Leaf)) { throw ('Incomplete package: ' + $file) }
}
# Only creates a fresh directory under Program Files; inherited ACLs protect scripts
# that the scheduled tasks will later execute with elevated privileges.
New-Item -ItemType Directory -Path $destination -ErrorAction Stop | Out-Null
foreach ($file in $files) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $destination $file) -ErrorAction Stop }
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
& $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $destination 'Manage-AsusKeyboardMaximum.ps1') -Action Install
if ($LASTEXITCODE -ne 0) { throw 'Maximum watcher installation failed. Review .analysis logs and Remove-Experimental.ps1 in the installation folder.' }
& $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $destination 'Manage-AsusKeyboardMode.ps1') -Mode Cycle
if ($LASTEXITCODE -ne 0) { throw 'Cycle setup failed; the maximum fallback may be active. Review logs and use Remove-Experimental.ps1 if required.' }
Write-Output ('Installation requested. Check .analysis\cycle-runtime\status.json for State=Listening, then test the hotkey. Installation folder: ' + $destination)
