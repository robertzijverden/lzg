param(
    [string]$SourceMediaRoot = "$PSScriptRoot\Workspace\Media",
    [string]$OutputRoot = "$PSScriptRoot\Workspace\USB",
    [switch]$Force
)

function Write-Log {
    param([string]$Message)
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
}

function Ensure-Path {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

$SourceMediaRoot = Resolve-Path $SourceMediaRoot -ErrorAction Stop
if (Test-Path $OutputRoot) {
    if ($Force) {
        Write-Log "Schone USB-buildmap maken: $OutputRoot"
        Remove-Item -Path "$OutputRoot\*" -Recurse -Force -ErrorAction SilentlyContinue
    }
}
else {
    Ensure-Path $OutputRoot
}

Write-Log "Kopieer bootmedia van: $SourceMediaRoot"
Get-ChildItem -Path $SourceMediaRoot -Force | ForEach-Object {
    $target = Join-Path $OutputRoot $_.Name
    if (Test-Path $target) {
        Remove-Item -Path $target -Recurse -Force -ErrorAction SilentlyContinue
    }
    Copy-Item -Path $_.FullName -Destination $OutputRoot -Recurse -Force
}

foreach ($folder in @('Config', 'DriverPacks', 'Tools')) {
    $source = Join-Path $PSScriptRoot $folder
    if (-not (Test-Path $source)) {
        Write-Log "Bronmap bestaat niet: $source"
        continue
    }

    Write-Log "Kopieer $folder naar USB-build: $OutputRoot"
    $destination = Join-Path $OutputRoot $folder
    if (Test-Path $destination) {
        Remove-Item -Path $destination -Recurse -Force -ErrorAction SilentlyContinue
    }
    Copy-Item -Path $source -Destination $OutputRoot -Recurse -Force
}

Write-Log "USB-build gereed: $OutputRoot"
Write-Log "Controleer dat de USB-structuur root Boot, EFI, sources en OSDCloud bevat."
