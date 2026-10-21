[CmdletBinding()]
param([string]$LegacyDirectory=(Join-Path $env:ProgramFiles 'AsusKeyboardBacklight-Experimental'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ComponentCommon.ps1')
. (Join-Path $PSScriptRoot 'Assert-Compatibility.ps1')
. (Join-Path $PSScriptRoot 'KeyboardStateStore.ps1')
Assert-AsusKeyboardCompatibility
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or -not [Environment]::Is64BitProcess){throw 'Run 64-bit Windows PowerShell 5.1 as administrator under the owner account.'}
$legacy=(Resolve-Path -LiteralPath $LegacyDirectory).Path
if($legacy.StartsWith('\\')){throw 'Local installation required.'}
$code=Join-Path $env:ProgramFiles 'AsusKeyboardUnified-v0.3'
$data=Join-Path $env:ProgramData 'NeaLogic\AsusKeyboardUnified-v0.3'
foreach($folder in @($code,$data)){if(Test-Path -LiteralPath $folder){throw ('Destination already exists; nothing overwritten: '+$folder)}}
foreach($name in @('Codex-ASUS-KeyboardPrelogin','Codex-ASUS-UnifiedPreflight')){if(Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue){throw ('Task already exists: '+$name)}}
$cycle=Get-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle'
$maximum=Get-ScheduledTask -TaskName 'Codex-ASUS-KeyboardMaximum'
foreach($entry in @(@{Task=$cycle;Script='Watch-AsusKeyboardCycle.ps1'},@{Task=$maximum;Script='Watch-AsusKeyboardMaximum.ps1'})){
    if(@($entry.Task.Actions | Where-Object {$_.Arguments -like ('*"'+(Join-Path $legacy $entry.Script)+'"*')}).Count -ne 1){throw 'Existing tasks do not belong to the selected legacy installation.'}
}
if($cycle.Principal.LogonType -ne 'Interactive' -or $cycle.State -eq 'Disabled' -or $maximum.State -ne 'Disabled'){throw 'An active three-state legacy installation with disabled maximum fallback is required.'}
if($cycle.Principal.UserId -notin @($identity.User.Value,$identity.Name,$env:USERNAME)){throw 'Installer owner differs from existing cycle owner.'}
$saved=Read-AsusKeyboardPreference (Join-Path $legacy 'keyboard-state.json')
if(-not $saved){throw 'No valid saved legacy choice. Nothing installed.'}
$files=@('ComponentCommon.ps1','Assert-Compatibility.ps1','Invoke-AsusKeyboardHotkey.ps1','Set-AsusKeyboardState.ps1','KeyboardStateStore.ps1','Watch-DesktopCycle.ps1','Run-Component.ps1','Manage-Component.ps1','Install-Component.ps1','README-IT-EN.md','AI-adaptation-IT-EN.txt')
foreach($name in $files){if(-not(Test-Path -LiteralPath (Join-Path $PSScriptRoot $name) -PathType Leaf)){throw ('Incomplete package: '+$name)}}
function New-ProtectedFolder([string]$Path){
    New-Item -ItemType Directory -Path $Path | Out-Null
    $acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetAccessRuleProtection($true,$false)
    foreach($sid in @('S-1-5-18','S-1-5-32-544')){$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow'))}
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-5-32-545'),'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow'))
    $acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'));Set-Acl -LiteralPath $Path -AclObject $acl
}
New-ProtectedFolder $code
New-ProtectedFolder $data
$changed=$false;$preflightCreated=$false
try{
    foreach($name in $files){
        $source=Join-Path $PSScriptRoot $name;$destination=Join-Path $code $name
        Copy-Item -LiteralPath $source -Destination $destination
        if((Get-FileHash -LiteralPath $source).Hash -cne (Get-FileHash -LiteralPath $destination).Hash){throw 'Protected copy hash mismatch.'}
    }
    Export-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle' | Set-Content -LiteralPath (Join-Path $data 'legacy-cycle.xml') -Encoding UTF8
    Export-ScheduledTask -TaskName 'Codex-ASUS-KeyboardMaximum' | Set-Content -LiteralPath (Join-Path $data 'legacy-maximum.xml') -Encoding UTF8
    Copy-Item -LiteralPath (Join-Path $legacy 'keyboard-state.json') -Destination (Join-Path $data 'keyboard-state.json')
    Write-ComponentJson (Join-Path $data 'config.json') @{Version=1;OwnerSid=$identity.User.Value;LegacyRoot=$legacy;CodeRoot=$code;LegacyCycleEnabled=$true;PersistentBoot=$false}
    $shell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $runner=Join-Path $code 'Run-Component.ps1'
    $system=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
    $action=New-ScheduledTaskAction -Execute $shell -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$runner+'" -Mode Preflight') -WorkingDirectory $code
    Register-ScheduledTask -TaskName 'Codex-ASUS-UnifiedPreflight' -Action $action -Principal $system -Settings $settings | Out-Null
    $preflightCreated=$true;Start-ScheduledTask -TaskName 'Codex-ASUS-UnifiedPreflight'
    $clock=[Diagnostics.Stopwatch]::StartNew()
    do{
        Start-Sleep -Milliseconds 300
        $status=Read-ComponentJson (Join-Path $data 'Preflight-status.json')
        if($status.State -eq 'Error'){throw $status.Detail}
    }until($status.State -eq 'Complete' -or $clock.Elapsed.TotalSeconds -ge 45)
    if($status.State -ne 'Complete'){throw 'SYSTEM read-only preflight did not confirm.'}
    while((Get-ScheduledTask -TaskName 'Codex-ASUS-UnifiedPreflight').State -eq 'Running'){
        if($clock.Elapsed.TotalSeconds -ge 50){throw 'Preflight did not exit.'};Start-Sleep -Milliseconds 200
    }
    Unregister-ScheduledTask -TaskName 'Codex-ASUS-UnifiedPreflight' -Confirm:$false;$preflightCreated=$false
    $legacyRuntime=Join-Path $legacy '.analysis\cycle-runtime'
    Set-Content -LiteralPath (Join-Path $legacyRuntime 'stop.txt') -Value 'Unified component migration' -Encoding ASCII
    $clock.Restart()
    do{
        Start-Sleep -Milliseconds 200
        $old=Read-ComponentJson (Join-Path $legacyRuntime 'status.json')
    }until($old.State -in @('Stopped','Error') -or $clock.Elapsed.TotalSeconds -ge 15)
    if($old.State -notin @('Stopped','Error')){throw 'Original cycle did not stop cooperatively.'}
    # Refresh confirmed state only after the old writer has exited.
    $saved=Read-AsusKeyboardPreference (Join-Path $legacy 'keyboard-state.json')
    Copy-Item -LiteralPath (Join-Path $legacy 'keyboard-state.json') -Destination (Join-Path $data 'keyboard-state.json') -Force
    $desktop=New-ScheduledTaskAction -Execute $shell -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$runner+'" -Mode Desktop') -WorkingDirectory $code
    Set-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle' -Action $desktop | Out-Null
    $changed=$true
    $bootAction=New-ScheduledTaskAction -Execute $shell -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$runner+'" -Mode Boot') -WorkingDirectory $code
    Register-ScheduledTask -TaskName 'Codex-ASUS-KeyboardPrelogin' -Action $bootAction -Trigger (New-ScheduledTaskTrigger -AtStartup) -Principal $system -Settings $settings | Out-Null
    & (Join-Path $code 'Manage-Component.ps1') -Action ArmOnce | Out-Null
    Start-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle'
    $clock.Restart()
    do{
        Start-Sleep -Milliseconds 400
        $desktopStatus=Read-ComponentJson (Join-Path $data 'desktop-runtime\status.json')
        if($desktopStatus.State -eq 'Error'){throw $desktopStatus.Detail}
    }until($desktopStatus.State -eq 'Listening' -or $clock.Elapsed.TotalSeconds -ge 40)
    if($desktopStatus.State -ne 'Listening'){throw 'Unified desktop did not confirm Listening.'}
    Write-ComponentJson (Join-Path $data 'installation-result.json') @{State='Installed-DesktopListening-BootTrialArmed';Desktop=$desktopStatus;Preflight=$status;CodeRoot=$code;DataRoot=$data;OriginalFilesModified=$false;PersistentBoot=$false;BootVisualTestPending=$true}
}catch{
    Write-ComponentJson (Join-Path $data 'installation-error.json') @{Error=$_.Exception.ToString();TaskActionChanged=$changed}
    if($preflightCreated){Unregister-ScheduledTask -TaskName 'Codex-ASUS-UnifiedPreflight' -Confirm:$false -ErrorAction SilentlyContinue}
    if($changed){& (Join-Path $code 'Manage-Component.ps1') -Action Rollback}
    else{
        $legacyStop=Join-Path $legacy '.analysis\cycle-runtime\stop.txt'
        if(Test-Path -LiteralPath $legacyStop){Remove-Item -LiteralPath $legacyStop}
        if((Get-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle').State -ne 'Running'){Start-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle'}
    }
    throw
}
