<#
.SYNOPSIS
    Inventarisiert alle Computerkonten im Active Directory nach Betriebssystem.
.DESCRIPTION
    Beantwortet die Frage "was laeuft eigentlich noch bei uns": Verteilung der
    Betriebssysteme und Build-Staende, Trennung nach Servern und Arbeitsplaetzen
    sowie eine Liste der Systeme, deren Betriebssystem das Supportende erreicht
    hat. Zusaetzlich werden Computerkonten ohne Anmeldung als Karteileichen
    ausgewiesen.
.NOTES
    Benoetigt das Modul ActiveDirectory (RSAT).
.EXAMPLE
    .\ad-computer-betriebssysteme.ps1
.EXAMPLE
    .\ad-computer-betriebssysteme.ps1 -CsvPfad C:\Berichte\computer.csv -Berichtsdatei C:\Berichte\computer.html
#>
[CmdletBinding()]
param(
    [string]$Suchbasis,
    [int]$InaktivAbTagen = 90,
    [string]$CsvPfad,
    [string]$Berichtsdatei
)

if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    throw 'Das Modul "ActiveDirectory" ist nicht verfuegbar. Bitte RSAT installieren.'
}

Import-Module ActiveDirectory -ErrorAction Stop

# Betriebssysteme ohne Herstellerunterstuetzung. Liste bei Bedarf anpassen.
$ohneSupport = @(
    'Windows XP', 'Windows Vista', 'Windows 7', 'Windows 8',
    'Windows Server 2003', 'Windows Server 2008', 'Windows Server 2012'
)

$parameter = @{
    Filter     = '*'
    Properties = 'OperatingSystem', 'OperatingSystemVersion', 'LastLogonDate',
                 'whenCreated', 'Enabled', 'Description', 'IPv4Address'
}
if ($Suchbasis) { $parameter['SearchBase'] = $Suchbasis }

Write-Host "`nLese Computerkonten aus dem Active Directory ..." -ForegroundColor Cyan

$stichtag = (Get-Date).AddDays(-$InaktivAbTagen)

$computer = Get-ADComputer @parameter | ForEach-Object {
    $os = if ($_.OperatingSystem) { $_.OperatingSystem } else { 'unbekannt' }

    $veraltet = $false
    foreach ($alt in $ohneSupport) {
        # "Windows Server 2012 R2" darf nicht als "Windows Server 2012" gelten.
        if ($os -like "$alt*" -and $os -notlike "$alt R2*") { $veraltet = $true; break }
    }

    $rolle = if ($os -match 'Server') { 'Server' }
             elseif ($os -eq 'unbekannt') { 'unbekannt' }
             else { 'Arbeitsplatz' }

    $tageInaktiv = if ($_.LastLogonDate) {
        [math]::Round(((Get-Date) - $_.LastLogonDate).TotalDays)
    } else { $null }

    [PSCustomObject]@{
        Computer        = $_.Name
        Rolle           = $rolle
        Betriebssystem  = $os
        OsVersion       = $_.OperatingSystemVersion
        Aktiviert       = $_.Enabled
        LetzteAnmeldung = $_.LastLogonDate
        TageInaktiv     = $tageInaktiv
        Erstellt        = $_.whenCreated
        IPAdresse       = $_.IPv4Address
        OhneSupport     = $veraltet
        Beschreibung    = $_.Description
        OU              = ($_.DistinguishedName -split ',', 2)[1]
    }
}

# --- Verteilung nach Betriebssystem ------------------------------------------
Write-Host "`n=== Verteilung nach Betriebssystem ===" -ForegroundColor Cyan

$verteilung = $computer | Group-Object Betriebssystem | Sort-Object Count -Descending |
    ForEach-Object {
        $erstes = $_.Group | Select-Object -First 1

        [PSCustomObject]@{
            Betriebssystem = $_.Name
            Rolle          = $erstes.Rolle
            Anzahl         = $_.Count
            Aktiviert      = @($_.Group | Where-Object Aktiviert).Count
            OhneSupport    = $erstes.OhneSupport
        }
    }

$verteilung | Format-Table -AutoSize

