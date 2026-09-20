<#
.SYNOPSIS
    Zeigt Status und Konfiguration aller Netzwerkadapter.
.DESCRIPTION
    Verbindet Adapterstatus, IP-Konfiguration, DNS-Server und Treiberinformationen
    zu einer Uebersicht - inklusive der Frage, ob die Adresse per DHCP bezogen wurde.
.EXAMPLE
    .\netzwerkadapter-status.ps1 -NurAktive
#>
[CmdletBinding()]
param(
    [switch]$NurAktive
)

$adapter = Get-NetAdapter
if ($NurAktive) {
    $adapter = $adapter | Where-Object Status -eq 'Up'
}

$bericht = foreach ($nic in $adapter) {
    $ip = Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $dns = (Get-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
    $gateway = (Get-NetRoute -InterfaceIndex $nic.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Select-Object -First 1).NextHop

    [PSCustomObject]@{
        Adapter      = $nic.Name
        Beschreibung = $nic.InterfaceDescription
        Status       = $nic.Status
        Geschwindigkeit = $nic.LinkSpeed
        MacAdresse   = $nic.MacAddress
        IPv4         = if ($ip) { '{0}/{1}' -f $ip.IPAddress, $ip.PrefixLength } else { '-' }
        Zuweisung    = if ($ip) { $ip.PrefixOrigin } else { '-' }
        Gateway      = if ($gateway) { $gateway } else { '-' }
        DnsServer    = ($dns -join ', ')
        Treiber      = $nic.DriverVersion
    }
}

$bericht | Format-List

$inaktiv = $bericht | Where-Object Status -ne 'Up'
if ($inaktiv) {
    Write-Host "`nInaktive Adapter: $(($inaktiv.Adapter) -join ', ')" -ForegroundColor Yellow
}
