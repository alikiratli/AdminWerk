<#
.SYNOPSIS
    Listet alle Programme auf, die beim Systemstart automatisch ausgefuehrt werden.
.DESCRIPTION
    Durchsucht die Run-Schluessel der Registrierung sowie die Autostart-Ordner von
    System und Benutzer. Eintraege ausserhalb der ueblichen Programmverzeichnisse
    werden als pruefungswuerdig markiert - ein typischer Persistenzmechanismus.
.EXAMPLE
    .\autostart-programme.ps1
#>
[CmdletBinding()]
param()

$registrierungspfade = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
)

$eintraege = foreach ($pfad in $registrierungspfade) {
    if (-not (Test-Path $pfad)) { continue }

    $schluessel = Get-Item -Path $pfad
    foreach ($name in $schluessel.GetValueNames()) {
        [PSCustomObject]@{
            Quelle  = $pfad
            Name    = $name
            Befehl  = $schluessel.GetValue($name)
        }
    }
}

# Autostart-Ordner ergaenzen
$ordner = @(
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"
    "$env:AppData\Microsoft\Windows\Start Menu\Programs\StartUp"
)

$eintraege += foreach ($verzeichnis in $ordner) {
    if (-not (Test-Path $verzeichnis)) { continue }

    Get-ChildItem -Path $verzeichnis -File -ErrorAction SilentlyContinue | ForEach-Object {
        [PSCustomObject]@{ Quelle = $verzeichnis; Name = $_.Name; Befehl = $_.FullName }
    }
}

$bericht = foreach ($eintrag in $eintraege) {
    # Pfad aus dem Befehl herausloesen, um ihn bewerten zu koennen
    $befehl = [string]$eintrag.Befehl
    $pfad = if ($befehl -match '^"([^"]+)"') { $matches[1] } else { ($befehl -split ' ')[0] }

    $verdaechtig = $pfad -and
                   $pfad -notmatch '^[A-Za-z]:\\(Program Files|Program Files \(x86\)|Windows)\\' -and
                   $pfad -notmatch '^[A-Za-z]:\\Users\\[^\\]+\\AppData\\Local\\(Microsoft|Programs)\\'

    [PSCustomObject]@{
        Name       = $eintrag.Name
        Programm   = $pfad
        Quelle     = ($eintrag.Quelle -replace '^HKLM:\\SOFTWARE\\', 'HKLM\') -replace '^HKCU:\\SOFTWARE\\', 'HKCU\'
        Vorhanden  = if ($pfad) { Test-Path -Path $pfad -ErrorAction SilentlyContinue } else { $false }
        Bewertung  = if ($verdaechtig) { 'PRUEFEN' } else { 'OK' }
    }
}

Write-Host "`n=== Autostart-Eintraege: $env:COMPUTERNAME ===`n" -ForegroundColor Cyan
$bericht | Sort-Object Bewertung, Name | Format-Table -AutoSize -Wrap

$pruefen = $bericht | Where-Object Bewertung -eq 'PRUEFEN'
if ($pruefen) {
    Write-Warning "$($pruefen.Count) Eintraege liegen ausserhalb der ueblichen Programmverzeichnisse."
}
else {
    Write-Host 'Alle Autostart-Eintraege liegen in ueblichen Programmverzeichnissen.' -ForegroundColor Green
}

Write-Host "Autostart-Eintraege gesamt: $($bericht.Count)" -ForegroundColor White
