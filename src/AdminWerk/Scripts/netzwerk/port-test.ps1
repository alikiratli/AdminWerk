<#
.SYNOPSIS
    Prueft die TCP-Erreichbarkeit mehrerer Ziele und Ports.
.DESCRIPTION
    Testet eine Matrix aus Zielen und Ports und gibt eine kompakte Tabelle zurueck.
    Nuetzlich, um nach Firewall-Aenderungen die wichtigsten Dienstwege zu pruefen.
.EXAMPLE
    .\port-test.ps1 -Ziele dc01, sql01 -Ports 53, 389, 445, 1433
#>
[CmdletBinding()]
param(
    [string[]]$Ziele = @('www.microsoft.com'),
    [int[]]$Ports = @(80, 443),
    [int]$ZeitlimitMs = 2000
)

$ergebnis = foreach ($ziel in $Ziele) {
    foreach ($port in $Ports) {
        $klient = New-Object System.Net.Sockets.TcpClient
        $start  = Get-Date

        try {
            $verbindung = $klient.BeginConnect($ziel, $port, $null, $null)
            $erfolg = $verbindung.AsyncWaitHandle.WaitOne($ZeitlimitMs, $false) -and $klient.Connected

            if ($erfolg) { $klient.EndConnect($verbindung) }
        }
        catch {
            $erfolg = $false
        }
        finally {
            $klient.Close()
        }

        [PSCustomObject]@{
            Ziel     = $ziel
            Port     = $port
            Dienst   = switch ($port) {
                20    { 'FTP-Daten' }   21   { 'FTP' }        22   { 'SSH' }
                23    { 'Telnet' }      25   { 'SMTP' }       53   { 'DNS' }
                80    { 'HTTP' }        88   { 'Kerberos' }   135  { 'RPC' }
                139   { 'NetBIOS' }     389  { 'LDAP' }       443  { 'HTTPS' }
                445   { 'SMB' }         636  { 'LDAPS' }      1433 { 'MSSQL' }
                3268  { 'Globaler Katalog' }                  3389 { 'RDP' }
                5985  { 'WinRM HTTP' }  5986 { 'WinRM HTTPS' }
                default { '-' }
            }
            Erreichbar = $erfolg
            DauerMs    = [math]::Round(((Get-Date) - $start).TotalMilliseconds)
        }
    }
}

$ergebnis | Format-Table -AutoSize

$fehlgeschlagen = $ergebnis | Where-Object { -not $_.Erreichbar }
if ($fehlgeschlagen) {
    Write-Warning "Nicht erreichbar: $(($fehlgeschlagen | ForEach-Object { '{0}:{1}' -f $_.Ziel, $_.Port }) -join ', ')"
}
else {
    Write-Host 'Alle geprueften Ports sind erreichbar.' -ForegroundColor Green
}
