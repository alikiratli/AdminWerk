<#
.SYNOPSIS
    Vergleicht den Starttyp von Diensten mit einer Soll-Vorgabe.
.DESCRIPTION
    Viele Stoerungen entstehen, weil ein Dienst zwar laeuft, sein Starttyp aber
    auf "Disabled" oder "Manual" steht und er nach dem naechsten Neustart fehlt.
    Das Skript stellt Ist- und Soll-Starttyp gegenueber.
.EXAMPLE
    .\dienste-starttyp.ps1
#>
[CmdletBinding()]
param(
    # Soll-Konfiguration: Dienstname = erwarteter Starttyp
    [hashtable]$Sollwerte = @{
        'EventLog'  = 'Automatic'
        'WinDefend' = 'Automatic'
        'wuauserv'  = 'Manual'
        'BITS'      = 'Manual'
        'Spooler'   = 'Automatic'
    }
)

$abweichungen = 0

$bericht = foreach ($name in $Sollwerte.Keys | Sort-Object) {
    $dienst = Get-CimInstance -ClassName Win32_Service -Filter "Name = '$name'" -ErrorAction SilentlyContinue

    if (-not $dienst) {
        [PSCustomObject]@{ Dienst = $name; Anzeigename = '-'; Ist = 'nicht vorhanden'; Soll = $Sollwerte[$name]; Bewertung = 'PRUEFEN' }
        $abweichungen++
        continue
    }

    # Win32_Service liefert "Auto"/"Manual"/"Disabled" - auf Get-Service-Schreibweise normalisieren.
    $ist = switch ($dienst.StartMode) {
        'Auto'     { 'Automatic' }
        'Manual'   { 'Manual' }
        'Disabled' { 'Disabled' }
        default    { $dienst.StartMode }
    }

    $passt = ($ist -eq $Sollwerte[$name])
    if (-not $passt) { $abweichungen++ }

    [PSCustomObject]@{
        Dienst      = $dienst.Name
        Anzeigename = $dienst.DisplayName
        Ist         = $ist
        Soll        = $Sollwerte[$name]
        Status      = $dienst.State
        Bewertung   = if ($passt) { 'OK' } else { 'ABWEICHUNG' }
    }
}

$bericht | Format-Table -AutoSize
$farbe = if ($abweichungen -gt 0) { 'Yellow' } else { 'Green' }
Write-Host "Abweichungen: $abweichungen" -ForegroundColor $farbe
