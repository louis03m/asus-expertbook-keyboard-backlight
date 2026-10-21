[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$AuditDirectory,
    [ValidateRange(0,86400)][int]$Seconds = 0
)
# Read-only registry notifications follow ASUS's normal on/off decisions.
# WMI exchanges occur only on startup or a notification while ASUS says on.
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $AuditDirectory -Force | Out-Null
$statusPath = Join-Path $AuditDirectory 'status.json'
$logPath = Join-Path $AuditDirectory 'events.jsonl'
$stopPath = Join-Path $AuditDirectory 'stop.txt'
$listenerMutex = $null; $listenerHeld = $false
$registryBase = $null; $registryKey = $null; $registrySignal = $null
$runId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
function Set-State([string]$State, [string]$Detail = '') {
    @{ State=$State; Detail=$Detail; Time=(Get-Date).ToString('o'); ProcessId=$PID; RunId=$runId } | ConvertTo-Json | Set-Content $statusPath -Encoding UTF8
}
function Log($Data) { $Data | ConvertTo-Json -Depth 5 -Compress | Add-Content $logPath -Encoding UTF8 }
try {
    # The EC address and command were verified on this exact model/BIOS only.
    $model = (Get-CimInstance -Namespace root/cimv2 -ClassName Win32_ComputerSystem).Model
    $bios = (Get-CimInstance -Namespace root/cimv2 -ClassName Win32_BIOS).SMBIOSBIOSVersion
    if ($model -notmatch '\bB1502CBA(?:_|\b)' -or $bios -cnotin @('B1502CBA.316','B1502CBA.317')) {
        throw ('Unverified model/BIOS; no EC commands: ' + $model + ' / ' + $bios)
    }
    $listenerMutex = New-Object Threading.Mutex($false, 'Global\Codex.Asus.KeyboardMaximum.Listener')
    try { $listenerHeld = $listenerMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $listenerHeld = $true }
    if (-not $listenerHeld) { throw 'A keyboard maximum listener is already running.' }
    if (Test-Path $stopPath) { Set-State 'Stopped' 'Stop marker exists.'; return }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class AsusRegistryNotification {
    [DllImport("advapi32.dll", SetLastError=true)]
    private static extern int RegNotifyChangeKeyValue(SafeRegistryHandle key,
        [MarshalAs(UnmanagedType.Bool)] bool subtree, uint filter,
        SafeWaitHandle signal, [MarshalAs(UnmanagedType.Bool)] bool asynchronous);
    public static void Arm(SafeRegistryHandle key, SafeWaitHandle signal) {
        int error = RegNotifyChangeKeyValue(key, false, 0x10000004, signal, true);
        if (error != 0) throw new Win32Exception(error);
    }
}
'@
    $registryBase = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
    $registryKey = $registryBase.OpenSubKey('SOFTWARE\ASUS\ASUS System Control Interface\AsusOptimization\ASUS Keyboard Hotkeys', $false)
    if ($null -eq $registryKey) { throw 'ASUS keyboard settings key not found.' }
    $registrySignal = New-Object Threading.AutoResetEvent($false)
    [AsusRegistryNotification]::Arm($registryKey.Handle,$registrySignal.SafeWaitHandle)
    Set-State 'Listening' ($bios + ' checked; read-only registry notifications; WMI correction only when ASUS says on.')
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $count = 0; $startup = $true
    while (($Seconds -eq 0 -or $clock.Elapsed.TotalSeconds -lt $Seconds) -and -not (Test-Path $stopPath)) {
        $triggered = $startup -or $registrySignal.WaitOne(1000)
        if (-not $triggered) { continue }
        if (-not $startup) { [AsusRegistryNotification]::Arm($registryKey.Handle,$registrySignal.SafeWaitHandle) }
        $reason = if ($startup) { 'Startup' } else { 'AsusRegistryChanged' }
        $startup = $false
        Start-Sleep -Milliseconds 200
        $logicalValue = $registryKey.GetValue('KeybdLightLevel', -1)
        if ($logicalValue -ne 0x83) {
            Log @{ Time=(Get-Date).ToString('o'); Reason=$reason; State='AsusOff-NoWrite'; RegistryValue=$logicalValue }
            continue
        }
        if (Test-Path $stopPath) { break }
        $count++
        $exchangePath = Join-Path $AuditDirectory ('transactions\{0}-{1:D5}' -f $runId,$count)
        $guard = { -not (Test-Path $stopPath) -and $registryKey.GetValue('KeybdLightLevel', -1) -eq 0x83 }.GetNewClosure()
        & (Join-Path $PSScriptRoot 'Wmi-Maximum-OneShot.ps1') -AuditDirectory $exchangePath -AllowOffNoOp -BeforeBrightnessWrite $guard
        $result = Get-Content (Join-Path $exchangePath 'result.json') -Raw | ConvertFrom-Json
        Log @{ Time=(Get-Date).ToString('o'); Reason=$reason; State=$result.State; Before=$result.Before; After=$result.After; WriteAttempts=$result.WriteAttempts; Error=$result.Error; Audit=$exchangePath }
        if ($result.State -eq 'Stopped' -and $result.Error -ne 'New hotkey pending; brightness write cancelled.') {
            throw ('WMI exchange stopped: ' + $result.Error)
        }
    }
    Set-State 'Stopped'
} catch { Set-State 'Error' $_.Exception.ToString(); throw }
finally {
    if ($null -ne $registryKey) { $registryKey.Dispose() }
    if ($null -ne $registryBase) { $registryBase.Dispose() }
    if ($null -ne $registrySignal) { $registrySignal.Dispose() }
    if ($listenerHeld) { $listenerMutex.ReleaseMutex() }
    if ($null -ne $listenerMutex) { $listenerMutex.Dispose() }
}
