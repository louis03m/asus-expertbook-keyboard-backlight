[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$AuditDirectory,
    [ValidateRange(0,86400)][int]$Seconds=600,
    [switch]$StartOff,
    [switch]$RestoreMaximumOnExit,
    [switch]$NoStateMemory
)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Path $AuditDirectory -Force | Out-Null
$cycleStatus=Join-Path $AuditDirectory 'status.json'
$cycleLog=Join-Path $AuditDirectory 'events.jsonl'
$cycleStop=Join-Path $AuditDirectory 'stop.txt'
$cycleSource='Codex.AsusKeyboardCycle.Key'
$cycleRun=Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$cycleMutex=$null;$cycleHeld=$false;$cycleBase=$null;$cycleRegistry=$null
$script:cycleCount=0;$script:cycleIndex=0
$cycleNames=@('Off','Medium','High')
$preferencePath=Join-Path $PSScriptRoot 'keyboard-state.json'
function Write-CycleStatus([string]$Status,[string]$Detail='') {
    @{State=$Status;Detail=$Detail;Time=(Get-Date).ToString('o');ProcessId=$PID;RunId=$cycleRun;CurrentLevel=$cycleNames[$script:cycleIndex];RememberLastState=(-not $NoStateMemory);PreferencePath=$preferencePath} | ConvertTo-Json | Set-Content $cycleStatus -Encoding UTF8
}
function Write-CycleLog($Record) { $Record | ConvertTo-Json -Depth 8 -Compress | Add-Content $cycleLog -Encoding UTF8 }
function Apply-CycleState([string]$Requested) {
    $script:cycleCount++
    $path=Join-Path $AuditDirectory ('transactions\{0}-{1:D5}' -f $cycleRun,$script:cycleCount)
    $nativeAction=if($Requested -eq 'Off'){'Off'}else{'On'}
    $native=& (Join-Path $PSScriptRoot 'Invoke-AsusKeyboardHotkey.ps1') -Action $nativeAction
    $expected=if($Requested -eq 'Off'){0x80}else{0x83}
    $settle=[Diagnostics.Stopwatch]::StartNew()
    while($cycleRegistry.GetValue('KeybdLightLevel',-1) -ne $expected -and $settle.ElapsedMilliseconds -lt 1000) {Start-Sleep -Milliseconds 20}
    if($cycleRegistry.GetValue('KeybdLightLevel',-1) -ne $expected){throw 'ASUS logical state was not acknowledged; no EC state write.'}
    Start-Sleep -Milliseconds 100
    # GetNewClosure captures local variables; explicitly snapshot parent values.
    $guardStop=$cycleStop;$guardRegistry=$cycleRegistry;$guardSource=$cycleSource;$guardExpected=$expected
    $guard={
        -not(Test-Path $guardStop) -and
        $guardRegistry.GetValue('KeybdLightLevel',-1) -eq $guardExpected -and
        @(Get-Event -SourceIdentifier $guardSource -ErrorAction SilentlyContinue | Where-Object { [uint32]$_.SourceEventArgs.NewEvent.EventID -eq 199 }).Count -eq 0
    }.GetNewClosure()
    & (Join-Path $PSScriptRoot 'Set-AsusKeyboardState.ps1') -State $Requested -AuditDirectory $path -BeforeBrightnessWrite $guard
    $exchange=Get-Content (Join-Path $path 'result.json') -Raw | ConvertFrom-Json
    $logical=$cycleRegistry.GetValue('KeybdLightLevel',-1)
    Write-CycleLog @{Time=(Get-Date).ToString('o');Requested=$Requested;State=$exchange.State;Before=$exchange.Before;After=$exchange.After;AsusRegistry=$logical;Native=$native;WriteAttempts=$exchange.WriteAttempts;Error=$exchange.Error;Audit=$path}
    if($exchange.State -eq 'Stopped') {
        if($exchange.Error -eq 'New hotkey pending; brightness write cancelled.') {return $false}
        throw ('WMI state exchange stopped: '+$exchange.Error)
    }
    if($logical -ne $expected) {
        if(@(Get-Event -SourceIdentifier $cycleSource -ErrorAction SilentlyContinue).Count -gt 0){return $false}
        throw 'ASUS state changed after the exchange; no repeat.'
    }
    return $true
}
try {
    . (Join-Path $PSScriptRoot 'KeyboardStateStore.ps1')
    $model=(Get-CimInstance -Namespace root/cimv2 -ClassName Win32_ComputerSystem).Model
    $bios=(Get-CimInstance -Namespace root/cimv2 -ClassName Win32_BIOS).SMBIOSBIOSVersion
    if($model -notmatch '\bB1502CBA(?:_|\b)' -or $bios -cnotin @('B1502CBA.316','B1502CBA.317')){throw 'Unverified model/BIOS; no keyboard commands.'}
    $optimization='C:\Windows\System32\DriverStore\FileRepository\asussci2.inf_amd64_197d319fab43e0fe\ASUSOptimization\AsusOptimization.exe'
    if((Get-FileHash $optimization).Hash -ine 'E160B6DE0ADAB88D834AABA6D3086495115B6CC23E8734273C5AD7DCCDA4340B'){throw 'ASUS service changed; keyboard dispatch needs rechecking.'}
    $cycleMutex=New-Object Threading.Mutex($false,'Global\Codex.Asus.KeyboardMaximum.Listener')
    try{$cycleHeld=$cycleMutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$cycleHeld=$true}
    if(-not $cycleHeld){throw 'Another keyboard correction listener is active.'}
    if(Test-Path $cycleStop){throw 'Cycle stop marker exists.'}
    $cycleBase=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
    $cycleRegistry=$cycleBase.OpenSubKey('SOFTWARE\ASUS\ASUS System Control Interface\AsusOptimization\ASUS Keyboard Hotkeys',$false)
    if($null -eq $cycleRegistry){throw 'ASUS keyboard settings key missing.'}
    Write-CycleStatus 'Starting' 'Waiting for the ASUS keyboard agent before restoring the saved level.'
    $agentWait=[Diagnostics.Stopwatch]::StartNew()
    do{
        try{
            $null=& (Join-Path $PSScriptRoot 'Invoke-AsusKeyboardHotkey.ps1') -Action Inspect
            break
        }catch{
            # Login can start our task before the ASUS user agent. Inspect sends no command.
            if($_.Exception.Message -ne 'The ASUS keyboard agent window was not found; no message sent.' -or $agentWait.ElapsedMilliseconds -ge 30000){throw}
            Start-Sleep -Milliseconds 250
        }
    }while(-not(Test-Path $cycleStop))
    if(Test-Path $cycleStop){Write-CycleStatus 'Stopped';return}
    Register-WmiEvent -Namespace root\wmi -Query 'SELECT * FROM AsusAtkWmiEvent' -SourceIdentifier $cycleSource | Out-Null
    $preference=$null;$preferenceRejected=$false
    if(-not $NoStateMemory){
        try{$preference=Read-AsusKeyboardPreference -Path $preferencePath}catch{
            $preferenceRejected=$true
            Write-CycleLog @{Time=(Get-Date).ToString('o');State='SavedStateRejected';Error=$_.Exception.Message}
        }
    }
    if($StartOff){$null=Apply-CycleState 'Off'}elseif($null -ne $preference){
        $script:cycleIndex=[Array]::IndexOf($cycleNames,[string]$preference.Level)
        $restored=Apply-CycleState $preference.Level
        Write-CycleLog @{Time=(Get-Date).ToString('o');State=$(if($restored){'SavedStateRestored'}else{'SavedStateRestoreSuperseded'});Level=$preference.Level;SavedUtc=$preference.SavedUtc}
        if($restored -and $preference.Bios -cne $bios){
            $migrated=Save-AsusKeyboardPreference -Path $preferencePath -Level $preference.Level -Source Migration -Bios $bios
            Write-CycleLog @{Time=(Get-Date).ToString('o');State='SavedStateBiosMigrated';Level=$migrated.Level;PreviousBios=$preference.Bios;Bios=$migrated.Bios}
        }
    }else{
        $initialPath=Join-Path $AuditDirectory ('transactions\'+$cycleRun+'-initial')
        & (Join-Path $PSScriptRoot 'Set-AsusKeyboardState.ps1') -State Read -AuditDirectory $initialPath
        $initial=Get-Content (Join-Path $initialPath 'result.json') -Raw | ConvertFrom-Json
        if($initial.State -ne 'Read-Confirmed'){throw 'Could not read the starting level.'}
        $script:cycleIndex=switch($initial.After){'0x00'{0};'0x03'{1};'0xDF'{2};default{throw 'Unknown starting level.'}}
        # First-run capture only; an invalid file is retained until a confirmed key.
        $initialExpected=if($script:cycleIndex -eq 0){128}else{131}
        if(-not $NoStateMemory -and -not $preferenceRejected -and $cycleRegistry.GetValue('KeybdLightLevel',-1) -eq $initialExpected){
            $null=Save-AsusKeyboardPreference -Path $preferencePath -Level $cycleNames[$script:cycleIndex] -Source InitialCapture -Bios $bios
        }
    }
    Write-CycleStatus 'Listening' 'Hotkey C7: Off -> Medium -> High -> Off; ASUS on for Medium and High.'
    $clock=[Diagnostics.Stopwatch]::StartNew()
    while(($Seconds -eq 0 -or $clock.Elapsed.TotalSeconds -lt $Seconds) -and -not(Test-Path $cycleStop)) {
        $notification=Wait-Event -SourceIdentifier $cycleSource -Timeout 1
        if($null -eq $notification){continue}
        $code=[uint32]$notification.SourceEventArgs.NewEvent.EventID
        Remove-Event -EventIdentifier $notification.EventIdentifier
        Write-CycleLog @{Time=(Get-Date).ToString('o');State='EventObserved';EventID=$code}
        if($code -ne 199){continue}
        $presses=1
        Start-Sleep -Milliseconds 200
        foreach($pending in @(Get-Event -SourceIdentifier $cycleSource -ErrorAction SilentlyContinue)) {
            if([uint32]$pending.SourceEventArgs.NewEvent.EventID -eq 199){$presses++}
            Remove-Event -EventIdentifier $pending.EventIdentifier
        }
        if(Test-Path $cycleStop){break}
        $script:cycleIndex=($script:cycleIndex+$presses)%3
        $applied=Apply-CycleState $cycleNames[$script:cycleIndex]
        if($applied -and -not $NoStateMemory){
            $saved=Save-AsusKeyboardPreference -Path $preferencePath -Level $cycleNames[$script:cycleIndex] -Source Hotkey -Bios $bios
            Write-CycleLog @{Time=(Get-Date).ToString('o');State='LastStateSaved';Level=$saved.Level;SavedUtc=$saved.SavedUtc}
        }
        Write-CycleStatus 'Listening' $(if($applied){'State confirmed with matching ASUS logical state.'}else{'Superseded by another hotkey; processing the pending event next.'})
    }
    Write-CycleStatus 'Stopped'
}catch{
    Write-CycleStatus 'Error' $_.Exception.ToString()
    $RestoreMaximumOnExit=$true
}finally{
    Unregister-Event -SourceIdentifier $cycleSource -ErrorAction SilentlyContinue
    if($null -ne $cycleRegistry){$cycleRegistry.Dispose()}
    if($null -ne $cycleBase){$cycleBase.Dispose()}
    if($cycleHeld){$cycleMutex.ReleaseMutex()}
    if($null -ne $cycleMutex){$cycleMutex.Dispose()}
    if($RestoreMaximumOnExit){
        try {
            $installedCycle=Get-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle' -ErrorAction SilentlyContinue
            if($installedCycle -and @($installedCycle.Actions | Where-Object { $_.Arguments -like ('*"'+(Join-Path $PSScriptRoot 'Watch-AsusKeyboardCycle.ps1')+'"*') }).Count -eq 1){
                Disable-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle' | Out-Null
            }
            Enable-ScheduledTask -TaskName 'Codex-ASUS-KeyboardMaximum' | Out-Null
            if((Get-ScheduledTask -TaskName 'Codex-ASUS-KeyboardMaximum').State -ne 'Running'){
                & (Join-Path $PSScriptRoot 'Manage-AsusKeyboardMaximum.ps1') -Action Start | Out-Null
            }
            Write-CycleLog @{Time=(Get-Date).ToString('o');State='MaximumRestoreRequested'}
        }catch{Write-CycleLog @{Time=(Get-Date).ToString('o');State='MaximumRestoreError';Error=$_.Exception.ToString()}}
    }
}
