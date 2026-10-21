# One bounded test of the ASUS AML mailbox path already present in this BIOS.
# No DLL loading, driver installation, service changes, raw ports, retries or polling.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$AuditDirectory,
    [switch]$AllowOffNoOp,
    [scriptblock]$BeforeBrightnessWrite
)
# Public distribution: fail closed before any window/mailbox operation.
. (Join-Path $PSScriptRoot 'Assert-Compatibility.ps1')
Assert-AsusKeyboardCompatibility

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $AuditDirectory -Force | Out-Null
$auditPath = Join-Path $AuditDirectory 'result.json'
$audit = [ordered]@{ Started = (Get-Date).ToString('o'); State = 'Starting'; Events = @(); WriteAttempts = 0; ControllerCalls = 0 }
function Save-Audit { $audit | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $auditPath -Encoding UTF8 }
function Record([string]$Name, $Detail) {
    $audit.Events += [ordered]@{ Time = (Get-Date).ToString('o'); Name = $Name; Detail = $Detail }
    Save-Audit
}
function Hex([byte[]]$Bytes) { [BitConverter]::ToString($Bytes).Replace('-', '') }
function Read-Slot {
    $instances = @(Get-CimInstance -Namespace root/wmi -ClassName MyWMIARGClass8)
    if ($instances.Count -ne 1 -or -not $instances[0].Active) { throw 'Slot 8 is not a unique active instance.' }
    if ($script:instanceName -and $instances[0].InstanceName -cne $script:instanceName) { throw 'Slot instance identity changed.' }
    if ($instances[0].WAG8.Count -ne 256) { throw 'Unexpected slot length.' }
    return $instances[0]
}
function Exchange([byte]$Command, [byte]$Value, [string]$Label) {
    $current = Read-Slot
    if ((Hex $current.WAG8) -cne (Hex $script:owned)) { throw 'Shared slot changed; stopping without overwriting it.' }
    [byte[]]$packet = New-Object byte[] 256
    $packet[0] = 0x30; $packet[2] = 1; $packet[4] = 0x10
    $packet[8] = $Command; $packet[9] = 0x90; $packet[10] = 0x54; $packet[11] = $Value
    Record ($Label + '-prepare') @{ Prefix = Hex $packet[0..15] }
    Set-CimInstance -InputObject $current -Property @{ WAG8 = $packet } | Out-Null
    $script:owned = $packet.Clone()
    $staged = Read-Slot
    if ((Hex $staged.WAG8) -cne (Hex $packet)) { throw 'Shared slot upload was not preserved; no method invoked.' }
    if ($Command -eq 0x81 -and $BeforeBrightnessWrite -and -not (& $BeforeBrightnessWrite)) {
        throw 'New hotkey pending; brightness write cancelled.'
    }
    $script:uncertain = $true
    $audit.ControllerCalls++
    if ($Command -eq 0x81) { $audit.WriteAttempts++ }
    Record ($Label + '-invoke') @{ Method = 'MyFn1'; Indx = 8 }
    $returnValue = Invoke-CimMethod -InputObject $script:method -MethodName MyFn1 -Arguments @{ Indx = [uint32]8 }
    $responseInstance = Read-Slot
    [byte[]]$response = $responseInstance.WAG8
    # Only status/error and five returned data bytes may change in G0_1.
    for ($i = 0; $i -lt 256; $i++) {
        if ($i -in @(6,7,9,10,11,12,13)) { continue }
        if ($response[$i] -ne $packet[$i]) { throw "Unexpected response change at byte $i; slot ownership uncertain." }
    }
    $script:owned = $response.Clone()
    $script:uncertain = $false
    Record ($Label + '-response') @{ Prefix = Hex $response[0..15]; MethodReturn = $returnValue.ReturnValue; Status = $response[6]; Error = $response[7]; Data = $response[9] }
    if ($response[6] -ne 0x80 -or $response[7] -ne 0) { throw 'AML reported an unsuccessful mailbox transaction; no retry.' }
    return [int]$response[9]
}
$script:instanceName = $null; $script:owned = $null; $script:uncertain = $false; $backup = $null
$transactionMutex = $null; $transactionHeld = $false
Save-Audit
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator token required.' }
    $transactionMutex = New-Object Threading.Mutex($false, 'Global\Codex.Asus.WAG8.Mailbox')
    try { $transactionHeld = $transactionMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $transactionHeld = $true }
    if (-not $transactionHeld) { throw 'Another Codex WMI exchange is active; no retry.' }
    $arg = Read-Slot
    $script:instanceName = $arg.InstanceName
    $methods = @(Get-CimInstance -Namespace root/wmi -ClassName MyWMIMethodClass | Where-Object { $_.InstanceName -ceq $script:instanceName -and $_.Active })
    if ($methods.Count -ne 1) { throw 'No unique matching active WMI method instance.' }
    $script:method = $methods[0]
    [byte[]]$backup = $arg.WAG8
    [IO.File]::WriteAllBytes((Join-Path $AuditDirectory 'WAG8-original.bin'), $backup)
    Record 'Preflight' @{ Instance = $script:instanceName; Original = Hex $backup }
    # Conservative: leave any previously used slot untouched, even if not busy.
    if (@($backup | Where-Object { $_ -ne 0 }).Count -ne 0) { throw 'Slot 8 is nonempty; leaving it untouched.' }
    $script:owned = $backup.Clone()
    $before = Exchange 0x80 0 'Read-before'
    $audit.Before = ('0x{0:X2}' -f $before); Save-Audit
    if ($before -eq 0 -and $AllowOffNoOp) {
        $audit.State = 'Off-NoWrite'
    } elseif ($before -eq 0xDF) {
        $audit.State = 'AlreadyDF-NoWrite'
    } elseif ($before -eq 3) {
        $null = Exchange 0x81 0xDF 'Write-DF'
        $after = Exchange 0x80 0 'Read-after'
        $audit.After = ('0x{0:X2}' -f $after)
        if ($after -ne 0xDF) { throw 'Readback differs from DF; no repeat or automatic reapplication.' }
        $audit.State = 'DF-Readback-Confirmed-Visual-Confirmation-Needed'
    } else {
        throw ('Unexpected initial value 0x{0:X2}; no brightness write.' -f $before)
    }
} catch {
    $audit.State = 'Stopped'; $audit.Error = $_.Exception.Message
    Record 'Error' $_.Exception.ToString()
} finally {
    if ($null -ne $backup -and $null -ne $script:owned -and -not $script:uncertain) {
        try {
            $latest = Read-Slot
            if ((Hex $latest.WAG8) -ceq (Hex $script:owned)) {
                Set-CimInstance -InputObject $latest -Property @{ WAG8 = $backup } | Out-Null
                $check = Read-Slot
                Record 'Shared-slot-restore' @{ Verified = ((Hex $check.WAG8) -ceq (Hex $backup)) }
            } else { Record 'Shared-slot-restore-skipped' 'Changed by another client; not overwritten.' }
        } catch { Record 'Shared-slot-restore-error' $_.Exception.Message }
    }
    $audit.Finished = (Get-Date).ToString('o'); Save-Audit
    if ($transactionHeld) { $transactionMutex.ReleaseMutex() }
    if ($null -ne $transactionMutex) { $transactionMutex.Dispose() }
}
