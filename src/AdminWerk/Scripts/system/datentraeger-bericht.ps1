<#
.SYNOPSIS
    Erstellt einen HTML-Bericht zur Datentraegerbelegung mehrerer Computer.
.DESCRIPTION
    Sammelt Kapazitaet und freien Speicher aller lokalen Datentraeger, faerbt
    kritische Werte farblich ein und legt den Bericht als HTML-Datei ab.
.EXAMPLE
    .\datentraeger-bericht.ps1 -Computername SRV01, SRV02 -Berichtsdatei C:\Berichte\datentraeger.html
#>
[CmdletBinding()]
param(
    [string[]]$Computername = $env:COMPUTERNAME,
    [int]$SchwellenwertProzent = 15,
    [string]$Berichtsdatei = "$env:ProgramData\AdminWerk\datentraeger-$(Get-Date -Format 'yyyyMMdd').html"
)

$daten = foreach ($computer in $Computername) {
    try {
        Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 3' -ComputerName $computer -ErrorAction Stop |
            ForEach-Object {
                $freiProzent = if ($_.Size -gt 0) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 1) } else { 0 }

                [PSCustomObject]@{
                    Computer    = $computer
                    Laufwerk    = $_.DeviceID
                    Bezeichnung = $_.VolumeName
                    GesamtGB    = [math]::Round($_.Size / 1GB, 2)
                    FreiGB      = [math]::Round($_.FreeSpace / 1GB, 2)
                    FreiProzent = $freiProzent
                    Status      = if ($freiProzent -lt $SchwellenwertProzent) { 'KRITISCH' } else { 'OK' }
                }
            }
    }
    catch {
        Write-Warning "$computer : $($_.Exception.Message)"
    }
}

$stil = @'
<style>
  body  { font-family: Segoe UI, sans-serif; background: #f6f8fa; color: #24292f; margin: 32px; }
  h1    { font-size: 22px; margin-bottom: 4px; }
  p.meta{ color: #57606a; margin-top: 0; font-size: 13px; }
  table { border-collapse: collapse; width: 100%; background: #fff; }
  th    { background: #24292f; color: #fff; text-align: left; padding: 8px 10px; font-size: 13px; }
  td    { border-bottom: 1px solid #d0d7de; padding: 7px 10px; font-size: 13px; }
  tr:hover td { background: #f0f3f6; }
</style>
'@

$kopf = "<h1>Datentraegerbericht</h1><p class='meta'>Erstellt am $(Get-Date -Format 'dd.MM.yyyy HH:mm') &middot; Schwellenwert: $SchwellenwertProzent %</p>"

$html = $daten |
    Sort-Object Computer, Laufwerk |
    ConvertTo-Html -Title 'AdminWerk Datentraegerbericht' -Head $stil -PreContent $kopf |
    Out-String

# Kritische Zeilen rot hinterlegen
$html = $html -replace '<td>KRITISCH</td>', '<td style="color:#b3261e;font-weight:600;">KRITISCH</td>'
$html = $html -replace '<td>OK</td>', '<td style="color:#1a7f37;font-weight:600;">OK</td>'

$verzeichnis = Split-Path -Path $Berichtsdatei -Parent
if (-not (Test-Path $verzeichnis)) {
    New-Item -Path $verzeichnis -ItemType Directory -Force | Out-Null
}

$html | Set-Content -Path $Berichtsdatei -Encoding UTF8
Write-Host "Bericht erstellt: $Berichtsdatei" -ForegroundColor Green

$daten | Format-Table -AutoSize
