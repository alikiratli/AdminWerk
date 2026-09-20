<#
.SYNOPSIS
    Findet inaktive Benutzer- und Computerkonten im Active Directory.
.DESCRIPTION
    Meldet Konten, die sich seit einer festgelegten Anzahl Tage nicht angemeldet
    haben, sowie abgelaufene und deaktivierte Konten. Verwaiste Konten sind ein
    haeufiger Einfallsweg und ein wiederkehrender Auditbefund.
.NOTES
    Benoetigt das Modul ActiveDirectory (RSAT).
.EXAMPLE
    .\ad-inaktive-benutzer.ps1 -Tage 90 -CsvPfad C:\Berichte\inaktiv.csv
#>
[CmdletBinding()]
param(
    [int]$Tage = 90,
    [string]$Suchbasis,
    [string]$CsvPfad
)

if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    throw 'Das Modul "ActiveDirectory" ist nicht verfuegbar. Bitte RSAT installieren.'
}

Import-Module ActiveDirectory -ErrorAction Stop

$stichtag = (Get-Date).AddDays(-$Tage)
$parameter = @{ Filter = '*'; Properties = 'LastLogonDate', 'PasswordLastSet', 'whenCreated', 'Description', 'Enabled', 'AccountExpirationDate' }
if ($Suchbasis) { $parameter['SearchBase'] = $Suchbasis }

Write-Host "`n=== Inaktive Konten (keine Anmeldung seit $Tage Tagen) ===`n" -ForegroundColor Cyan

# --- Benutzer ----------------------------------------------------------------
$benutzer = Get-ADUser @parameter |
    Where-Object { $_.Enabled -and (-not $_.LastLogonDate -or $_.LastLogonDate -lt $stichtag) } |
    ForEach-Object {
        [PSCustomObject]@{
            Typ              = 'Benutzer'
            Name             = $_.SamAccountName
            AnzeigeName      = $_.Name
            LetzteAnmeldung  = $_.LastLogonDate
            TageInaktiv      = if ($_.LastLogonDate) { [math]::Round(((Get-Date) - $_.LastLogonDate).TotalDays) } else { 'nie angemeldet' }
            KennwortGesetzt  = $_.PasswordLastSet
            Erstellt         = $_.whenCreated
            Beschreibung     = $_.Description
            OrganisationsEinheit = ($_.DistinguishedName -split ',', 2)[1]
        }
    }

Write-Host "Benutzer: $($benutzer.Count)" -ForegroundColor White
$benutzer | Sort-Object LetzteAnmeldung | Format-Table Name, AnzeigeName, LetzteAnmeldung, TageInaktiv -AutoSize

# --- Computer ----------------------------------------------------------------
$computer = Get-ADComputer @parameter |
    Where-Object { $_.Enabled -and (-not $_.LastLogonDate -or $_.LastLogonDate -lt $stichtag) } |
    ForEach-Object {
        [PSCustomObject]@{
            Typ             = 'Computer'
            Name            = $_.Name
            LetzteAnmeldung = $_.LastLogonDate
            TageInaktiv     = if ($_.LastLogonDate) { [math]::Round(((Get-Date) - $_.LastLogonDate).TotalDays) } else { 'nie angemeldet' }
            Erstellt        = $_.whenCreated
            Beschreibung    = $_.Description
        }
    }

Write-Host "`nComputer: $($computer.Count)" -ForegroundColor White
$computer | Sort-Object LetzteAnmeldung | Format-Table Name, LetzteAnmeldung, TageInaktiv -AutoSize

# --- Abgelaufene Konten ------------------------------------------------------
Write-Host "`n=== Abgelaufene Konten ===" -ForegroundColor Cyan
$abgelaufen = Search-ADAccount -AccountExpired -UsersOnly |
    Select-Object SamAccountName, Name, AccountExpirationDate, Enabled
if ($abgelaufen) { $abgelaufen | Format-Table -AutoSize } else { Write-Host 'Keine' -ForegroundColor Green }

# --- Gesperrte Konten --------------------------------------------------------
Write-Host '=== Gesperrte Konten ===' -ForegroundColor Cyan
$gesperrt = Search-ADAccount -LockedOut -UsersOnly | Select-Object SamAccountName, Name, LockedOut
if ($gesperrt) { $gesperrt | Format-Table -AutoSize } else { Write-Host 'Keine' -ForegroundColor Green }

if ($CsvPfad) {
    @($benutzer) + @($computer) | Export-Csv -Path $CsvPfad -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Host "`nCSV-Export: $CsvPfad" -ForegroundColor Green
}
