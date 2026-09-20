<#
.SYNOPSIS
    Legt lokale Benutzerkonten an - einzeln oder als Stapel aus einer CSV-Datei.
.DESCRIPTION
    Erzeugt lokale Konten, setzt ein Kennwort und nimmt das Konto optional in
    Gruppen auf. Das Kennwort kann vorgegeben oder automatisch erzeugt werden.

    WICHTIG: Das Skript laeuft standardmaessig im Testlauf und veraendert nichts.
    Es zeigt nur, was es tun wuerde. Erst mit -Anwenden wird tatsaechlich angelegt.
.PARAMETER CsvDatei
    Semikolongetrennte Datei mit den Spalten:
    Benutzername;Vollname;Beschreibung;Gruppen;Kennwort
    Mehrere Gruppen durch Komma trennen. Kennwort darf leer bleiben.
.PARAMETER Anwenden
    Fuehrt die Aenderungen wirklich aus. Ohne diesen Schalter: reiner Testlauf.
.NOTES
    Benoetigt Administratorrechte. Erzeugte Kennwoerter werden am Ende einmalig
    angezeigt und nirgends gespeichert - bitte sofort sicher weitergeben.
.EXAMPLE
    .\benutzer-anlegen.ps1 -Benutzername m.mustermann -Vollname "Max Mustermann" -Gruppen Benutzer
.EXAMPLE
    .\benutzer-anlegen.ps1 -CsvDatei C:\Vorlagen\neue-konten.csv -Anwenden
#>
[CmdletBinding()]
param(
    [string]$Benutzername,

    [string]$Vollname,

    [string]$Beschreibung,

    [string[]]$Gruppen,

    [string]$CsvDatei,

    # Ohne diesen Schalter wird nichts veraendert.
    [switch]$Anwenden,

    [int]$KennwortLaenge = 16,

    # Muss der Benutzer das Kennwort bei der ersten Anmeldung aendern?
    [switch]$KennwortAendernErzwingen = $true
)

$istAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($Anwenden -and -not $istAdmin) {
    throw 'Zum Anlegen von Konten wird eine PowerShell-Sitzung mit Administratorrechten benoetigt.'
}

