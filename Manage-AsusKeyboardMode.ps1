[CmdletBinding()]
param([ValidateSet('Cycle','CycleWithoutMemory','Maximum','Status')][string]$Mode='Status')
$ErrorActionPreference='Stop'
$cycleTaskName='Codex-ASUS-KeyboardCycle'
$maximumTaskName='Codex-ASUS-KeyboardMaximum'
$runtime=Join-Path $PSScriptRoot '.analysis\cycle-runtime'
$report=Join-Path $PSScriptRoot '.analysis\keyboard-mode-management.json'
$result=[ordered]@{Time=(Get-Date).ToString('o');Mode=$Mode;State='Starting'}
try {
    $existingCycle=Get-ScheduledTask -TaskName $cycleTaskName -ErrorAction SilentlyContinue
    $watcher=Join-Path $PSScriptRoot 'Watch-AsusKeyboardCycle.ps1'
    if($existingCycle -and @($existingCycle.Actions | Where-Object { $_.Arguments -like ('*"'+$watcher+'"*') }).Count -ne 1){throw 'Different cycle task found; left untouched.'}
    if($Mode -ne 'Status'){
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
        $principal=New-Object Security.Principal.WindowsPrincipal($identity)
        if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Run this mode manager as administrator.'}
    }
    switch($Mode){
        Status {
            $result.State='Status'
            $result.Maximum=[string](Get-ScheduledTask -TaskName $maximumTaskName).State
            $result.Cycle=if($existingCycle){[string]$existingCycle.State}else{'NotInstalled'}
            $result.RememberLastState=($existingCycle -and $existingCycle.Actions.Arguments -notmatch '-NoStateMemory')
            $pointer=Join-Path $PSScriptRoot '.analysis\cycle-current.txt'
            if(Test-Path $pointer){$result.CycleStatus=Get-Content (Join-Path (Get-Content $pointer -Raw).Trim() 'status.json') -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json}
        }
        Maximum {
            & (Join-Path $PSScriptRoot 'Restore-AsusKeyboardMaximum.ps1') | Out-Null
            $result.State='Maximum-Start-Requested'
        }
        {$_ -in @('Cycle','CycleWithoutMemory')} {
            foreach($name in @('Watch-AsusKeyboardCycle.ps1','Set-AsusKeyboardState.ps1','Invoke-AsusKeyboardHotkey.ps1','KeyboardStateStore.ps1')){
                if(-not(Test-Path (Join-Path $PSScriptRoot $name))){throw ('Missing cycle script: '+$name)}
            }
            # Cooperatively stop any preview/current cycle, then suspend maximum.
            & (Join-Path $PSScriptRoot 'Restore-AsusKeyboardMaximum.ps1') | Out-Null
            & (Join-Path $PSScriptRoot 'Manage-AsusKeyboardMaximum.ps1') -Action Stop | Out-Null
            if((Get-ScheduledTask -TaskName $maximumTaskName).State -eq 'Running'){throw 'Maximum corrector has not stopped.'}
            Disable-ScheduledTask -TaskName $maximumTaskName | Out-Null
            New-Item -ItemType Directory -Path $runtime -Force | Out-Null
            $stop=Join-Path $runtime 'stop.txt'
            if(Test-Path -LiteralPath $stop){Remove-Item -LiteralPath $stop}
            Set-Content (Join-Path $PSScriptRoot '.analysis\cycle-current.txt') $runtime
            $arguments='-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -AuditDirectory "{1}" -Seconds 0' -f $watcher,$runtime
            if($Mode -eq 'CycleWithoutMemory'){$arguments+=' -NoStateMemory'}
            $action=New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -Argument $arguments -WorkingDirectory $PSScriptRoot
            $trigger=New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
            $trigger.Delay='PT5S'
            $taskPrincipal=New-ScheduledTaskPrincipal -UserId $identity.User.Value -LogonType Interactive -RunLevel Highest
            $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
            Register-ScheduledTask -TaskName $cycleTaskName -Action $action -Trigger $trigger -Principal $taskPrincipal -Settings $settings -Description 'ASUS original keyboard hotkey cycles Off, Medium, High; ASUS logical state stays on for both lit levels.' -Force | Out-Null
            Export-ScheduledTask -TaskName $cycleTaskName | Set-Content (Join-Path $runtime 'installed-task.xml') -Encoding UTF8
            Start-ScheduledTask -TaskName $cycleTaskName
            $result.State='Cycle-Installed-And-Start-Requested'
            $result.RememberLastState=($Mode -eq 'Cycle')
        }
    }
}catch{
    $result.State='Error';$result.Error=$_.Exception.ToString()
    if($Mode -in @('Cycle','CycleWithoutMemory')){
        try { & (Join-Path $PSScriptRoot 'Restore-AsusKeyboardMaximum.ps1') | Out-Null;$result.Fallback='Maximum restore requested' }catch{$result.FallbackError=$_.Exception.ToString()}
    }
}
$result | ConvertTo-Json -Depth 8 | Set-Content $report -Encoding UTF8
$result | ConvertTo-Json -Depth 8
if($result.State -eq 'Error'){exit 1}
