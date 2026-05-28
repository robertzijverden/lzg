$ErrorActionPreference = "Stop"
$ConfigUrl = "https://raw.githubusercontent.com/robertzijverden/lzg/main/osdcloud-config.json"

function Get-LZGOSDCloudDataRoot {
    $volumes = Get-Volume | Where-Object { $_.DriveLetter }

    $dataVolume = $volumes | Where-Object {
        (Test-Path "$($_.DriveLetter):\OSDCloud\Config") -or
        (Test-Path "$($_.DriveLetter):\OSDCloud\DriverPacks")
    } | Select-Object -First 1

    if ($dataVolume) {
        return "$($dataVolume.DriveLetter):\OSDCloud"
    }

    $bootVolume = $volumes | Where-Object {
        Test-Path "$($_.DriveLetter):\OSDCloud"
    } | Select-Object -First 1

    if ($bootVolume) {
        return "$($bootVolume.DriveLetter):\OSDCloud"
    }

    throw "OSDCloud USB data root niet gevonden."
}

function Get-LZGOSDCloudBootRoot {
    $volumes = Get-Volume | Where-Object { $_.DriveLetter }
    $bootVolume = $volumes | Where-Object {
        Test-Path "$($_.DriveLetter):\OSDCloud\PostInstall"
    } | Select-Object -First 1

    if ($bootVolume) {
        return "$($bootVolume.DriveLetter):\OSDCloud"
    }

    return $null
}

$UsbRoot = Get-LZGOSDCloudDataRoot
$BootRoot = Get-LZGOSDCloudBootRoot
$LogDir = "$UsbRoot\Logs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

Start-Transcript -Path "$LogDir\WinPE-Deploy.log" -Append

Write-Host "LZG OSD gestart."
Write-Host "Config ophalen: $ConfigUrl"

$LocalConfigPath = "$UsbRoot\Config\osdcloud-config.json"
New-Item -ItemType Directory -Path (Split-Path $LocalConfigPath) -Force | Out-Null

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Config = $null
try {
    $ConfigRaw = (Invoke-WebRequest -Uri $ConfigUrl -UseBasicParsing -ErrorAction Stop).Content
    $Config = $ConfigRaw | ConvertFrom-Json -ErrorAction Stop
    Write-Host "Config succesvol geladen vanuit GitHub."
    $ConfigRaw | Set-Content -Path $LocalConfigPath -Encoding UTF8
}
catch {
    if (Test-Path $LocalConfigPath) {
        Write-Host "GitHub-config niet beschikbaar, gebruik lokale config: $LocalConfigPath"
        $Config = Get-Content -Path $LocalConfigPath -Raw | ConvertFrom-Json
    }
    else {
        throw "Config niet gevonden via GitHub en geen lokaal bestand aanwezig."
    }
}

Write-Host "Windows installatie starten:"
Write-Host "OSVersion:  $($Config.OSVersion)"
Write-Host "OSBuild:    $($Config.OSBuild)"
Write-Host "OSEdition:  $($Config.OSEdition)"
Write-Host "OSLanguage: $($Config.OSLanguage)"

$osdCloudParams = @{
    OSVersion    = $Config.OSVersion
    OSBuild      = $Config.OSBuild
    OSEdition    = $Config.OSEdition
    OSLanguage   = $Config.OSLanguage
    OSActivation = $Config.OSActivation
    ZTI          = $true
}

Start-OSDCloud @osdCloudParams

Write-Host "Post-install bestanden kopieren naar Windows."

$TargetRoot = "C:\ProgramData\LZGOSD"
New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null

if ($BootRoot -and (Test-Path "$BootRoot\PostInstall")) {
    Copy-Item "$BootRoot\PostInstall" "$TargetRoot\PostInstall" -Recurse -Force
}
elseif (Test-Path "$UsbRoot\PostInstall") {
    Copy-Item "$UsbRoot\PostInstall" "$TargetRoot\PostInstall" -Recurse -Force
}
else {
    Write-Warning "PostInstall map niet gevonden op OSDCloud USB."
}

Copy-Item "$UsbRoot\DriverPacks" "$TargetRoot\DriverPacks" -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item "$UsbRoot\DriverPacks\VendorTools" "$TargetRoot\Tools" -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item "$UsbRoot\Config" "$TargetRoot\Config" -Recurse -Force -ErrorAction SilentlyContinue

$SetupScripts = "C:\Windows\Setup\Scripts"
New-Item -ItemType Directory -Path $SetupScripts -Force | Out-Null

@'
@echo off
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "C:\ProgramData\LZGOSD\PostInstall\PostInstall.ps1"
exit /b 0
'@ | Set-Content -Path "$SetupScripts\SetupComplete.cmd" -Encoding ASCII

Stop-Transcript
Restart-Computer -Force
