<#
.SYNOPSIS
    Prueft die Mitgliedschaft in den privilegierten AD-Gruppen.
.DESCRIPTION
    Wertet Domaenen-Admins, Organisations-Admins, Schema-Admins sowie weitere
    hoch privilegierte Gruppen aus - einschliesslich verschachtelter Mitglieder.
    Zusaetzlich werden Konten mit "Kennwort laeuft nie ab" hervorgehoben.
.NOTES
    Benoetigt das Modul ActiveDirectory (RSAT).
.EXAMPLE
    .\ad-domaenen-admins.ps1
#>
[CmdletBinding()]
param()

if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    throw 'Das Modul "ActiveDirectory" ist nicht verfuegbar. Bitte RSAT installieren.'
}

Import-Module ActiveDirectory -ErrorAction Stop

$domaene = Get-ADDomain
# Ueber die bekannten RIDs statt ueber Gruppennamen: sprachunabhaengig.
$gruppen = @(
    @{ Name = 'Domaenen-Admins';      Sid = "$($domaene.DomainSID)-512" }
    @{ Name = 'Organisations-Admins'; Sid = "$($domaene.DomainSID)-519" }
    @{ Name = 'Schema-Admins';        Sid = "$($domaene.DomainSID)-518" }
    @{ Name = 'Administratoren';      Sid = 'S-1-5-32-544' }
    @{ Name = 'Konten-Operatoren';    Sid = 'S-1-5-32-548' }
    @{ Name = 'Server-Operatoren';    Sid = 'S-1-5-32-549' }
    @{ Name = 'Sicherungs-Operatoren'; Sid = 'S-1-5-32-551' }
)

Write-Host "`n=== Privilegierte Gruppen: $($domaene.DNSRoot) ===`n" -ForegroundColor Cyan

$alle = foreach ($eintrag in $gruppen) {
    $gruppe = Get-ADGroup -Identity $eintrag.Sid -ErrorAction SilentlyContinue
    if (-not $gruppe) { continue }

    $mitglieder = Get-ADGroupMember -Identity $gruppe -Recursive -ErrorAction SilentlyContinue

    Write-Host "--- $($eintrag.Name) ($($gruppe.Name)) : $($mitglieder.Count) Mitglieder ---" -ForegroundColor White

    $details = foreach ($mitglied in $mitglieder) {
        $konto = Get-ADUser -Identity $mitglied.DistinguishedName -Properties LastLogonDate, PasswordLastSet, PasswordNeverExpires, Enabled -ErrorAction SilentlyContinue
        if (-not $konto) { continue }

        [PSCustomObject]@{
            Gruppe            = $eintrag.Name
            Konto             = $konto.SamAccountName
            Name              = $konto.Name
            Aktiviert         = $konto.Enabled
            LetzteAnmeldung   = $konto.LastLogonDate
            KennwortGesetzt   = $konto.PasswordLastSet
            KennwortOhneAblauf = $konto.PasswordNeverExpires
        }
    }

    $details | Format-Table Konto, Name, Aktiviert, LetzteAnmeldung, KennwortOhneAblauf -AutoSize
    $details
}

Write-Host '=== Auffaelligkeiten ===' -ForegroundColor Cyan

$ohneAblauf = $alle | Where-Object KennwortOhneAblauf | Select-Object -Unique Konto, Gruppe
if ($ohneAblauf) {
    Write-Warning 'Privilegierte Konten, deren Kennwort nie ablaeuft:'
    $ohneAblauf | Format-Table -AutoSize
}

$altesKennwort = $alle | Where-Object { $_.KennwortGesetzt -and $_.KennwortGesetzt -lt (Get-Date).AddDays(-365) }
if ($altesKennwort) {
    Write-Warning 'Privilegierte Konten mit Kennwort aelter als ein Jahr:'
    $altesKennwort | Select-Object Konto, Gruppe, KennwortGesetzt | Format-Table -AutoSize
}

$inaktiv = $alle | Where-Object { $_.Aktiviert -and $_.LetzteAnmeldung -and $_.LetzteAnmeldung -lt (Get-Date).AddDays(-90) }
if ($inaktiv) {
    Write-Warning 'Privilegierte Konten ohne Anmeldung in den letzten 90 Tagen:'
    $inaktiv | Select-Object Konto, Gruppe, LetzteAnmeldung | Format-Table -AutoSize
}
