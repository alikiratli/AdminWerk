<#
.SYNOPSIS
    Sammelt das Software-Inventar mehrerer Computer und erzeugt einen Gesamtbericht.
.DESCRIPTION
    Liest auf jedem Zielsystem die Uninstall-Zweige der Registrierung aus und
    fuehrt die Ergebnisse zusammen. Neben der Gesamtliste entstehen zwei
    Auswertungen, die im Alltag am haeufigsten gebraucht werden:
    eine Verteilungsuebersicht (welches Programm liegt in welcher Version auf wie
    vielen Rechnern) und eine gezielte Suche nach einem Produkt - etwa fuer eine
    Lizenzzaehlung oder die Frage "wo ist die verwundbare Version noch installiert".
.PARAMETER Suchbegriff
    Zeigt zusaetzlich, auf welchen Computern ein Programm installiert ist.
.EXAMPLE
    .\software-inventar-netzwerk.ps1 -Computername SRV01, SRV02 -CsvPfad C:\Berichte\software.csv
.EXAMPLE
    .\software-inventar-netzwerk.ps1 -AusActiveDirectory -Suchbegriff "7-Zip"
#>
[CmdletBinding()]
param(
    [string[]]$Computername = $env:COMPUTERNAME,

    [string]$ComputerlisteDatei,

    [switch]$AusActiveDirectory,

    [string]$Suchbegriff,

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

# --- Abfrageblock, der auf jedem Zielsystem laeuft ----------------------------
$abfrage = {
    $zweige = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    Get-ItemProperty -Path $zweige -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
        ForEach-Object {
            $installiert = $null
            if ($_.InstallDate -match '^\d{8}$') {
                $installiert = [datetime]::ParseExact($_.InstallDate, 'yyyyMMdd', $null)
            }

            [PSCustomObject]@{
                Computer    = $env:COMPUTERNAME
                Name        = $_.DisplayName
                Version     = $_.DisplayVersion
                Hersteller  = $_.Publisher
                Installiert = $installiert
                Architektur = if ($_.PSPath -match 'WOW6432Node') { 'x86' } else { 'x64' }
            }
        }
}

Write-Host "Sammle Software-Inventar von $($Computername.Count) Computern ..." -ForegroundColor Cyan

$inventar = foreach ($computer in $Computername) {
    $istLokal = ($computer -eq $env:COMPUTERNAME) -or ($computer -eq 'localhost') -or ($computer -eq '.')

    try {
        if ($istLokal) {
            & $abfrage
        }
        else {
            Invoke-Command -ComputerName $computer -ScriptBlock $abfrage -ErrorAction Stop |
                Select-Object Computer, Name, Version, Hersteller, Installiert, Architektur
        }
    }
    catch {
        Write-Warning "$computer : $($_.Exception.Message)"
    }
}

$inventar = $inventar | Sort-Object Computer, Name

Write-Host "`nErfasste Eintraege: $($inventar.Count) auf $(($inventar.Computer | Select-Object -Unique).Count) Computern" -ForegroundColor White

# --- Verteilungsuebersicht ---------------------------------------------------
Write-Host "`n=== Verteilung (Programm / Version / Anzahl Computer) ===" -ForegroundColor Cyan

$verteilung = $inventar | Group-Object Name, Version |
    ForEach-Object {
        $erstes = $_.Group | Select-Object -First 1

        [PSCustomObject]@{
            Name       = $erstes.Name
            Version    = $erstes.Version
            Hersteller = $erstes.Hersteller
            Computer   = $_.Count
            Rechner    = ($_.Group.Computer | Sort-Object -Unique) -join ', '
        }
    } | Sort-Object -Property @{ Expression = 'Computer'; Descending = $true },
                              @{ Expression = 'Name'; Descending = $false }

$verteilung | Select-Object -First 30 Name, Version, Hersteller, Computer | Format-Table -AutoSize

# --- Programme mit uneinheitlichen Versionsstaenden --------------------------
$uneinheitlich = $inventar | Group-Object Name |
    Where-Object { ($_.Group.Version | Select-Object -Unique).Count -gt 1 } |
    ForEach-Object {
        [PSCustomObject]@{
            Name      = $_.Name
            Versionen = ($_.Group.Version | Sort-Object -Unique) -join ' | '
            Anzahl    = ($_.Group.Version | Select-Object -Unique).Count
        }
    } | Sort-Object Anzahl -Descending

if ($uneinheitlich) {
    Write-Host '=== Programme mit unterschiedlichen Versionsstaenden ===' -ForegroundColor Cyan
    $uneinheitlich | Select-Object -First 20 | Format-Table -AutoSize -Wrap
}

# --- Gezielte Suche ----------------------------------------------------------
if ($Suchbegriff) {
    Write-Host "=== Treffer fuer '$Suchbegriff' ===" -ForegroundColor Cyan

    $treffer = $inventar | Where-Object { $_.Name -like "*$Suchbegriff*" }

    if ($treffer) {
        $treffer | Format-Table Computer, Name, Version, Architektur, Installiert -AutoSize
        Write-Host "Installiert auf $(($treffer.Computer | Select-Object -Unique).Count) von $($Computername.Count) Computern." -ForegroundColor White

        $ohne = $Computername | Where-Object { $_ -notin $treffer.Computer }
        if ($ohne) {
            Write-Host "Nicht installiert auf: $($ohne -join ', ')" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "Keine Treffer." -ForegroundColor Yellow
    }
}

# --- Export ------------------------------------------------------------------
if ($CsvPfad) {
    $inventar | Export-Csv -Path $CsvPfad -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Host "`nCSV-Export: $CsvPfad" -ForegroundColor Green
}

if ($Berichtsdatei) {
    $stil = @'
<style>
  body  { font-family: Segoe UI, sans-serif; background: #f6f8fa; color: #24292f; margin: 32px; }
  h1    { font-size: 22px; margin-bottom: 4px; }
  h2    { font-size: 16px; margin-top: 28px; }
  p.meta{ color: #57606a; margin-top: 0; font-size: 13px; }
  table { border-collapse: collapse; width: 100%; background: #fff; }
  th    { background: #24292f; color: #fff; text-align: left; padding: 8px 10px; font-size: 13px; }
  td    { border-bottom: 1px solid #d0d7de; padding: 7px 10px; font-size: 13px; }
</style>
'@

    $kopf = "<h1>Software-Inventar</h1><p class='meta'>Erstellt am $(Get-Date -Format 'dd.MM.yyyy HH:mm') &middot; $(($inventar.Computer | Select-Object -Unique).Count) Computer &middot; $($inventar.Count) Eintraege</p><h2>Verteilung</h2>"

    $html = $verteilung | Select-Object Name, Version, Hersteller, Computer |
        ConvertTo-Html -Title 'AdminWerk Software-Inventar' -Head $stil -PreContent $kopf | Out-String

    $verzeichnis = Split-Path -Path $Berichtsdatei -Parent
    if ($verzeichnis -and -not (Test-Path $verzeichnis)) {
        New-Item -Path $verzeichnis -ItemType Directory -Force | Out-Null
    }

    $html | Set-Content -Path $Berichtsdatei -Encoding UTF8
    Write-Host "HTML-Bericht: $Berichtsdatei" -ForegroundColor Green
}
