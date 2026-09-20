<#
.SYNOPSIS
    Wertet den Verlauf der Remotedesktop-Sitzungen aus.
.DESCRIPTION
    Fuehrt die verstreuten RDP-Spuren zu einem Bild zusammen:
    - Erfolgreiche Verbindungen mit Quell-IP (TerminalServices-RemoteConnectionManager, ID 1149)
    - An-, Ab- und Wiederanmeldungen (LocalSessionManager, IDs 21/23/24/25)
    - Fehlgeschlagene RDP-Anmeldungen aus dem Sicherheitsprotokoll (4625, Anmeldetyp 10)
    Am Ende stehen die Auswertungen, die bei einem Verdachtsfall zaehlen:
    Verbindungen je Quell-IP, je Konto und ausserhalb der Arbeitszeit.
.NOTES
    Benoetigt Administratorrechte. Auf reinen Arbeitsplatzsystemen sind die
    TerminalServices-Protokolle unter Umstaenden leer.
.EXAMPLE
    .\rdp-sitzungsverlauf.ps1 -Tage 7
.EXAMPLE
    .\rdp-sitzungsverlauf.ps1 -Tage 30 -ArbeitszeitVon 7 -ArbeitszeitBis 19 -CsvPfad C:\Berichte\rdp.csv
#>
[CmdletBinding()]
param(
    [int]$Tage = 7,

    # Zeitfenster, ausserhalb dessen Verbindungen gesondert ausgewiesen werden.
    [int]$ArbeitszeitVon = 6,
    [int]$ArbeitszeitBis = 20,

    [string]$CsvPfad
)

$seit = (Get-Date).AddDays(-$Tage)

function Get-Ereignisse {
    param([string]$Protokoll, [int[]]$Ids)

    try {
        return @(Get-WinEvent -FilterHashtable @{
            LogName   = $Protokoll
            Id        = $Ids
            StartTime = $seit
        } -ErrorAction Stop)
    }
    catch {
        return @()
    }
}

Write-Host "`n=== RDP-Sitzungsverlauf: $env:COMPUTERNAME (letzte $Tage Tage) ===`n" -ForegroundColor Cyan

# --- Erfolgreiche Verbindungen mit Quell-IP ----------------------------------
$verbindungen = foreach ($ereignis in Get-Ereignisse -Protokoll 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational' -Ids 1149) {
    $xml = [xml]$ereignis.ToXml()
    $daten = $xml.Event.UserData.EventXML

    [PSCustomObject]@{
        Zeitpunkt = $ereignis.TimeCreated
        Ereignis  = 'Verbindung angenommen'
        Konto     = if ($daten.Param1) { '{0}\{1}' -f $daten.Param2, $daten.Param1 } else { '-' }
        QuellIP   = $daten.Param3
        SitzungsID = '-'
    }
}

# --- Sitzungsereignisse ------------------------------------------------------
$beschreibung = @{
    21 = 'Anmeldung erfolgreich'
    23 = 'Abmeldung'
    24 = 'Sitzung getrennt'
    25 = 'Sitzung wiederaufgenommen'
}

$sitzungen = foreach ($ereignis in Get-Ereignisse -Protokoll 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational' -Ids 21, 23, 24, 25) {
    $xml = [xml]$ereignis.ToXml()
    $daten = $xml.Event.UserData.EventXML

    [PSCustomObject]@{
        Zeitpunkt  = $ereignis.TimeCreated
        Ereignis   = $beschreibung[[int]$ereignis.Id]
        Konto      = $daten.User
        QuellIP    = if ($daten.Address -and $daten.Address -ne 'LOKAL') { $daten.Address } else { 'lokal' }
        SitzungsID = $daten.SessionID
    }
}

$alle = @($verbindungen) + @($sitzungen) | Sort-Object Zeitpunkt -Descending

