<#
.SYNOPSIS
    Patch-Compliance-Bericht ueber mehrere Computer.
.DESCRIPTION
    Ermittelt je Computer den Patchstand: letztes installiertes Update, Alter in
    Tagen, Anzahl ausstehender Updates, davon sicherheitsrelevant, sowie einen
    ausstehenden Neustart. Daraus wird je Computer eine Einstufung gebildet
    (KONFORM / WARNUNG / NICHT KONFORM) und am Ende eine Gesamtquote.
    Die Abfrage laeuft ueber Remoting (Invoke-Command), da die
    Windows-Update-Schnittstelle nur lokal auf dem Zielsystem antwortet.
.PARAMETER MaximalesUpdateAlterTage
    Ab wann der Patchstand als veraltet gilt. Standard: 45 Tage.
.EXAMPLE
    .\patch-compliance-bericht.ps1 -Computername SRV01, SRV02
.EXAMPLE
    .\patch-compliance-bericht.ps1 -AusActiveDirectory -Berichtsdatei C:\Berichte\patch.html
#>
[CmdletBinding()]
param(
    [string[]]$Computername = $env:COMPUTERNAME,

    [string]$ComputerlisteDatei,

    [switch]$AusActiveDirectory,

    [int]$MaximalesUpdateAlterTage = 45,

    [string]$Berichtsdatei,

    [string]$CsvPfad
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
    $Computername = (Get-ADComputer -Filter { Enabled -eq $true }).Name
}

