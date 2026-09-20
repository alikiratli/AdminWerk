<#
.SYNOPSIS
    Legt AD-Benutzerkonten aus einer CSV-Datei an (Onboarding im Stapel).
.DESCRIPTION
    Erzeugt Konten im Active Directory, setzt Kennwoerter, fuellt die
    Stammdaten (Abteilung, Titel, Vorgesetzter, E-Mail) und nimmt die Konten in
    Gruppen auf. Der Anmeldename wird geprueft und Dubletten werden erkannt.

    WICHTIG: Das Skript laeuft standardmaessig im Testlauf und veraendert nichts.
    Erst mit -Anwenden wird tatsaechlich angelegt.
.PARAMETER CsvDatei
    Semikolongetrennte Datei mit den Spalten:
    Benutzername;Vorname;Nachname;Abteilung;Titel;EMail;Vorgesetzter;Gruppen;OU
    Nicht benoetigte Spalten duerfen leer bleiben. Mehrere Gruppen mit Komma trennen.
.NOTES
    Benoetigt das Modul ActiveDirectory (RSAT) und Rechte zum Anlegen von Konten
    in der Ziel-OU. Erzeugte Kennwoerter werden einmalig angezeigt.
.EXAMPLE
    .\ad-benutzer-anlegen.ps1 -CsvDatei C:\Vorlagen\onboarding.csv
.EXAMPLE
    .\ad-benutzer-anlegen.ps1 -CsvDatei C:\Vorlagen\onboarding.csv -StandardOU "OU=Benutzer,DC=firma,DC=local" -Anwenden
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvDatei,

    # Wird verwendet, wenn die CSV-Zeile keine eigene OU angibt.
    [string]$StandardOU,

    [string]$UpnSuffix,

    [switch]$Anwenden,

    [int]$KennwortLaenge = 16,

    [string]$ProtokollCsv
)

if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    throw 'Das Modul "ActiveDirectory" ist nicht verfuegbar. Bitte RSAT installieren.'
}

Import-Module ActiveDirectory -ErrorAction Stop

if (-not (Test-Path $CsvDatei)) {
    throw "CSV-Datei nicht gefunden: $CsvDatei"
}

$domaene = Get-ADDomain
if (-not $UpnSuffix) { $UpnSuffix = $domaene.DNSRoot }

function New-Kennwort {
    param([int]$Laenge = 16)

    # Ohne leicht verwechselbare Zeichen (l, I, 1, O, 0).
    $gross  = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $klein  = 'abcdefghijkmnopqrstuvwxyz'
    $zahl   = '23456789'
    $sonder = '!#%&*+-=?@'
    $alle   = $gross + $klein + $zahl + $sonder

    $zufall = New-Object System.Random
    $zeichen = @(
        $gross[$zufall.Next($gross.Length)]
        $klein[$zufall.Next($klein.Length)]
        $zahl[$zufall.Next($zahl.Length)]
        $sonder[$zufall.Next($sonder.Length)]
    )

    for ($i = $zeichen.Count; $i -lt $Laenge; $i++) {
        $zeichen += $alle[$zufall.Next($alle.Length)]
    }

    return -join ($zeichen | Sort-Object { $zufall.Next() })
}

$zeilen = Import-Csv -Path $CsvDatei -Delimiter ';' -Encoding UTF8

if (-not $Anwenden) {
    Write-Host "`n*** TESTLAUF - es wird nichts veraendert. Mit -Anwenden ausfuehren. ***`n" -ForegroundColor Yellow
}

Write-Host "Verarbeite $($zeilen.Count) Zeilen aus $CsvDatei" -ForegroundColor Cyan

