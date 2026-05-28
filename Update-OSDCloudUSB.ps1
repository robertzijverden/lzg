param(
    [string]$Root = "$PSScriptRoot",
    [string]$OutputFolder = "$PSScriptRoot\Workspace\USB",
    [string]$UsbDriveLetter = '',
    [switch]$CatalogOnly
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
            $configContent = Invoke-WebRequest -Uri $remoteConfig -UseBasicParsing -ErrorAction Stop | Select-Object -ExpandProperty Content
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

# Bouw de USB-image in Workspace\USB
$buildScript = Join-Path $Root 'Build-OSDCloudUSB.ps1'
if (Test-Path $buildScript) {
    Write-Log "Bouw de USB masterfolder."
    & $buildScript -Force
}
else {
    throw "Build-OSDCloudUSB.ps1 niet gevonden: $buildScript"
}

if ($UsbDriveLetter) {
    $UsbDrive = "$UsbDriveLetter`:"
    if (-not (Test-Path $UsbDrive)) {
        throw "USB-station niet gevonden op letter: $UsbDriveLetter"
    }

    Write-Log "Kopieer bestanden naar USB: $UsbDrive"
    Get-ChildItem -Path $OutputFolder -Force | ForEach-Object {
        $target = Join-Path $UsbDrive $_.Name
        if (Test-Path $target) {
            Remove-Item -Path $target -Recurse -Force -ErrorAction SilentlyContinue
        }
        Copy-Item -Path $_.FullName -Destination $UsbDrive -Recurse -Force
    }
    Write-Log "USB bijgewerkt op $UsbDrive"
}

Write-Log "OSDCloud USB update voltooid."
Write-Log "Gebruik $OutputFolder als master USB-output of kopieer handmatig naar een geformatteerde USB-stick."
