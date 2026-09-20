<#
.SYNOPSIS
    Prueft die geplanten Aufgaben (Scheduled Tasks) auf Fehler und Auffaelligkeiten.
.DESCRIPTION
    Listet deaktivierte Aufgaben, Aufgaben mit fehlgeschlagenem letzten Lauf sowie
    Aufgaben, die unter einem hoch privilegierten Konto laufen. Microsoft-eigene
    Aufgaben werden standardmaessig ausgeblendet.
.EXAMPLE
    .\geplante-aufgaben-audit.ps1 -MitMicrosoftAufgaben
#>
[CmdletBinding()]
param(
    # Auch die mitgelieferten Aufgaben unter \Microsoft\ einbeziehen.
    [switch]$MitMicrosoftAufgaben
)

$aufgaben = Get-ScheduledTask
if (-not $MitMicrosoftAufgaben) {
    $aufgaben = $aufgaben | Where-Object { $_.TaskPath -notlike '\Microsoft\*' }
}

$bericht = foreach ($aufgabe in $aufgaben) {
    $info = $aufgabe | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue

    [PSCustomObject]@{
        Name           = $aufgabe.TaskName
        Pfad           = $aufgabe.TaskPath
        Status         = $aufgabe.State
        Benutzerkonto  = $aufgabe.Principal.UserId
        Rechte         = $aufgabe.Principal.RunLevel
        LetzterLauf    = $info.LastRunTime
        LetztesErgebnis = $info.LastTaskResult
        NaechsterLauf  = $info.NextRunTime
        Bewertung      = if ($info.LastTaskResult -in 0, 267011, $null) { 'OK' } else { 'FEHLER' }
    }
}

Write-Host "`n=== Geplante Aufgaben mit Fehlern ===" -ForegroundColor Cyan
$fehler = $bericht | Where-Object Bewertung -eq 'FEHLER'
if ($fehler) { $fehler | Format-Table -AutoSize } else { Write-Host 'Keine' -ForegroundColor Green }

Write-Host "`n=== Deaktivierte Aufgaben ===" -ForegroundColor Cyan
$deaktiviert = $bericht | Where-Object Status -eq 'Disabled'
if ($deaktiviert) { $deaktiviert | Format-Table Name, Pfad, Benutzerkonto -AutoSize } else { Write-Host 'Keine' -ForegroundColor Green }

Write-Host "`n=== Aufgaben mit hohen Rechten (SYSTEM / Highest) ===" -ForegroundColor Cyan
$privilegiert = $bericht | Where-Object { $_.Rechte -eq 'Highest' -or $_.Benutzerkonto -match 'SYSTEM' }
if ($privilegiert) { $privilegiert | Format-Table Name, Pfad, Benutzerkonto, Rechte -AutoSize } else { Write-Host 'Keine' -ForegroundColor Green }

Write-Host "`nGeprueft: $($bericht.Count) Aufgaben" -ForegroundColor White