$ergebnis = foreach ($zeile in $zeilen) {
    $name = $zeile.Benutzername

    if (-not $name) {
        Write-Warning 'Zeile ohne Benutzername wird uebersprungen.'
        continue
    }

    # --- Vorpruefungen -------------------------------------------------------
    $vorhanden = Get-ADUser -Filter { SamAccountName -eq $name } -ErrorAction SilentlyContinue
    if ($vorhanden) {
        Write-Warning "Konto '$name' existiert bereits - wird uebersprungen."
        [PSCustomObject]@{ Benutzername = $name; Aktion = 'uebersprungen'; Kennwort = '-'; OU = '-'; Gruppen = '-'; Hinweis = 'existiert bereits' }
        continue
    }

    if ($name.Length -gt 20) {
        Write-Warning "Anmeldename '$name' ist laenger als 20 Zeichen und wird von AD abgelehnt."
        [PSCustomObject]@{ Benutzername = $name; Aktion = 'FEHLER'; Kennwort = '-'; OU = '-'; Gruppen = '-'; Hinweis = 'Anmeldename zu lang' }
        continue
    }

    $ou = if ($zeile.OU) { $zeile.OU } elseif ($StandardOU) { $StandardOU } else { $null }
    if (-not $ou) {
        Write-Warning "Fuer '$name' ist keine OU angegeben und kein -StandardOU gesetzt."
        [PSCustomObject]@{ Benutzername = $name; Aktion = 'FEHLER'; Kennwort = '-'; OU = '-'; Gruppen = '-'; Hinweis = 'keine Ziel-OU' }
        continue
    }

    $gruppen = if ($zeile.Gruppen) { $zeile.Gruppen -split ',' | ForEach-Object { $_.Trim() } } else { @() }
    $anzeigename = (('{0} {1}' -f $zeile.Vorname, $zeile.Nachname)).Trim()
    $kennwort = New-Kennwort -Laenge $KennwortLaenge

    # --- Testlauf ------------------------------------------------------------
    if (-not $Anwenden) {
        [PSCustomObject]@{
            Benutzername = $name
            Aktion       = 'wuerde angelegt'
            Kennwort     = '(wird erzeugt)'
            OU           = $ou
            Gruppen      = ($gruppen -join ', ')
            Hinweis      = $anzeigename
        }
        continue
    }

    # --- Anlegen -------------------------------------------------------------
    try {
        $parameter = @{
            Name                  = $anzeigename
            SamAccountName        = $name
            UserPrincipalName     = "$name@$UpnSuffix"
            Path                  = $ou
            AccountPassword       = (ConvertTo-SecureString -String $kennwort -AsPlainText -Force)
            Enabled               = $true
            ChangePasswordAtLogon = $true
            ErrorAction           = 'Stop'
        }

        if ($zeile.Vorname)   { $parameter['GivenName'] = $zeile.Vorname }
        if ($zeile.Nachname)  { $parameter['Surname'] = $zeile.Nachname }
        if ($zeile.Abteilung) { $parameter['Department'] = $zeile.Abteilung }
        if ($zeile.Titel)     { $parameter['Title'] = $zeile.Titel }
        if ($zeile.EMail)     { $parameter['EmailAddress'] = $zeile.EMail }
        if ($anzeigename)     { $parameter['DisplayName'] = $anzeigename }

        if ($zeile.Vorgesetzter) {
            $chef = Get-ADUser -Filter { SamAccountName -eq $($zeile.Vorgesetzter) } -ErrorAction SilentlyContinue
            if ($chef) { $parameter['Manager'] = $chef.DistinguishedName }
            else { Write-Warning "Vorgesetzter '$($zeile.Vorgesetzter)' fuer '$name' nicht gefunden." }
        }

        New-ADUser @parameter

        $zugeordnet = @()
        foreach ($gruppe in $gruppen) {
            if (-not $gruppe) { continue }

            try {
                Add-ADGroupMember -Identity $gruppe -Members $name -ErrorAction Stop
                $zugeordnet += $gruppe
            }
            catch {
                Write-Warning "Gruppe '$gruppe' fuer '$name': $($_.Exception.Message)"
            }
        }

        [PSCustomObject]@{
            Benutzername = $name
            Aktion       = 'angelegt'
            Kennwort     = $kennwort
            OU           = $ou
            Gruppen      = ($zugeordnet -join ', ')
            Hinweis      = $anzeigename
        }
    }
    catch {
        Write-Warning "Konto '$name' konnte nicht angelegt werden: $($_.Exception.Message)"
        [PSCustomObject]@{ Benutzername = $name; Aktion = 'FEHLER'; Kennwort = '-'; OU = $ou; Gruppen = '-'; Hinweis = $_.Exception.Message }
    }
}

Write-Host "`n=== Ergebnis ===" -ForegroundColor Cyan
$ergebnis | Format-Table Benutzername, Aktion, OU, Gruppen, Hinweis -AutoSize -Wrap

if ($Anwenden) {
    $angelegt = @($ergebnis | Where-Object Aktion -eq 'angelegt')

    if ($angelegt) {
        Write-Host "`n=== Erstkennwoerter ===" -ForegroundColor Yellow
        $angelegt | Format-Table Benutzername, Kennwort -AutoSize
        Write-Host 'Diese Kennwoerter werden nur hier angezeigt. Bitte jetzt sicher weitergeben.' -ForegroundColor Yellow
        Write-Host 'Alle Konten muessen das Kennwort bei der ersten Anmeldung aendern.' -ForegroundColor Yellow
    }

    if ($ProtokollCsv) {
        # Bewusst ohne Kennwortspalte - Protokolle sollen keine Kennwoerter enthalten.
        $ergebnis | Select-Object Benutzername, Aktion, OU, Gruppen, Hinweis |
            Export-Csv -Path $ProtokollCsv -NoTypeInformation -Encoding UTF8 -Delimiter ';'
        Write-Host "Protokoll (ohne Kennwoerter): $ProtokollCsv" -ForegroundColor Green
    }
}
else {
    Write-Host 'Testlauf beendet. Zum Ausfuehren erneut mit -Anwenden starten.' -ForegroundColor Yellow
}
