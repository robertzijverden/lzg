param(
    [string]$Root = "C:\OSDCloud-LZG",
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:RepoZipUrl = 'https://github.com/robertzijverden/lzg/archive/refs/heads/main.zip'
$script:RawConfigUrl = 'https://raw.githubusercontent.com/robertzijverden/lzg/main/osdcloud-config.json'
$script:ConsoleTitle = 'LZG OSDCLOUD BEHEERCONSOLE'

function Write-Ui {
    param(
        [string]$Text = '',
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::Green
    )
    Write-Host $Text -ForegroundColor $ForegroundColor
}

function Wait-LZGKey {
    if (-not $NoPause) {
        Write-Ui ''
        Write-Ui 'Druk op ENTER om terug te keren naar het menu...'
        [void](Read-Host)
    }
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-InstalledModuleVersionText {
    param([string]$Name)
    $module = Get-Module -ListAvailable $Name | Sort-Object Version -Descending | Select-Object -First 1
    if ($module) {
        return "$($module.Version)"
    }
    return 'Niet geinstalleerd'
}

function Get-LZGStatus {
    $workspace = Join-Path $Root 'Workspace'
    $media = Join-Path $workspace 'Media\sources\boot.wim'
    $config = Join-Path $Root 'Config\osdcloud-config.json'
    $driverManifest = Join-Path $Root 'Config\osdcloud-driver-manifest.json'

    [pscustomobject]@{
        Root           = $Root
        Admin          = if (Test-IsAdmin) { 'JA' } else { 'NEE' }
        OSDModule      = Get-InstalledModuleVersionText 'OSD'
        OSDCloudModule = Get-InstalledModuleVersionText 'OSDCloud'
        Workspace      = if (Test-Path $workspace) { 'JA' } else { 'NEE' }
        BootWim        = if (Test-Path $media) { 'JA' } else { 'NEE' }
        Config         = if (Test-Path $config) { 'JA' } else { 'NEE' }
        DriverManifest = if (Test-Path $driverManifest) { 'JA' } else { 'NEE' }
    }
}

function Show-Header {
    Clear-Host
    $status = Get-LZGStatus
    Write-Host ''
    Write-Host '===============================================================================' -ForegroundColor Green
    Write-Host (" {0,-77}" -f $script:ConsoleTitle) -ForegroundColor Green
    Write-Host '===============================================================================' -ForegroundColor Green
    Write-Host (" Systeem : {0,-28} Admin : {1,-3}  OSD : {2,-12} OSDCloud : {3}" -f $env:COMPUTERNAME, $status.Admin, $status.OSDModule, $status.OSDCloudModule) -ForegroundColor Green
    Write-Host (" Root    : {0}" -f $status.Root) -ForegroundColor Green
    Write-Host (" WS      : {0}   BootWIM : {1}   Config : {2}   DriverManifest : {3}" -f $status.Workspace, $status.BootWim, $status.Config, $status.DriverManifest) -ForegroundColor Green
    Write-Host '-------------------------------------------------------------------------------' -ForegroundColor Green
}

function Invoke-Step {
    param(
        [string]$Title,
        [scriptblock]$Action
    )

    Show-Header
    Write-Ui "ACTIE: $Title" Yellow
    Write-Ui '-------------------------------------------------------------------------------'
    try {
        & $Action
        Write-Ui ''
        Write-Ui 'ACTIE GEREED.' Cyan
    }
    catch {
        Write-Ui ''
        Write-Ui "FOUT: $($_.Exception.Message)" Red
    }
    Wait-LZGKey
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

function Sync-LZGFromGitHub {
    Ensure-Directory $Root
    $tempRoot = Join-Path $env:TEMP "LZGOSDCloud-$([guid]::NewGuid().ToString('N'))"
    $zipPath = Join-Path $tempRoot 'repo.zip'
    $extractPath = Join-Path $tempRoot 'extract'

    try {
        Ensure-Directory $tempRoot
        Write-Ui "Download repository: $script:RepoZipUrl"
        Invoke-WebRequest -Uri $script:RepoZipUrl -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        $sourceRoot = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1
        if (-not $sourceRoot) {
            throw 'Uitgepakte repository niet gevonden.'
        }
        Sync-RepositoryContent -SourceRoot $sourceRoot.FullName -TargetRoot $Root
        Write-Ui "Gesynchroniseerd naar: $Root"
    }
    finally {
        Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-RequiredModules {
    $scope = if (Test-IsAdmin) { 'AllUsers' } else { 'CurrentUser' }
    Write-Ui "PowerShell modules installeren/bijwerken in scope: $scope"

    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -Force -Scope $scope | Out-Null
    }

    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

    foreach ($module in @('OSD', 'OSDCloud')) {
        Write-Ui "Controleer module: $module"
        if (Get-Module -ListAvailable $module) {
            Update-Module -Name $module -Force -ErrorAction SilentlyContinue
        }
        else {
            Install-Module -Name $module -Scope $scope -Force -AllowClobber
        }
    }
}

function Set-LZGWorkspace {
    Import-Module OSD -Force
    $workspace = Join-Path $Root 'Workspace'
    Ensure-Directory $workspace
    Set-OSDCloudWorkspace -WorkspacePath $workspace | Out-Null
    Write-Ui "OSDCloud workspace ingesteld op: $workspace"
}

function Invoke-LZGScript {
    param(
        [string]$ScriptName,
        [string[]]$Arguments = @()
    )

    $scriptPath = Join-Path $Root $ScriptName
    if (-not (Test-Path $scriptPath)) {
        throw "Script niet gevonden: $scriptPath"
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$ScriptName eindigde met exitcode $LASTEXITCODE"
    }
}

function Show-OSDCommandHelp {
    Write-Ui 'Handmatige OSDCloud commands:' Yellow
    Write-Ui ''
    Write-Ui 'Import-Module OSD'
    Write-Ui "Set-OSDCloudWorkspace -WorkspacePath $Root\Workspace"
    Write-Ui 'New-OSDCloudUSB'
    Write-Ui 'Update-OSDCloudUSB'
    Write-Ui ''
    Write-Ui 'Gebruik voor fysieke USB alleen de OSD commands. Niet handmatig kopieren.'
}

function Show-Menu {
    Show-Header
    Write-Ui '  1. Volledige voorbereiding beheer-pc'
    Write-Ui '  2. Synchroniseer deze beheer-pc met GitHub'
    Write-Ui '  3. Installeer/update vereiste PowerShell modules'
    Write-Ui '  4. Stel OSDCloud workspace in'
    Write-Ui '  5. Test vendor catalogi zonder grote downloads'
    Write-Ui '  6. Download driverpacks en synchroniseer workspace'
    Write-Ui '  7. Maak nieuwe bootbare OSDCloud USB (OSD New-OSDCloudUSB)'
    Write-Ui '  8. Werk bestaande OSDCloud USB bij (OSD Update-OSDCloudUSB)'
    Write-Ui '  9. Update OSD/Autopilot modules op bestaande USB'
    Write-Ui ' 10. Toon handmatige OSDCloud commands'
    Write-Ui ' 11. Toon README'
    Write-Ui '  0. Afsluiten'
    Write-Ui '-------------------------------------------------------------------------------'
}

do {
    Show-Menu
    $choice = Read-Host 'Keuze'

    switch ($choice) {
        '1' {
            Invoke-Step 'Volledige voorbereiding beheer-pc' {
                Sync-LZGFromGitHub
                Install-RequiredModules
                Set-LZGWorkspace
                Invoke-LZGScript -ScriptName 'Update-OSDCloudUSB.ps1' -Arguments @('-CatalogOnly')
            }
        }
        '2' { Invoke-Step 'Synchroniseer deze beheer-pc met GitHub' { Sync-LZGFromGitHub } }
        '3' { Invoke-Step 'Installeer/update vereiste PowerShell modules' { Install-RequiredModules } }
        '4' { Invoke-Step 'Stel OSDCloud workspace in' { Set-LZGWorkspace } }
        '5' { Invoke-Step 'Test vendor catalogi zonder grote downloads' { Invoke-LZGScript -ScriptName 'Update-OSDCloudUSB.ps1' -Arguments @('-CatalogOnly') } }
        '6' { Invoke-Step 'Download driverpacks en synchroniseer workspace' { Invoke-LZGScript -ScriptName 'Update-OSDCloudUSB.ps1' } }
        '7' { Invoke-Step 'Maak nieuwe bootbare OSDCloud USB' { Invoke-LZGScript -ScriptName 'Update-OSDCloudUSB.ps1' -Arguments @('-CreatePhysicalUSB') } }
        '8' { Invoke-Step 'Werk bestaande OSDCloud USB bij' { Invoke-LZGScript -ScriptName 'Update-OSDCloudUSB.ps1' -Arguments @('-UpdatePhysicalUSB') } }
        '9' { Invoke-Step 'Update modules op bestaande OSDCloud USB' { Invoke-LZGScript -ScriptName 'Update-OSDCloudUSB.ps1' -Arguments @('-PSUpdate') } }
        '10' { Invoke-Step 'Handmatige OSDCloud commands' { Show-OSDCommandHelp } }
        '11' {
            Invoke-Step 'README' {
                $readme = Join-Path $Root 'README-USB.md'
                if (Test-Path $readme) {
                    Get-Content $readme | ForEach-Object { Write-Ui $_ }
                }
                else {
                    Write-Ui "README niet gevonden: $readme" Red
                }
            }
        }
        '0' { break }
        default {
            Write-Ui 'Ongeldige keuze.' Red
            Start-Sleep -Seconds 1
        }
    }
} while ($true)
