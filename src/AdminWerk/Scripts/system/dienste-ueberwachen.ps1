<#
.SYNOPSIS
    Ueberwacht kritische Windows-Dienste und startet gestoppte Dienste neu.
.DESCRIPTION
    Prueft eine Liste von Diensten. Laeuft ein Dienst nicht, wird er gestartet
    und das Ergebnis protokolliert. Mit -NurPruefen wird nichts veraendert.
.PARAMETER Dienste
    Namen der zu pruefenden Dienste (Dienstname, nicht Anzeigename).
.EXAMPLE
    .\dienste-ueberwachen.ps1 -Dienste Spooler, BITS, wuauserv
.EXAMPLE
    .\dienste-ueberwachen.ps1 -NurPruefen
#>
[CmdletBinding()]
param(
    [string[]]$Dienste = @('Spooler', 'BITS', 'wuauserv', 'WinDefend', 'EventLog'),

    # Nur berichten, keine Dienste starten.
    [switch]$NurPruefen,

    [string]$LogDatei = "$env:ProgramData\AdminWerk\dienste.log"
)

function Write-Protokoll {
    param([string]$Text)

    $verzeichnis = Split-Path -Path $LogDatei -Parent
    if (-not (Test-Path -Path $verzeichnis)) {
        New-Item -Path $verzeichnis -ItemType Directory -Force | Out-Null
    }

    Add-Content -Path $LogDatei -Encoding UTF8 -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Text)
}

$bericht = foreach ($name in $Dienste) {
    $dienst = Get-Service -Name $name -ErrorAction SilentlyContinue

    if (-not $dienst) {
        Write-Protokoll "[FEHLT] Dienst '$name' existiert auf $env:COMPUTERNAME nicht."
        [PSCustomObject]@{ Dienst = $name; Anzeigename = '-'; Status = 'NICHT VORHANDEN'; Aktion = 'keine' }
        continue
    }

    if ($dienst.Status -eq 'Running') {
        [PSCustomObject]@{ Dienst = $dienst.Name; Anzeigename = $dienst.DisplayName; Status = 'Running'; Aktion = 'keine' }
        continue
    }

    if ($NurPruefen) {
        [PSCustomObject]@{ Dienst = $dienst.Name; Anzeigename = $dienst.DisplayName; Status = $dienst.Status; Aktion = 'nur gemeldet' }
        continue
    }

    try {
        Start-Service -Name $dienst.Name -ErrorAction Stop
        $dienst.Refresh()
        Write-Protokoll "[START] Dienst '$($dienst.Name)' wurde neu gestartet."
        [PSCustomObject]@{ Dienst = $dienst.Name; Anzeigename = $dienst.DisplayName; Status = $dienst.Status; Aktion = 'gestartet' }
    }
    catch {
        Write-Protokoll "[FEHLER] Dienst '$($dienst.Name)' konnte nicht gestartet werden: $($_.Exception.Message)"
        [PSCustomObject]@{ Dienst = $dienst.Name; Anzeigename = $dienst.DisplayName; Status = 'Stopped'; Aktion = "Fehler: $($_.Exception.Message)" }
    }
}

$bericht | Format-Table -AutoSize
