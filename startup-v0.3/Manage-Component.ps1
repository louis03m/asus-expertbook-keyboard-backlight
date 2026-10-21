[CmdletBinding()]
param([ValidateSet('Status','ArmOnce','EnablePersistentBoot','Rollback')][string]$Action='Status',[switch]$VisualBootConfirmed)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ComponentCommon.ps1')
. (Join-Path $PSScriptRoot 'KeyboardStateStore.ps1')
$data=Join-Path $env:ProgramData 'NeaLogic\AsusKeyboardUnified-v0.3'
$config=Read-ComponentJson (Join-Path $data 'config.json')
if(-not $config -or $config.Version -ne 1 -or $config.CodeRoot -cne $PSScriptRoot){throw 'Protected component configuration missing or mismatched.'}
if($Action -eq 'Status'){
    @{Config=$config;Boot=(Read-ComponentJson (Join-Path $data 'Boot-status.json'));Desktop=(Read-ComponentJson (Join-Path $data 'desktop-runtime\status.json'));Preference=(Read-AsusKeyboardPreference (Join-Path $data 'keyboard-state.json'));Armed=(Test-Path -LiteralPath (Join-Path $data 'boot-armed.json'))} | ConvertTo-Json -Depth 8
    return
}
$identity=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Run component management as administrator.'}
$runner=Join-Path $PSScriptRoot 'Run-Component.ps1'
if($Action -in @('ArmOnce','EnablePersistentBoot')){
    if($Action -eq 'EnablePersistentBoot'){
        if(-not $VisualBootConfirmed){throw 'Persistent boot requires visual boot confirmation; use the explicit switch only after checking the real pre-session test.'}
        $boot=Read-ComponentJson (Join-Path $data 'Boot-status.json')
        if($boot.State -ne 'HandedOff'){throw 'No successful pre-session handoff recorded.'}
        $proof=Read-ComponentJson (Join-Path $data 'boot-proof.json')
        if(-not $proof.Success -or $proof.BootId -cne $boot.BootId -or $proof.Scope -cne 'PreloginFirmwareOnly'){throw 'No successful pre-session firmware readback recorded for that boot.'}
        $config.PersistentBoot=$true
    }else{$config.PersistentBoot=$false}
    $bootTask=Get-ScheduledTask -TaskName 'Codex-ASUS-KeyboardPrelogin'
    if(@($bootTask.Actions | Where-Object {$_.Arguments -like ('*"'+$runner+'" -Mode Boot')}).Count -ne 1){throw 'Unexpected boot task.'}
    Write-ComponentJson (Join-Path $data 'config.json') $config
    Write-ComponentJson (Join-Path $data 'boot-armed.json') @{Version=1;NotBeforeBootId=(Get-ComponentBootId);Utc=[DateTime]::UtcNow.ToString('o')}
    Enable-ScheduledTask -TaskName 'Codex-ASUS-KeyboardPrelogin' | Out-Null
    Write-Output ('Boot mode prepared: '+$Action+'. No restart requested.')
    return
}
# Rollback affects only tasks whose actions match this protected installation.
$cycle=Get-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle'
if(@($cycle.Actions | Where-Object {$_.Arguments -like ('*"'+$runner+'" -Mode Desktop')}).Count -ne 1){throw 'Cycle task is no longer owned by this component; no automatic overwrite.'}
$boot=Get-ScheduledTask -TaskName 'Codex-ASUS-KeyboardPrelogin' -ErrorAction SilentlyContinue
if($boot -and @($boot.Actions | Where-Object {$_.Arguments -like ('*"'+$runner+'" -Mode Boot')}).Count -ne 1){throw 'Unrelated boot task found.'}
Write-ComponentJson (Join-Path $data 'rollback-started.json') @{Utc=[DateTime]::UtcNow.ToString('o')}
Set-Content -LiteralPath (Join-Path $data 'stop.txt') -Value 'Cooperative rollback' -Encoding ASCII
$desktopStop=Join-Path $data 'desktop-runtime\stop.txt'
if(Test-Path -LiteralPath (Split-Path $desktopStop -Parent)){Set-Content -LiteralPath $desktopStop -Value 'Cooperative rollback' -Encoding ASCII}
Disable-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle' | Out-Null
if($boot){Disable-ScheduledTask -TaskName 'Codex-ASUS-KeyboardPrelogin' | Out-Null}
$mutex=Get-ComponentMutex;$held=$false
try{
    try{$held=$mutex.WaitOne(15000)}catch [Threading.AbandonedMutexException]{$held=$true}
    if(-not $held){throw 'Worker still owns a transaction; rollback stopped without forcing termination.'}
    if($config.InstallKind -eq 'Fresh'){
        Unregister-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle' -Confirm:$false
        if($boot){Unregister-ScheduledTask -TaskName 'Codex-ASUS-KeyboardPrelogin' -Confirm:$false}
        Write-ComponentJson (Join-Path $data 'rollback-complete.json') @{Utc=[DateTime]::UtcNow.ToString('o');State='Native ASUS handling restored';FilesRetained=$true}
        Write-Output 'Standalone tasks removed. Native ASUS handling retained; files/logs and current brightness preserved.'
        return
    }
    $preference=Read-AsusKeyboardPreference (Join-Path $data 'keyboard-state.json')
    if($preference){
        Copy-Item -LiteralPath (Join-Path $config.LegacyRoot 'keyboard-state.json') -Destination (Join-Path $data ('legacy-preference-before-rollback-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json'))
        Copy-Item -LiteralPath (Join-Path $data 'keyboard-state.json') -Destination (Join-Path $config.LegacyRoot 'keyboard-state.json') -Force
    }
    foreach($entry in @(@{Name='Codex-ASUS-KeyboardCycle';File='legacy-cycle.xml'},@{Name='Codex-ASUS-KeyboardMaximum';File='legacy-maximum.xml'})){
        Register-ScheduledTask -TaskName $entry.Name -Xml (Get-Content -LiteralPath (Join-Path $data $entry.File) -Raw) -Force | Out-Null
    }
    if($boot){Unregister-ScheduledTask -TaskName 'Codex-ASUS-KeyboardPrelogin' -Confirm:$false}
    $legacyStop=Join-Path $config.LegacyRoot '.analysis\cycle-runtime\stop.txt'
    if(Test-Path -LiteralPath $legacyStop){Remove-Item -LiteralPath $legacyStop}
}finally{if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
if($config.LegacyCycleEnabled){
    $exitTimer=[Diagnostics.Stopwatch]::StartNew()
    while((Get-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle').State -eq 'Running'){
        if($exitTimer.Elapsed.TotalSeconds -gt 15){throw 'Original task restored, but old wrapper has not exited; start the legacy task after it exits.'}
        Start-Sleep -Milliseconds 250
    }
    Start-ScheduledTask -TaskName 'Codex-ASUS-KeyboardCycle'
}
Write-ComponentJson (Join-Path $data 'rollback-complete.json') @{Utc=[DateTime]::UtcNow.ToString('o');State='Original tasks restored';Preference=$preference.Level}
Write-Output 'Original task definitions restored. Code, logs and backup files retained. No ASUS service or driver changed.'
