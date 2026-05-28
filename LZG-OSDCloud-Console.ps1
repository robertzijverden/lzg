param(
    [string]$Root = "C:\OSDCloud-LZG",
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:RepoZipUrl = 'https://github.com/robertzijverden/lzg/archive/refs/heads/main.zip'
$script:ConsoleTitle = 'LZG OSDCLOUD BEHEERCONSOLE'
$script:ScreenWidth = 120
$script:ScreenHeight = 35
$script:MenuTop = 9
$script:OutputTop = 22
$script:OutputHeight = 9
$script:OutputLines = New-Object System.Collections.Generic.List[string]
$script:CurrentAction = 'Gereed'

function Initialize-LZGConsole {
    try {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public class LZGConsoleWindow {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@ -ErrorAction SilentlyContinue
        [void][LZGConsoleWindow]::ShowWindow([LZGConsoleWindow]::GetConsoleWindow(), 3)
    }
    catch {
    }

    try {
        if ([Console]::LargestWindowWidth -ge $script:ScreenWidth) {
            [Console]::BufferWidth = $script:ScreenWidth
            [Console]::WindowWidth = $script:ScreenWidth
        }
        if ([Console]::LargestWindowHeight -ge $script:ScreenHeight) {
            [Console]::BufferHeight = $script:ScreenHeight
            [Console]::WindowHeight = $script:ScreenHeight
        }
        [Console]::Title = $script:ConsoleTitle
        [Console]::CursorVisible = $false
    }
    catch {
    }
}

function Limit-Text {
    param(
        [string]$Text,
        [int]$Width
    )

    if ($null -eq $Text) {
        $Text = ''
    }
    $Text = $Text -replace "`r|`n", ' '
    if ($Text.Length -gt $Width) {
        return $Text.Substring(0, [Math]::Max(0, $Width - 1))
    }
    return $Text.PadRight($Width)
}

function Write-At {
    param(
        [int]$Left,
        [int]$Top,
        [string]$Text,
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::Green,
        [ConsoleColor]$BackgroundColor = [ConsoleColor]::Black
    )

    try {
        [Console]::SetCursorPosition($Left, $Top)
        Write-Host $Text -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor -NoNewline
    }
    catch {
    }
}

function Draw-Line {
    param(
        [int]$Top,
        [string]$Char = '=',
        [ConsoleColor]$Color = [ConsoleColor]::Green
    )
    Write-At -Left 0 -Top $Top -Text ($Char * $script:ScreenWidth) -ForegroundColor $Color
}

function Draw-Box {
    param(
        [int]$Left,
        [int]$Top,
        [int]$Width,
        [int]$Height,
        [string]$Title = ''
    )

    Write-At $Left $Top ('+' + ('-' * ($Width - 2)) + '+')
    for ($row = 1; $row -lt ($Height - 1); $row++) {
        Write-At $Left ($Top + $row) ('|' + (' ' * ($Width - 2)) + '|')
    }
    Write-At $Left ($Top + $Height - 1) ('+' + ('-' * ($Width - 2)) + '+')
    if ($Title) {
        Write-At ($Left + 2) $Top (" $Title ") Yellow
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

function Add-Output {
    param(
        [string]$Text,
        [ConsoleColor]$Color = [ConsoleColor]::Green
    )

    if ($null -eq $Text) {
        $Text = ''
    }

    foreach ($line in ($Text -split "`r?`n")) {
        if ($script:OutputLines.Count -ge $script:OutputHeight) {
            $script:OutputLines.RemoveAt(0)
        }
        $script:OutputLines.Add($line)
    }
    Render-OutputPane
}

function Clear-Output {
    $script:OutputLines.Clear()
    Render-OutputPane
}

function Render-OutputPane {
    $contentWidth = $script:ScreenWidth - 4
    for ($i = 0; $i -lt $script:OutputHeight; $i++) {
        $text = ''
        if ($i -lt $script:OutputLines.Count) {
            $text = $script:OutputLines[$i]
        }
        Write-At 2 ($script:OutputTop + 1 + $i) (Limit-Text $text $contentWidth) Green
    }
}

function Render-Screen {
    Clear-Host
    $status = Get-LZGStatus

    Draw-Line 0 '='
    Write-At 2 1 (Limit-Text $script:ConsoleTitle 78) Yellow
    Write-At 84 1 (Limit-Text ("{0:yyyy-MM-dd HH:mm}" -f (Get-Date)) 32) Green
    Draw-Line 2 '='

    Write-At 2 3 (Limit-Text ("SYSTEEM: {0}   ADMIN: {1}" -f $env:COMPUTERNAME, $status.Admin) 56)
    Write-At 62 3 (Limit-Text ("ACTIE: {0}" -f $script:CurrentAction) 55) Cyan
    Write-At 2 4 (Limit-Text ("ROOT: {0}" -f $status.Root) 115)
    Write-At 2 5 (Limit-Text ("OSD: {0}   OSDCLOUD: {1}   WORKSPACE: {2}   BOOT.WIM: {3}" -f $status.OSDModule, $status.OSDCloudModule, $status.Workspace, $status.BootWim) 115)
    Write-At 2 6 (Limit-Text ("CONFIG: {0}   DRIVER MANIFEST: {1}" -f $status.Config, $status.DriverManifest) 115)
    Draw-Line 7 '-'

    Draw-Box 0 8 120 13 'MENU'
    Write-At 3 10 ' 1  Volledige voorbereiding beheer-pc'
    Write-At 3 11 ' 2  Synchroniseer deze beheer-pc met GitHub'
    Write-At 3 12 ' 3  Installeer/update vereiste PowerShell modules'
    Write-At 3 13 ' 4  Stel OSDCloud workspace in'
    Write-At 3 14 ' 5  Test vendor catalogi zonder grote downloads'
    Write-At 3 15 ' 6  Download driverpacks en synchroniseer workspace'
    Write-At 64 10 ' 7  Maak nieuwe bootbare OSDCloud USB'
    Write-At 64 11 ' 8  Werk bestaande OSDCloud USB bij'
    Write-At 64 12 ' 9  Update modules op bestaande USB'
    Write-At 64 13 '10  Toon handmatige OSDCloud commands'
    Write-At 64 14 '11  Toon README'
    Write-At 64 15 ' 0  Afsluiten'
    Write-At 3 18 'Fysieke USB-acties gebruiken altijd OSD New-OSDCloudUSB / Update-OSDCloudUSB.' Cyan

    Draw-Box 0 $script:OutputTop 120 ($script:OutputHeight + 2) 'OUTPUT'
    Render-OutputPane
    Draw-Box 0 33 120 2 'COMMAND'
}

function Read-MenuChoice {
    Write-At 2 34 (Limit-Text 'Keuze: ' 8) Yellow
    try { [Console]::CursorVisible = $true } catch {}
    try { [Console]::SetCursorPosition(10, 34) } catch {}
    $choice = Read-Host
    try { [Console]::CursorVisible = $false } catch {}
    return $choice
}

function Wait-LZGKey {
    if (-not $NoPause) {
        Write-At 2 34 (Limit-Text 'Druk op ENTER om terug te keren naar het menu...' 80) Yellow
        try { [Console]::CursorVisible = $true } catch {}
        try { [Console]::SetCursorPosition(51, 34) } catch {}
        [void](Read-Host)
        try { [Console]::CursorVisible = $false } catch {}
    }
}

function Invoke-Step {
    param(
        [string]$Title,
        [scriptblock]$Action
    )

    $script:CurrentAction = $Title
    Clear-Output
    Render-Screen
    Add-Output "Start: $Title"
    try {
        & $Action
        Add-Output 'Actie gereed.'
    }
    catch {
        Add-Output "FOUT: $($_.Exception.Message)"
    }
    Wait-LZGKey
    $script:CurrentAction = 'Gereed'
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
        Add-Output "Sync: $item"
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
        Add-Output "Download repository: $script:RepoZipUrl"
        Invoke-WebRequest -Uri $script:RepoZipUrl -OutFile $zipPath -UseBasicParsing
        Add-Output 'Pak repository uit.'
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        $sourceRoot = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1
        if (-not $sourceRoot) {
            throw 'Uitgepakte repository niet gevonden.'
        }
        Sync-RepositoryContent -SourceRoot $sourceRoot.FullName -TargetRoot $Root
        Add-Output "Gesynchroniseerd naar: $Root"
    }
    finally {
        Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-RequiredModules {
    $scope = if (Test-IsAdmin) { 'AllUsers' } else { 'CurrentUser' }
    Add-Output "PowerShell modules installeren/bijwerken in scope: $scope"

    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Add-Output 'NuGet package provider installeren.'
        Install-PackageProvider -Name NuGet -Force -Scope $scope | Out-Null
    }

    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

    foreach ($module in @('OSD', 'OSDCloud')) {
        Add-Output "Controleer module: $module"
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
    Add-Output "OSDCloud workspace ingesteld op: $workspace"
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

    Add-Output ("Uitvoeren: {0} {1}" -f $ScriptName, ($Arguments -join ' '))
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath @Arguments 2>&1 |
        ForEach-Object { Add-Output $_.ToString() }

    if ($LASTEXITCODE -ne 0) {
        throw "$ScriptName eindigde met exitcode $LASTEXITCODE"
    }
}

function Show-OSDCommandHelp {
    Add-Output 'Handmatige OSDCloud commands:'
    Add-Output 'Import-Module OSD'
    Add-Output "Set-OSDCloudWorkspace -WorkspacePath $Root\Workspace"
    Add-Output 'New-OSDCloudUSB'
    Add-Output 'Update-OSDCloudUSB'
    Add-Output 'Gebruik voor fysieke USB alleen de OSD commands. Niet handmatig kopieren.'
}

function Show-Readme {
    $readme = Join-Path $Root 'README-USB.md'
    if (-not (Test-Path $readme)) {
        Add-Output "README niet gevonden: $readme"
        return
    }

    Get-Content $readme | Select-Object -First 80 | ForEach-Object { Add-Output $_ }
}

Initialize-LZGConsole
try {
    do {
        Render-Screen
        $choice = Read-MenuChoice

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
            '11' { Invoke-Step 'README' { Show-Readme } }
            '0' { break }
            default {
                Add-Output 'Ongeldige keuze.'
                Start-Sleep -Milliseconds 800
            }
        }
    } while ($true)
}
finally {
    try { [Console]::CursorVisible = $true } catch {}
    Clear-Host
}
