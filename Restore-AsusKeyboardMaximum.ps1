[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$pointer=Join-Path $PSScriptRoot '.analysis\cycle-current.txt'
if(Test-Path -LiteralPath $pointer) {
    $cycleDirectory=[IO.Path]::GetFullPath((Get-Content $pointer -Raw).Trim())
    $allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.analysis'))+[IO.Path]::DirectorySeparatorChar
    if(-not $cycleDirectory.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected cycle log directory; no stop file written.'}
    Set-Content -LiteralPath (Join-Path $cycleDirectory 'stop.txt') -Value 'Restore maximum requested' -Encoding UTF8
    $timer=[Diagnostics.Stopwatch]::StartNew()
    do {
        $cycleStatus=Get-Content (Join-Path $cycleDirectory 'status.json') -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
        if($cycleStatus.State -in @('Stopped','Error')){break}
        $cycleProcess=if($cycleStatus.ProcessId){Get-Process -Id $cycleStatus.ProcessId -ErrorAction SilentlyContinue}else{$null}
        if($null -eq $cycleProcess){break}
        Start-Sleep -Milliseconds 200
    }while($timer.Elapsed.TotalSeconds -lt 10)
    if($cycleStatus.State -notin @('Stopped','Error') -and $null -ne $cycleProcess){throw 'Cycle has not stopped yet; no forced termination.'}
    Start-Sleep -Milliseconds 300
}
$cycleTask=Get-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle' -ErrorAction SilentlyContinue
if($cycleTask){Disable-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle' | Out-Null}
Enable-ScheduledTask -TaskName 'Codex-ASUS-KeyboardMaximum' | Out-Null
if((Get-ScheduledTask -TaskName 'Codex-ASUS-KeyboardMaximum').State -ne 'Running'){
    & (Join-Path $PSScriptRoot 'Manage-AsusKeyboardMaximum.ps1') -Action Start
}
Write-Output 'Original maximum correction restored; cycle task disabled if installed.'
