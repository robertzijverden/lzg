param(
    [string]$Root = "$PSScriptRoot",
    [ValidateSet('All', 'Dell', 'HP', 'Microsoft')]
    [string]$Vendor = 'All',
    [switch]$CatalogOnly,
    [switch]$SkipTools
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Log {
    param([string]$Message)
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
}

function Ensure-Path {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function ConvertTo-SafeFolderName {
    param([string]$Name)
    $safe = $Name
    foreach ($char in [System.IO.Path]::GetInvalidFileNameChars()) {
        $safe = $safe.Replace($char, '-')
    }
    return ($safe -replace '\s+', ' ').Trim()
}

function Save-SourceFile {
    param(
        [string]$Url,
        [string]$Destination
    )

    Ensure-Path (Split-Path $Destination)
    Write-Log "Downloaden: $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
}

function Expand-CabFile {
    param(
        [string]$CabPath,
        [string]$Destination
    )

    Ensure-Path $Destination
    $output = & expand.exe -F:* $CabPath $Destination 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "CAB uitpakken mislukt: $output"
    }
}

function Expand-SoftPaqFile {
    param(
        [string]$SoftPaqPath,
        [string]$Destination
    )

    Ensure-Path $Destination
    $arguments = "/s /e /f`"$Destination`""
    $process = Start-Process -FilePath $SoftPaqPath -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) {
        throw "SoftPaq uitpakken mislukt met exitcode $($process.ExitCode): $SoftPaqPath"
    }
}

function Expand-DellPackageFile {
    param(
        [string]$PackagePath,
        [string]$Destination
    )

    Ensure-Path $Destination
    $extension = [System.IO.Path]::GetExtension($PackagePath).ToLower()
    switch ($extension) {
        '.cab' {
            Expand-CabFile -CabPath $PackagePath -Destination $Destination
        }
        '.exe' {
            $arguments = "/s /e=`"$Destination`""
            $process = Start-Process -FilePath $PackagePath -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
            if ($process.ExitCode -ne 0) {
                Write-Log "Dell EXE kon niet automatisch worden uitgepakt met exitcode $($process.ExitCode). EXE wordt bewaard voor post-install."
            }
            Copy-Item -Path $PackagePath -Destination (Join-Path $Destination (Split-Path -Leaf $PackagePath)) -Force
        }
        default {
            throw "Onbekend Dell driverpack type: $PackagePath"
        }
    }
}

function Expand-MsiFile {
    param(
        [string]$MsiPath,
        [string]$Destination
    )

    Ensure-Path $Destination
    $arguments = "/a `"$MsiPath`" /qn TARGETDIR=`"$Destination`""
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) {
        throw "MSI administratieve extractie mislukt met exitcode $($process.ExitCode): $MsiPath"
    }
}

function Read-DriverManifest {
    $manifestPath = Join-Path $Root 'Config\osdcloud-driver-manifest.json'
    if (-not (Test-Path $manifestPath)) {
        throw "Driver manifest niet gevonden: $manifestPath"
    }
    Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
}

function Get-DellDriverPackCatalog {
    param([string]$CatalogUrl)

    $cabPath = Join-Path $env:TEMP 'LZG-Dell-DriverPackCatalog.cab'
    $xmlPath = Join-Path $env:TEMP 'LZG-Dell-DriverPackCatalog.xml'
    Remove-Item -Path $cabPath, $xmlPath -Force -ErrorAction SilentlyContinue

    Save-SourceFile -Url $CatalogUrl -Destination $cabPath
    $output = & expand.exe $cabPath $xmlPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Dell catalog uitpakken mislukt: $output"
    }

    [xml]$catalog = Get-Content -Path $xmlPath -Raw
    foreach ($item in $catalog.DriverPackManifest.DriverPackage) {
        $osCodes = @($item.SupportedOperatingSystems.OperatingSystem.osCode)
        if (-not ($osCodes -match 'Windows11')) {
            continue
        }

        [pscustomobject]@{
            Vendor      = 'Dell'
            Model       = ($item.SupportedSystems.Brand.Model.name | Select-Object -First 1)
            Version     = $item.dellVersion
            ReleaseDate = [datetime]$item.dateTime
            FileName    = Split-Path -Leaf $item.path
            Url         = "https://downloads.dell.com/$($item.path)"
            HashMD5     = $item.HashMD5
        }
    }
}

