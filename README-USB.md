# OSDCloud USB Build en Update

## Doel
Deze scripts maken een up-to-date OSDCloud USB voor:

- Microsoft Surface Go 2, Go 3 en Go 4
- HP ProBook G4 t/m G11 series
- Dell Latitude 3520

De bootmedia blijft beheerd door OSDCloud. De LZG scripts voegen alleen config, post-install scripts en offline driver-/firmwarepakketten toe aan de bestaande OSDCloud workspace. Daardoor blijft de USB via de normale OSDCloud/ADK route Secure Boot-compatible.

## Gebruik

Open PowerShell als administrator:

```powershell
cd C:\OSDCloud-LZG
```

Op een nieuwe beheer-pc kun je de omgeving rechtstreeks vanaf GitHub installeren:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "iwr https://raw.githubusercontent.com/robertzijverden/lzg/main/Install-LZGOSDCloudConsole.ps1 -UseBasicParsing | iex"
```

Daarna start je de beheerconsole:

```powershell
C:\OSDCloud-LZG\Start-LZGOSDCloudConsole.cmd
```

In de console kies je optie `1` voor volledige voorbereiding van de beheer-pc.

Test eerst zonder grote downloads:

```powershell
.\Update-OSDCloudUSB.ps1 -CatalogOnly
```

Download daarna de driverpacks en synchroniseer de OSDCloud workspace:

```powershell
.\Update-OSDCloudUSB.ps1
```

Maak een nieuwe bootbare USB via het officiele OSD command:

```powershell
.\Update-OSDCloudUSB.ps1 -CreatePhysicalUSB
```

Werk een bestaande OSDCloud USB bij via het officiele OSD command:

```powershell
.\Update-OSDCloudUSB.ps1 -UpdatePhysicalUSB
```

## OSD commands handmatig

Je kunt de fysieke USB ook volledig handmatig met OSDCloud commands beheren:

```powershell
Import-Module OSD
Set-OSDCloudWorkspace -WorkspacePath C:\OSDCloud-LZG\Workspace
New-OSDCloudUSB
Update-OSDCloudUSB
```

Gebruik geen handmatige bestandskopie om de bootmedia te maken. `New-OSDCloudUSB` partitioneert en maakt de USB bootbaar op de OSDCloud manier.

## Wat gebeurt er

- `Update-OSDCloudUSB.ps1`
  - synchroniseert `osdcloud-config.json` vanuit GitHub
  - haalt vendor driverpacks op
  - synchroniseert `Config`, `DriverPacks` en `Tools` naar de OSDCloud workspace
  - kan optioneel OSD's eigen `New-OSDCloudUSB` of `Update-OSDCloudUSB` starten

- `Build-OSDCloudUSB.ps1`
  - wijzigt geen bootstructuur
  - kopieert alleen LZG-bestanden naar `Workspace\Config`, `Workspace\DriverPacks` en `Workspace\DriverPacks\VendorTools`

- `Update-DriverPacks.ps1`
  - haalt Dell Latitude 3520 op via Dell Driver Pack Catalog
  - haalt HP ProBook G4 t/m G11 op via HP Client Driver Pack Catalog
  - haalt Surface Go 2, Go 3 en Go 4 op via de OSDCloud Surface-catalogus

## Belangrijk

- Laat `Workspace\Media` door OSDCloud maken en onderhouden.
- De vendor-downloads komen rechtstreeks van Dell, HP en Microsoft.
- Je hoeft geen driver-ZIPs meer in GitHub te zetten.
- Pas `Config\osdcloud-driver-manifest.json` alleen aan als je modellen wilt toevoegen of verwijderen.