# --- Build-Staende innerhalb der Betriebssysteme ------------------------------
Write-Host '=== Build-Staende ===' -ForegroundColor Cyan
$computer | Where-Object Betriebssystem -ne 'unbekannt' |
    Group-Object Betriebssystem, OsVersion | Sort-Object Count -Descending |
    Select-Object -First 20 @{ Name = 'Betriebssystem / Build'; Expression = { $_.Name } },
        @{ Name = 'Anzahl'; Expression = { $_.Count } } |
    Format-Table -AutoSize

# --- Server und Arbeitsplaetze getrennt --------------------------------------
foreach ($rolle in 'Server', 'Arbeitsplatz') {
    $teilmenge = $computer | Where-Object { $_.Rolle -eq $rolle -and $_.Aktiviert }

    Write-Host "=== $rolle ($($teilmenge.Count) aktiviert) ===" -ForegroundColor Cyan
    $teilmenge | Sort-Object Betriebssystem, Computer |
        Select-Object -First 30 Computer, Betriebssystem, LetzteAnmeldung, IPAdresse |
        Format-Table -AutoSize
}

# --- Systeme ohne Herstellerunterstuetzung -----------------------------------
Write-Host '=== Betriebssysteme ohne Herstellerunterstuetzung ===' -ForegroundColor Cyan
$veraltete = $computer | Where-Object { $_.OhneSupport -and $_.Aktiviert }

if ($veraltete) {
    $veraltete | Sort-Object Betriebssystem, Computer |
        Format-Table Computer, Betriebssystem, LetzteAnmeldung, OU -AutoSize -Wrap
    Write-Warning "$($veraltete.Count) aktivierte Computerkonten laufen auf einem nicht mehr unterstuetzten Betriebssystem."
}
else {
    Write-Host 'Keine' -ForegroundColor Green
}

# --- Karteileichen -----------------------------------------------------------
Write-Host "=== Computerkonten ohne Anmeldung seit $InaktivAbTagen Tagen ===" -ForegroundColor Cyan
$inaktiv = $computer | Where-Object { $_.Aktiviert -and (-not $_.LetzteAnmeldung -or $_.LetzteAnmeldung -lt $stichtag) }

if ($inaktiv) {
    $inaktiv | Sort-Object LetzteAnmeldung |
        Format-Table Computer, Betriebssystem, LetzteAnmeldung, TageInaktiv, Erstellt -AutoSize
    Write-Warning "$($inaktiv.Count) Computerkonten sind Aufraeumkandidaten."
}
else {
    Write-Host 'Keine' -ForegroundColor Green
}

# --- Zusammenfassung ---------------------------------------------------------
Write-Host '=========================================================' -ForegroundColor Cyan
Write-Host ('Computerkonten gesamt : {0}' -f $computer.Count)
Write-Host ('Davon aktiviert       : {0}' -f @($computer | Where-Object Aktiviert).Count)
Write-Host ('Server                : {0}' -f @($computer | Where-Object Rolle -eq 'Server').Count)
Write-Host ('Arbeitsplaetze        : {0}' -f @($computer | Where-Object Rolle -eq 'Arbeitsplatz').Count)
Write-Host ('Ohne Support          : {0}' -f @($veraltete).Count)
Write-Host ('Inaktiv               : {0}' -f @($inaktiv).Count)
Write-Host '=========================================================' -ForegroundColor Cyan

# --- Export ------------------------------------------------------------------
if ($CsvPfad) {
    $computer | Export-Csv -Path $CsvPfad -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Host "CSV-Export: $CsvPfad" -ForegroundColor Green
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

    $kopf = "<h1>Computer- und Betriebssysteminventar</h1><p class='meta'>Erstellt am $(Get-Date -Format 'dd.MM.yyyy HH:mm') &middot; $($computer.Count) Computerkonten</p><h2>Verteilung nach Betriebssystem</h2>"

    $html = $verteilung | ConvertTo-Html -Title 'AdminWerk Computerinventar' -Head $stil -PreContent $kopf | Out-String
    $html = $html -replace '<td>True</td>', '<td style="color:#b3261e;font-weight:600;">True</td>'

    $verzeichnis = Split-Path -Path $Berichtsdatei -Parent
    if ($verzeichnis -and -not (Test-Path $verzeichnis)) {
        New-Item -Path $verzeichnis -ItemType Directory -Force | Out-Null
    }

    $html | Set-Content -Path $Berichtsdatei -Encoding UTF8
    Write-Host "HTML-Bericht: $Berichtsdatei" -ForegroundColor Green
}
