<#
.SYNOPSIS
    Aktiviert oder deaktiviert Konten - lokal oder im Active Directory.
.DESCRIPTION
    Deckt den Austrittsfall ab: Konto deaktivieren, optional aus allen Gruppen
    entfernen, Beschreibung mit Datum und Grund versehen und in eine OU
    verschieben. Genauso den Wiedereintritt: Konto reaktivieren.

    WICHTIG: Das Skript laeuft standardmaessig im Testlauf und veraendert nichts.
    Erst mit -Anwenden wird tatsaechlich geaendert. Eingebaute Konten
    (SID-Endung -500, -501) werden grundsaetzlich nicht angefasst.
.PARAMETER Aktion
    Deaktivieren oder Aktivieren.
.PARAMETER AusGruppenEntfernen
    Entfernt das Konto aus allen Gruppen ausser der Primaergruppe. Nur beim Deaktivieren.
.EXAMPLE
    .\konten-aktivieren-deaktivieren.ps1 -Benutzername m.mustermann -Aktion Deaktivieren
.EXAMPLE
    .\konten-aktivieren-deaktivieren.ps1 -Benutzername m.mustermann -Aktion Deaktivieren -ActiveDirectory -AusGruppenEntfernen -Grund "Austritt 30.09." -Anwenden
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$Benutzername,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Deaktivieren', 'Aktivieren')]
    [string]$Aktion,

    # Im Active Directory statt lokal arbeiten.
    [switch]$ActiveDirectory,

    [switch]$AusGruppenEntfernen,

    [string]$Grund,

    # Ziel-OU, in die deaktivierte Konten verschoben werden (nur mit -ActiveDirectory).
    [string]$ZielOU,

    [switch]$Anwenden
)

$istAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($Anwenden -and -not $ActiveDirectory -and -not $istAdmin) {
    throw 'Zum Aendern lokaler Konten wird eine PowerShell-Sitzung mit Administratorrechten benoetigt.'
}

if ($ActiveDirectory) {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw 'Das Modul "ActiveDirectory" ist nicht verfuegbar. Bitte RSAT installieren.'
    }

    Import-Module ActiveDirectory -ErrorAction Stop
}

if (-not $Anwenden) {
    Write-Host "`n*** TESTLAUF - es wird nichts veraendert. Mit -Anwenden ausfuehren. ***`n" -ForegroundColor Yellow
}

$vermerk = if ($Grund) {
    '{0} am {1}: {2}' -f $Aktion, (Get-Date -Format 'dd.MM.yyyy'), $Grund
} else {
    '{0} am {1}' -f $Aktion, (Get-Date -Format 'dd.MM.yyyy')
}

