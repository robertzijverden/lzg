# OSDCloud USB Build en Update

## Doel
Deze scripts maken een up-to-date OSDCloud USB-masterkopie voor:
- Microsoft Surface Go 2, Go 3 en Go 4
- HP ProBook G4 ... G11 series
- Dell Latitude 3520

De build bevat Windows 11-installatie en offline driver-/firmwarepakketten.

## Gebruik

1. Open PowerShell in `C:\OSDCloud-LZG`.
2. Voer uit:

```powershell
.\Update-OSDCloudUSB.ps1
```

3. Wil je direct naar een USB-schijf schrijven?

```powershell
.\Update-OSDCloudUSB.ps1 -UsbDriveLetter E
```

4. De mastercopy verschijnt in `Workspace\USB`.

## Wat gebeurt er

- `Update-OSDCloudUSB.ps1`
  - synchroniseert `osdcloud-config.json` vanuit de openbare GitHub root via raw.githubusercontent.com
  - werkt offline driverpacks bij via `Config/osdcloud-driver-manifest.json`
  - bouwt `Workspace\USB` met bootmedia + `Config`, `DriverPacks`, `Tools`

- `Build-OSDCloudUSB.ps1`
  - kopieert alleen de benodigde bestanden naar de USB-buildmap

- `Update-DriverPacks.ps1`
  - haalt Dell Latitude 3520 op via Dell Driver Pack Catalog
  - haalt HP ProBook G4 t/m G11 op via HP Client Driver Pack Catalog
  - haalt Surface Go 2, Go 3 en Go 4 op via de OSDCloud Surface-catalogus
  - pakt de pakketten uit naar `DriverPacks`

## Belangrijk

- Plaats je eigen Windows 11 bootmedia in `Workspace\Media`.
- De vendor-downloads komen rechtstreeks van Dell, HP en Microsoft; je hoeft geen driver-ZIPs meer in GitHub te zetten.
- Pas `Config/osdcloud-config.json` en `Config/osdcloud-driver-manifest.json` alleen aan als je modellen wilt toevoegen of verwijderen.

## Vendor catalogus testen

Controleer eerst of de officiële vendor-catalogi bereikbaar zijn zonder grote downloads:

```powershell
.\Update-DriverPacks.ps1 -CatalogOnly
```

Of test de volledige USB-flow zonder grote driverdownloads:

```powershell
.\Update-OSDCloudUSB.ps1 -CatalogOnly
```

Per vendor:

```powershell
.\Update-DriverPacks.ps1 -CatalogOnly -Vendor Dell
.\Update-DriverPacks.ps1 -CatalogOnly -Vendor HP
.\Update-DriverPacks.ps1 -CatalogOnly -Vendor Microsoft
```

Download en pak alles echt uit:

```powershell
.\Update-DriverPacks.ps1
```

Daarna USB opnieuw bouwen:

```powershell
.\Update-OSDCloudUSB.ps1 -UsbDriveLetter E
```
