param(
    [string]$Root = "C:\ProgramData\LZGOSD",
    [string]$ConfigPath = "$Root\Config\osdcloud-config.json",
    [string]$DriverRoot = "$Root\DriverPacks",
    [string]$ToolsRoot = "$Root\Tools",
    [psobject]$Config = $null
)

$ErrorActionPreference = "Continue"

function Write-LZGLog {
    param([string]$Message)
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
}

function Get-LZGConfig {
    if ($Config) {
        return $Config
    }
    if (Test-Path $ConfigPath) {
        return Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    }
    return $null
}

function Get-LZGHardwareInfo {
    $cs = Get-CimInstance Win32_ComputerSystem
    [pscustomobject]@{
        Manufacturer = $cs.Manufacturer
        Model        = $cs.Model
    }
}

function Resolve-LZGDriverPath {
    param(
        [string]$Manufacturer,
        [string]$Model
    )

    $mapPath = "$Root\Config\DriverMap.json"
    if (-not (Test-Path $mapPath)) {
        Write-LZGLog "DriverMap niet gevonden: $mapPath"
        return $null
    }

    $map = Get-Content $mapPath -Raw | ConvertFrom-Json
    $vendorKey = $null

    if ($Manufacturer -match "Dell") {
        $vendorKey = "Dell"
    }
    elseif ($Manufacturer -match "HP|Hewlett") {
        $vendorKey = "HP"
    }
    elseif ($Manufacturer -match "Microsoft") {
        $vendorKey = "Microsoft"
    }

    if (-not $vendorKey) {
        Write-LZGLog "Onbekende fabrikant: $Manufacturer"
        return $null
    }

    $vendorMap = $map.$vendorKey
    if (-not $vendorMap) {
        Write-LZGLog "Geen mapping voor fabrikant: $vendorKey"
        return $null
    }

    foreach ($entry in $vendorMap.PSObject.Properties) {
        if ($Model -like "*$($entry.Name)*") {
            $mappedPath = Join-Path $DriverRoot $entry.Value
            if (Test-Path $mappedPath) {
                return $mappedPath
            }
        }
    }

    if ($vendorKey -eq "HP") {
        $hpRoot = Join-Path $DriverRoot "HP"
        if (Test-Path $hpRoot) {
            $normalizedModel = ($Model -replace '[^a-zA-Z0-9]', '').ToLower()
            $hpMatch = Get-ChildItem -Path $hpRoot -Directory -ErrorAction SilentlyContinue |
                Where-Object {
                    $normalizedFolder = ($_.Name -replace '[^a-zA-Z0-9]', '').ToLower()
                    $normalizedModel -like "*$normalizedFolder*" -or $normalizedFolder -like "*$normalizedModel*"
                } |
                Sort-Object { $_.Name.Length } -Descending |
                Select-Object -First 1

            if ($hpMatch) {
                Write-LZGLog "Dynamische HP drivermap gevonden: $($hpMatch.FullName)"
                return $hpMatch.FullName
            }
        }
    }

    Write-LZGLog "Geen modelmatch gevonden voor model: $Model"
    return $null
}

function Resolve-LZGFirmwarePath {
    param(
        [string]$Manufacturer,
        [string]$Model
    )

    if ($Manufacturer -match "Dell") {
        return Join-Path $DriverRoot 'Firmware\Dell'
    }
    if ($Manufacturer -match "HP|Hewlett") {
        return Join-Path $DriverRoot 'Firmware\HP'
    }
    if ($Manufacturer -match "Microsoft") {
        return Join-Path $DriverRoot 'Firmware\Surface'
    }

    return $null
}

