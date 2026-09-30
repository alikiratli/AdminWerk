<#
.SYNOPSIS
    Prueft Druckertreiber, Point-and-Print-Richtlinien und den Druckspooler.
.DESCRIPTION
    Drei Blickwinkel auf den lokalen Computer:

      Treiber      - alle installierten Druckertreiber mit Typ, Umgebung und
                     Dateiversion, und welche davon kein Drucker mehr benutzt
                     (ohne die Treiber, die Windows selbst mitbringt).
      Richtlinien  - die Point-and-Print-Einstellungen, die seit "PrintNightmare"
                     (CVE-2021-34527) zaehlen. Gefaehrlich ist die Kombination, bei der
                     Standardbenutzer Treiber ohne Warnung und ohne Erhoehung
                     installieren duerfen.
      Spooler      - laeuft die Druckwarteschlange auf einem Domaenencontroller, ist
                     das ein Befund: Microsoft empfiehlt dort, sie abzuschalten.

    Ein gefaehrlicher Point-and-Print-Zustand oder ein laufender Spooler auf einem
    Domaenencontroller fuehren zu Exitcode 1. Das Skript liest nur.
.PARAMETER CsvPfad
    Schreibt die Treiberliste zusaetzlich als CSV (Semikolon, UTF-8).
.EXAMPLE
    .\druckertreiber-pointandprint.ps1
.EXAMPLE
    .\druckertreiber-pointandprint.ps1 -CsvPfad C:\Berichte\druckertreiber.csv
#>
[CmdletBinding()]
param(
    [string]$CsvPfad
)

$befunde = New-Object System.Collections.Generic.List[string]

# --- Treiber -----------------------------------------------------------------
Write-Host "`n=== Druckertreiber: $env:COMPUTERNAME ===" -ForegroundColor Cyan

$drucker = @(Get-CimInstance -ClassName Win32_Printer -ErrorAction SilentlyContinue)
$benutzt = @{}
foreach ($d in $drucker) {
    $name = [string]$d.DriverName
    if (-not $benutzt.ContainsKey($name)) { $benutzt[$name] = 0 }
    $benutzt[$name]++
}

$treiber = foreach ($t in @(Get-CimInstance -ClassName Win32_PrinterDriver -ErrorAction SilentlyContinue)) {
    # Name hat die Form "Treibername,Version,Umgebung".
    $teile = ([string]$t.Name) -split ','
    $name = $teile[0]

    $dateiversion = ''
    if ($t.DriverPath -and (Test-Path -LiteralPath $t.DriverPath)) {
        $dateiversion = (Get-Item -LiteralPath $t.DriverPath).VersionInfo.FileVersion
    }

    $anzahl = 0
    if ($benutzt.ContainsKey($name)) { $anzahl = $benutzt[$name] }

    [PSCustomObject]@{
        Treiber     = $name
        Typ         = 'V{0}' -f $t.Version
        Umgebung    = $teile[-1]
        Dateiversion = $dateiversion
        Drucker     = $anzahl
    }
}
$treiber = @($treiber)

