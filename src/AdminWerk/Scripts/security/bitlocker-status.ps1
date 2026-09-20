<#
.SYNOPSIS
    Prueft den BitLocker-Verschluesselungsstatus aller Laufwerke.
.DESCRIPTION
    Zeigt Schutzstatus, Verschluesselungsverfahren und die hinterlegten
    Schluesselschutzvorrichtungen. Fehlt ein Wiederherstellungsschluessel im
    Active Directory, ist das ein haeufiger Auditbefund.
.NOTES
    Benoetigt Administratorrechte.
.EXAMPLE
    .\bitlocker-status.ps1
#>
[CmdletBinding()]
param()

if (-not (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
    throw 'Das BitLocker-Modul ist auf diesem System nicht verfuegbar.'
}

$laufwerke = Get-BitLockerVolume

Write-Host "`n=== BitLocker: $env:COMPUTERNAME ===`n" -ForegroundColor Cyan

$bericht = foreach ($laufwerk in $laufwerke) {
    $schutz = ($laufwerk.KeyProtector | ForEach-Object { $_.KeyProtectorType }) -join ', '

    [PSCustomObject]@{
        Laufwerk            = $laufwerk.MountPoint
        Typ                 = $laufwerk.VolumeType
        Schutzstatus        = $laufwerk.ProtectionStatus
        Zustand             = $laufwerk.VolumeStatus
        VerschluesseltProzent = $laufwerk.EncryptionPercentage
        Verfahren           = $laufwerk.EncryptionMethod
        Schluesselschutz    = if ($schutz) { $schutz } else { 'keiner' }
        Bewertung           = if ($laufwerk.ProtectionStatus -eq 'On') { 'OK' } else { 'KRITISCH' }
    }
}

$bericht | Format-Table -AutoSize

# Wiederherstellungskennwoerter (nur IDs anzeigen, keine Kennwoerter ausgeben)
Write-Host '=== Wiederherstellungsschluessel ===' -ForegroundColor Cyan
foreach ($laufwerk in $laufwerke) {
    $wiederherstellung = $laufwerk.KeyProtector | Where-Object KeyProtectorType -eq 'RecoveryPassword'

    if ($wiederherstellung) {
        foreach ($schluessel in $wiederherstellung) {
            Write-Host ('{0}  Schluessel-ID: {1}' -f $laufwerk.MountPoint, $schluessel.KeyProtectorId) -ForegroundColor Green
        }
    }
    else {
        Write-Host ('{0}  kein Wiederherstellungskennwort hinterlegt' -f $laufwerk.MountPoint) -ForegroundColor Yellow
    }
}

$ungeschuetzt = $bericht | Where-Object Bewertung -eq 'KRITISCH'
if ($ungeschuetzt) {
    Write-Warning "Nicht geschuetzte Laufwerke: $($ungeschuetzt.Laufwerk -join ', ')"
}
