<#
.SYNOPSIS
    Testet die Namensaufloesung gegen einen oder mehrere DNS-Server.
.DESCRIPTION
    Loest eine Liste von Namen auf und vergleicht dabei mehrere DNS-Server.
    Abweichende Antworten deuten auf veraltete Zonen oder falsche Weiterleitungen hin.
.EXAMPLE
    .\dns-aufloesung-testen.ps1 -Namen dc01.firma.local, www.firma.de -DnsServer 10.0.0.10, 8.8.8.8
#>
[CmdletBinding()]
param(
    [string[]]$Namen = @('www.microsoft.com'),

    # Leer lassen, um die am Adapter konfigurierten DNS-Server zu verwenden.
    [string[]]$DnsServer
)

if (-not $DnsServer) {
    $DnsServer = (Get-DnsClientServerAddress -AddressFamily IPv4 |
        Where-Object { $_.ServerAddresses }).ServerAddresses | Select-Object -Unique
}

Write-Host "Verwendete DNS-Server: $($DnsServer -join ', ')`n" -ForegroundColor Cyan

$ergebnis = foreach ($name in $Namen) {
    foreach ($server in $DnsServer) {
        try {
            $antwort = Resolve-DnsName -Name $name -Server $server -Type A -DnsOnly -ErrorAction Stop |
                Where-Object QueryType -eq 'A'

            [PSCustomObject]@{
                Name       = $name
                DnsServer  = $server
                Ergebnis   = ($antwort.IPAddress -join ', ')
                TTL        = ($antwort | Select-Object -First 1).TTL
                Status     = 'OK'
            }
        }
        catch {
            [PSCustomObject]@{
                Name      = $name
                DnsServer = $server
                Ergebnis  = '-'
                TTL       = $null
                Status    = 'FEHLER'
            }
        }
    }
}

$ergebnis | Format-Table -AutoSize

# Abweichende Antworten zwischen den Servern sichtbar machen
$ergebnis | Group-Object Name | Where-Object { ($_.Group.Ergebnis | Select-Object -Unique).Count -gt 1 } |
    ForEach-Object { Write-Warning "Uneinheitliche Antwort fuer '$($_.Name)' - Zonen und Weiterleitungen pruefen." }
