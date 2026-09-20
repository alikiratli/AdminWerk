<#
.SYNOPSIS
    Zeigt die Prozesse mit der hoechsten CPU- und Arbeitsspeicherlast.
.DESCRIPTION
    Erste Anlaufstelle bei "der Server ist langsam". Die CPU-Auslastung wird ueber
    zwei Messpunkte berechnet, damit nicht nur die kumulierte Rechenzeit seit dem
    Prozessstart angezeigt wird.
.EXAMPLE
    .\top-prozesse.ps1 -Anzahl 10 -MessIntervallSekunden 3
#>
[CmdletBinding()]
param(
    [int]$Anzahl = 10,
    [int]$MessIntervallSekunden = 3
)

$kerne = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors

Write-Host "Messe CPU-Auslastung ueber $MessIntervallSekunden Sekunden ..." -ForegroundColor White

$start = Get-Process | Select-Object Id, ProcessName, @{ Name = 'CPU'; Expression = { $_.CPU } }
Start-Sleep -Seconds $MessIntervallSekunden
$ende = Get-Process

$messung = foreach ($prozess in $ende) {
    $vorher = $start | Where-Object Id -eq $prozess.Id | Select-Object -First 1
    if (-not $vorher) { continue }

    $cpuDelta = $prozess.CPU - $vorher.CPU
    $auslastung = if ($cpuDelta -gt 0) {
        [math]::Round(($cpuDelta / $MessIntervallSekunden / $kerne) * 100, 1)
    }
    else { 0 }

    # StartTime wirft bei Systemprozessen einen Zugriffsfehler - bewusst abfangen.
    $startzeit = $null
    try { $startzeit = $prozess.StartTime } catch { }

    [PSCustomObject]@{
        Prozess           = $prozess.ProcessName
        PID               = $prozess.Id
        CpuProzent        = $auslastung
        ArbeitsspeicherMB = [math]::Round($prozess.WorkingSet64 / 1MB, 1)
        Handles           = $prozess.HandleCount
        Startzeit         = $startzeit
    }
}

Write-Host "`n=== Top $Anzahl nach CPU ===" -ForegroundColor Cyan
$messung | Sort-Object CpuProzent -Descending | Select-Object -First $Anzahl | Format-Table -AutoSize

Write-Host "`n=== Top $Anzahl nach Arbeitsspeicher ===" -ForegroundColor Cyan
$messung | Sort-Object ArbeitsspeicherMB -Descending | Select-Object -First $Anzahl | Format-Table -AutoSize
