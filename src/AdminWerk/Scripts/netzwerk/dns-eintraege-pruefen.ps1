<#
.SYNOPSIS
    Prueft DNS-Eintraege einer Zone auf Vollstaendigkeit und Karteileichen.
.DESCRIPTION
    Drei Pruefungen in einem Skript:
    1. Alle Eintraege einer Zone auflisten, nach Typ gruppiert (A, CNAME, MX, SRV, ...).
    2. Die SRV-Eintraege pruefen, ueber die Clients ihre Domaenencontroller finden -
       fehlen sie, funktioniert die Anmeldung an der Domaene nicht zuverlaessig.
    3. Veraltete Eintraege finden: A-Eintraege, deren Ziel nicht mehr antwortet,
       und Eintraege, die seit langer Zeit nicht mehr aktualisiert wurden.
.NOTES
    Vollstaendig nur mit dem Modul DnsServer (RSAT). Ohne das Modul werden die
    Eintraege per Abfrage geprueft, aber nicht aus der Zone gelesen.
.EXAMPLE
    .\dns-eintraege-pruefen.ps1 -Zone firma.local -Server dc01
.EXAMPLE
    .\dns-eintraege-pruefen.ps1 -Zone firma.local -VeralteteFinden -AlterTage 90
#>
[CmdletBinding()]
param(
    [string]$Zone,

    [string]$Server = $env:COMPUTERNAME,

    # Einzelne Namen gezielt abfragen, auch ohne DnsServer-Modul.
    [string[]]$Namen,

    [switch]$VeralteteFinden,

    [int]$AlterTage = 90,

    [string]$CsvPfad
)

# --- Gezielte Abfrage einzelner Namen ----------------------------------------
if ($Namen) {
    Write-Host "`n=== Abfrage einzelner Namen ===`n" -ForegroundColor Cyan

    foreach ($name in $Namen) {
        foreach ($typ in 'A', 'AAAA', 'CNAME', 'MX') {
            try {
                $antwort = Resolve-DnsName -Name $name -Type $typ -Server $Server -ErrorAction Stop |
                    Where-Object { $_.QueryType -eq $typ }

                foreach ($eintrag in $antwort) {
                    $wert = switch ($typ) {
                        'A'     { $eintrag.IPAddress }
                        'AAAA'  { $eintrag.IPAddress }
                        'CNAME' { $eintrag.NameHost }
                        'MX'    { '{0} (Prioritaet {1})' -f $eintrag.NameExchange, $eintrag.Preference }
                    }

                    Write-Host ('[ OK ] {0,-34} {1,-6} {2}' -f $name, $typ, $wert) -ForegroundColor Green
                }
            }
            catch {
                # Kein Eintrag dieses Typs - das ist der Normalfall, nicht der Fehlerfall.
                Write-Verbose ("{0}: kein {1}-Eintrag" -f $name, $typ)
            }
        }
    }
}

if (-not $Zone) {
    if (-not $Namen) {
        Write-Warning 'Bitte -Zone oder -Namen angeben.'
    }
    return
}

if (-not (Get-Module -ListAvailable -Name DnsServer)) {
    throw 'Das Modul "DnsServer" wird fuer die Zonenpruefung benoetigt. Bitte die DNS-Server-Tools (RSAT) installieren.'
}

Import-Module DnsServer -ErrorAction Stop

# --- Alle Eintraege der Zone -------------------------------------------------
Write-Host "`n=== Zone: $Zone auf $Server ===`n" -ForegroundColor Cyan

$eintraege = Get-DnsServerResourceRecord -ZoneName $Zone -ComputerName $Server -ErrorAction Stop

