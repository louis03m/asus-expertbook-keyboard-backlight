# Pure installation classification. No task, filesystem or controller mutations.
function Get-KeyboardInstallationPlan {
    param($Cycle,$Maximum,$Boot,$InstalledConfig,[string]$CodeRoot,[string]$OwnerSid,[string]$OwnerName,[string]$OwnerShort,[string]$LegacyDirectory)
    $runner=Join-Path $CodeRoot 'Run-Component.ps1'
    function Test-OwnedAction($Task,[string]$Script,[string]$Suffix=''){
        return ($Task -and @($Task.Actions).Count -eq 1 -and $Task.Actions[0].Arguments -like ('*"'+$Script+'"'+$Suffix))
    }
    if($InstalledConfig){
        if($InstalledConfig.Version -ne 1 -or $InstalledConfig.CodeRoot -cne $CodeRoot -or $InstalledConfig.OwnerSid -cne $OwnerSid){throw 'Installed component identity does not match.'}
        if(-not(Test-OwnedAction $Cycle $runner ' -Mode Desktop') -or -not(Test-OwnedAction $Boot $runner ' -Mode Boot')){throw 'Installed component task actions do not match.'}
        $kind=if($InstalledConfig.InstallKind -eq 'Fresh'){'Fresh'}else{'Legacy'}
        if($kind -eq 'Fresh' -and $Maximum){throw 'Unexpected maximum task beside standalone installation.'}
        if($kind -eq 'Legacy' -and -not(Test-OwnedAction $Maximum (Join-Path $InstalledConfig.LegacyRoot 'Watch-AsusKeyboardMaximum.ps1') ' -Action*')){
            # The original task runs the watcher directly; verify its quoted path,
            # allowing its original audit arguments.
            if(-not $Maximum -or @($Maximum.Actions | Where-Object {$_.Arguments -like ('*"'+(Join-Path $InstalledConfig.LegacyRoot 'Watch-AsusKeyboardMaximum.ps1')+'"*')}).Count -ne 1){throw 'Legacy fallback task changed.'}
        }
        return [pscustomobject]@{Mode='Update';InstallKind=$kind;LegacyRoot=$InstalledConfig.LegacyRoot}
    }
    if(-not $Cycle -and -not $Maximum -and -not $Boot){return [pscustomobject]@{Mode='Fresh';InstallKind='Fresh';LegacyRoot=$null}}
    if($Boot -or -not $Cycle -or -not $Maximum){throw 'Partial or unrelated keyboard tasks found; no changes.'}
    if(@($Cycle.Actions).Count -ne 1 -or $Cycle.Actions[0].Arguments -notmatch '(?i)(?:^|\s)-File\s+"([^"]+\\Watch-AsusKeyboardCycle\.ps1)"(?:\s|$)'){throw 'Cannot identify the existing cycle script.'}
    $legacy=[IO.Path]::GetFullPath((Split-Path $Matches[1] -Parent))
    if($legacy.StartsWith('\\')){throw 'Local installation required.'}
    if($LegacyDirectory -and [IO.Path]::GetFullPath($LegacyDirectory) -ine $legacy){throw 'Requested legacy folder does not match task action.'}
    if(@($Maximum.Actions | Where-Object {$_.Arguments -like ('*"'+(Join-Path $legacy 'Watch-AsusKeyboardMaximum.ps1')+'"*')}).Count -ne 1){throw 'Maximum task does not match existing cycle folder.'}
    if([string]$Cycle.Principal.LogonType -ne 'Interactive' -or [string]$Cycle.State -eq 'Disabled' -or [string]$Maximum.State -ne 'Disabled'){throw 'Existing cycle must be enabled and maximum fallback disabled.'}
    if($Cycle.Principal.UserId -notin @($OwnerSid,$OwnerName,$OwnerShort)){throw 'Existing cycle belongs to another owner.'}
    return [pscustomobject]@{Mode='Legacy';InstallKind='Legacy';LegacyRoot=$legacy}
}