function Update-DellDriverPacks {
    param([psobject]$Config)

    Write-Log 'Dell Driver Pack catalog ophalen.'
    $catalog = @(Get-DellDriverPackCatalog -CatalogUrl $Config.CatalogUrl)
    foreach ($model in $Config.Models) {
        $match = $catalog |
            Where-Object { $_.Model -like "*$($model.Match)*" } |
            Sort-Object ReleaseDate -Descending |
            Select-Object -First 1

        if (-not $match) {
            Write-Log "Dell driverpack niet gevonden voor: $($model.Name)"
            continue
        }

        Write-Log "Dell geselecteerd: $($match.Model) $($match.Version) [$($match.ReleaseDate.ToString('yyyy-MM-dd'))]"
        Write-Log "Dell URL: $($match.Url)"
        if ($CatalogOnly) {
            continue
        }

        $targetFolder = Join-Path $Root $model.LocalPath
        $downloadPath = Join-Path $env:TEMP $match.FileName
        if (Test-Path $targetFolder) {
            Remove-Item -Path $targetFolder -Recurse -Force
        }
        Ensure-Path $targetFolder
        Save-SourceFile -Url $match.Url -Destination $downloadPath

        Expand-DellPackageFile -PackagePath $downloadPath -Destination $targetFolder
        Write-Log "Dell drivers bijgewerkt: $targetFolder"
    }
}

function Get-HPDriverPackCatalog {
    param([string]$CatalogUrl)

    $cabPath = Join-Path $env:TEMP 'LZG-HPClientDriverPackCatalog.cab'
    $xmlPath = Join-Path $env:TEMP 'LZG-HPClientDriverPackCatalog.xml'
    Remove-Item -Path $cabPath, $xmlPath -Force -ErrorAction SilentlyContinue

    Save-SourceFile -Url $CatalogUrl -Destination $cabPath
    $output = & expand.exe $cabPath $xmlPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "HP catalog uitpakken mislukt: $output"
    }

    [xml]$catalog = Get-Content -Path $xmlPath -Raw
    $softpaqs = @($catalog.NewDataSet.HPClientDriverPackCatalog.SoftPaqList.SoftPaq)
    $models = @($catalog.NewDataSet.HPClientDriverPackCatalog.ProductOSDriverPackList.ProductOSDriverPack)

    foreach ($item in $models) {
        $softpaq = $softpaqs | Where-Object { $_.Id -eq $item.SoftPaqId } | Select-Object -First 1
        if (-not $softpaq) {
            continue
        }

        if (($item.OSName -notmatch 'Windows 11') -and ([int]$item.OSId -lt 4317)) {
            continue
        }

        $releaseDate = [datetime]::MinValue
        if (-not [datetime]::TryParse([string]$softpaq.DateReleased, [ref]$releaseDate)) {
            $releaseDate = [datetime]::MinValue
        }

        [pscustomobject]@{
            Vendor      = 'HP'
            Model       = $item.SystemName
            SystemId    = $item.SystemId
            SoftPaqId   = $item.SoftPaqId
            OSName      = $item.OSName
            ReleaseDate = $releaseDate
            FileName    = Split-Path -Leaf $softpaq.Url
            Url         = $softpaq.Url
            HashMD5     = $softpaq.MD5
        }
    }
}

