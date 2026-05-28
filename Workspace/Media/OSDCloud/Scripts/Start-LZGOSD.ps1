$ErrorActionPreference = "Stop"
$ConfigUrl = "https://raw.githubusercontent.com/robertzijverden/lzg/main/osdcloud-config.json"

function Get-LZGUSBRoot {
    $volumes = Get-Volume | Where-Object {
        $_.DriveLetter -and (Test-Path "$($_.DriveLetter):\OSDCloud")
    }

    if (-not $volumes) {
        throw "USB root niet gevonden."
    }

    return "$($volumes[0].DriveLetter):\"
}

$UsbRoot = Get-LZGUSBRoot
$LogDir = "$UsbRoot\OSDCloud\Logs"
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

Start-OSDCloud 
    -OSVersion $Config.OSVersion 
    -OSBuild $Config.OSBuild 
    -OSEdition $Config.OSEdition 
    -OSLanguage $Config.OSLanguage 
    -OSActivation $Config.OSActivation 
    -ZTI

Write-Host "Post-install bestanden kopieren naar Windows."

$TargetRoot = "C:\ProgramData\LZGOSD"
New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null

Copy-Item "$UsbRoot\OSDCloud\PostInstall" "$TargetRoot\PostInstall" -Recurse -Force
Copy-Item "$UsbRoot\DriverPacks" "$TargetRoot\DriverPacks" -Recurse -Force
Copy-Item "$UsbRoot\Tools" "$TargetRoot\Tools" -Recurse -Force
Copy-Item "$UsbRoot\Config" "$TargetRoot\Config" -Recurse -Force

$SetupScripts = "C:\Windows\Setup\Scripts"
New-Item -ItemType Directory -Path $SetupScripts -Force | Out-Null

@'
@echo off
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "C:\ProgramData\LZGOSD\PostInstall\PostInstall.ps1"
exit /b 0
'@ | Set-Content -Path "$SetupScripts\SetupComplete.cmd" -Encoding ASCII

Stop-Transcript
Restart-Computer -Force
