<#
.SYNOPSIS
    Zeigt die letzten erfolgreichen Anmeldungen am System.
.DESCRIPTION
    Wertet die Ereignis-ID 4624 aus und blendet die zahlreichen System- und
    Dienstanmeldungen aus, sodass nur die tatsaechlichen Benutzeranmeldungen
    uebrig bleiben.
.NOTES
    Benoetigt Administratorrechte fuer das Sicherheitsprotokoll.
.EXAMPLE
    .\letzte-anmeldungen.ps1 -Stunden 48
#>
[CmdletBinding()]
param(
    [int]$Stunden = 24,
    [int]$Anzahl = 30
)

$anmeldetypen = @{
    '2'  = 'Interaktiv'
    '3'  = 'Netzwerk'
    '4'  = 'Stapelverarbeitung'
    '5'  = 'Dienst'
    '7'  = 'Entsperren'
    '10' = 'Remotedesktop'
    '11' = 'Zwischengespeichert'
}

try {
    $ereignisse = @(Get-WinEvent -FilterHashtable @{
        LogName   = 'Security'
        Id        = 4624
        StartTime = (Get-Date).AddHours(-$Stunden)
    } -ErrorAction Stop)
}
catch {
    Write-Host "Keine Anmeldeereignisse in den letzten $Stunden Stunden." -ForegroundColor Yellow
    return
}

$anmeldungen = foreach ($ereignis in $ereignisse) {
    $xml = [xml]$ereignis.ToXml()
    $daten = @{}
    foreach ($feld in $xml.Event.EventData.Data) { $daten[$feld.Name] = $feld.'#text' }

    # Maschinenkonten und die lokalen Systemkonten ausblenden
    if ($daten['TargetUserName'] -match '\$$') { continue }
    if ($daten['TargetUserName'] -in 'SYSTEM', 'LOCAL SERVICE', 'NETWORK SERVICE', 'ANONYMOUS LOGON', 'DWM-1', 'DWM-2', 'UMFD-0', 'UMFD-1') { continue }

    [PSCustomObject]@{
        Zeitpunkt  = $ereignis.TimeCreated
        Konto      = '{0}\{1}' -f $daten['TargetDomainName'], $daten['TargetUserName']
        Anmeldetyp = if ($anmeldetypen[$daten['LogonType']]) { $anmeldetypen[$daten['LogonType']] } else { $daten['LogonType'] }
        Quelle     = if ($daten['WorkstationName']) { $daten['WorkstationName'] } else { '-' }
        IpAdresse  = if ($daten['IpAddress'] -and $daten['IpAddress'] -ne '-') { $daten['IpAddress'] } else { 'lokal' }
        Prozess    = $daten['ProcessName']
    }
}

Write-Host "`n=== Erfolgreiche Anmeldungen (letzte $Stunden h) ===`n" -ForegroundColor Cyan

$anmeldungen | Sort-Object Zeitpunkt -Descending | Select-Object -First $Anzahl |
    Format-Table Zeitpunkt, Konto, Anmeldetyp, Quelle, IpAdresse -AutoSize

Write-Host '--- Zusammenfassung nach Konto ---' -ForegroundColor White
$anmeldungen | Group-Object Konto | Sort-Object Count -Descending |
    Select-Object @{ Name = 'Konto'; Expression = { $_.Name } },
        @{ Name = 'Anmeldungen'; Expression = { $_.Count } },
        @{ Name = 'Zuletzt'; Expression = { ($_.Group | Sort-Object Zeitpunkt -Descending | Select-Object -First 1).Zeitpunkt } } |
    Format-Table -AutoSize

$remote = $anmeldungen | Where-Object Anmeldetyp -eq 'Remotedesktop'
if ($remote) {
    Write-Host '--- Remotedesktop-Anmeldungen ---' -ForegroundColor Yellow
    $remote | Sort-Object Zeitpunkt -Descending | Format-Table Zeitpunkt, Konto, IpAdresse -AutoSize
}
