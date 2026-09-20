<#
.SYNOPSIS
    Erstellt ein Inventar der installierten Software.
.DESCRIPTION
    Liest die Uninstall-Zweige der Registrierung (64 Bit, 32 Bit und Benutzerprofil).
    Das ist deutlich schneller und zuverlaessiger als Win32_Product, das bei jedem
    Aufruf eine MSI-Neukonfiguration ausloest.
.PARAMETER CsvPfad
    Optionaler Pfad fuer einen CSV-Export.
.EXAMPLE
    .\software-inventar.ps1 -CsvPfad C:\Berichte\software.csv
#>
[CmdletBinding()]
param(
    [string]$CsvPfad,
    [string]$Filter
)

$zweige = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$software = Get-ItemProperty -Path $zweige -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
    ForEach-Object {
        $installiert = $null
        if ($_.InstallDate -match '^\d{8}$') {
            $installiert = [datetime]::ParseExact($_.InstallDate, 'yyyyMMdd', $null)
        }

        [PSCustomObject]@{
            Computer       = $env:COMPUTERNAME
            Name           = $_.DisplayName
            Version        = $_.DisplayVersion
            Hersteller     = $_.Publisher
            Installiert    = $installiert
            Architektur    = if ($_.PSPath -match 'WOW6432Node') { 'x86' } else { 'x64' }
            Deinstallation = $_.UninstallString
        }
    } |
    Sort-Object Name -Unique

if ($Filter) {
    $software = $software | Where-Object { $_.Name -like "*$Filter*" }
}

$software | Select-Object Name, Version, Hersteller, Installiert, Architektur | Format-Table -AutoSize

Write-Host "`nInstallierte Programme: $($software.Count)" -ForegroundColor Cyan

if ($CsvPfad) {
    $verzeichnis = Split-Path -Path $CsvPfad -Parent
    if ($verzeichnis -and -not (Test-Path $verzeichnis)) {
        New-Item -Path $verzeichnis -ItemType Directory -Force | Out-Null
    }

    $software | Export-Csv -Path $CsvPfad -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Host "CSV-Export: $CsvPfad" -ForegroundColor Green
}