function New-Kennwort {
    param([int]$Laenge = 16)

    # Bewusst ohne leicht verwechselbare Zeichen (l, I, 1, O, 0).
    $gross  = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $klein  = 'abcdefghijkmnopqrstuvwxyz'
    $zahl   = '23456789'
    $sonder = '!#%&*+-=?@'
    $alle   = $gross + $klein + $zahl + $sonder

    $zufall = New-Object System.Random
    # Je ein Zeichen aus jeder Gruppe, damit die Komplexitaetsregel sicher erfuellt ist.
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

# --- Zu verarbeitende Konten zusammenstellen ---------------------------------
$anzulegen = @()

if ($CsvDatei) {
    if (-not (Test-Path $CsvDatei)) {
        throw "CSV-Datei nicht gefunden: $CsvDatei"
    }

    $anzulegen = Import-Csv -Path $CsvDatei -Delimiter ';' -Encoding UTF8 | ForEach-Object {
        [PSCustomObject]@{
            Benutzername = $_.Benutzername
            Vollname     = $_.Vollname
            Beschreibung = $_.Beschreibung
            Gruppen      = if ($_.Gruppen) { $_.Gruppen -split ',' | ForEach-Object { $_.Trim() } } else { @() }
            Kennwort     = $_.Kennwort
        }
    }
}
elseif ($Benutzername) {
    $anzulegen = @([PSCustomObject]@{
        Benutzername = $Benutzername
        Vollname     = $Vollname
        Beschreibung = $Beschreibung
        Gruppen      = $Gruppen
        Kennwort     = $null
    })
}
else {
    throw 'Bitte -Benutzername oder -CsvDatei angeben.'
}

if (-not $Anwenden) {
    Write-Host "`n*** TESTLAUF - es wird nichts veraendert. Mit -Anwenden ausfuehren. ***`n" -ForegroundColor Yellow
}

# --- Verarbeitung ------------------------------------------------------------
$ergebnis = foreach ($konto in $anzulegen) {
    $name = $konto.Benutzername

    if (-not $name) {
        Write-Warning 'Zeile ohne Benutzername wird uebersprungen.'
        continue
    }

    $vorhanden = Get-LocalUser -Name $name -ErrorAction SilentlyContinue
    if ($vorhanden) {
        Write-Warning "Konto '$name' existiert bereits - wird uebersprungen."
        [PSCustomObject]@{ Benutzername = $name; Aktion = 'uebersprungen'; Kennwort = '-'; Gruppen = '-'; Hinweis = 'existiert bereits' }
        continue
    }

    $kennwort = if ($konto.Kennwort) { $konto.Kennwort } else { New-Kennwort -Laenge $KennwortLaenge }
    $erzeugt  = -not $konto.Kennwort

    if (-not $Anwenden) {
        [PSCustomObject]@{
            Benutzername = $name
            Aktion       = 'wuerde angelegt'
            Kennwort     = if ($erzeugt) { '(wird erzeugt)' } else { '(aus CSV)' }
            Gruppen      = ($konto.Gruppen -join ', ')
            Hinweis      = $konto.Vollname
        }
        continue
    }

    try {
        $sicher = ConvertTo-SecureString -String $kennwort -AsPlainText -Force

        $parameter = @{
            Name                 = $name
            Password             = $sicher
            PasswordNeverExpires = $false
            ErrorAction          = 'Stop'
        }
        if ($konto.Vollname)     { $parameter['FullName'] = $konto.Vollname }
        if ($konto.Beschreibung) { $parameter['Description'] = $konto.Beschreibung }

        New-LocalUser @parameter | Out-Null

        if ($KennwortAendernErzwingen) {
            # Erzwingt die Kennwortaenderung bei der naechsten Anmeldung.
            & net.exe user $name /logonpasswordchg:yes | Out-Null
        }

        $zugeordnet = @()
        foreach ($gruppe in $konto.Gruppen) {
            if (-not $gruppe) { continue }

            try {
                Add-LocalGroupMember -Group $gruppe -Member $name -ErrorAction Stop
                $zugeordnet += $gruppe
            }
            catch {
                Write-Warning "Gruppe '$gruppe' fuer '$name': $($_.Exception.Message)"
            }
        }

        [PSCustomObject]@{
            Benutzername = $name
            Aktion       = 'angelegt'
            Kennwort     = if ($erzeugt) { $kennwort } else { '(vorgegeben)' }
            Gruppen      = ($zugeordnet -join ', ')
            Hinweis      = $konto.Vollname
        }
    }
    catch {
        Write-Warning "Konto '$name' konnte nicht angelegt werden: $($_.Exception.Message)"
        [PSCustomObject]@{ Benutzername = $name; Aktion = 'FEHLER'; Kennwort = '-'; Gruppen = '-'; Hinweis = $_.Exception.Message }
    }
}

Write-Host "`n=== Ergebnis ===" -ForegroundColor Cyan
$ergebnis | Format-Table -AutoSize -Wrap

if ($Anwenden) {
    $mitKennwort = $ergebnis | Where-Object { $_.Aktion -eq 'angelegt' -and $_.Kennwort -ne '(vorgegeben)' }
    if ($mitKennwort) {
        Write-Host 'Die erzeugten Kennwoerter werden nur hier angezeigt und nirgends gespeichert.' -ForegroundColor Yellow
        Write-Host 'Bitte jetzt sicher an die Benutzer weitergeben.' -ForegroundColor Yellow
    }
}
else {
    Write-Host 'Testlauf beendet. Zum Ausfuehren erneut mit -Anwenden starten.' -ForegroundColor Yellow
}
