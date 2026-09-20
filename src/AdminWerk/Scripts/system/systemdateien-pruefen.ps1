<#
.SYNOPSIS
    Prueft und repariert beschaedigte Windows-Systemdateien (DISM und SFC).
.DESCRIPTION
    Fuehrt die empfohlene Reihenfolge aus: zuerst DISM gegen das Komponentenspeicher-
    Abbild, danach SFC gegen die geschuetzten Systemdateien. Mit -NurPruefen wird
    ausschliesslich geprueft, ohne etwas zu reparieren.
.NOTES
    Benoetigt eine PowerShell-Sitzung mit Administratorrechten. Laufzeit: 10-40 Minuten.
.EXAMPLE
    .\systemdateien-pruefen.ps1 -NurPruefen
#>
[CmdletBinding()]
param(
    [switch]$NurPruefen,
    [string]$Berichtsdatei = "$env:ProgramData\AdminWerk\systemdateien-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
)

$istAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $istAdmin) {
    throw 'Dieses Skript benoetigt eine PowerShell-Sitzung mit Administratorrechten.'
}

$verzeichnis = Split-Path -Path $Berichtsdatei -Parent
if (-not (Test-Path -Path $verzeichnis)) {
    New-Item -Path $verzeichnis -ItemType Directory -Force | Out-Null
}

function Invoke-Schritt {
    param([string]$Titel, [string]$Programm, [string[]]$Argumente)

    Write-Host "`n=== $Titel ===" -ForegroundColor Cyan
    $ausgabe = & $Programm @Argumente 2>&1
    $ausgabe | Tee-Object -FilePath $Berichtsdatei -Append | Out-Host

    [PSCustomObject]@{
        Schritt   = $Titel
        ExitCode  = $LASTEXITCODE
        Bewertung = if ($LASTEXITCODE -eq 0) { 'OK' } else { 'PRUEFEN' }
    }
}

$ergebnisse = @()

if ($NurPruefen) {
    $ergebnisse += Invoke-Schritt -Titel 'DISM: Abbild pruefen' -Programm 'DISM.exe' -Argumente @('/Online', '/Cleanup-Image', '/ScanHealth')
    $ergebnisse += Invoke-Schritt -Titel 'SFC: Nur pruefen'     -Programm 'sfc.exe'  -Argumente @('/verifyonly')
}
else {
    $ergebnisse += Invoke-Schritt -Titel 'DISM: Abbild pruefen'     -Programm 'DISM.exe' -Argumente @('/Online', '/Cleanup-Image', '/ScanHealth')
    $ergebnisse += Invoke-Schritt -Titel 'DISM: Abbild reparieren'  -Programm 'DISM.exe' -Argumente @('/Online', '/Cleanup-Image', '/RestoreHealth')
    $ergebnisse += Invoke-Schritt -Titel 'SFC: Systemdateien pruefen und reparieren' -Programm 'sfc.exe' -Argumente @('/scannow')
}

Write-Host "`n=== Zusammenfassung ===" -ForegroundColor Cyan
$ergebnisse | Format-Table -AutoSize
Write-Host "Vollstaendiges Protokoll: $Berichtsdatei"
