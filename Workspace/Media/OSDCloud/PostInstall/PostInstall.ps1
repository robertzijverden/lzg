$ErrorActionPreference = "Continue"

$Root            = "C:\ProgramData\LZGOSD"
$LogDir          = "$Root\Logs"
$DriverRoot      = "$Root\DriverPacks"
$ToolsRoot       = "$Root\Tools"
$MapPath         = "$Root\Config\DriverMap.json"
$ConfigPath      = "$Root\Config\osdcloud-config.json"
$DriverManifest  = "$Root\Config\osdcloud-driver-manifest.json"

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path "$LogDir\PostInstall.log" -Append

function Write-LZGLog {
    param([string]$Message)
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
}

function Get-LZGPostInstallConfig {
    if (Test-Path $ConfigPath) {
        return Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    }
    return $null
}

function Get-LZGDriverManifest {
    if (Test-Path $DriverManifest) {
        return Get-Content -Path $DriverManifest -Raw | ConvertFrom-Json
    }

    $config = Get-LZGPostInstallConfig
    if ($config -and $config.DriverManifestUrl) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $manifestRaw = (Invoke-WebRequest -Uri $config.DriverManifestUrl -UseBasicParsing -ErrorAction Stop).Content
            $manifestRaw | Set-Content -Path $DriverManifest -Encoding UTF8
            return $manifestRaw | ConvertFrom-Json
        }
        catch {
            Write-LZGLog "Driver manifest niet geladen: $($_.Exception.Message)"
        }
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

    if (-not (Test-Path $MapPath)) {
        Write-LZGLog "DriverMap niet gevonden: $MapPath"
        return $null
    }

    $map = Get-Content $MapPath -Raw | ConvertFrom-Json

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
            return Join-Path $DriverRoot $entry.Value
        }
    }

    Write-LZGLog "Geen modelmatch gevonden voor model: $Model"
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
    pnputil.exe /add-driver "$driverPath\*.inf" /subdirs /install

    Write-LZGLog "Offline driverinstallatie afgerond."
}

function Invoke-LZGVendorTools {
    $hw = Get-LZGHardwareInfo

    if ($hw.Manufacturer -match "Dell") {
        $dcu = "$ToolsRoot\Dell\dcu-cli.exe"

        if (Test-Path $dcu) {
            Write-LZGLog "Dell Command Update uitvoeren, alleen drivers."
            Start-Process -FilePath $dcu -ArgumentList "/applyUpdates -silent -reboot=disable -updateType=driver" -Wait
        }
        else {
            Write-LZGLog "Dell Command Update niet gevonden: $dcu"
        }
    }

    if ($hw.Manufacturer -match "HP|Hewlett") {
        $hpia = "$ToolsRoot\HP\HPImageAssistant.exe"

        if (Test-Path $hpia) {
            Write-LZGLog "HP Image Assistant uitvoeren, alleen drivers."
            Start-Process -FilePath $hpia -ArgumentList "/Operation:Analyze /Action:Install /Category:Drivers /Silent" -Wait
        }
        else {
            Write-LZGLog "HP Image Assistant niet gevonden: $hpia"
        }
    }
}

function Start-LZGWindowsUpdate {
    Write-LZGLog "Windows Update scan triggeren."

    Start-Service wuauserv -ErrorAction SilentlyContinue
    Start-Service bits -ErrorAction SilentlyContinue

    try {
        UsoClient StartScan
        Start-Sleep -Seconds 5
        UsoClient StartDownload
        Start-Sleep -Seconds 5
        UsoClient StartInstall
    }
    catch {
        Write-LZGLog "Windows Update trigger fout: $($_.Exception.Message)"
    }
}

Install-LZGOfflineDrivers
Invoke-LZGVendorTools

$Config = Get-LZGPostInstallConfig
& "$Root\PostInstall\Update-Drivers.ps1" -Root $Root -ConfigPath $ConfigPath -DriverRoot $DriverRoot -ToolsRoot $ToolsRoot -Config $Config
& "$Root\PostInstall\Update-Windows.ps1" -Root $Root -ConfigPath $ConfigPath -Config $Config

Write-LZGLog "Post-install afgerond. Herstart over 30 seconden."

Stop-Transcript

shutdown.exe /r /t 30 /c "LZG OSD post-install afgerond."
