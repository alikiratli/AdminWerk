<#
.SYNOPSIS
    Verfolgt den Netzwerkpfad zu einem Ziel und misst die Latenz je Abschnitt.
.DESCRIPTION
    Ergaenzt tracert um eine Auswertung: Der Sprung mit dem groessten Latenzzuwachs
    wird hervorgehoben - dort liegt in der Regel der Engpass.
.EXAMPLE
    .\routenverfolgung.ps1 -Ziel www.microsoft.com
#>
[CmdletBinding()]
param(
    [string]$Ziel = 'www.microsoft.com',
    [int]$MaximaleSpruenge = 20
)

Write-Host "Verfolge Route zu $Ziel ...`n" -ForegroundColor Cyan

$route = Test-NetConnection -ComputerName $Ziel -TraceRoute -Hops $MaximaleSpruenge -WarningAction SilentlyContinue

if (-not $route.TraceRoute) {
    Write-Warning "Keine Route zu $Ziel ermittelbar."
    return
}

$vorherigeLatenz = 0
$sprung = 0

$abschnitte = foreach ($hop in $route.TraceRoute) {
    $sprung++

    $antwort = Test-Connection -ComputerName $hop -Count 1 -ErrorAction SilentlyContinue
    $latenz = if ($antwort) { $antwort.ResponseTime } else { $null }

    $zuwachs = if ($null -ne $latenz -and $vorherigeLatenz -gt 0) { $latenz - $vorherigeLatenz } else { 0 }
    if ($null -ne $latenz) { $vorherigeLatenz = $latenz }

    [PSCustomObject]@{
        Sprung    = $sprung
        Adresse   = $hop
        LatenzMs  = if ($null -ne $latenz) { $latenz } else { 'keine Antwort' }
        ZuwachsMs = $zuwachs
    }
}

$abschnitte | Format-Table -AutoSize

$engpass = $abschnitte | Sort-Object ZuwachsMs -Descending | Select-Object -First 1
if ($engpass.ZuwachsMs -gt 30) {
    Write-Warning "Groesster Latenzzuwachs bei Sprung $($engpass.Sprung) ($($engpass.Adresse)): +$($engpass.ZuwachsMs) ms"
}

Write-Host "Ziel erreichbar: $($route.PingSucceeded)" -ForegroundColor White
