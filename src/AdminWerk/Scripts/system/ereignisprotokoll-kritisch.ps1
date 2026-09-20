<#
.SYNOPSIS
    Sammelt kritische Fehler und Warnungen aus den Windows-Ereignisprotokollen.
.DESCRIPTION
    Liest System- und Anwendungsprotokoll der letzten Stunden, gruppiert die
    Meldungen nach Quelle und Ereignis-ID und zeigt die haeufigsten Treffer zuerst.
.EXAMPLE
    .\ereignisprotokoll-kritisch.ps1 -Stunden 24 -Anzahl 20
#>
[CmdletBinding()]
param(
    [int]$Stunden = 24,
    [string[]]$Protokolle = @('System', 'Application'),
    [int]$Anzahl = 15
)

$seit = (Get-Date).AddHours(-$Stunden)

# Level 1 = Kritisch, 2 = Fehler, 3 = Warnung
$ereignisse = foreach ($protokoll in $Protokolle) {
    try {
        Get-WinEvent -FilterHashtable @{
            LogName   = $protokoll
            Level     = 1, 2
            StartTime = $seit
        } -ErrorAction Stop
    }
    catch [Exception] {
        if ($_.Exception.Message -notmatch 'No events were found') {
            Write-Warning "Protokoll '$protokoll' konnte nicht gelesen werden: $($_.Exception.Message)"
        }
    }
}

if (-not $ereignisse) {
    Write-Host "Keine kritischen Ereignisse in den letzten $Stunden Stunden." -ForegroundColor Green
    return
}

Write-Host "`n=== Haeufigste kritische Ereignisse (letzte $Stunden h) ===`n" -ForegroundColor Cyan

$ereignisse |
    Group-Object -Property LogName, Id, ProviderName |
    Sort-Object Count -Descending |
    Select-Object -First $Anzahl |
    ForEach-Object {
        $erstes = $_.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1

        [PSCustomObject]@{
            Protokoll  = $erstes.LogName
            EreignisID = $erstes.Id
            Quelle     = $erstes.ProviderName
            Anzahl     = $_.Count
            Zuletzt    = $erstes.TimeCreated
            Meldung    = ($erstes.Message -split "`r?`n")[0]
        }
    } |
    Format-Table -AutoSize -Wrap

Write-Host "`nGesamtzahl kritischer Ereignisse: $($ereignisse.Count)" -ForegroundColor Yellow
