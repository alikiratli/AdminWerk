<#
.SYNOPSIS
    Vollstaendige Netzwerkdiagnose in einem Durchlauf.
.DESCRIPTION
    Arbeitet die klassische Fehlersuche von unten nach oben ab:
    Adapter -> IP-Konfiguration -> Gateway -> DNS-Server -> Namensaufloesung -> Internet.
    Der erste fehlschlagende Schritt zeigt, wo das Problem liegt.
.EXAMPLE
    .\netzwerk-schnellcheck.ps1
#>
[CmdletBinding()]
param(
    [string]$Testziel = 'www.microsoft.com',
    [string]$TestIP   = '1.1.1.1'
)

function Write-Schritt {
    param([string]$Titel, [bool]$Erfolg, [string]$Detail)

    $symbol = if ($Erfolg) { '[ OK ]' } else { '[FEHL]' }
    $farbe  = if ($Erfolg) { 'Green' } else { 'Red' }

    Write-Host ('{0,-7} {1,-28} {2}' -f $symbol, $Titel, $Detail) -ForegroundColor $farbe
}

Write-Host "`n=== Netzwerkdiagnose: $env:COMPUTERNAME ===`n" -ForegroundColor Cyan

# 1. Netzwerkadapter
$adapter = Get-NetAdapter | Where-Object Status -eq 'Up'
Write-Schritt -Titel 'Netzwerkadapter aktiv' -Erfolg ([bool]$adapter) `
    -Detail (($adapter | ForEach-Object { '{0} ({1})' -f $_.Name, $_.LinkSpeed }) -join ', ')

if (-not $adapter) {
    Write-Warning 'Kein aktiver Netzwerkadapter - weitere Pruefungen entfallen.'
    return
}

# 2. IP-Konfiguration
$konfiguration = Get-NetIPConfiguration | Where-Object { $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1
$ipv4 = $konfiguration.IPv4Address.IPAddress
$apipa = $ipv4 -like '169.254.*'

Write-Schritt -Titel 'IPv4-Adresse' -Erfolg ([bool]$ipv4 -and -not $apipa) `
    -Detail $(if ($apipa) { "$ipv4 (APIPA - kein DHCP erreichbar)" } else { "$ipv4/$($konfiguration.IPv4Address.PrefixLength)" })

# 3. Standardgateway
$gateway = $konfiguration.IPv4DefaultGateway.NextHop
if ($gateway) {
    $gatewayErreichbar = Test-Connection -ComputerName $gateway -Count 2 -Quiet -ErrorAction SilentlyContinue
    Write-Schritt -Titel 'Standardgateway erreichbar' -Erfolg $gatewayErreichbar -Detail $gateway
}
else {
    Write-Schritt -Titel 'Standardgateway' -Erfolg $false -Detail 'nicht konfiguriert'
}

# 4. DNS-Server
$dnsServer = $konfiguration.DNSServer | Where-Object AddressFamily -eq 2 | Select-Object -ExpandProperty ServerAddresses
Write-Schritt -Titel 'DNS-Server konfiguriert' -Erfolg ([bool]$dnsServer) -Detail ($dnsServer -join ', ')

# 5. Internet auf IP-Ebene (umgeht DNS)
$internetIP = Test-Connection -ComputerName $TestIP -Count 2 -Quiet -ErrorAction SilentlyContinue
Write-Schritt -Titel 'Internet (IP-Ebene)' -Erfolg $internetIP -Detail "Ping $TestIP"

# 6. Namensaufloesung
try {
    $aufloesung = Resolve-DnsName -Name $Testziel -Type A -ErrorAction Stop | Select-Object -First 1
    Write-Schritt -Titel 'Namensaufloesung' -Erfolg $true -Detail "$Testziel -> $($aufloesung.IPAddress)"
}
catch {
    Write-Schritt -Titel 'Namensaufloesung' -Erfolg $false -Detail "$Testziel konnte nicht aufgeloest werden"
}

# 7. HTTPS-Verbindung
$https = Test-NetConnection -ComputerName $Testziel -Port 443 -WarningAction SilentlyContinue
Write-Schritt -Titel 'HTTPS (Port 443)' -Erfolg $https.TcpTestSucceeded -Detail $Testziel

Write-Host ''