$aufbereitet = foreach ($eintrag in $eintraege) {
    $wert = switch ($eintrag.RecordType) {
        'A'     { $eintrag.RecordData.IPv4Address.IPAddressToString }
        'AAAA'  { $eintrag.RecordData.IPv6Address.IPAddressToString }
        'CNAME' { $eintrag.RecordData.HostNameAlias }
        'MX'    { '{0} (Prioritaet {1})' -f $eintrag.RecordData.MailExchange, $eintrag.RecordData.Preference }
        'SRV'   { '{0}:{1}' -f $eintrag.RecordData.DomainName, $eintrag.RecordData.Port }
        'NS'    { $eintrag.RecordData.NameServer }
        'PTR'   { $eintrag.RecordData.PtrDomainName }
        'TXT'   { $eintrag.RecordData.DescriptiveText }
        'SOA'   { $eintrag.RecordData.PrimaryServer }
        default { '-' }
    }

    [PSCustomObject]@{
        Name       = $eintrag.HostName
        Typ        = $eintrag.RecordType
        Wert       = $wert
        TTL        = $eintrag.TimeToLive
        Zeitstempel = $eintrag.Timestamp
        Statisch   = ($null -eq $eintrag.Timestamp)
    }
}

Write-Host '--- Anzahl je Eintragstyp ---' -ForegroundColor White
$aufbereitet | Group-Object Typ | Sort-Object Count -Descending |
    Select-Object @{ Name = 'Typ'; Expression = { $_.Name } }, Count | Format-Table -AutoSize

Write-Host '--- Eintraege (Auszug) ---' -ForegroundColor White
$aufbereitet | Where-Object Typ -in 'A', 'CNAME', 'MX' | Sort-Object Typ, Name |
    Select-Object -First 40 Name, Typ, Wert, TTL, Statisch | Format-Table -AutoSize

# --- Domaenencontroller-SRV-Eintraege ----------------------------------------
Write-Host '=== SRV-Eintraege fuer die Domaenenanmeldung ===' -ForegroundColor Cyan

$srvNamen = @(
    '_ldap._tcp.dc._msdcs'
    '_kerberos._tcp.dc._msdcs'
    '_ldap._tcp'
    '_kerberos._tcp'
    '_gc._tcp'
)

foreach ($srv in $srvNamen) {
    $vollerName = "$srv.$Zone"

    try {
        $antwort = Resolve-DnsName -Name $vollerName -Type SRV -Server $Server -ErrorAction Stop |
            Where-Object QueryType -eq 'SRV'

        $ziele = ($antwort | ForEach-Object { '{0}:{1}' -f $_.NameTarget, $_.Port }) -join ', '
        Write-Host ('[ OK ] {0,-40} {1}' -f $srv, $ziele) -ForegroundColor Green
    }
    catch {
        Write-Host ('[FEHL] {0,-40} kein Eintrag gefunden' -f $srv) -ForegroundColor Red
    }
}

# --- Veraltete Eintraege -----------------------------------------------------
if ($VeralteteFinden) {
    Write-Host "`n=== Moeglicherweise veraltete Eintraege ===" -ForegroundColor Cyan

    $stichtag = (Get-Date).AddDays(-$AlterTage)

    Write-Host "--- Dynamische A-Eintraege ohne Aktualisierung seit $AlterTage Tagen ---" -ForegroundColor White
    $alt = $aufbereitet | Where-Object { $_.Typ -eq 'A' -and $_.Zeitstempel -and $_.Zeitstempel -lt $stichtag }
    if ($alt) { $alt | Sort-Object Zeitstempel | Format-Table Name, Wert, Zeitstempel -AutoSize }
    else { Write-Host 'Keine' -ForegroundColor Green }

    Write-Host '--- A-Eintraege, deren Ziel nicht antwortet ---' -ForegroundColor White
    $tot = foreach ($eintrag in $aufbereitet | Where-Object Typ -eq 'A') {
        if ($eintrag.Name -eq '@' -or -not $eintrag.Wert) { continue }

        if (-not (Test-Connection -ComputerName $eintrag.Wert -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
            [PSCustomObject]@{ Name = $eintrag.Name; IPAdresse = $eintrag.Wert; Zeitstempel = $eintrag.Zeitstempel }
        }
    }

    if ($tot) {
        $tot | Format-Table -AutoSize
        Write-Warning "$($tot.Count) A-Eintraege zeigen auf nicht antwortende Adressen. Vor dem Loeschen pruefen - ICMP kann auch geblockt sein."
    }
    else {
        Write-Host 'Keine' -ForegroundColor Green
    }
}

if ($CsvPfad) {
    $aufbereitet | Export-Csv -Path $CsvPfad -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Host "`nCSV-Export: $CsvPfad" -ForegroundColor Green
}