function Install-LZGOfflineDrivers {
    $hw = Get-LZGHardwareInfo
    Write-LZGLog "Fabrikant: $($hw.Manufacturer)"
    Write-LZGLog "Model: $($hw.Model)"

    $driverPath = Resolve-LZGDriverPath -Manufacturer $hw.Manufacturer -Model $hw.Model
    if (-not $driverPath) {
        Write-LZGLog "Geen driverpad gevonden. Offline driverinstallatie overgeslagen."
        return
    }

    if (-not (Test-Path $driverPath)) {
        Write-LZGLog "Driverpad bestaat niet: $driverPath"
        return
    }

    Write-LZGLog "Offline drivers installeren vanaf: $driverPath"
    $infFiles = Get-ChildItem -Path $driverPath -Filter *.inf -Recurse -File -ErrorAction SilentlyContinue
    if ($infFiles) {
        pnputil.exe /add-driver "$driverPath\*.inf" /subdirs /install
    }
    else {
        Write-LZGLog "Geen INF-bestanden gevonden. Zoek naar vendor installer in driverpad."
        Get-ChildItem -Path $driverPath -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            switch ($_.Extension.ToLower()) {
                '.msi' {
                    Write-LZGLog "Driver MSI installeren: $($_.FullName)"
                    Start-Process -FilePath 'msiexec.exe' -ArgumentList "/i `"$($_.FullName)`" /qn /norestart" -Wait
                }
                '.exe' {
                    Write-LZGLog "Driver EXE uitvoeren: $($_.FullName)"
                    Start-Process -FilePath $_.FullName -ArgumentList '/s', '/quiet', '/norestart' -Wait -ErrorAction SilentlyContinue
                }
            }
        }
    }
    Write-LZGLog "Offline driverinstallatie afgerond."
}

function Install-LZGOfflineFirmware {
    $hw = Get-LZGHardwareInfo
    $firmwarePath = Resolve-LZGFirmwarePath -Manufacturer $hw.Manufacturer -Model $hw.Model

    if (-not $firmwarePath) {
        Write-LZGLog "Geen firmwarepad geconfigureerd voor $($hw.Manufacturer)."
        return
    }

    if (-not (Test-Path $firmwarePath)) {
        Write-LZGLog "Firmwarepad bestaat niet: $firmwarePath"
        return
    }

    $files = Get-ChildItem -Path $firmwarePath -File -Recurse -ErrorAction SilentlyContinue
    if (-not $files) {
        Write-LZGLog "Geen firmwarebestanden gevonden in $firmwarePath"
        return
    }

    foreach ($file in $files) {
        switch ($file.Extension.ToLower()) {
            '.msi' {
                Write-LZGLog "Firmware MSI installeren: $($file.FullName)"
                Start-Process -FilePath 'msiexec.exe' -ArgumentList "/i `"$($file.FullName)`" /qn /norestart" -Wait
            }
            '.exe' {
                Write-LZGLog "Firmware EXE uitvoeren: $($file.FullName)"
                Start-Process -FilePath $file.FullName -ArgumentList '/quiet', '/norestart' -Wait -ErrorAction SilentlyContinue
            }
            '.cab' {
                Write-LZGLog "Firmware CAB toevoegen: $($file.FullName)"
                Start-Process -FilePath 'dism.exe' -ArgumentList "/online /add-package /packagepath:`"$($file.FullName)`"" -Wait
            }
            default {
                Write-LZGLog "Onbekend firmwarebestand: $($file.FullName)"
            }
        }
    }

    Write-LZGLog "Firmware installatie afgerond voor $($hw.Manufacturer)."
}

function Invoke-LZGVendorTools {
    $hw = Get-LZGHardwareInfo

    if ($hw.Manufacturer -match "Dell") {
        $dcu = "$ToolsRoot\Dell\dcu-cli.exe"
        if (Test-Path $dcu) {
            Write-LZGLog "Dell Command Update uitvoeren, drivers + firmware."
            Start-Process -FilePath $dcu -ArgumentList "/applyUpdates -silent -reboot=disable -updateType=all" -Wait
        }
        else {
            Write-LZGLog "Dell Command Update niet gevonden: $dcu"
        }
    }
    if ($hw.Manufacturer -match "HP|Hewlett") {
        $hpia = "$ToolsRoot\HP\HPImageAssistant.exe"
        if (Test-Path $hpia) {
            Write-LZGLog "HP Image Assistant uitvoeren, drivers + firmware."
            Start-Process -FilePath $hpia -ArgumentList "/Operation:Analyze /Action:Install /Category:Drivers,Firmware /Silent" -Wait
        }
        else {
            Write-LZGLog "HP Image Assistant niet gevonden: $hpia"
        }
    }
    if ($hw.Manufacturer -match "Microsoft") {
        Write-LZGLog "Microsoft/Surface gedetecteerd. Windows Update wordt gebruikt voor aanvullende firmware-updates."
    }
}

function Download-DriverManifest {
    $config = Get-LZGConfig
    if (-not $config?.DriverManifestUrl) {
        return $null
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $manifestRaw = (Invoke-WebRequest -Uri $config.DriverManifestUrl -UseBasicParsing -ErrorAction Stop).Content
        $manifestPath = "$Root\Config\osdcloud-driver-manifest.json"
        $manifestRaw | Set-Content -Path $manifestPath -Encoding UTF8
        Write-LZGLog "Driver manifest geladen van GitHub: $($config.DriverManifestUrl)"
        return $manifestRaw | ConvertFrom-Json
    }
    catch {
        Write-LZGLog "Driver manifest niet geladen: $($_.Exception.Message)"
        return $null
    }
}

Write-LZGLog "Start driver update flow."
$driverManifest = if (Test-Path "$Root\Config\osdcloud-driver-manifest.json") { Get-Content -Path "$Root\Config\osdcloud-driver-manifest.json" -Raw | ConvertFrom-Json } else { Download-DriverManifest }
if ($driverManifest) {
    Write-LZGLog "Driver manifest aanwezig."
}

Install-LZGOfflineDrivers
Install-LZGOfflineFirmware
Invoke-LZGVendorTools

Write-LZGLog "Driver update flow afgerond."
