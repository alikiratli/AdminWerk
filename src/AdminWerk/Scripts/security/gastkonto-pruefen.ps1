<#
.SYNOPSIS
    Prueft Gast- und Standardkonten sowie deren Zustand.
.DESCRIPTION
    Ermittelt das Gastkonto und das eingebaute Administratorkonto ueber ihre
    bekannten SID-Endungen (-501 bzw. -500) und meldet, wenn sie aktiviert sind
    oder ihr Kennwort nie ablaeuft.
.EXAMPLE
    .\gastkonto-pruefen.ps1
#>
[CmdletBinding()]
param()

$konten = Get-LocalUser

$gast          = $konten | Where-Object { $_.SID.Value -like '*-501' }
$administrator = $konten | Where-Object { $_.SID.Value -like '*-500' }

Write-Host "`n=== Eingebaute Konten: $env:COMPUTERNAME ===`n" -ForegroundColor Cyan

foreach ($konto in @($administrator, $gast)) {
    if (-not $konto) { continue }

    $rolle = if ($konto.SID.Value -like '*-500') { 'Eingebauter Administrator' } else { 'Gastkonto' }
    $farbe = if ($konto.Enabled) { 'Yellow' } else { 'Green' }

    Write-Host "$rolle : $($konto.Name)" -ForegroundColor White
    Write-Host ('  Aktiviert            : {0}' -f $konto.Enabled) -ForegroundColor $farbe
    Write-Host ('  Kennwort zuletzt am  : {0}' -f $konto.PasswordLastSet)
    Write-Host ('  Kennwort laeuft ab   : {0}' -f $(if ($konto.PasswordExpires) { $konto.PasswordExpires } else { 'nie' }))
    Write-Host ('  Letzte Anmeldung     : {0}' -f $konto.LastLogon)
    Write-Host ''
}

if ($gast -and $gast.Enabled) {
    Write-Warning "Das Gastkonto ist aktiviert. Empfehlung: Disable-LocalUser -Name '$($gast.Name)'"
}
else {
    Write-Host 'Das Gastkonto ist deaktiviert.' -ForegroundColor Green
}

Write-Host "`n=== Alle lokalen Konten ===" -ForegroundColor Cyan
$konten | Select-Object Name, Enabled, LastLogon, PasswordLastSet, PasswordRequired, Description |
    Sort-Object Name | Format-Table -AutoSize