$ergebnis = foreach ($name in $Benutzername) {

    # ---------- Active Directory ----------
    if ($ActiveDirectory) {
        $konto = Get-ADUser -Filter { SamAccountName -eq $name } -Properties Description, MemberOf, Enabled -ErrorAction SilentlyContinue

        if (-not $konto) {
            Write-Warning "AD-Konto '$name' nicht gefunden."
            [PSCustomObject]@{ Konto = $name; Bereich = 'AD'; VorherAktiv = '-'; Aktion = 'nicht gefunden'; Gruppen = '-' }
            continue
        }

        $gruppen = @($konto.MemberOf | ForEach-Object { (Get-ADGroup $_).Name })

        if (-not $Anwenden) {
            $geplant = @("Konto $Aktion")
            if ($AusGruppenEntfernen -and $Aktion -eq 'Deaktivieren' -and $gruppen) { $geplant += "aus $($gruppen.Count) Gruppen entfernen" }
            if ($ZielOU) { $geplant += "nach '$ZielOU' verschieben" }

            [PSCustomObject]@{
                Konto = $konto.SamAccountName; Bereich = 'AD'; VorherAktiv = $konto.Enabled
                Aktion = 'wuerde: ' + ($geplant -join ', '); Gruppen = ($gruppen -join ', ')
            }
            continue
        }

        try {
            if ($Aktion -eq 'Deaktivieren') {
                Disable-ADAccount -Identity $konto -ErrorAction Stop

                if ($AusGruppenEntfernen) {
                    foreach ($gruppe in $konto.MemberOf) {
                        try { Remove-ADGroupMember -Identity $gruppe -Members $konto -Confirm:$false -ErrorAction Stop }
                        catch { Write-Warning "Gruppe konnte nicht entfernt werden: $($_.Exception.Message)" }
                    }
                }
            }
            else {
                Enable-ADAccount -Identity $konto -ErrorAction Stop
            }

            Set-ADUser -Identity $konto -Description $vermerk -ErrorAction Stop

            if ($ZielOU -and $Aktion -eq 'Deaktivieren') {
                Move-ADObject -Identity $konto.DistinguishedName -TargetPath $ZielOU -ErrorAction Stop
            }

            [PSCustomObject]@{
                Konto = $konto.SamAccountName; Bereich = 'AD'; VorherAktiv = $konto.Enabled
                Aktion = "$Aktion erfolgreich"; Gruppen = ($gruppen -join ', ')
            }
        }
        catch {
            Write-Warning "$name : $($_.Exception.Message)"
            [PSCustomObject]@{ Konto = $name; Bereich = 'AD'; VorherAktiv = $konto.Enabled; Aktion = "FEHLER: $($_.Exception.Message)"; Gruppen = '-' }
        }

        continue
    }

    # ---------- Lokales Konto ----------
    $konto = Get-LocalUser -Name $name -ErrorAction SilentlyContinue

    if (-not $konto) {
        Write-Warning "Lokales Konto '$name' nicht gefunden."
        [PSCustomObject]@{ Konto = $name; Bereich = 'lokal'; VorherAktiv = '-'; Aktion = 'nicht gefunden'; Gruppen = '-' }
        continue
    }

    # Eingebaute Konten schuetzen: Administrator (-500) und Gast (-501).
    if ($konto.SID.Value -like '*-500' -or $konto.SID.Value -like '*-501') {
        Write-Warning "'$name' ist ein eingebautes Konto und wird von diesem Skript nicht veraendert."
        [PSCustomObject]@{ Konto = $name; Bereich = 'lokal'; VorherAktiv = $konto.Enabled; Aktion = 'geschuetzt - uebersprungen'; Gruppen = '-' }
        continue
    }

    $mitgliedschaften = @(
        Get-LocalGroup | ForEach-Object {
            $gruppe = $_
            $treffer = Get-LocalGroupMember -Group $gruppe -ErrorAction SilentlyContinue |
                Where-Object { ($_.Name -split '\\')[-1] -eq $name }
            if ($treffer) { $gruppe.Name }
        }
    )

    if (-not $Anwenden) {
        $geplant = @("Konto $Aktion")
        if ($AusGruppenEntfernen -and $Aktion -eq 'Deaktivieren' -and $mitgliedschaften) {
            $geplant += "aus $($mitgliedschaften.Count) Gruppen entfernen"
        }

        [PSCustomObject]@{
            Konto = $konto.Name; Bereich = 'lokal'; VorherAktiv = $konto.Enabled
            Aktion = 'wuerde: ' + ($geplant -join ', '); Gruppen = ($mitgliedschaften -join ', ')
        }
        continue
    }

    try {
        if ($Aktion -eq 'Deaktivieren') {
            Disable-LocalUser -Name $name -ErrorAction Stop

            if ($AusGruppenEntfernen) {
                foreach ($gruppe in $mitgliedschaften) {
                    try { Remove-LocalGroupMember -Group $gruppe -Member $name -ErrorAction Stop }
                    catch { Write-Warning "Gruppe '$gruppe': $($_.Exception.Message)" }
                }
            }
        }
        else {
            Enable-LocalUser -Name $name -ErrorAction Stop
        }

        Set-LocalUser -Name $name -Description $vermerk -ErrorAction SilentlyContinue

        [PSCustomObject]@{
            Konto = $konto.Name; Bereich = 'lokal'; VorherAktiv = $konto.Enabled
            Aktion = "$Aktion erfolgreich"; Gruppen = ($mitgliedschaften -join ', ')
        }
    }
    catch {
        Write-Warning "$name : $($_.Exception.Message)"
        [PSCustomObject]@{ Konto = $name; Bereich = 'lokal'; VorherAktiv = $konto.Enabled; Aktion = "FEHLER: $($_.Exception.Message)"; Gruppen = '-' }
    }
}

Write-Host "`n=== Ergebnis ===" -ForegroundColor Cyan
$ergebnis | Format-Table -AutoSize -Wrap

if (-not $Anwenden) {
    Write-Host 'Testlauf beendet. Zum Ausfuehren erneut mit -Anwenden starten.' -ForegroundColor Yellow
}
