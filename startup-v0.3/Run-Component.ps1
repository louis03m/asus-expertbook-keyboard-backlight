[CmdletBinding()]
param([ValidateSet('Preflight','Boot','Desktop')][string]$Mode='Preflight')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ComponentCommon.ps1')
. (Join-Path $PSScriptRoot 'Assert-Compatibility.ps1')
. (Join-Path $PSScriptRoot 'KeyboardStateStore.ps1')
$data=Join-Path $env:ProgramData 'NeaLogic\AsusKeyboardUnified-v0.3'
$config=Read-ComponentJson (Join-Path $data 'config.json')
if(-not $config -or $config.Version -ne 1 -or $config.CodeRoot -cne $PSScriptRoot){throw 'Invalid protected component configuration.'}
$run=Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$runtime=Join-Path $data ($Mode+'-'+$run)
New-Item -ItemType Directory -Path $runtime | Out-Null
$preferencePath=Join-Path $data 'keyboard-state.json'
$pendingPath=Join-Path $data 'prelogin-choice.json'
$handoffPath=Join-Path $data 'handoff.json'
$stopPath=Join-Path $data 'stop.txt'
$bootStatus=Join-Path $data 'Boot-status.json'
$modeStatus=Join-Path $data ($Mode+'-status.json')
$mutex=$null;$held=$false;$base=$null;$key=$null;$subscribed=$false
$source='Codex.Asus.Unified.Prelogin.'+$PID
$bootId=$null;$userPresent=$false;$count=0
function Log-Component([string]$Kind,$Detail){
    @{Utc=[DateTime]::UtcNow.ToString('o');Mode=$Mode;Kind=$Kind;Detail=$Detail} | ConvertTo-Json -Compress -Depth 8 | Add-Content -LiteralPath (Join-Path $runtime 'events.jsonl') -Encoding UTF8
}
function Set-ComponentStatus([string]$State,[string]$Detail=''){
    Write-ComponentJson $modeStatus @{State=$State;Detail=$Detail;Utc=[DateTime]::UtcNow.ToString('o');BootId=$bootId;Run=$run;Runtime=$runtime;ProcessId=$PID;SessionId=(Get-Process -Id $PID).SessionId;ControllerOwner=$held}
}
function Test-Handoff {
    if(Test-Path -LiteralPath $stopPath){return $true}
    $request=Read-ComponentJson $handoffPath
    return ($request -and $request.BootId -ceq $bootId)
}
function Test-UserSessionPresent {
    return -not [string]::IsNullOrEmpty([string](Get-CimInstance -Namespace root/cimv2 -ClassName Win32_ComputerSystem).UserName)
}
function Apply-Prelogin([string]$Level,[bool]$FromHotkey){
    if(Test-Handoff){return $false}
    $script:count++
    if($script:count -gt 90){throw 'Prelogin exchange limit reached.'}
    $audit=Join-Path $runtime ('transaction-'+$script:count)
    $guard={
        -not(Test-Handoff) -and
        @(Get-Event -SourceIdentifier $source -ErrorAction SilentlyContinue | Where-Object {[uint32]$_.SourceEventArgs.NewEvent.EventID -eq 199}).Count -eq 0
    }
    & (Join-Path $PSScriptRoot 'Set-AsusKeyboardState.ps1') -State $Level -AuditDirectory $audit -BeforeBrightnessWrite $guard
    $result=Read-ComponentJson (Join-Path $audit 'result.json')
    Log-Component 'PreloginExchange' @{Level=$Level;Result=$result.State;Before=$result.Before;After=$result.After;Error=$result.Error;FromHotkey=$FromHotkey;AsusLogical=$key.GetValue('KeybdLightLevel',-1);Confirmation='FirmwareReadbackOnly'}
    if($result.State -eq 'Stopped' -and $result.Error -eq 'New hotkey pending; brightness write cancelled.'){return $false}
    if(-not(Test-ComponentExchange $result $Level)){throw ('Prelogin firmware transaction did not confirm: '+$result.Error)}
    Write-ComponentJson (Join-Path $data 'boot-proof.json') @{BootId=$bootId;Level=$Level;Readback=$result.After;Success=$true;Scope='PreloginFirmwareOnly';Utc=[DateTime]::UtcNow.ToString('o')}
    if($FromHotkey){
        # Keep EC-only choices separate. Desktop must synchronize ASUS before committing
        # them into the ordinary confirmed preference record.
        Write-ComponentJson $pendingPath @{Version=1;BootId=$bootId;Model='B1502CBA';Bios=$bios;Level=$Level;Readback=$result.After;Confirmation='FirmwareReadbackOnly';ObservedAsusRegistry=$key.GetValue('KeybdLightLevel',-1);Utc=[DateTime]::UtcNow.ToString('o')}
    }
    return $true
}
try{
    Assert-AsusKeyboardCompatibility
    $bios=(Get-CimInstance -Namespace root/cimv2 -ClassName Win32_BIOS).SMBIOSBIOSVersion
    $bootId=Get-ComponentBootId
    if($Mode -eq 'Desktop'){
        if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne $config.OwnerSid){throw 'Desktop component owner mismatch.'}
        Write-ComponentJson $handoffPath @{BootId=$bootId;Utc=[DateTime]::UtcNow.ToString('o')}
        $mutex=Get-ComponentMutex
        try{$held=$mutex.WaitOne(15000)}catch [Threading.AbandonedMutexException]{$held=$true}
        if(-not $held){throw 'Prelogin worker did not release control; no second writer started.'}
        $mutex.ReleaseMutex();$held=$false;$mutex.Dispose();$mutex=$null
        $startup=Read-LatestComponentChoice $preferencePath $pendingPath $bios
        $desktopRuntime=Join-Path $data 'desktop-runtime'
        New-Item -ItemType Directory -Path $desktopRuntime -Force | Out-Null
        $stop=Join-Path $desktopRuntime 'stop.txt'
        if(Test-Path -LiteralPath $stop){Remove-Item -LiteralPath $stop}
        Set-ComponentStatus 'DesktopStarting' 'Prelogin ownership released; ASUS synchronization is performed by the desktop watcher.'
        $params=@{AuditDirectory=$desktopRuntime;Seconds=0;PreferencePath=$preferencePath}
        if($startup.Pending){$params.StartupLevel=[string]$startup.Level}
        & (Join-Path $PSScriptRoot 'Watch-DesktopCycle.ps1') @params
        $status=Read-ComponentJson (Join-Path $desktopRuntime 'status.json')
        if($status.State -eq 'Error'){throw ('Desktop cycle failed: '+$status.Detail)}
        Set-ComponentStatus 'Stopped'
        return
    }
    if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne 'S-1-5-18'){throw 'Boot/preflight worker must run as SYSTEM.'}
    $preference=Read-AsusKeyboardPreference $preferencePath
    if($Mode -eq 'Preflight'){
        Register-WmiEvent -Namespace root/wmi -Query 'SELECT * FROM AsusAtkWmiEvent' -SourceIdentifier $source | Out-Null
        $subscribed=$true
        # Fixed Read mode: this validates SYSTEM mailbox access without a brightness write.
        $audit=Join-Path $runtime 'read-only-exchange'
        & (Join-Path $PSScriptRoot 'Set-AsusKeyboardState.ps1') -State Read -AuditDirectory $audit
        $result=Read-ComponentJson (Join-Path $audit 'result.json')
        if($result.State -ne 'Read-Confirmed' -or $result.WriteAttempts -ne 0 -or @($result.Events | Where-Object {$_.Name -eq 'Shared-slot-restore' -and $_.Detail.Verified -eq $true}).Count -ne 1){throw 'SYSTEM read-only mailbox check failed.'}
        Log-Component 'SystemReadOnlyVerified' @{Value=$result.After;WriteAttempts=0;Saved=$preference.Level}
        Set-ComponentStatus 'Complete' 'SYSTEM WMI subscription and bounded read verified; zero brightness writes.'
        return
    }
    if(-not $preference){throw 'No valid saved preference; no default High and no controller commands.'}
    $choice=Read-LatestComponentChoice $preferencePath $pendingPath $bios
    $armedPath=Join-Path $data 'boot-armed.json'
    $armed=Read-ComponentJson $armedPath
    if(-not $armed -or $armed.Version -ne 1 -or $armed.NotBeforeBootId -ceq $bootId){Set-ComponentStatus 'NotArmed';return}
    if(-not $config.PersistentBoot){Move-Item -LiteralPath $armedPath -Destination (Join-Path $runtime 'consumed-arm.json')}
    if(Test-Handoff){Set-ComponentStatus 'HandedOff' 'Desktop already requested control.';return}
    if(Test-UserSessionPresent){Set-ComponentStatus 'UserSessionPresent' 'Desktop wrapper owns the logged-on phase.';return}
    # Never touch the mailbox while the user/legacy listener owns control.
    $mutex=Get-ComponentMutex
    try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
    if(-not $held){Set-ComponentStatus 'OtherListenerActive';return}
    $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
    $key=$base.OpenSubKey('SOFTWARE\ASUS\ASUS System Control Interface\AsusOptimization\ASUS Keyboard Hotkeys',$false)
    if(-not $key){throw 'ASUS logical-state key missing; no controller commands.'}
    Register-WmiEvent -Namespace root/wmi -Query 'SELECT * FROM AsusAtkWmiEvent' -SourceIdentifier $source | Out-Null
    $subscribed=$true
    $desired=[string]$choice.Level
    $timer=[Diagnostics.Stopwatch]::StartNew()
    # Give the normal ASUS service initialization a bounded settling period.
    while($timer.Elapsed.TotalSeconds -lt 2 -and -not(Test-Handoff)){Start-Sleep -Milliseconds 100}
    if(Test-Handoff){Set-ComponentStatus 'HandedOff';return}
    if(Test-UserSessionPresent){Set-ComponentStatus 'UserSessionPresent';return}
    $pending=@(Get-Event -SourceIdentifier $source -ErrorAction SilentlyContinue | Where-Object {[uint32]$_.SourceEventArgs.NewEvent.EventID -eq 199})
    if($pending.Count -eq 0){$null=Apply-Prelogin $desired $false}
    Set-ComponentStatus 'PreloginListening' ('Saved level '+$desired+'; EC-only phase until ASUS desktop synchronization.')
    while($timer.Elapsed.TotalMinutes -lt 30 -and -not(Test-Handoff)){
        if(Test-UserSessionPresent){Set-ComponentStatus 'HandedOff' 'User session appeared; releasing control before the desktop watcher.';return}
        $notification=Wait-Event -SourceIdentifier $source -Timeout 1
        if(-not $notification){continue}
        $presses=0
        Start-Sleep -Milliseconds 250
        foreach($event in @(Get-Event -SourceIdentifier $source -ErrorAction SilentlyContinue)){
            if([uint32]$event.SourceEventArgs.NewEvent.EventID -eq 199){$presses++}
            Remove-Event -EventIdentifier $event.EventIdentifier
        }
        if($presses -eq 0){continue}
        $desired=Get-NextKeyboardLevel $desired $presses
        if(Apply-Prelogin $desired $true){Set-ComponentStatus 'PreloginListening' ('Confirmed physical level '+$desired+'; ASUS desktop synchronization pending.')}
    }
    Set-ComponentStatus $(if(Test-Handoff){'HandedOff'}else{'Stopped'})
}catch{
    Log-Component 'Error' $_.Exception.ToString()
    Set-ComponentStatus 'Error' $_.Exception.Message
    $setupActive=$false
    $setup=Read-ComponentJson (Join-Path $data 'setup-in-progress.json')
    if($setup){
        $installer=Get-Process -Id $setup.ProcessId -ErrorAction SilentlyContinue
        $setupActive=$installer -and $installer.StartTime.ToUniversalTime().ToString('o') -ceq $setup.StartUtc
    }
    if($Mode -eq 'Desktop' -and -not $setupActive){
        # Child watcher has released the listener mutex before returning an error.
        $shell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        Start-Process -FilePath $shell -ArgumentList ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $PSScriptRoot 'Manage-Component.ps1')+'" -Action Rollback') -WindowStyle Hidden | Out-Null
    }
}finally{
    if($subscribed){Unregister-Event -SourceIdentifier $source -ErrorAction SilentlyContinue;Get-Event -SourceIdentifier $source -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue}
    if($key){$key.Dispose()};if($base){$base.Dispose()}
    if($held){$mutex.ReleaseMutex()};if($mutex){$mutex.Dispose()}
}
