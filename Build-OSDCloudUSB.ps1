param(
    [string]$WorkspacePath = "$PSScriptRoot\Workspace",
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

function Sync-Folder {
    param(
        [string]$Source,
        [string]$Destination,
        [switch]$Clean
    )

    if (-not (Test-Path $Source)) {
        Write-Log "Bronmap bestaat niet, overslaan: $Source"
        return
    }

    if ($Clean -and (Test-Path $Destination)) {
        Remove-Item -Path $Destination -Recurse -Force -ErrorAction SilentlyContinue
    }

    Ensure-Path $Destination
    Get-ChildItem -Path $Source -Force | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $Destination -Recurse -Force
    }
}

$WorkspacePath = Resolve-Path $WorkspacePath -ErrorAction Stop
$mediaPath = Join-Path $WorkspacePath 'Media'

if (-not (Test-Path (Join-Path $mediaPath 'sources\boot.wim'))) {
    throw "OSDCloud Media ontbreekt of is niet door OSDCloud gebouwd: $mediaPath"
}

Write-Log "Gebruik bestaande OSDCloud workspace: $WorkspacePath"
Write-Log "Bootmedia blijft beheerd door OSDCloud: $mediaPath"

Sync-Folder -Source (Join-Path $PSScriptRoot 'Config') -Destination (Join-Path $WorkspacePath 'Config') -Clean:$Force
Sync-Folder -Source (Join-Path $PSScriptRoot 'DriverPacks') -Destination (Join-Path $WorkspacePath 'DriverPacks') -Clean:$Force
Sync-Folder -Source (Join-Path $PSScriptRoot 'Tools') -Destination (Join-Path $WorkspacePath 'DriverPacks\VendorTools') -Clean:$Force

Write-Log "LZG Config/DriverPacks/Tools zijn naar de OSDCloud workspace gesynchroniseerd."
Write-Log "Maak een nieuwe bootbare USB met:"
Write-Log "  Import-Module OSD; Set-OSDCloudWorkspace -WorkspacePath `"$WorkspacePath`"; New-OSDCloudUSB"
Write-Log "Werk een bestaande OSDCloud USB bij met:"
Write-Log "  Import-Module OSD; Set-OSDCloudWorkspace -WorkspacePath `"$WorkspacePath`"; Update-OSDCloudUSB"