if ($treiber.Count -eq 0) {
    Write-Host 'Keine Druckertreiber gefunden.' -ForegroundColor DarkGray
}
else {
    $treiber | Sort-Object Treiber, Umgebung | Format-Table -AutoSize

    # Die Microsoft-Treiber gehoeren zu Windows und kommen mit dem naechsten Update
    # wieder - als Aufraeumkandidaten waeren sie nur Rauschen.
    $ungenutzt = @($treiber | Where-Object { $_.Drucker -eq 0 -and $_.Treiber -notlike 'Microsoft *' })
    if ($ungenutzt.Count -gt 0) {
        Write-Host ("{0} Treiber ohne Drucker - Kandidaten zum Aufraeumen (Druckverwaltung oder Remove-PrinterDriver):" -f `
            $ungenutzt.Count) -ForegroundColor Yellow
        $ungenutzt | ForEach-Object { Write-Host ("  {0} ({1})" -f $_.Treiber, $_.Umgebung) }
    }
}

# --- Point and Print ---------------------------------------------------------
Write-Host "`n=== Point-and-Print-Richtlinien ===" -ForegroundColor Cyan

$ppSchluessel = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint'
$pp = Get-ItemProperty -Path $ppSchluessel -ErrorAction SilentlyContinue

$nurAdmins = $null
$ohneWarnung = $null
$aktualisieren = $null
if ($pp) {
    $nurAdmins = $pp.RestrictDriverInstallationToAdministrators
    $ohneWarnung = $pp.NoWarningNoElevationOnInstall
    $aktualisieren = $pp.UpdatePromptSettings
}

function Get-Anzeige {
    param($Wert)
    if ($null -eq $Wert) { 'nicht gesetzt' } else { [string]$Wert }
}

[PSCustomObject]@{
    RestrictDriverInstallationToAdministrators = Get-Anzeige $nurAdmins
    NoWarningNoElevationOnInstall              = Get-Anzeige $ohneWarnung
    UpdatePromptSettings                       = Get-Anzeige $aktualisieren
} | Format-List

# Seit den Updates vom August 2021 gilt "nicht gesetzt" wie 1: nur Administratoren
# installieren Treiber. Erst eine ausdrueckliche 0 oeffnet das wieder.
$nurAdminsAus = ($nurAdmins -eq 0) -and ($null -ne $nurAdmins)
$ohneRueckfrage = ($ohneWarnung -eq 1) -or ($aktualisieren -eq 1) -or ($aktualisieren -eq 2)

if ($nurAdminsAus -and $ohneRueckfrage) {
    $befund = 'Point and Print: Standardbenutzer duerfen Treiber ohne Warnung und ohne Erhoehung installieren.'
    $befunde.Add($befund)
    Write-Warning $befund
    Write-Host '  Empfehlung: RestrictDriverInstallationToAdministrators = 1 oder beide Rueckfragen einschalten.' -ForegroundColor Yellow
}
elseif ($nurAdminsAus) {
    Write-Host 'Standardbenutzer duerfen Treiber installieren, werden aber gefragt. Pruefen, ob das gewollt ist.' -ForegroundColor Yellow
}
else {
    Write-Host 'Nur Administratoren installieren Druckertreiber.' -ForegroundColor Green
}

# --- Spooler -----------------------------------------------------------------
Write-Host "`n=== Druckwarteschlange (Spooler) ===" -ForegroundColor Cyan

$system = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
$istDc = $system -and ($system.DomainRole -eq 4 -or $system.DomainRole -eq 5)
$spooler = Get-CimInstance -ClassName Win32_Service -Filter "Name='Spooler'" -ErrorAction SilentlyContinue

$virtuellMuster = 'Microsoft Print to PDF|Microsoft XPS|OneNote|Fax|Send To Microsoft'
$echteDrucker = @($drucker | Where-Object {
    [string]$_.DriverName -notmatch $virtuellMuster -and [string]$_.Name -notmatch $virtuellMuster
})

# "Allow Print Spooler to accept client connections": 2 = abgeschaltet.
$fernzugriff = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers' `
    -Name RegisterSpoolerRemoteRpcEndPoint -ErrorAction SilentlyContinue).RegisterSpoolerRemoteRpcEndPoint

[PSCustomObject]@{
    Zustand          = if ($spooler) { $spooler.State } else { 'nicht vorhanden' }
    Starttyp         = if ($spooler) { $spooler.StartMode } else { '-' }
    Domaenencontroller = [bool]$istDc
    EchteDrucker     = $echteDrucker.Count
    Clientverbindungen = if ($fernzugriff -eq 2) { 'per Richtlinie abgelehnt' } else { 'erlaubt (Standard)' }
} | Format-List

$laeuft = $spooler -and $spooler.State -eq 'Running'
if ($istDc -and $laeuft) {
    $befund = 'Die Druckwarteschlange laeuft auf einem Domaenencontroller.'
    $befunde.Add($befund)
    Write-Warning $befund
    Write-Host '  Empfehlung: Dienst "Spooler" beenden und deaktivieren, sofern hier nicht gedruckt wird.' -ForegroundColor Yellow
}
elseif ($laeuft -and $echteDrucker.Count -eq 0) {
    Write-Host 'Kein Drucker eingerichtet, der Spooler laeuft trotzdem. Wird hier nie gedruckt, kann er aus.' -ForegroundColor DarkGray
}

if ($CsvPfad) {
    $treiber | Export-Csv -Path $CsvPfad -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Host "CSV-Export: $CsvPfad" -ForegroundColor Green
}

if ($befunde.Count -gt 0) {
    exit 1
}
