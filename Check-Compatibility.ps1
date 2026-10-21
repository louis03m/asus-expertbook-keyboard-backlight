[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Assert-Compatibility.ps1')
Assert-AsusKeyboardCompatibility
Write-Output 'Model, BIOS and ASUS image hashes match the tested machine. This check sends no keyboard/controller commands. Public installer has not been tested on a second computer.'
