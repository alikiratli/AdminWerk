<#
.SYNOPSIS
    Zeigt die Auslastung aller DHCP-Bereiche und warnt bei knappem Adressvorrat.
.DESCRIPTION
    Wertet jeden Bereich eines Windows-DHCP-Servers aus: freie und vergebene
    Adressen, Auslastung in Prozent sowie abgelaufene Leases.
.NOTES
    Benoetigt das Feature "DHCP-Server-Tools" (Modul DhcpServer).
.EXAMPLE
    .\dhcp-scope-auslastung.ps1 -Server dhcp01 -WarnungAbProzent 80
#>
[CmdletBinding()]
param(
    [string]$Server = $env:COMPUTERNAME,
    [int]$WarnungAbProzent = 85
)

if (-not (Get-Module -ListAvailable -Name DhcpServer)) {
    throw 'Das Modul "DhcpServer" ist nicht verfuegbar. Bitte die DHCP-Server-Tools (RSAT) installieren.'
}

Import-Module DhcpServer -ErrorAction Stop

$bereiche = Get-DhcpServerv4Scope -ComputerName $Server

$bericht = foreach ($bereich in $bereiche) {
    $statistik = Get-DhcpServerv4ScopeStatistics -ComputerName $Server -ScopeId $bereich.ScopeId

    [PSCustomObject]@{
        BereichID       = $bereich.ScopeId
        Name            = $bereich.Name
        Status          = $bereich.State
        Von             = $bereich.StartRange
        Bis             = $bereich.EndRange
        Leasedauer      = $bereich.LeaseDuration
        Vergeben        = $statistik.InUse
        Frei            = $statistik.Free
        AuslastungProzent = [math]::Round($statistik.PercentageInUse, 1)
        Bewertung       = if ($statistik.PercentageInUse -ge $WarnungAbProzent) { 'KRITISCH' } else { 'OK' }
    }
}

$bericht | Format-Table -AutoSize

$kritisch = $bericht | Where-Object Bewertung -eq 'KRITISCH'
foreach ($eintrag in $kritisch) {
    Write-Warning "Bereich $($eintrag.BereichID) ($($eintrag.Name)) ist zu $($eintrag.AuslastungProzent) % ausgelastet."
}

Write-Host "`n=== Abgelaufene Leases ===" -ForegroundColor Cyan
$abgelaufen = foreach ($bereich in $bereiche) {
    Get-DhcpServerv4Lease -ComputerName $Server -ScopeId $bereich.ScopeId -ErrorAction SilentlyContinue |
        Where-Object { $_.LeaseExpiryTime -and $_.LeaseExpiryTime -lt (Get-Date) }
}

if ($abgelaufen) {
    $abgelaufen | Select-Object IPAddress, HostName, ClientId, LeaseExpiryTime | Format-Table -AutoSize
}
else {
    Write-Host 'Keine abgelaufenen Leases.' -ForegroundColor Green
}
