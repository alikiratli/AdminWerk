<#
.SYNOPSIS
    Prueft den freien Speicherplatz aller lokalen Datentraeger.
.DESCRIPTION
    Meldet jeden Datentraeger, dessen freier Speicher unter den Schwellenwert faellt,
    und schreibt bei Unterschreitung einen Eintrag in eine Logdatei.
.PARAMETER SchwellenwertProzent
    Ab welchem freien Anteil (in Prozent) gewarnt wird. Standard: 15.
.EXAMPLE
    .\datentraeger-pruefen.ps1 -SchwellenwertProzent 20
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 99)]
    [int]$SchwellenwertProzent = 15,

    [string]$LogDatei = "$env:ProgramData\AdminWerk\datentraeger.log"
)

$ergebnis = Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' |
    ForEach-Object {
        $freiProzent = if ($_.Size -gt 0) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 1) } else { 0 }

        [PSCustomObject]@{
            Laufwerk     = $_.DeviceID
            Bezeichnung  = $_.VolumeName
            GesamtGB     = [math]::Round($_.Size / 1GB, 2)
            FreiGB       = [math]::Round($_.FreeSpace / 1GB, 2)
            FreiProzent  = $freiProzent
            Status       = if ($freiProzent -lt $SchwellenwertProzent) { 'KRITISCH' } else { 'OK' }
        }
    }

$ergebnis | Format-Table -AutoSize

# Kritische Laufwerke zusaetzlich protokollieren
$kritisch = $ergebnis | Where-Object Status -eq 'KRITISCH'

if ($kritisch) {
    $verzeichnis = Split-Path -Path $LogDatei -Parent
    if (-not (Test-Path -Path $verzeichnis)) {
        New-Item -Path $verzeichnis -ItemType Directory -Force | Out-Null
    }

    foreach ($laufwerk in $kritisch) {
        $zeile = '{0} [WARNUNG] {1} Laufwerk {2} nur noch {3} % frei ({4} GB von {5} GB)' -f `
            (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $env:COMPUTERNAME,
            $laufwerk.Laufwerk, $laufwerk.FreiProzent, $laufwerk.FreiGB, $laufwerk.GesamtGB

        Add-Content -Path $LogDatei -Value $zeile -Encoding UTF8
        Write-Warning $zeile
    }

    exit 1
}

Write-Host "Alle Datentraeger liegen ueber dem Schwellenwert von $SchwellenwertProzent %." -ForegroundColor Green
