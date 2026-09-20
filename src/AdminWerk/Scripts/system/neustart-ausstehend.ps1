<#
.SYNOPSIS
    Erkennt, ob auf dem System ein Neustart aussteht.
.DESCRIPTION
    Prueft alle gaengigen Anzeiger: Component Based Servicing, Windows Update,
    ausstehende Dateiumbenennungen sowie eine anstehende Domaenenbeitritt-/Umbenennung.
    Gibt ein Objekt mit allen Einzelbefunden zurueck.
.EXAMPLE
    .\neustart-ausstehend.ps1
#>
[CmdletBinding()]
param()

function Test-RegistrierungsSchluessel {
    param([string]$Pfad)
    return (Test-Path -Path $Pfad)
}

$cbs = Test-RegistrierungsSchluessel 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
$windowsUpdate = Test-RegistrierungsSchluessel 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'

# Ausstehende Dateioperationen, die erst beim Neustart ausgefuehrt werden
$sessionManager = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue
$dateiUmbenennung = [bool]$sessionManager.PendingFileRenameOperations

# Ausstehende Computerumbenennung
$aktiverName = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -ErrorAction SilentlyContinue).ComputerName
$zielName    = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -ErrorAction SilentlyContinue).ComputerName
$umbenennung = ($aktiverName -and $zielName -and $aktiverName -ne $zielName)

$ergebnis = [PSCustomObject]@{
    Computer                  = $env:COMPUTERNAME
    ComponentBasedServicing   = $cbs
    WindowsUpdate             = $windowsUpdate
    DateiumbenennungAusstehend = $dateiUmbenennung
    ComputerUmbenennung       = $umbenennung
    NeustartErforderlich      = ($cbs -or $windowsUpdate -or $dateiUmbenennung -or $umbenennung)
}

$ergebnis | Format-List

if ($ergebnis.NeustartErforderlich) {
    Write-Warning 'Es steht ein Neustart aus.'
    exit 1
}

Write-Host 'Kein Neustart erforderlich.' -ForegroundColor Green
