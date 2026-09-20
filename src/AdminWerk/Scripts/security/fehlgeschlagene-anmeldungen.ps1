<#
.SYNOPSIS
    Wertet fehlgeschlagene Anmeldeversuche aus dem Sicherheitsprotokoll aus.
.DESCRIPTION
    Liest die Ereignis-ID 4625, gruppiert die Versuche nach Konto, Quellrechner und
    Grund und erkennt so Kennwortangriffe (Brute Force, Password Spraying).
.NOTES
    Benoetigt Administratorrechte fuer das Sicherheitsprotokoll.
.EXAMPLE
    .\fehlgeschlagene-anmeldungen.ps1 -Stunden 24
#>
[CmdletBinding()]
param(
    [int]$Stunden = 24,
    [int]$SchwelleProKonto = 5
)

try {
    $ereignisse = @(Get-WinEvent -FilterHashtable @{
        LogName   = 'Security'
        Id        = 4625
        StartTime = (Get-Date).AddHours(-$Stunden)
    } -ErrorAction Stop)
}
catch {
    Write-Host "Keine fehlgeschlagenen Anmeldungen in den letzten $Stunden Stunden." -ForegroundColor Green
    return
}

$fehlerGruende = @{
    '0xC000006A' = 'Falsches Kennwort'
    '0xC0000064' = 'Benutzer existiert nicht'
    '0xC0000072' = 'Konto deaktiviert'
    '0xC0000234' = 'Konto gesperrt'
    '0xC0000070' = 'Anmeldung von dieser Arbeitsstation nicht erlaubt'
    '0xC000006F' = 'Anmeldung ausserhalb der erlaubten Zeit'
    '0xC0000193' = 'Konto abgelaufen'
    '0xC0000071' = 'Kennwort abgelaufen'
}

$anmeldetypen = @{
    '2'  = 'Interaktiv (Konsole)'
    '3'  = 'Netzwerk (SMB)'
    '4'  = 'Stapelverarbeitung'
    '5'  = 'Dienst'
    '7'  = 'Entsperren'
    '8'  = 'Netzwerk (Klartext)'
    '10' = 'Remotedesktop'
    '11' = 'Zwischengespeichert'
}

$details = foreach ($ereignis in $ereignisse) {
    $xml = [xml]$ereignis.ToXml()
    $daten = @{}
    foreach ($feld in $xml.Event.EventData.Data) { $daten[$feld.Name] = $feld.'#text' }

    $status = $daten['SubStatus']
    if ($status -eq '0x0') { $status = $daten['Status'] }

    [PSCustomObject]@{
        Zeitpunkt  = $ereignis.TimeCreated
        Konto      = $daten['TargetUserName']
        Domaene    = $daten['TargetDomainName']
        Quelle     = if ($daten['WorkstationName']) { $daten['WorkstationName'] } else { $daten['IpAddress'] }
        IpAdresse  = $daten['IpAddress']
        Anmeldetyp = if ($anmeldetypen[$daten['LogonType']]) { $anmeldetypen[$daten['LogonType']] } else { $daten['LogonType'] }
        Grund      = if ($fehlerGruende[$status]) { $fehlerGruende[$status] } else { $status }
        Prozess    = $daten['ProcessName']
    }
}

Write-Host "`n=== Fehlgeschlagene Anmeldungen (letzte $Stunden h) ===" -ForegroundColor Cyan
Write-Host "Gesamtzahl: $($details.Count)`n" -ForegroundColor White

Write-Host '--- Nach Konto ---' -ForegroundColor White
$proKonto = $details | Group-Object Konto | Sort-Object Count -Descending
$proKonto | Select-Object @{ Name = 'Konto'; Expression = { $_.Name } },
    @{ Name = 'Versuche'; Expression = { $_.Count } },
    @{ Name = 'Quellen'; Expression = { ($_.Group.Quelle | Select-Object -Unique) -join ', ' } } |
    Format-Table -AutoSize

Write-Host '--- Nach Quelle ---' -ForegroundColor White
$details | Group-Object Quelle | Sort-Object Count -Descending |
    Select-Object @{ Name = 'Quelle'; Expression = { $_.Name } },
        @{ Name = 'Versuche'; Expression = { $_.Count } },
        @{ Name = 'Konten'; Expression = { ($_.Group.Konto | Select-Object -Unique) -join ', ' } } |
    Format-Table -AutoSize

Write-Host '--- Nach Ursache ---' -ForegroundColor White
$details | Group-Object Grund | Sort-Object Count -Descending |
    Select-Object @{ Name = 'Ursache'; Expression = { $_.Name } }, Count | Format-Table -AutoSize

Write-Host '--- Letzte 15 Ereignisse ---' -ForegroundColor White
$details | Sort-Object Zeitpunkt -Descending | Select-Object -First 15 Zeitpunkt, Konto, Quelle, Anmeldetyp, Grund |
    Format-Table -AutoSize

# Auffaellige Muster hervorheben
foreach ($gruppe in $proKonto | Where-Object Count -ge $SchwelleProKonto) {
    Write-Warning "Konto '$($gruppe.Name)': $($gruppe.Count) Fehlversuche - moeglicher Kennwortangriff."
}

$sprayVerdacht = $details | Group-Object Quelle | Where-Object { ($_.Group.Konto | Select-Object -Unique).Count -ge 5 }
foreach ($gruppe in $sprayVerdacht) {
    Write-Warning "Quelle '$($gruppe.Name)' hat $(($gruppe.Group.Konto | Select-Object -Unique).Count) verschiedene Konten probiert - Verdacht auf Password Spraying."
}
