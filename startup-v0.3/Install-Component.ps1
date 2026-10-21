[CmdletBinding()]
param([string]$LegacyDirectory,[ValidateSet('Off','Medium','High')][string]$InitialLevel)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ComponentCommon.ps1')
. (Join-Path $PSScriptRoot 'Assert-Compatibility.ps1')
. (Join-Path $PSScriptRoot 'KeyboardStateStore.ps1')
. (Join-Path $PSScriptRoot 'InstallationPlan.ps1')
Assert-AsusKeyboardCompatibility
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or -not [Environment]::Is64BitProcess){throw 'Use elevated 64-bit Windows PowerShell 5.1 under the task owner account.'}
$code=Join-Path $env:ProgramFiles 'AsusKeyboardUnified-v0.3'
$data=Join-Path $env:ProgramData 'NeaLogic\AsusKeyboardUnified-v0.3'
$runner=Join-Path $code 'Run-Component.ps1'
$cycle=Get-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle' -ErrorAction SilentlyContinue
$maximum=Get-ScheduledTask -TaskName 'Codex-ASUS-KeyboardMaximum' -ErrorAction SilentlyContinue
$boot=Get-ScheduledTask -TaskName 'Codex-ASUS-KeyboardPrelogin' -ErrorAction SilentlyContinue
$config=Read-ComponentJson (Join-Path $data 'config.json')
$plan=Get-KeyboardInstallationPlan -Cycle $cycle -Maximum $maximum -Boot $boot -InstalledConfig $config -CodeRoot $code -OwnerSid $identity.User.Value -OwnerName $identity.Name -OwnerShort $env:USERNAME -LegacyDirectory $LegacyDirectory
if($InitialLevel -and $plan.Mode -ne 'Fresh'){throw 'InitialLevel is for first installation only; existing choices are preserved.'}
if(Get-ScheduledTask -TaskName 'Codex-ASUS-UnifiedPreflight' -ErrorAction SilentlyContinue){throw 'Preflight task already exists; no overwrite.'}
if($plan.Mode -eq 'Update'){
    foreach($folder in @($code,$data)){if(-not(Test-Path -LiteralPath $folder) -or -not(Get-Acl -LiteralPath $folder).AreAccessRulesProtected){throw 'Installed folders are missing or unprotected.'}}
}else{
    foreach($folder in @($code,$data)){if(Test-Path -LiteralPath $folder){throw 'Partial/existing destination found; no overwrite.'}}
}
$legacy=$plan.LegacyRoot
if($plan.Mode -eq 'Legacy'){
    $saved=Read-AsusKeyboardPreference (Join-Path $legacy 'keyboard-state.json')
    if(-not $saved){throw 'Existing preference invalid; no task changes.'}
}
$files=@('ComponentCommon.ps1','Assert-Compatibility.ps1','InstallationPlan.ps1','Invoke-AsusKeyboardHotkey.ps1','Set-AsusKeyboardState.ps1','KeyboardStateStore.ps1','Watch-DesktopCycle.ps1','Run-Component.ps1','Manage-Component.ps1','Install-Component.ps1','README-IT-EN.md','AI-adaptation-IT-EN.txt')
foreach($name in $files){if(-not(Test-Path -LiteralPath (Join-Path $PSScriptRoot $name) -PathType Leaf)){throw ('Incomplete package: '+$name)}}
function New-ProtectedFolder([string]$Path){
    New-Item -ItemType Directory -Path $Path | Out-Null
    $acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetAccessRuleProtection($true,$false)
    foreach($sid in @('S-1-5-18','S-1-5-32-544')){$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow'))}
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-5-32-545'),'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow'))
    $acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'));Set-Acl -LiteralPath $Path -AclObject $acl
}
function Stop-CycleCooperatively([string]$Runtime){
    Set-Content -LiteralPath (Join-Path $Runtime 'stop.txt') -Value 'Standalone setup' -Encoding ASCII
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while((Get-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle').State -eq 'Running'){
        if($timer.Elapsed.TotalSeconds -ge 20){throw 'Cycle has not exited; no forced termination.'}
        Start-Sleep -Milliseconds 250
    }
}
if($plan.Mode -ne 'Update'){New-ProtectedFolder $code;New-ProtectedFolder $data}
$backup=Join-Path $data ('setup-backup-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $backup | Out-Null
$shell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
$system=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$preflightCreated=$false;$taskChanged=$false;$stopped=$false;$sourceCopied=$false
try{
    Write-ComponentJson (Join-Path $data 'setup-in-progress.json') @{ProcessId=$PID;StartUtc=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')}
    if($plan.Mode -eq 'Update'){
        Copy-Item -LiteralPath (Join-Path $data 'config.json') -Destination (Join-Path $backup 'config.json')
        foreach($name in $files){if(Test-Path -LiteralPath (Join-Path $code $name)){Copy-Item -LiteralPath (Join-Path $code $name) -Destination (Join-Path $backup $name)}}
        Set-Content -LiteralPath (Join-Path $data 'stop.txt') -Value 'Update requested' -Encoding ASCII
        Disable-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle' | Out-Null
        $stopped=$true;Stop-CycleCooperatively (Join-Path $data 'desktop-runtime')
    }elseif($plan.Mode -eq 'Legacy'){
        Export-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle' | Set-Content -LiteralPath (Join-Path $data 'legacy-cycle.xml') -Encoding UTF8
        Export-ScheduledTask -TaskName 'Codex-ASUS-KeyboardMaximum' | Set-Content -LiteralPath (Join-Path $data 'legacy-maximum.xml') -Encoding UTF8
        Copy-Item -LiteralPath (Join-Path $legacy 'keyboard-state.json') -Destination (Join-Path $data 'keyboard-state.json')
    }
    if($plan.Mode -eq 'Update'){
        $mutex=Get-ComponentMutex;$held=$false
        try{
            try{$held=$mutex.WaitOne(15000)}catch [Threading.AbandonedMutexException]{$held=$true}
            if(-not $held){throw 'Boot worker still active; no code overwritten.'}
            $sourceCopied=$true
            foreach($name in $files){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $code $name) -Force}
        }finally{if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
    }else{
        foreach($name in $files){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $code $name)}
        $sourceCopied=$true
        $config=[pscustomobject]@{Version=1;OwnerSid=$identity.User.Value;LegacyRoot=$legacy;CodeRoot=$code;LegacyCycleEnabled=($plan.Mode -eq 'Legacy');PersistentBoot=$false;InstallKind=$plan.InstallKind;PackageVersion='0.3.1-preview'}
    }
    foreach($name in $files){if((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash -cne (Get-FileHash -LiteralPath (Join-Path $code $name)).Hash){throw 'Protected copy hash mismatch.'}}
    $config | Add-Member NoteProperty PackageVersion '0.3.1-preview' -Force
    $config | Add-Member NoteProperty InstallKind $plan.InstallKind -Force
    Write-ComponentJson (Join-Path $data 'config.json') $config
    $action=New-ScheduledTaskAction -Execute $shell -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$runner+'" -Mode Preflight') -WorkingDirectory $code
    $started=[DateTime]::UtcNow
    Register-ScheduledTask -TaskName 'Codex-ASUS-UnifiedPreflight' -Action $action -Principal $system -Settings $settings | Out-Null
    $preflightCreated=$true;Start-ScheduledTask -TaskName 'Codex-ASUS-UnifiedPreflight'
    $timer=[Diagnostics.Stopwatch]::StartNew()
    do{
        Start-Sleep -Milliseconds 300
        $status=Read-ComponentJson (Join-Path $data 'Preflight-status.json')
        $current=$status -and [DateTimeOffset]::Parse($status.Utc).UtcDateTime -ge $started
        if($current -and $status.State -eq 'Error'){throw $status.Detail}
    }until(($current -and $status.State -eq 'Complete') -or $timer.Elapsed.TotalSeconds -ge 45)
    if(-not $current -or $status.State -ne 'Complete'){throw 'SYSTEM read-only preflight incomplete.'}
    while((Get-ScheduledTask -TaskName 'Codex-ASUS-UnifiedPreflight').State -eq 'Running'){
        if($timer.Elapsed.TotalSeconds -ge 50){throw 'Preflight did not exit.'};Start-Sleep -Milliseconds 200
    }
    Unregister-ScheduledTask -TaskName 'Codex-ASUS-UnifiedPreflight' -Confirm:$false;$preflightCreated=$false
    if($plan.Mode -eq 'Fresh'){
        $read=Read-ComponentJson (Join-Path $status.Runtime 'read-only-exchange\result.json')
        $level=if($InitialLevel){$InitialLevel}else{switch($read.After){'0x00'{'Off'} '0x03'{'Medium'} '0xDF'{'High'} default{throw 'Unknown captured level; no default.'}}}
        $bios=(Get-CimInstance -Namespace root/cimv2 -ClassName Win32_BIOS).SMBIOSBIOSVersion
        $null=Save-AsusKeyboardPreference -Path (Join-Path $data 'keyboard-state.json') -Level $level -Source InitialCapture -Bios $bios
    }elseif($plan.Mode -eq 'Legacy'){
        Disable-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle' | Out-Null
        $stopped=$true;Stop-CycleCooperatively (Join-Path $legacy '.analysis\cycle-runtime')
        $null=Read-AsusKeyboardPreference (Join-Path $legacy 'keyboard-state.json')
        Copy-Item -LiteralPath (Join-Path $legacy 'keyboard-state.json') -Destination (Join-Path $data 'keyboard-state.json') -Force
    }
    $desktop=New-ScheduledTaskAction -Execute $shell -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$runner+'" -Mode Desktop') -WorkingDirectory $code
    if($plan.Mode -eq 'Fresh'){
        $trigger=New-ScheduledTaskTrigger -AtLogOn -User $identity.Name;$trigger.Delay='PT5S'
        $user=New-ScheduledTaskPrincipal -UserId $identity.User.Value -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle' -Action $desktop -Trigger $trigger -Principal $user -Settings $settings | Out-Null
    }else{Set-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle' -Action $desktop | Out-Null}
    $taskChanged=$true
    if($plan.Mode -ne 'Update'){
        $bootAction=New-ScheduledTaskAction -Execute $shell -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$runner+'" -Mode Boot') -WorkingDirectory $code
        Register-ScheduledTask -TaskName 'Codex-ASUS-KeyboardPrelogin' -Action $bootAction -Trigger (New-ScheduledTaskTrigger -AtStartup) -Principal $system -Settings $settings | Out-Null
        & (Join-Path $code 'Manage-Component.ps1') -Action ArmOnce | Out-Null
    }
    $stop=Join-Path $data 'stop.txt';if(Test-Path -LiteralPath $stop){Remove-Item -LiteralPath $stop}
    Enable-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle' | Out-Null
    Start-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle'
    $timer.Restart()
    do{
        Start-Sleep -Milliseconds 400
        $desktopStatus=Read-ComponentJson (Join-Path $data 'desktop-runtime\status.json')
        $fresh=$desktopStatus -and [DateTimeOffset]::Parse($desktopStatus.Time).UtcDateTime -ge $started
        if($fresh -and $desktopStatus.State -eq 'Error'){throw $desktopStatus.Detail}
    }until(($fresh -and $desktopStatus.State -eq 'Listening') -or $timer.Elapsed.TotalSeconds -ge 40)
    if(-not $fresh -or $desktopStatus.State -ne 'Listening'){throw 'Desktop did not confirm Listening.'}
    Write-ComponentJson (Join-Path $data 'installation-result.json') @{State='Installed-DesktopListening';Mode=$plan.Mode;Version='0.3.1-preview';Desktop=$desktopStatus;Preflight=$status;PersistentBoot=$config.PersistentBoot;Backup=$backup}
}catch{
    Write-ComponentJson (Join-Path $data 'installation-error.json') @{Error=$_.Exception.ToString();Mode=$plan.Mode;Backup=$backup}
    if($preflightCreated){Unregister-ScheduledTask -TaskName 'Codex-ASUS-UnifiedPreflight' -Confirm:$false -ErrorAction SilentlyContinue}
    if($plan.Mode -eq 'Update'){
        if($sourceCopied){foreach($file in Get-ChildItem -LiteralPath $backup -File | Where-Object {$_.Name -ne 'config.json'}){Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $code $file.Name) -Force}}
        Copy-Item -LiteralPath (Join-Path $backup 'config.json') -Destination (Join-Path $data 'config.json') -Force
        foreach($path in @((Join-Path $data 'stop.txt'),(Join-Path $data 'desktop-runtime\stop.txt'))){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path}}
        Enable-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle' | Out-Null
        if((Get-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle').State -ne 'Running'){Start-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle'}
    }elseif($taskChanged){& (Join-Path $code 'Manage-Component.ps1') -Action Rollback}
    elseif($plan.Mode -eq 'Legacy' -and $stopped){
        $stop=Join-Path $legacy '.analysis\cycle-runtime\stop.txt';if(Test-Path -LiteralPath $stop){Remove-Item -LiteralPath $stop}
        Enable-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle' | Out-Null;Start-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle'
    }
    throw
}finally{
    $marker=Join-Path $data 'setup-in-progress.json'
    $active=Read-ComponentJson $marker
    if($active -and $active.ProcessId -eq $PID){Remove-Item -LiteralPath $marker}
}
