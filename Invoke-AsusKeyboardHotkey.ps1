[CmdletBinding()]
param([ValidateSet('Inspect','On','Off')][string]$Action='Inspect')
# Public distribution: fail closed before any window/mailbox operation.
. (Join-Path $PSScriptRoot 'Assert-Compatibility.ps1')
Assert-AsusKeyboardCompatibility

$ErrorActionPreference='Stop'
if(-not ('AsusKeyboardWindow' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AsusKeyboardWindow {
    public static uint VerifiedProcess;
    public static string VerifiedImage;
    [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
    public static extern IntPtr FindWindowW(string cls,string title);
    [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
    public static extern IntPtr FindWindowExW(IntPtr parent,IntPtr after,string cls,string title);
    [DllImport("user32.dll",SetLastError=true)]
    public static extern uint GetWindowThreadProcessId(IntPtr window,out uint process);
    [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
    public static extern uint RegisterWindowMessageW(string message);
    [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
    public static extern IntPtr SendMessageTimeoutW(IntPtr window,uint message,UIntPtr wp,IntPtr lp,uint flags,uint timeout,out UIntPtr result);
}
'@
}
$window=[AsusKeyboardWindow]::FindWindowW('ASUS AsHotkeyExec App Class','ASUS AsHotkeyExec App')
if($window -eq [IntPtr]::Zero){$window=[AsusKeyboardWindow]::FindWindowW('ASUS AsHotkeyExec KeyLock App Class','ASUS AsHotkeyExec KeyLock App')}
foreach($class in @('ASUS AsHotkeyExec App Class','ASUS AsHotkeyExec KeyLock App Class')) {
    if($window -eq [IntPtr]::Zero){$window=[AsusKeyboardWindow]::FindWindowW($class,$null)}
    if($window -eq [IntPtr]::Zero){$window=[AsusKeyboardWindow]::FindWindowExW([IntPtr](-3),[IntPtr]::Zero,$class,$null)}
}
if($window -eq [IntPtr]::Zero){$window=[AsusKeyboardWindow]::FindWindowW('HCONTROL','HControl')}
if($window -eq [IntPtr]::Zero){throw 'The ASUS keyboard agent window was not found; no message sent.'}
[uint32]$agentPid=0
$null=[AsusKeyboardWindow]::GetWindowThreadProcessId($window,[ref]$agentPid)
$expected='C:\Windows\System32\DriverStore\FileRepository\asussci2.inf_amd64_197d319fab43e0fe\ASUSOptimization\AsusOptimizationStartupTask.exe'
if([AsusKeyboardWindow]::VerifiedProcess -ne $agentPid) {
    $agent=Get-CimInstance -Namespace root/cimv2 -ClassName Win32_Process -Filter ('ProcessId='+$agentPid)
    if($agent.ExecutablePath -ine $expected){throw ('Unexpected ASUS agent image: '+$agent.ExecutablePath)}
    if($agent.SessionId -ne (Get-Process -Id $PID).SessionId){throw 'The ASUS agent belongs to a different session.'}
    if((Get-FileHash -LiteralPath $expected).Hash -ine 'EABE93FE2EBD5A406F37BBFD1B4D0F295A58A8D2BE46DE4C1F69FDCF9689761A'){throw 'ASUS agent changed; static message decoding must be rechecked.'}
    [AsusKeyboardWindow]::VerifiedProcess=$agentPid
    [AsusKeyboardWindow]::VerifiedImage=$agent.ExecutablePath
}
$result=[ordered]@{Action=$Action;Window=('0x{0:X}' -f $window.ToInt64());ProcessId=$agentPid;Image=[AsusKeyboardWindow]::VerifiedImage;Sent=$false}
if($Action -ne 'Inspect') {
    $code=if($Action -eq 'On'){0xC4}else{0xC5}
    $message=[AsusKeyboardWindow]::RegisterWindowMessageW('ACPI Simulation through ATKHotkey from Application')
    if($message -lt 0xC000){throw 'Failed to register the known ASUS message.'}
    [UIntPtr]$reply=[UIntPtr]::Zero
    $sent=[AsusKeyboardWindow]::SendMessageTimeoutW($window,$message,[UIntPtr]([uint32]$code),[IntPtr]::Zero,0x22,1000,[ref]$reply)
    if($sent -eq [IntPtr]::Zero){throw ('ASUS message failed or timed out; no retry. Win32='+[Runtime.InteropServices.Marshal]::GetLastWin32Error())}
    $result.Sent=$true;$result.Code=('0x{0:X2}' -f $code)
}
[pscustomobject]$result
