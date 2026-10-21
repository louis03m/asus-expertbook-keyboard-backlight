$ErrorActionPreference='Stop'
function Write-ComponentJson([string]$Path,$Value){
    $temporary=$Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    [IO.File]::WriteAllText($temporary,($Value | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
    if([IO.File]::Exists($Path)){[IO.File]::Replace($temporary,$Path,($Path+'.previous'),$false)}else{[IO.File]::Move($temporary,$Path)}
}
function Read-ComponentJson([string]$Path){
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $null}
    if((Get-Item -LiteralPath $Path).Length -gt 16384){throw 'Oversized component record.'}
    $stream=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $reader=[IO.StreamReader]::new($stream)
    try{return ($reader.ReadToEnd() | ConvertFrom-Json)}finally{$reader.Dispose()}
}
function Get-ComponentBootId {
    return (Get-CimInstance -Namespace root/cimv2 -ClassName Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o')
}
function Get-ComponentMutex {
    $security=[Security.AccessControl.MutexSecurity]::new()
    foreach($sid in @('S-1-5-18','S-1-5-32-544')){
        $security.AddAccessRule([Security.AccessControl.MutexAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','Allow'))
    }
    $created=$false
    return [Threading.Mutex]::new($false,'Global\Codex.Asus.KeyboardMaximum.Listener',[ref]$created,$security)
}
function Get-NextKeyboardLevel([ValidateSet('Off','Medium','High')][string]$Level,[int]$Presses=1){
    if($Presses -lt 1 -or $Presses -gt 30){throw 'Invalid key count.'}
    $levels=@('Off','Medium','High')
    return $levels[([Array]::IndexOf($levels,$Level)+$Presses)%3]
}
function Read-PreloginChoice([string]$Path,[string]$BootId,[string]$Bios){
    $record=Read-ComponentJson $Path
    if($null -eq $record){return $null}
    if($record.Version -ne 1 -or $record.BootId -cne $BootId -or $record.Model -cne 'B1502CBA' -or $record.Bios -cne $Bios -or $record.Level -cnotin @('Off','Medium','High') -or $record.Confirmation -cne 'FirmwareReadbackOnly'){
        throw 'Prelogin choice binding is invalid.'
    }
    if($record.Readback -cne @{Off='0x00';Medium='0x03';High='0xDF'}[$record.Level]){throw 'Invalid prelogin readback.'}
    return $record
}
function Test-ComponentExchange($Result,[ValidateSet('Off','Medium','High')][string]$Level){
    if($null -eq $Result -or $Result.State -cnotin @('AlreadyRequestedState-NoWrite','State-Readback-Confirmed')){return $false}
    if($Result.After -cne @{Off='0x00';Medium='0x03';High='0xDF'}[$Level]){return $false}
    $restoration=@($Result.Events | Where-Object {$_.Name -eq 'Shared-slot-restore'})
    return ($restoration.Count -eq 1 -and $restoration[0].Detail.Verified -eq $true)
}
function Read-LatestComponentChoice([string]$PreferencePath,[string]$PendingPath,[string]$Bios){
    $confirmed=Read-AsusKeyboardPreference $PreferencePath
    if(-not $confirmed){throw 'Confirmed preference missing; no default level.'}
    $pending=Read-ComponentJson $PendingPath
    if($pending){
        $pending=Read-PreloginChoice $PendingPath ([string]$pending.BootId) $Bios
        $time=[DateTimeOffset]::Parse($pending.Utc)
        if($time -gt [DateTimeOffset]::Parse($confirmed.SavedUtc)){
            return [pscustomobject]@{Level=$pending.Level;Pending=$true;SourceBootId=$pending.BootId}
        }
    }
    return [pscustomobject]@{Level=$confirmed.Level;Pending=$false;SourceBootId=$null}
}
