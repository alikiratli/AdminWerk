<#
.SYNOPSIS
    Findet deaktivierte, abgelaufene und gesperrte Konten im Active Directory.
.DESCRIPTION
    Raeumt den Bestand auf: deaktivierte Konten (mit Angabe, wie lange schon),
    abgelaufene Konten, aktuell gesperrte Konten sowie Konten, die zwar
    deaktiviert sind, aber noch in privilegierten Gruppen stehen - das ist der
    Befund, der bei Audits regelmaessig auffaellt.
    Auf Wunsch wird eine Loeschliste fuer besonders lange deaktivierte Konten
    erzeugt; geloescht wird nichts.
.NOTES
    Benoetigt das Modul ActiveDirectory (RSAT). Reines Leseskript.
.EXAMPLE
    .\ad-deaktivierte-konten.ps1
.EXAMPLE
    .\ad-deaktivierte-konten.ps1 -LoeschvorschlagAbTagen 365 -CsvPfad C:\Berichte\deaktiviert.csv
#>
[CmdletBinding()]
param(
    [string]$Suchbasis,

    # Ab wann ein deaktiviertes Konto zum Loeschvorschlag wird.
    [int]$LoeschvorschlagAbTagen = 365,

    [string]$CsvPfad
)

if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    throw 'Das Modul "ActiveDirectory" ist nicht verfuegbar. Bitte RSAT installieren.'
}

Import-Module ActiveDirectory -ErrorAction Stop

$parameter = @{
    Filter     = { Enabled -eq $false }
    Properties = 'LastLogonDate', 'whenChanged', 'whenCreated', 'Description',
                 'AccountExpirationDate', 'MemberOf', 'PasswordLastSet'
}
if ($Suchbasis) { $parameter['SearchBase'] = $Suchbasis }

Write-Host "`n=== Deaktivierte Benutzerkonten ===`n" -ForegroundColor Cyan

$deaktiviert = Get-ADUser @parameter | ForEach-Object {
    # whenChanged ist die beste verfuegbare Naeherung fuer "seit wann deaktiviert".
    $tageSeitAenderung = if ($_.whenChanged) {
        [math]::Round(((Get-Date) - $_.whenChanged).TotalDays)
    } else { $null }

    [PSCustomObject]@{
        Konto             = $_.SamAccountName
        Name              = $_.Name
        LetzteAnmeldung   = $_.LastLogonDate
        ZuletztGeaendert  = $_.whenChanged
        TageUnveraendert  = $tageSeitAenderung
        Erstellt          = $_.whenCreated
        AblaufDatum       = $_.AccountExpirationDate
        Gruppenanzahl     = @($_.MemberOf).Count
        Gruppen           = (@($_.MemberOf) | ForEach-Object { ($_ -split ',')[0] -replace '^CN=', '' }) -join ', '
        Beschreibung      = $_.Description
        OU                = ($_.DistinguishedName -split ',', 2)[1]
    }
}

if ($deaktiviert) {
    $deaktiviert | Sort-Object ZuletztGeaendert |
        Format-Table Konto, Name, LetzteAnmeldung, ZuletztGeaendert, Gruppenanzahl -AutoSize
    Write-Host "Deaktivierte Konten: $($deaktiviert.Count)" -ForegroundColor White
}
else {
    Write-Host 'Keine deaktivierten Konten gefunden.' -ForegroundColor Green
}

# --- Deaktiviert, aber noch in privilegierten Gruppen ------------------------
Write-Host "`n=== Deaktiviert, aber noch in privilegierten Gruppen ===" -ForegroundColor Cyan

$domaene = Get-ADDomain
$privilegiert = @(
    "$($domaene.DomainSID)-512"   # Domaenen-Admins
    "$($domaene.DomainSID)-518"   # Schema-Admins
    "$($domaene.DomainSID)-519"   # Organisations-Admins
    'S-1-5-32-544'                # Administratoren
    'S-1-5-32-548'                # Konten-Operatoren
    'S-1-5-32-549'                # Server-Operatoren
    'S-1-5-32-551'                # Sicherungs-Operatoren
)

$privilegierteNamen = foreach ($sid in $privilegiert) {
    $gruppe = Get-ADGroup -Identity $sid -ErrorAction SilentlyContinue
    if ($gruppe) { $gruppe.Name }
}

$mitRechten = foreach ($konto in $deaktiviert) {
    if (-not $konto.Gruppen) { continue }

    $treffer = @($konto.Gruppen -split ', ' | Where-Object { $_ -in $privilegierteNamen })
    if ($treffer) {
        [PSCustomObject]@{
            Konto            = $konto.Konto
            Name             = $konto.Name
            PrivilegierteGruppen = $treffer -join ', '
            ZuletztGeaendert = $konto.ZuletztGeaendert
        }
    }
}

if ($mitRechten) {
    $mitRechten | Format-Table -AutoSize -Wrap
    Write-Warning "$(@($mitRechten).Count) deaktivierte Konten stehen noch in privilegierten Gruppen. Mitgliedschaft entfernen."
}
else {
    Write-Host 'Keine' -ForegroundColor Green
}

# --- Abgelaufene Konten ------------------------------------------------------
Write-Host "`n=== Abgelaufene Konten ===" -ForegroundColor Cyan
$abgelaufen = Search-ADAccount -AccountExpired -UsersOnly |
    Select-Object SamAccountName, Name, AccountExpirationDate, Enabled

if ($abgelaufen) {
    $abgelaufen | Sort-Object AccountExpirationDate | Format-Table -AutoSize

    $nochAktiv = $abgelaufen | Where-Object Enabled
    if ($nochAktiv) {
        Write-Warning "$(@($nochAktiv).Count) abgelaufene Konten sind noch aktiviert."
    }
}
else {
    Write-Host 'Keine' -ForegroundColor Green
}

# --- Gesperrte Konten --------------------------------------------------------
Write-Host "`n=== Aktuell gesperrte Konten ===" -ForegroundColor Cyan
$gesperrt = Search-ADAccount -LockedOut -UsersOnly |
    Select-Object SamAccountName, Name, LastLogonDate, LockedOut

if ($gesperrt) {
    $gesperrt | Format-Table -AutoSize
    Write-Host 'Entsperren mit: Unlock-ADAccount -Identity <Konto>' -ForegroundColor Yellow
}
else {
    Write-Host 'Keine' -ForegroundColor Green
}

# --- Loeschvorschlaege -------------------------------------------------------
Write-Host "`n=== Loeschvorschlaege (seit ueber $LoeschvorschlagAbTagen Tagen unveraendert deaktiviert) ===" -ForegroundColor Cyan

$loeschbar = $deaktiviert | Where-Object { $_.TageUnveraendert -gt $LoeschvorschlagAbTagen }

if ($loeschbar) {
    $loeschbar | Sort-Object TageUnveraendert -Descending |
        Format-Table Konto, Name, ZuletztGeaendert, TageUnveraendert, OU -AutoSize -Wrap

    Write-Host ''
    Write-Host 'Dieses Skript loescht nichts. Vor dem Loeschen bitte pruefen, ob noch' -ForegroundColor Yellow
    Write-Host 'Postfaecher, Dateiberechtigungen oder Dienste an den Konten haengen.' -ForegroundColor Yellow
}
else {
    Write-Host 'Keine' -ForegroundColor Green
}

if ($CsvPfad) {
    $deaktiviert | Export-Csv -Path $CsvPfad -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Host "`nCSV-Export: $CsvPfad" -ForegroundColor Green
}
