# Preference storage only. No WMI, registry, process or controller operations.
function Read-AsusKeyboardPreference {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $null}
    if((Get-Item -LiteralPath $Path).Length -gt 4096){throw 'Keyboard preference file is too large.'}
    $record=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if($null -eq $record -or $record.Version -ne 1 -or $record.Model -cne 'B1502CBA' -or $record.Bios -cne 'B1502CBA.316'){
        throw 'Keyboard preference schema or device binding is invalid.'
    }
    if($record.Level -cnotin @('Off','Medium','High')){throw 'Keyboard preference level is invalid.'}
    $firmware=@{Off='0x00';Medium='0x03';High='0xDF'}[$record.Level]
    $logical=if($record.Level -eq 'Off'){128}else{131}
    if($record.Firmware -cne $firmware -or $record.AsusRegistry -ne $logical){throw 'Keyboard preference confirmation fields are inconsistent.'}
    return $record
}
function Save-AsusKeyboardPreference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][ValidateSet('Off','Medium','High')][string]$Level,
        [Parameter(Mandatory=$true)][ValidateSet('Hotkey','InitialCapture','Migration','Verification','VerificationRestore')][string]$Source
    )
    $Level=@{off='Off';medium='Medium';high='High'}[$Level.ToLowerInvariant()]
    $previous=$null
    try{$previous=Read-AsusKeyboardPreference -Path $Path}catch{ }
    if($null -ne $previous -and $previous.Level -ceq $Level){return $previous}
    $record=[ordered]@{
        Version=1;Model='B1502CBA';Bios='B1502CBA.316';Level=$Level
        Firmware=@{Off='0x00';Medium='0x03';High='0xDF'}[$Level]
        AsusRegistry=$(if($Level -eq 'Off'){128}else{131})
        SavedUtc=[DateTime]::UtcNow.ToString('o');Source=$Source
    }
    $absolute=[IO.Path]::GetFullPath($Path)
    $temporary=$absolute+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    $stream=$null
    try{
        $encoding=New-Object Text.UTF8Encoding($false)
        $bytes=$encoding.GetBytes(($record | ConvertTo-Json -Depth 4))
        $stream=New-Object IO.FileStream($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None,4096,[IO.FileOptions]::WriteThrough)
        $stream.Write($bytes,0,$bytes.Length);$stream.Flush($true);$stream.Dispose();$stream=$null
        if([IO.File]::Exists($absolute)){[IO.File]::Replace($temporary,$absolute,($absolute+'.previous'),$false)}else{[IO.File]::Move($temporary,$absolute)}
    }finally{
        if($null -ne $stream){$stream.Dispose()}
        if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary}
    }
    return (Read-AsusKeyboardPreference -Path $absolute)
}
