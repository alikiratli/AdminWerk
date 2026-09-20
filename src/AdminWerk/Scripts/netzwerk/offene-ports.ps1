<#
.SYNOPSIS
    Listet alle lauschenden TCP-Ports samt zugehoerigem Prozess.
.DESCRIPTION
    Verbindet Get-NetTCPConnection mit den Prozessdaten, sodass sofort erkennbar ist,
    welches Programm einen Port geoeffnet hat. Auch ein Sicherheits-Basischeck.
.EXAMPLE
    .\offene-ports.ps1 -NurExtern
#>
[CmdletBinding()]
param(
    # Nur Ports anzeigen, die nicht ausschliesslich an localhost gebunden sind.
    [switch]$NurExtern
)

$verbindungen = Get-NetTCPConnection -State Listen

if ($NurExtern) {
    $verbindungen = $verbindungen | Where-Object { $_.LocalAddress -notin '127.0.0.1', '::1' }
}

$bericht = foreach ($verbindung in $verbindungen) {
    $prozess = Get-Process -Id $verbindung.OwningProcess -ErrorAction SilentlyContinue

    [PSCustomObject]@{
        LokaleAdresse = $verbindung.LocalAddress
        Port          = $verbindung.LocalPort
        Prozess       = if ($prozess) { $prozess.ProcessName } else { 'unbekannt' }
        PID           = $verbindung.OwningProcess
        Pfad          = if ($prozess) { $prozess.Path } else { '-' }
    }
}

$bericht | Sort-Object Port -Unique | Format-Table -AutoSize

Write-Host "`nLauschende Ports: $(($bericht.Port | Select-Object -Unique).Count)" -ForegroundColor Cyan