function Update-HPDriverPacks {
    param([psobject]$Config)

    Write-Log 'HP Client Driver Pack catalog ophalen.'
    $catalog = @(Get-HPDriverPackCatalog -CatalogUrl $Config.CatalogUrl)
    foreach ($rule in $Config.Models) {
        $matches = @($catalog |
            Where-Object { $_.Model -match $rule.MatchRegex } |
            Sort-Object Model, ReleaseDate -Descending |
            Group-Object Model |
            ForEach-Object { $_.Group | Select-Object -First 1 })

        Write-Log "HP driverpacks gevonden voor regel '$($rule.Name)': $($matches.Count)"
        foreach ($match in $matches) {
            Write-Log "HP geselecteerd: $($match.Model) $($match.SoftPaqId) [$($match.ReleaseDate.ToString('yyyy-MM-dd'))]"
            Write-Log "HP URL: $($match.Url)"
            if ($CatalogOnly) {
                continue
            }

            $safeName = ConvertTo-SafeFolderName $match.Model
            $targetFolder = Join-Path (Join-Path $Root $rule.LocalPathRoot) $safeName
            $downloadPath = Join-Path $env:TEMP $match.FileName
            if (Test-Path $targetFolder) {
                Remove-Item -Path $targetFolder -Recurse -Force
            }
            Ensure-Path $targetFolder
            Save-SourceFile -Url $match.Url -Destination $downloadPath
            Expand-SoftPaqFile -SoftPaqPath $downloadPath -Destination $targetFolder
            Write-Log "HP drivers bijgewerkt: $targetFolder"
        }
    }
}

function Get-SurfacePackageFromOSDCloud {
    param([string]$Model)

    $module = Get-Module -ListAvailable OSDCloud | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $module) {
        throw 'OSDCloud module niet gevonden. Kan Surface drivercatalogus niet lezen.'
    }

    $catalogPath = Join-Path $module.ModuleBase 'catalogs\driverpack\microsoft.xml'
    if (-not (Test-Path $catalogPath)) {
        throw "Surface catalogus niet gevonden: $catalogPath"
    }

    Import-Clixml -Path $catalogPath |
        Where-Object { $_.Model -eq $Model } |
        Sort-Object Name -Descending |
        Select-Object -First 1
}

function Update-SurfaceDriverPacks {
    param([psobject]$Config)

    foreach ($model in $Config.Models) {
        $package = Get-SurfacePackageFromOSDCloud -Model $model.Name
        if (-not $package) {
            Write-Log "Surface package niet gevonden voor: $($model.Name)"
            continue
        }

        Write-Log "Surface geselecteerd: $($package.Model) $($package.FileName)"
        Write-Log "Surface URL: $($package.Url)"
        if ($CatalogOnly) {
            continue
        }

        $targetFolder = Join-Path $Root $model.LocalPath
        $downloadPath = Join-Path $env:TEMP $package.FileName
        if (Test-Path $targetFolder) {
            Remove-Item -Path $targetFolder -Recurse -Force
        }
        Ensure-Path $targetFolder
        Save-SourceFile -Url $package.Url -Destination $downloadPath
        Expand-MsiFile -MsiPath $downloadPath -Destination $targetFolder
        Copy-Item -Path $downloadPath -Destination (Join-Path $targetFolder $package.FileName) -Force
        Write-Log "Surface drivers en firmware bijgewerkt: $targetFolder"
    }
}

$manifest = Read-DriverManifest

if ($Vendor -in @('All', 'Dell')) {
    Update-DellDriverPacks -Config $manifest.Dell
}

if ($Vendor -in @('All', 'HP')) {
    Update-HPDriverPacks -Config $manifest.HP
}

if ($Vendor -in @('All', 'Microsoft')) {
    Update-SurfaceDriverPacks -Config $manifest.Microsoft
}

if ($SkipTools -or -not $manifest.Tools.DownloadVendorTools) {
    Write-Log 'Losse vendor tools overgeslagen. Offline driverpacks bevatten drivers en firmware.'
}

Write-Log 'Driverpack update voltooid.'
