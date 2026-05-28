$ErrorActionPreference = "Continue"
param(
    [string]$Root = "C:\ProgramData\LZGOSD",
    [string]$ConfigPath = "$Root\Config\osdcloud-config.json",
    [psobject]$Config = $null
)

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

function Start-LZGWindowsUpdate {
    Write-LZGLog "Windows Update scan triggeren."

    Start-Service wuauserv -ErrorAction SilentlyContinue
    Start-Service bits -ErrorAction SilentlyContinue

    try {
        UsoClient StartScan
        Start-Sleep -Seconds 10
        UsoClient StartDownload
        Start-Sleep -Seconds 10
        UsoClient StartInstall
        Start-Sleep -Seconds 10
        Write-LZGLog "Windows Update opdracht verstuurd via UsoClient."
    }
    catch {
        Write-LZGLog "Windows Update trigger fout: $($_.Exception.Message)"
    }
}

function Start-LZGWindowsUpdateModule {
    if (Get-Command Install-WindowsUpdate -ErrorAction SilentlyContinue) {
        Write-LZGLog "PSWindowsUpdate gevonden; patches installeren."
        try {
            Import-Module PSWindowsUpdate -ErrorAction Stop
            Install-WindowsUpdate -AcceptAll -IgnoreReboot -AutoReboot -Verbose
        }
        catch {
            Write-LZGLog "PSWindowsUpdate uitvoering gefaald: $($_.Exception.Message)"
            Start-LZGWindowsUpdate
        }
    }
    else {
        Write-LZGLog "PSWindowsUpdate niet beschikbaar, gebruik UsoClient."
        Start-LZGWindowsUpdate
    }
}

Write-LZGLog "Start Windows patchflow."
$config = Get-LZGConfig
if ($config -and $config.PatchAfterInstall -eq $false) {
    Write-LZGLog "Windows patchen overgeslagen op basis van config."
    return
}

Start-LZGWindowsUpdateModule
Write-LZGLog "Windows patchflow afgerond."
