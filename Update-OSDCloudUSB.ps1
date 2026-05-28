param(
    [string]$Root = "$PSScriptRoot",
    [string]$WorkspacePath = "$PSScriptRoot\Workspace",
    [switch]$CatalogOnly,
    [switch]$UpdatePhysicalUSB,
    [switch]$CreatePhysicalUSB,
    [switch]$PSUpdate
)

function Write-Log {
    param([string]$Message)
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
}

Write-Log "Start update van OSDCloud USB build."

# Sync config files uit GitHub en lokale root Config
$remoteConfigUrls = @(
    "https://raw.githubusercontent.com/robertzijverden/lzg/main/osdcloud-config.json",
    "https://raw.githubusercontent.com/robertzijverden/lzg/main/Config/osdcloud-config.json"
)
$localConfig = Join-Path $Root 'Config\osdcloud-config.json'
$configContent = $null

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    foreach ($remoteConfig in $remoteConfigUrls) {
        Write-Log "Proberen configuratie op te halen van GitHub: $remoteConfig"
        try {
            $response = Invoke-WebRequest -Uri $remoteConfig -UseBasicParsing -ErrorAction Stop
            $configContent = ([string]$response.Content).TrimStart([char]0xFEFF)
            Write-Log "Configuratie gevonden op GitHub: $remoteConfig"
            break
        }
        catch {
            Write-Log "Niet gevonden op GitHub: $remoteConfig"
        }
    }

    if (-not $configContent) {
        throw "Geen GitHub-config gevonden."
    }

    $existingConfig = if (Test-Path $localConfig) { Get-Content -Path $localConfig -Raw | ConvertFrom-Json } else { $null }
    $configObject = $configContent | ConvertFrom-Json

    if (-not $configObject.DriverManifestUrl -and $existingConfig -and $existingConfig.DriverManifestUrl) {
        Write-Log "Behoud bestaande DriverManifestUrl vanuit lokale config."
        if ($configObject.PSObject.Properties.Match('DriverManifestUrl').Count -eq 0) {
            $configObject | Add-Member -MemberType NoteProperty -Name DriverManifestUrl -Value $existingConfig.DriverManifestUrl
        }
        else {
            $configObject.DriverManifestUrl = $existingConfig.DriverManifestUrl
        }
    }

    if ($configObject.DriverManifestUrl -and $configObject.DriverManifestUrl -match '/Config/') {
        $alternateUrl = $configObject.DriverManifestUrl -replace '/Config/', '/'
        try {
            Invoke-WebRequest -Method Head -Uri $alternateUrl -UseBasicParsing -ErrorAction Stop | Out-Null
            Write-Log "Vervang DriverManifestUrl met alternatieve root URL: $alternateUrl"
            $configObject.DriverManifestUrl = $alternateUrl
        }
        catch {
            Write-Log "Alternatieve DriverManifestUrl niet gevonden: $alternateUrl"
        }
    }

    $configContent = $configObject | ConvertTo-Json -Depth 10
    $configContent | Set-Content -Path $localConfig -Encoding UTF8
    Write-Log "Configuratie bijgewerkt: $localConfig"
}
catch {
    if (Test-Path $localConfig) {
        Write-Log "GitHub-config niet bereikbaar, behoud lokale config: $localConfig"
    }
    else {
        throw "Kan config niet ophalen vanaf GitHub en lokaal bestand ontbreekt."
    }
}

# Werk offline driverpacks en toolupdates bij
$driverPackScript = Join-Path $Root 'Update-DriverPacks.ps1'
if (Test-Path $driverPackScript) {
    Write-Log "Update offline driverpacks en tools."
    if ($CatalogOnly) {
        & $driverPackScript -Root $Root -CatalogOnly
    }
    else {
        & $driverPackScript -Root $Root
    }
}
else {
    Write-Log "Update-DriverPacks.ps1 niet gevonden: $driverPackScript"
}

# Synchroniseer de LZG bestanden naar de OSDCloud workspace.
$buildScript = Join-Path $Root 'Build-OSDCloudUSB.ps1'
if (Test-Path $buildScript) {
    Write-Log "Synchroniseer LZG bestanden naar de OSDCloud workspace."
    & $buildScript -WorkspacePath $WorkspacePath -Force
}
else {
    throw "Build-OSDCloudUSB.ps1 niet gevonden: $buildScript"
}

if ($CreatePhysicalUSB -or $UpdatePhysicalUSB -or $PSUpdate) {
    Import-Module OSD -Force
    Set-OSDCloudWorkspace -WorkspacePath $WorkspacePath | Out-Null

    if ($CreatePhysicalUSB) {
        Write-Log "Nieuwe bootbare OSDCloud USB maken via OSD command: New-OSDCloudUSB"
        New-OSDCloudUSB -WorkspacePath $WorkspacePath
    }

    if ($UpdatePhysicalUSB -or $PSUpdate) {
        Write-Log "Bestaande OSDCloud USB bijwerken via OSD command: Update-OSDCloudUSB"
        if ($PSUpdate) {
            Update-OSDCloudUSB -PSUpdate
        }
        else {
            Update-OSDCloudUSB
        }
    }
}

Write-Log "OSDCloud USB update voltooid."
Write-Log "Gebruik OSD commands voor fysieke USB:"
Write-Log "  Nieuwe USB:      .\Update-OSDCloudUSB.ps1 -CreatePhysicalUSB"
Write-Log "  Bestaande USB:   .\Update-OSDCloudUSB.ps1 -UpdatePhysicalUSB"
