<#
.SYNOPSIS
  Builds the Radxa Orion O6 / O6N Android BIOS (Radxa edk2-cix + the patches in .\patches) in Docker
  and puts the result in .\output.

.EXAMPLE
  .\build.ps1 -O6             # Orion O6  -> .\output\O6-BIOS-1.3.2-android-dmod\
  .\build.ps1 -O6N            # Orion O6N -> .\output\O6N-BIOS-1.3.2-android-dmod\
  .\build.ps1 -O6 -O6N        # both boards, one after the other
  .\build.ps1 -O6 -Stock      # the same Android build without the patches -> ...-android\
  .\build.ps1 -O6 -DebugBuild # DEBUG firmware (verbose serial log)

  Without -O6 / -O6N it builds the O6.
#>
param(
  [switch]$O6,
  [switch]$O6N,
  [switch]$Stock,
  [switch]$DebugBuild,
  [string]$Ref = '1.3.2',
  [string]$OutputDir = (Join-Path $PSScriptRoot 'output'),
  [string]$Image = 'radxa-o6-bios-builder',
  [string]$SourceVolume = 'radxa-o6-bios-src'
)
$ErrorActionPreference = 'Stop'

$boards = @()
if ($O6)  { $boards += 'O6' }
if ($O6N) { $boards += 'O6N' }
if ($boards.Count -eq 0) {
  $boards = @('O6')
  Write-Host 'No board given: building the Orion O6 (-O6N for the Orion O6N, -O6 -O6N for both).' -ForegroundColor Yellow
}
$patches = if ($Stock) { '0' } else { '1' }
$target  = if ($DebugBuild) { 'DEBUG' } else { 'RELEASE' }
New-Item -ItemType Directory -Force $OutputDir | Out-Null
$OutputDir = (Resolve-Path $OutputDir).Path

docker build -t $Image $PSScriptRoot
if ($LASTEXITCODE -ne 0) { throw 'docker build failed' }

docker volume create $SourceVolume | Out-Null

foreach ($board in $boards) {
  Write-Host "`n=== Building the $board BIOS ===" -ForegroundColor Cyan
  docker run --rm `
    -v "${SourceVolume}:/work" `
    -v "${OutputDir}:/out" `
    -e "EDK2_CIX_REF=$Ref" -e "BOARD=$board" -e "UEFI_TARGET=$target" -e "PATCHES=$patches" `
    $Image
  if ($LASTEXITCODE -ne 0) { throw "$board BIOS build failed (exit code $LASTEXITCODE)" }
}

Write-Host "`nDone ($($boards -join ', ')). Output in $OutputDir" -ForegroundColor Green
Get-ChildItem $OutputDir
