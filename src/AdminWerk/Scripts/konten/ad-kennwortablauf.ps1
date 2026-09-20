<#
.SYNOPSIS
    Meldet Benutzer, deren Kennwort demnaechst ablaeuft.
.DESCRIPTION
    Ermittelt anhand der Domaenenrichtlinie das Ablaufdatum jedes Kennworts und
    listet alle Konten, die innerhalb der naechsten Tage handeln muessen.
    Optional kann die Liste als CSV fuer den Servicedesk exportiert werden.
.NOTES
    Benoetigt das Modul ActiveDirectory (RSAT).
.EXAMPLE
    .\ad-kennwortablauf.ps1 -VorlaufTage 14
#>
[CmdletBinding()]
param(
    [int]$VorlaufTage = 14,
    [string]$Suchbasis,
    [string]$CsvPfad
)

if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    throw 'Das Modul "ActiveDirectory" ist nicht verfuegbar. Bitte RSAT installieren.'
}

Import-Module ActiveDirectory -ErrorAction Stop

$richtlinie = Get-ADDefaultDomainPasswordPolicy
$maximalesAlter = $richtlinie.MaxPasswordAge

if ($maximalesAlter.TotalDays -eq 0) {
    Write-Warning 'Die Domaenenrichtlinie sieht kein Kennwortablaufdatum vor.'
    return
}

$parameter = @{
    Filter     = { Enabled -eq $true -and PasswordNeverExpires -eq $false }
    Properties = 'PasswordLastSet', 'PasswordNeverExpires', 'EmailAddress', 'LastLogonDate', 'Manager'
}
if ($Suchbasis) { $parameter['SearchBase'] = $Suchbasis }

$konten = Get-ADUser @parameter | Where-Object PasswordLastSet

$bericht = foreach ($konto in $konten) {
    $ablauf = $konto.PasswordLastSet + $maximalesAlter
    $resttage = [math]::Floor(($ablauf - (Get-Date)).TotalDays)

    [PSCustomObject]@{
        Konto           = $konto.SamAccountName
        Name            = $konto.Name
        EMail           = $konto.EmailAddress
        KennwortGesetzt = $konto.PasswordLastSet
        LaeuftAbAm      = $ablauf
        Resttage        = $resttage
        Status          = if ($resttage -lt 0) { 'ABGELAUFEN' } elseif ($resttage -le 3) { 'DRINGEND' } else { 'bald faellig' }
    }
}

$faellig = $bericht | Where-Object Resttage -le $VorlaufTage | Sort-Object Resttage

Write-Host "`n=== Kennwoerter mit Ablauf in den naechsten $VorlaufTage Tagen ===`n" -ForegroundColor Cyan

if (-not $faellig) {
    Write-Host 'Keine Kennwoerter laufen im gewaehlten Zeitraum ab.' -ForegroundColor Green
    return
}

$faellig | Format-Table Konto, Name, LaeuftAbAm, Resttage, Status, EMail -AutoSize

Write-Host ('Abgelaufen: {0}   Dringend (<= 3 Tage): {1}   Gesamt: {2}' -f `
    @($faellig | Where-Object Status -eq 'ABGELAUFEN').Count,
    @($faellig | Where-Object Status -eq 'DRINGEND').Count,
    $faellig.Count) -ForegroundColor White

Write-Host "`n=== Konten mit 'Kennwort laeuft nie ab' ===" -ForegroundColor Cyan
$ohneAblauf = Get-ADUser -Filter { Enabled -eq $true -and PasswordNeverExpires -eq $true } -Properties PasswordLastSet |
    Select-Object SamAccountName, Name, PasswordLastSet
if ($ohneAblauf) { $ohneAblauf | Format-Table -AutoSize } else { Write-Host 'Keine' -ForegroundColor Green }

if ($CsvPfad) {
    $faellig | Export-Csv -Path $CsvPfad -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Host "CSV-Export: $CsvPfad" -ForegroundColor Green
}
