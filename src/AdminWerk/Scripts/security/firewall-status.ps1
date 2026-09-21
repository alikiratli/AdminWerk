<#
.SYNOPSIS
    Prueft die Windows-Firewall-Profile und deren Standardverhalten.
.DESCRIPTION
    Zeigt fuer Domaenen-, privates und oeffentliches Profil an, ob die Firewall
    aktiv ist, welches Standardverhalten fuer ein- und ausgehenden Verkehr gilt
    und ob die Protokollierung eingeschaltet ist.
.EXAMPLE
    .\firewall-status.ps1
#>
[CmdletBinding()]
param()

$firewallProfile = Get-NetFirewallProfile

Write-Host "`n=== Firewall-Profile: $env:COMPUTERNAME ===`n" -ForegroundColor Cyan

$bericht = foreach ($profil in $firewallProfile) {
    [PSCustomObject]@{
        Profil             = $profil.Name
        Aktiv              = $profil.Enabled
        Eingehend          = $profil.DefaultInboundAction
        Ausgehend          = $profil.DefaultOutboundAction
        BenachrichtigungAus = $profil.NotifyOnListen
        ProtokollVerworfen = $profil.LogBlocked
        ProtokollErlaubt   = $profil.LogAllowed
        Protokolldatei     = $profil.LogFileName
        Bewertung          = if ($profil.Enabled -and $profil.DefaultInboundAction -ne 'Allow') { 'OK' } else { 'PRUEFEN' }
    }
}

$bericht | Format-List

$abgeschaltet = $bericht | Where-Object { -not $_.Aktiv }
if ($abgeschaltet) {
    Write-Warning "Firewall ist in folgenden Profilen deaktiviert: $($abgeschaltet.Profil -join ', ')"
}
else {
    Write-Host 'Die Firewall ist in allen Profilen aktiv.' -ForegroundColor Green
}
