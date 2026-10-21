[CmdletBinding()]
param([ValidateSet('Install','Start','Stop','Restart','Remove','Status')][string]$Action = 'Status')
$ErrorActionPreference = 'Stop'
$taskName = 'Codex-ASUS-KeyboardMaximum'
$watcherPath = Join-Path $PSScriptRoot 'Watch-AsusKeyboardMaximum.ps1'
$runtimePath = Join-Path $PSScriptRoot '.analysis\keyboard-maximum-runtime'
$resultPath = Join-Path $PSScriptRoot '.analysis\keyboard-maximum-management.json'
$stopPath = Join-Path $runtimePath 'stop.txt'
New-Item -ItemType Directory -Path $runtimePath -Force | Out-Null
$result = [ordered]@{ Time=(Get-Date).ToString('o'); Action=$Action; Task=$taskName; State='Starting' }
function Stop-Gracefully {
    Set-Content -LiteralPath $stopPath -Value 'Requested by Manage-AsusKeyboardMaximum.ps1' -Encoding UTF8
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        $currentTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($null -eq $currentTask -or $currentTask.State -ne 'Running') { return }
        Start-Sleep -Milliseconds 250
    } while ($timer.Elapsed.TotalSeconds -lt 10)
    throw 'The watcher has not stopped yet. It was not forcefully terminated; try Status later.'
}
try {
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing -and @($existing.Actions | Where-Object { $_.Arguments -like ('*"' + $watcherPath + '"*') }).Count -ne 1) {
        throw 'A task with this name has different actions; leaving it untouched.'
    }
    if ($Action -ne 'Status') {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this management script as administrator.' }
    }
    switch ($Action) {
        Install {
            foreach ($file in @($watcherPath,(Join-Path $PSScriptRoot 'Wmi-Maximum-OneShot.ps1'))) {
                if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw ('Required script missing: ' + $file) }
            }
            if ($existing) {
                Export-ScheduledTask -TaskName $taskName | Set-Content (Join-Path $runtimePath ('task-before-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.xml')) -Encoding UTF8
                Stop-Gracefully
            }
            if (Test-Path -LiteralPath $stopPath) { Remove-Item -LiteralPath $stopPath }
            $arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -AuditDirectory "{1}"' -f $watcherPath,$runtimePath
            $taskAction = New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -Argument $arguments -WorkingDirectory $PSScriptRoot
            $trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
            $trigger.Delay = 'PT5S'
            $taskPrincipal = New-ScheduledTaskPrincipal -UserId $identity.User.Value -LogonType Interactive -RunLevel Highest
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
            Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $trigger -Principal $taskPrincipal -Settings $settings -Description 'Keeps ASUS keyboard on/off hotkey behavior and raises medium backlight to the verified maximum via the existing WMI mailbox.' -Force | Out-Null
            Export-ScheduledTask -TaskName $taskName | Set-Content (Join-Path $runtimePath 'installed-task.xml') -Encoding UTF8
            Start-ScheduledTask -TaskName $taskName
            $result.State = 'Installed-And-Start-Requested'
        }
        Start {
            if (-not $existing) { throw 'Task not installed.' }
            if ($existing.State -eq 'Running') { throw 'Task is already running.' }
            if (Test-Path -LiteralPath $stopPath) { Remove-Item -LiteralPath $stopPath }
            Start-ScheduledTask -TaskName $taskName
            $result.State = 'Start-Requested'
        }
        Stop { Stop-Gracefully; $result.State = 'Stopped' }
        Restart {
            if (-not $existing) { throw 'Task not installed.' }
            Stop-Gracefully
            if (Test-Path -LiteralPath $stopPath) { Remove-Item -LiteralPath $stopPath }
            Start-ScheduledTask -TaskName $taskName
            $result.State = 'Restart-Requested'
        }
        Remove {
            Stop-Gracefully
            if ($existing) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
            $result.State = 'Removed'; $result.Note = 'Scripts and diagnostic logs retained; brightness left as it was.'
        }
        Status {
            $result.State = if ($existing) { [string]$existing.State } else { 'NotInstalled' }
            if (Test-Path (Join-Path $runtimePath 'status.json')) { $result.Watcher = Get-Content (Join-Path $runtimePath 'status.json') -Raw | ConvertFrom-Json }
        }
    }
} catch { $result.State='Error'; $result.Error=$_.Exception.ToString() }
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
$result | ConvertTo-Json -Depth 8
if ($result.State -eq 'Error') { exit 1 }
