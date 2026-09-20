<#
.SYNOPSIS
    Wertet die aktiven Windows-Firewall-Regeln fuer eingehenden Verkehr aus.
.DESCRIPTION
    Zeigt Profilstatus sowie alle aktiven Erlaubnisregeln fuer eingehende
    Verbindungen mit Port, Protokoll und zugehoerigem Programm.
.EXAMPLE
    .\firewall-regeln.ps1 -NurEingehendErlaubt
#>
[CmdletBinding()]
param(
    [switch]$NurEingehendErlaubt = $true
)

Write-Host "`n=== Firewall-Profile ===" -ForegroundColor Cyan
Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction, LogFileName |
    Format-Table -AutoSize

Write-Host "=== Aktive Regeln (eingehend, erlaubt) ===" -ForegroundColor Cyan

$regeln = Get-NetFirewallRule -Enabled True -Direction Inbound
if ($NurEingehendErlaubt) {
    $regeln = $regeln | Where-Object Action -eq 'Allow'
}

$bericht = foreach ($regel in $regeln) {
    $port      = $regel | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
    $anwendung = $regel | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
    $adresse   = $regel | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue

    [PSCustomObject]@{
        Name       = $regel.DisplayName
        Profil     = $regel.Profile
        Protokoll  = $port.Protocol
        LokalerPort = ($port.LocalPort -join ', ')
        Quelle     = ($adresse.RemoteAddress -join ', ')
        Programm   = $anwendung.Program
        Gruppe     = $regel.DisplayGroup
    }
}

$bericht | Sort-Object Name | Format-Table -AutoSize -Wrap

Write-Host "`nAktive eingehende Regeln: $($bericht.Count)" -ForegroundColor White

# Regeln, die von beliebiger Quelle erlaubt sind, gesondert ausweisen
$offen = $bericht | Where-Object { $_.Quelle -contains 'Any' -and $_.LokalerPort -ne 'Any' -and $_.LokalerPort }
if ($offen) {
    Write-Host "`nHinweis: $($offen.Count) Regeln erlauben Zugriff von beliebigen Quelladressen." -ForegroundColor Yellow
}
