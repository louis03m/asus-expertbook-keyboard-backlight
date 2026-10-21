# Read-only preflight. No mailbox, controller or keyboard commands.
function Assert-AsusKeyboardCompatibility {
    $model = (Get-CimInstance -Namespace root/cimv2 -ClassName Win32_ComputerSystem).Model
    $bios = (Get-CimInstance -Namespace root/cimv2 -ClassName Win32_BIOS).SMBIOSBIOSVersion
    if ($model -notmatch '\bB1502CBA(?:_|\b)' -or $bios -cnotin @('B1502CBA.316','B1502CBA.317')) {
        throw 'Unsupported model/BIOS. This package only accepts B1502CBA / B1502CBA.316 or B1502CBA.317. Do not bypass this check.'
    }
    $driverRoot = 'C:\Windows\System32\DriverStore\FileRepository\asussci2.inf_amd64_197d319fab43e0fe\ASUSOptimization'
    $images = @{
        'AsusOptimization.exe' = 'E160B6DE0ADAB88D834AABA6D3086495115B6CC23E8734273C5AD7DCCDA4340B'
        'AsusOptimizationStartupTask.exe' = 'EABE93FE2EBD5A406F37BBFD1B4D0F295A58A8D2BE46DE4C1F69FDCF9689761A'
    }
    foreach ($name in $images.Keys) {
        $path = Join-Path $driverRoot $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $images[$name]) {
            throw ('Unverified ASUS driver/agent: ' + $name + '. Do not bypass the check.')
        }
    }
}