# --- Abfrageblock, der auf jedem Zielsystem ausgefuehrt wird ------------------
$abfrage = {
    $letztes = Get-HotFix -ErrorAction SilentlyContinue |
        Sort-Object InstalledOn -Descending | Select-Object -First 1

    $ausstehend = $null
    $sicherheit = $null

    try {
        $sitzung = New-Object -ComObject Microsoft.Update.Session
        $treffer = $sitzung.CreateUpdateSearcher().Search('IsInstalled=0 and IsHidden=0')
        $ausstehend = $treffer.Updates.Count

        $sicherheit = 0
        foreach ($update in $treffer.Updates) {
            foreach ($kategorie in $update.Categories) {
                if ($kategorie.Name -match 'Sicherheit|Security|Critical') { $sicherheit++; break }
            }
        }
    }
    catch {
        # Windows-Update-Schnittstelle nicht erreichbar - Felder bleiben leer.
    }

    $neustart = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
                (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')

    $os = Get-CimInstance Win32_OperatingSystem

    [PSCustomObject]@{
        Betriebssystem   = $os.Caption
        OsVersion        = $os.Version
        LetztesUpdate    = $letztes.HotFixID
        Installiert      = $letztes.InstalledOn
        Ausstehend       = $ausstehend
        Sicherheitsupdates = $sicherheit
        NeustartNoetig   = $neustart
        LetzterStart     = $os.LastBootUpTime
    }
}

Write-Host "Ermittle Patchstand von $($Computername.Count) Computern ..." -ForegroundColor Cyan

$bericht = foreach ($computer in $Computername) {
    $istLokal = ($computer -eq $env:COMPUTERNAME) -or ($computer -eq 'localhost') -or ($computer -eq '.')

    try {
        if ($istLokal) {
            $daten = & $abfrage
        }
        else {
            $daten = Invoke-Command -ComputerName $computer -ScriptBlock $abfrage -ErrorAction Stop
        }
    }
    catch {
        Write-Warning "$computer : $($_.Exception.Message)"

        [PSCustomObject]@{
            Computer = $computer; Betriebssystem = '-'; LetztesUpdate = '-'; AlterTage = $null
            Ausstehend = $null; Sicherheitsupdates = $null; NeustartNoetig = $null
            Einstufung = 'NICHT ERREICHBAR'
        }
        continue
    }

    $alter = if ($daten.Installiert) {
        [math]::Round(((Get-Date) - $daten.Installiert).TotalDays)
    }
    else { $null }

    # Einstufung: Sicherheitsupdates wiegen am schwersten.
    $einstufung = 'KONFORM'
    if ($daten.Sicherheitsupdates -gt 0)                        { $einstufung = 'NICHT KONFORM' }
    elseif ($alter -ne $null -and $alter -gt ($MaximalesUpdateAlterTage * 2)) { $einstufung = 'NICHT KONFORM' }
    elseif ($alter -ne $null -and $alter -gt $MaximalesUpdateAlterTage)       { $einstufung = 'WARNUNG' }
    elseif ($daten.Ausstehend -gt 0 -or $daten.NeustartNoetig)  { $einstufung = 'WARNUNG' }

    [PSCustomObject]@{
        Computer           = $computer
        Betriebssystem     = $daten.Betriebssystem
        LetztesUpdate      = $daten.LetztesUpdate
        Installiert        = $daten.Installiert
        AlterTage          = $alter
        Ausstehend         = $daten.Ausstehend
        Sicherheitsupdates = $daten.Sicherheitsupdates
        NeustartNoetig     = $daten.NeustartNoetig
        Einstufung         = $einstufung
    }
}

Write-Host "`n=== Patch-Compliance ===" -ForegroundColor Cyan
$bericht | Sort-Object Einstufung, AlterTage -Descending |
    Format-Table Computer, LetztesUpdate, AlterTage, Ausstehend, Sicherheitsupdates, NeustartNoetig, Einstufung -AutoSize

# --- Zusammenfassung ---------------------------------------------------------
$konform      = @($bericht | Where-Object Einstufung -eq 'KONFORM').Count
$warnung      = @($bericht | Where-Object Einstufung -eq 'WARNUNG').Count
$nichtKonform = @($bericht | Where-Object Einstufung -eq 'NICHT KONFORM').Count
$offline      = @($bericht | Where-Object Einstufung -eq 'NICHT ERREICHBAR').Count
$bewertbar    = $konform + $warnung + $nichtKonform
$quote        = if ($bewertbar -gt 0) { [math]::Round(($konform / $bewertbar) * 100) } else { 0 }
$farbe        = if ($quote -ge 90) { 'Green' } elseif ($quote -ge 70) { 'Yellow' } else { 'Red' }

Write-Host '=========================================================' -ForegroundColor Cyan
Write-Host ('Compliance-Quote: {0} % ({1} von {2} Systemen konform)' -f $quote, $konform, $bewertbar) -ForegroundColor $farbe
Write-Host ('Konform: {0}   Warnung: {1}   Nicht konform: {2}   Nicht erreichbar: {3}' -f $konform, $warnung, $nichtKonform, $offline)
Write-Host '=========================================================' -ForegroundColor Cyan

# --- Export ------------------------------------------------------------------
if ($CsvPfad) {
    $bericht | Export-Csv -Path $CsvPfad -NoTypeInformation -Encoding UTF8 -Delimiter ';'
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

    $kopf = "<h1>Patch-Compliance-Bericht</h1><p class='meta'>Erstellt am $(Get-Date -Format 'dd.MM.yyyy HH:mm') &middot; Quote: $quote % &middot; Schwellenwert: $MaximalesUpdateAlterTage Tage</p>"

    $html = $bericht | Sort-Object Einstufung |
        ConvertTo-Html -Title 'AdminWerk Patch-Compliance' -Head $stil -PreContent $kopf | Out-String

    $html = $html -replace '<td>KONFORM</td>', '<td style="color:#1a7f37;font-weight:600;">KONFORM</td>'
    $html = $html -replace '<td>WARNUNG</td>', '<td style="color:#9a6700;font-weight:600;">WARNUNG</td>'
    $html = $html -replace '<td>NICHT KONFORM</td>', '<td style="color:#b3261e;font-weight:600;">NICHT KONFORM</td>'

    $verzeichnis = Split-Path -Path $Berichtsdatei -Parent
    if ($verzeichnis -and -not (Test-Path $verzeichnis)) {
        New-Item -Path $verzeichnis -ItemType Directory -Force | Out-Null
    }

    $html | Set-Content -Path $Berichtsdatei -Encoding UTF8
    Write-Host "HTML-Bericht: $Berichtsdatei" -ForegroundColor Green
}