if (-not $alle) {
    Write-Host 'Keine RDP-Ereignisse im gewaehlten Zeitraum gefunden.' -ForegroundColor Yellow
    Write-Host 'Auf Arbeitsplatzsystemen sind die TerminalServices-Protokolle oft leer.' -ForegroundColor DarkGray
}
else {
    Write-Host '--- Letzte 30 Ereignisse ---' -ForegroundColor White
    $alle | Select-Object -First 30 | Format-Table Zeitpunkt, Ereignis, Konto, QuellIP, SitzungsID -AutoSize

    # --- Verbindungen je Quell-IP -------------------------------------------
    Write-Host '--- Verbindungen je Quelladresse ---' -ForegroundColor White
    $alle | Where-Object { $_.QuellIP -and $_.QuellIP -ne 'lokal' -and $_.QuellIP -ne '-' } |
        Group-Object QuellIP | Sort-Object Count -Descending |
        Select-Object @{ Name = 'QuellIP'; Expression = { $_.Name } },
            @{ Name = 'Ereignisse'; Expression = { $_.Count } },
            @{ Name = 'Konten'; Expression = { ($_.Group.Konto | Select-Object -Unique) -join ', ' } },
            @{ Name = 'Zuletzt'; Expression = { ($_.Group | Sort-Object Zeitpunkt -Descending | Select-Object -First 1).Zeitpunkt } } |
        Format-Table -AutoSize -Wrap

    # --- Verbindungen je Konto ----------------------------------------------
    Write-Host '--- Verbindungen je Konto ---' -ForegroundColor White
    $alle | Where-Object Konto -ne '-' | Group-Object Konto | Sort-Object Count -Descending |
        Select-Object @{ Name = 'Konto'; Expression = { $_.Name } },
            @{ Name = 'Ereignisse'; Expression = { $_.Count } },
            @{ Name = 'Quellen'; Expression = { ($_.Group.QuellIP | Where-Object { $_ -ne '-' } | Select-Object -Unique) -join ', ' } },
            @{ Name = 'Zuletzt'; Expression = { ($_.Group | Sort-Object Zeitpunkt -Descending | Select-Object -First 1).Zeitpunkt } } |
        Format-Table -AutoSize -Wrap

    # --- Ausserhalb der Arbeitszeit -----------------------------------------
    $ausserhalb = $alle | Where-Object {
        $_.Ereignis -eq 'Anmeldung erfolgreich' -and
        ($_.Zeitpunkt.Hour -lt $ArbeitszeitVon -or $_.Zeitpunkt.Hour -ge $ArbeitszeitBis -or
         $_.Zeitpunkt.DayOfWeek -in 'Saturday', 'Sunday')
    }

    Write-Host "--- Anmeldungen ausserhalb $ArbeitszeitVon-$ArbeitszeitBis Uhr oder am Wochenende ---" -ForegroundColor White
    if ($ausserhalb) {
        $ausserhalb | Format-Table Zeitpunkt, Konto, QuellIP -AutoSize
        Write-Host 'Nicht automatisch verdaechtig - aber einen Blick wert.' -ForegroundColor Yellow
    }
    else {
        Write-Host 'Keine' -ForegroundColor Green
    }
}

# --- Fehlgeschlagene RDP-Anmeldungen -----------------------------------------
Write-Host "`n=== Fehlgeschlagene RDP-Anmeldungen ===" -ForegroundColor Cyan

$fehlversuche = foreach ($ereignis in Get-Ereignisse -Protokoll 'Security' -Ids 4625) {
    $xml = [xml]$ereignis.ToXml()
    $daten = @{}
    foreach ($feld in $xml.Event.EventData.Data) { $daten[$feld.Name] = $feld.'#text' }

    # Anmeldetyp 10 = Remotedesktop. Typ 3 mit IP zaehlt bei NLA ebenfalls dazu.
    $istRdp = ($daten['LogonType'] -eq '10') -or
              ($daten['LogonType'] -eq '3' -and $daten['IpAddress'] -and $daten['IpAddress'] -ne '-')
    if (-not $istRdp) { continue }

    [PSCustomObject]@{
        Zeitpunkt = $ereignis.TimeCreated
        Konto     = $daten['TargetUserName']
        Domaene   = $daten['TargetDomainName']
        QuellIP   = $daten['IpAddress']
        Anmeldetyp = $daten['LogonType']
    }
}

if ($fehlversuche) {
    Write-Host "Fehlversuche gesamt: $(@($fehlversuche).Count)`n" -ForegroundColor White

    Write-Host '--- Je Quelladresse ---' -ForegroundColor White
    $fehlversuche | Group-Object QuellIP | Sort-Object Count -Descending |
        Select-Object @{ Name = 'QuellIP'; Expression = { $_.Name } },
            @{ Name = 'Versuche'; Expression = { $_.Count } },
            @{ Name = 'Konten'; Expression = { ($_.Group.Konto | Select-Object -Unique) -join ', ' } } |
        Format-Table -AutoSize -Wrap

    Write-Host '--- Letzte 15 Fehlversuche ---' -ForegroundColor White
    $fehlversuche | Sort-Object Zeitpunkt -Descending | Select-Object -First 15 |
        Format-Table Zeitpunkt, Konto, QuellIP, Anmeldetyp -AutoSize

    # Eine Quelle, die viele verschiedene Konten probiert, ist das klassische Angriffsmuster.
    foreach ($gruppe in $fehlversuche | Group-Object QuellIP) {
        $kontenanzahl = ($gruppe.Group.Konto | Select-Object -Unique).Count

        if ($gruppe.Count -ge 10) {
            Write-Warning "Quelle $($gruppe.Name): $($gruppe.Count) Fehlversuche - moeglicher Kennwortangriff ueber RDP."
        }
        if ($kontenanzahl -ge 5) {
            Write-Warning "Quelle $($gruppe.Name) hat $kontenanzahl verschiedene Konten probiert - Verdacht auf Password Spraying."
        }
    }

    Write-Host "`nGegenmassnahmen: RDP nur ueber VPN oder Gateway veroeffentlichen," -ForegroundColor Yellow
    Write-Host 'NLA erzwingen und die Kontosperrungsrichtlinie pruefen.' -ForegroundColor Yellow
}
else {
    Write-Host 'Keine fehlgeschlagenen RDP-Anmeldungen gefunden.' -ForegroundColor Green
}

if ($CsvPfad) {
    @($alle) + @($fehlversuche | Select-Object Zeitpunkt,
        @{ Name = 'Ereignis'; Expression = { 'Anmeldung fehlgeschlagen' } }, Konto, QuellIP,
        @{ Name = 'SitzungsID'; Expression = { '-' } }) |
        Sort-Object Zeitpunkt -Descending |
        Export-Csv -Path $CsvPfad -NoTypeInformation -Encoding UTF8 -Delimiter ';'

    Write-Host "`nCSV-Export: $CsvPfad" -ForegroundColor Green
}
