<#
.SYNOPSIS
    Zentraler Dienststatusbericht ueber mehrere Computer.
.DESCRIPTION
    Fragt auf allen angegebenen Computern dieselbe Dienstliste ab und stellt das
    Ergebnis als Matrix dar: eine Zeile je Computer, eine Spalte je Dienst.
    So faellt sofort auf, wo ein Dienst fehlt, steht oder auf "Disabled" steht.
    Die Computerliste kann direkt, aus einer Textdatei oder aus dem Active
    Directory kommen.
.PARAMETER Computername
    Liste der abzufragenden Computer. Standard: der lokale Computer.
.PARAMETER ComputerlisteDatei
    Textdatei mit einem Computernamen je Zeile.
.PARAMETER AusActiveDirectory
    Holt alle aktivierten Serverkonten aus dem Active Directory.
.EXAMPLE
    .\dienste-mehrere-computer.ps1 -Computername SRV01, SRV02 -Dienste Spooler, wuauserv
.EXAMPLE
    .\dienste-mehrere-computer.ps1 -AusActiveDirectory -Berichtsdatei C:\Berichte\dienste.html
#>
[CmdletBinding()]
param(
    [string[]]$Computername = $env:COMPUTERNAME,

    [string]$ComputerlisteDatei,

    [switch]$AusActiveDirectory,

    [string[]]$Dienste = @('Spooler', 'BITS', 'wuauserv', 'WinDefend', 'EventLog', 'LanmanServer'),

    [string]$Berichtsdatei,

    [string]$CsvPfad,

    # Erwarteter Zustand. Alles andere wird als Abweichung gemeldet.
    [ValidateSet('Running', 'Stopped')]
    [string]$Sollzustand = 'Running'
)

# --- Computerliste zusammenstellen -------------------------------------------
if ($ComputerlisteDatei) {
    if (-not (Test-Path $ComputerlisteDatei)) {
        throw "Computerliste nicht gefunden: $ComputerlisteDatei"
    }

    $Computername = Get-Content -Path $ComputerlisteDatei |
        Where-Object { $_.Trim() -and -not $_.StartsWith('#') } |
        ForEach-Object { $_.Trim() }
}

if ($AusActiveDirectory) {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw 'Das Modul "ActiveDirectory" ist nicht verfuegbar. Bitte RSAT installieren.'
    }

    Import-Module ActiveDirectory -ErrorAction Stop
    $Computername = (Get-ADComputer -Filter { Enabled -eq $true -and OperatingSystem -like '*Server*' }).Name
}

Write-Host "Frage $($Computername.Count) Computer ab ..." -ForegroundColor Cyan

# --- Abfrage -----------------------------------------------------------------
$roh = foreach ($computer in $Computername) {
    $erreichbar = Test-Connection -ComputerName $computer -Count 1 -Quiet -ErrorAction SilentlyContinue

    if (-not $erreichbar) {
        Write-Warning "$computer ist nicht erreichbar."
        [PSCustomObject]@{ Computer = $computer; Dienst = '-'; Anzeigename = '-'; Status = 'NICHT ERREICHBAR'; Starttyp = '-' }
        continue
    }

    try {
        $gefunden = Get-CimInstance -ClassName Win32_Service -ComputerName $computer -ErrorAction Stop |
            Where-Object { $Dienste -contains $_.Name }

        foreach ($name in $Dienste) {
            $dienst = $gefunden | Where-Object Name -eq $name | Select-Object -First 1

            if ($dienst) {
                [PSCustomObject]@{
                    Computer    = $computer
                    Dienst      = $dienst.Name
                    Anzeigename = $dienst.DisplayName
                    Status      = $dienst.State
                    Starttyp    = $dienst.StartMode
                }
            }
            else {
                [PSCustomObject]@{
                    Computer = $computer; Dienst = $name; Anzeigename = '-'
                    Status = 'NICHT VORHANDEN'; Starttyp = '-'
                }
            }
        }
    }
    catch {
        Write-Warning "$computer : $($_.Exception.Message)"
        [PSCustomObject]@{ Computer = $computer; Dienst = '-'; Anzeigename = '-'; Status = 'FEHLER'; Starttyp = '-' }
    }
}

# --- Matrixdarstellung: eine Zeile je Computer -------------------------------
$matrix = foreach ($gruppe in $roh | Group-Object Computer) {
    $zeile = [ordered]@{ Computer = $gruppe.Name }

    foreach ($name in $Dienste) {
        $eintrag = $gruppe.Group | Where-Object Dienst -eq $name | Select-Object -First 1
        $zeile[$name] = if ($eintrag) { $eintrag.Status } else { '-' }
    }

    [PSCustomObject]$zeile
}

Write-Host "`n=== Dienststatus ===" -ForegroundColor Cyan
$matrix | Format-Table -AutoSize

# --- Abweichungen ------------------------------------------------------------
$abweichungen = $roh | Where-Object { $_.Status -ne $Sollzustand -and $_.Dienst -ne '-' }

Write-Host "=== Abweichungen vom Sollzustand '$Sollzustand' ===" -ForegroundColor Cyan
if ($abweichungen) {
    $abweichungen | Sort-Object Computer, Dienst | Format-Table Computer, Dienst, Status, Starttyp -AutoSize
    Write-Warning "$($abweichungen.Count) Abweichungen auf $(($abweichungen.Computer | Select-Object -Unique).Count) Computern."
}
else {
    Write-Host 'Keine Abweichungen.' -ForegroundColor Green
}

# --- Export ------------------------------------------------------------------
if ($CsvPfad) {
    $roh | Export-Csv -Path $CsvPfad -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Host "CSV-Export: $CsvPfad" -ForegroundColor Green
}

if ($Berichtsdatei) {
    $stil = @'
<style>
  body  { font-family: Segoe UI, sans-serif; background: #f6f8fa; color: #24292f; margin: 32px; }
  h1    { font-size: 22px; margin-bottom: 4px; }
  p.meta{ color: #57606a; margin-top: 0; font-size: 13px; }
  table { border-collapse: collapse; width: 100%; background: #fff; }
  th    { background: #24292f; color: #fff; text-align: left; padding: 8px 10px; font-size: 13px; }
  td    { border-bottom: 1px solid #d0d7de; padding: 7px 10px; font-size: 13px; }
</style>
'@

    $kopf = "<h1>Dienststatusbericht</h1><p class='meta'>Erstellt am $(Get-Date -Format 'dd.MM.yyyy HH:mm') &middot; $($Computername.Count) Computer &middot; Sollzustand: $Sollzustand</p>"

    $html = $matrix | ConvertTo-Html -Title 'AdminWerk Dienstbericht' -Head $stil -PreContent $kopf | Out-String
    $html = $html -replace '<td>Running</td>', '<td style="color:#1a7f37;font-weight:600;">Running</td>'
    $html = $html -replace '<td>Stopped</td>', '<td style="color:#b3261e;font-weight:600;">Stopped</td>'
    $html = $html -replace '<td>NICHT ERREICHBAR</td>', '<td style="color:#b3261e;font-weight:600;">NICHT ERREICHBAR</td>'

    $verzeichnis = Split-Path -Path $Berichtsdatei -Parent
    if ($verzeichnis -and -not (Test-Path $verzeichnis)) {
        New-Item -Path $verzeichnis -ItemType Directory -Force | Out-Null
    }

    $html | Set-Content -Path $Berichtsdatei -Encoding UTF8
    Write-Host "HTML-Bericht: $Berichtsdatei" -ForegroundColor Green
}
