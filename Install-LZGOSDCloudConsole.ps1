param(
    [string]$InstallRoot = "C:\OSDCloud-LZG",
    [string]$RepositoryZipUrl = "https://github.com/robertzijverden/lzg/archive/refs/heads/main.zip",
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-InstallLog {
    param([string]$Message)
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Sync-RepositoryContent {
    param(
        [string]$SourceRoot,
        [string]$TargetRoot
    )

    $itemsToSync = @(
        'Build-OSDCloudUSB.ps1',
        'Install-LZGOSDCloudConsole.ps1',
        'LZG-OSDCloud-Console.ps1',
        'README-USB.md',
        'Start-LZGOSDCloudConsole.cmd',
        'Update-DriverPacks.ps1',
        'Update-OSDCloudUSB.ps1',
        'Config',
        'Workspace\Media\OSDCloud'
    )

    foreach ($item in $itemsToSync) {
        $source = Join-Path $SourceRoot $item
        if (-not (Test-Path $source)) {
            continue
        }

        $destination = Join-Path $TargetRoot $item
        Ensure-Directory (Split-Path $destination)

        if (Test-Path $destination) {
            Remove-Item -Path $destination -Recurse -Force -ErrorAction SilentlyContinue
        }

        Copy-Item -Path $source -Destination (Split-Path $destination) -Recurse -Force
    }

    foreach ($folder in @('DriverPacks', 'Tools', 'Workspace')) {
        Ensure-Directory (Join-Path $TargetRoot $folder)
    }
}

Ensure-Directory $InstallRoot
$tempRoot = Join-Path $env:TEMP "LZGOSDCloud-$([guid]::NewGuid().ToString('N'))"
$zipPath = Join-Path $tempRoot 'repo.zip'
$extractPath = Join-Path $tempRoot 'extract'

try {
    Ensure-Directory $tempRoot
    Write-InstallLog "Download GitHub repository: $RepositoryZipUrl"
    Invoke-WebRequest -Uri $RepositoryZipUrl -OutFile $zipPath -UseBasicParsing

    Write-InstallLog "Pak repository uit."
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
    $sourceRoot = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1
    if (-not $sourceRoot) {
        throw "Uitgepakte repository niet gevonden."
    }

    Write-InstallLog "Synchroniseer LZG OSDCloud bestanden naar $InstallRoot"
    Sync-RepositoryContent -SourceRoot $sourceRoot.FullName -TargetRoot $InstallRoot

    if (-not $NoLaunch) {
        $console = Join-Path $InstallRoot 'LZG-OSDCloud-Console.ps1'
        Write-InstallLog "Start LZG OSDCloud Console."
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $console
    }
}
finally {
    Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
