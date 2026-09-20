<#
.SYNOPSIS
    Prueft die Konfiguration des Remotedesktops (RDP).
.DESCRIPTION
    Ermittelt, ob RDP aktiviert ist, auf welchem Port es lauscht, ob die
    Authentifizierung auf Netzwerkebene (NLA) erzwungen wird, wer zugreifen darf
    und welche Firewall-Regeln dafuer offen sind.
.EXAMPLE
    .\rdp-konfiguration.ps1
#>
[CmdletBinding()]
param()

$basis    = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
$station  = "$basis\WinStations\RDP-Tcp"

$gesperrt = (Get-ItemProperty -Path $basis -Name fDenyTSConnections -ErrorAction SilentlyContinue).fDenyTSConnections
$aktiv    = ($gesperrt -eq 0)

Write-Host "`n=== Remotedesktop: $env:COMPUTERNAME ===`n" -ForegroundColor Cyan

if (-not $aktiv) {
    Write-Host 'RDP ist deaktiviert.' -ForegroundColor Green
    return
}

$nla   = (Get-ItemProperty -Path $station -Name UserAuthentication -ErrorAction SilentlyContinue).UserAuthentication
$port  = (Get-ItemProperty -Path $station -Name PortNumber -ErrorAction SilentlyContinue).PortNumber
$stufe = (Get-ItemProperty -Path $station -Name SecurityLayer -ErrorAction SilentlyContinue).SecurityLayer

$sicherheitsstufe = switch ($stufe) {
    0 { 'RDP (niedrig)' }
    1 { 'Aushandeln' }
    2 { 'SSL/TLS (empfohlen)' }
    default { 'unbekannt' }
}

[PSCustomObject]@{
    RdpAktiviert    = $aktiv
    Port            = $port
    PortStandard    = ($port -eq 3389)
    NlaErzwungen    = ($nla -eq 1)
    Sicherheitsstufe = $sicherheitsstufe
} | Format-List

if ($nla -ne 1) {
    Write-Warning 'NLA ist nicht aktiv. Empfehlung: Authentifizierung auf Netzwerkebene erzwingen.'
}

Write-Host '=== Zugriffsberechtigte ===' -ForegroundColor Cyan
try {
    Get-LocalGroupMember -SID 'S-1-5-32-555' -ErrorAction Stop |
        Select-Object Name, ObjectClass, PrincipalSource | Format-Table -AutoSize
}
catch {
    Write-Host 'Gruppe "Remotedesktopbenutzer" ist leer - nur Administratoren duerfen sich verbinden.' -ForegroundColor DarkGray
}

Write-Host '=== Firewall-Regeln fuer RDP ===' -ForegroundColor Cyan
Get-NetFirewallRule -DisplayGroup 'Remotedesktop' -ErrorAction SilentlyContinue |
    Where-Object Enabled -eq 'True' |
    Select-Object DisplayName, Profile, Action, Direction | Format-Table -AutoSize

Write-Host '=== Aktive Sitzungen ===' -ForegroundColor Cyan
$sitzungen = & quser.exe 2>$null
if ($sitzungen) { $sitzungen } else { Write-Host 'Keine aktiven Sitzungen.' -ForegroundColor DarkGray }
