[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run as administrator from the installed folder.' }
$entries = @(
    @{Name='Codex-ASUS-KeyboardCycle';Script='Watch-AsusKeyboardCycle.ps1';Runtime='.analysis\cycle-runtime'},
    @{Name='Codex-ASUS-KeyboardMaximum';Script='Watch-AsusKeyboardMaximum.ps1';Runtime='.analysis\keyboard-maximum-runtime'}
)
# Validate every task before changing any task. Never stop/replace another copy.
foreach ($entry in $entries) {
    $task = Get-ScheduledTask -TaskName $entry.Name -ErrorAction SilentlyContinue
    $watcher = Join-Path $PSScriptRoot $entry.Script
    if ($task -and @($task.Actions | Where-Object { $_.Arguments -like ('*"' + $watcher + '"*') }).Count -ne 1) { throw ('Task belongs to another directory; left untouched: ' + $entry.Name) }
}
foreach ($entry in $entries) {
    $task = Get-ScheduledTask -TaskName $entry.Name -ErrorAction SilentlyContinue
    if (-not $task) { continue }
    $runtime = Join-Path $PSScriptRoot $entry.Runtime
    New-Item -ItemType Directory -Path $runtime -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $runtime 'stop.txt') -Value 'Community package removal requested' -Encoding UTF8
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        $task = Get-ScheduledTask -TaskName $entry.Name -ErrorAction SilentlyContinue
        if (-not $task -or $task.State -ne 'Running') { break }
        Start-Sleep -Milliseconds 250
    } while ($timer.Elapsed.TotalSeconds -lt 15)
    if ($task -and $task.State -eq 'Running') { throw 'Watcher has not stopped. No forced termination; wait and retry removal.' }
    if ($task) { Disable-ScheduledTask -TaskName $entry.Name | Out-Null }
}
foreach ($entry in $entries) {
    $task = Get-ScheduledTask -TaskName $entry.Name -ErrorAction SilentlyContinue
    if ($task -and $task.State -eq 'Running') { throw 'A watcher restarted. No tasks removed; retry after inspecting logs.' }
}
foreach ($entry in $entries) {
    if (Get-ScheduledTask -TaskName $entry.Name -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $entry.Name -Confirm:$false }
}
Write-Output 'Community tasks removed. ASUS services/drivers were not changed. Files/logs and current brightness are retained; ASUS resumes its original hotkey behavior.'
