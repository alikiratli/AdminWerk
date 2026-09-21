<#
.SYNOPSIS
    Zeigt die geltende Kennwort- und Kontosperrungsrichtlinie.
.DESCRIPTION
    Liest die lokale Richtlinie ueber "net accounts" aus und vergleicht sie mit
    empfohlenen Mindestwerten. In einer Domaene wird zusaetzlich die
    Standard-Domaenenrichtlinie ausgewertet, sofern das AD-Modul vorhanden ist.
.EXAMPLE
    .\kennwortrichtlinie.ps1
#>
[CmdletBinding()]
param(
    [int]$MindestLaenge = 12,
    [int]$MaximalesAlterTage = 365,
    [int]$MindestAlterTage = 1,
    [int]$SperrschwelleMax = 10
)

Write-Host "`n=== Lokale Kennwortrichtlinie: $env:COMPUTERNAME ===`n" -ForegroundColor Cyan

# "net accounts" ist sprachabhaengig - deshalb wird der Wert hinter dem Doppelpunkt gelesen.
$ausgabe = & net.exe accounts 2>$null
$ausgabe | ForEach-Object { Write-Host "  $_" }

function Get-Wert {
    param([string[]]$Zeilen, [int]$Index)

    if ($Index -lt 0 -or $Index -ge $Zeilen.Count) { return $null }
    $teile = $Zeilen[$Index] -split ':', 2
    if ($teile.Count -lt 2) { return $null }

    $wert = $teile[1].Trim()
    if ($wert -match '^\d+$') { return [int]$wert }
    return $wert
}

$zeilen = @($ausgabe | Where-Object { $_ -match ':' })

# Reihenfolge von "net accounts" ist stabil: 0 = Mindestalter ... 3 = Mindestlaenge
$minAlter   = Get-Wert -Zeilen $zeilen -Index 1
$maxAlter   = Get-Wert -Zeilen $zeilen -Index 2
$minLaenge  = Get-Wert -Zeilen $zeilen -Index 3
$verlauf    = Get-Wert -Zeilen $zeilen -Index 4
$sperre     = Get-Wert -Zeilen $zeilen -Index 5

Write-Host "`n=== Bewertung ===" -ForegroundColor Cyan

$bewertung = @(
    [PSCustomObject]@{
        Kriterium = 'Mindestlaenge'
        Ist       = $minLaenge
        Empfohlen = ">= $MindestLaenge"
        Bewertung = if ($minLaenge -is [int] -and $minLaenge -ge $MindestLaenge) { 'OK' } else { 'PRUEFEN' }
    }
    [PSCustomObject]@{
        Kriterium = 'Maximales Kennwortalter (Tage)'
        Ist       = $maxAlter
        Empfohlen = "<= $MaximalesAlterTage"
        Bewertung = if ($maxAlter -is [int] -and $maxAlter -le $MaximalesAlterTage) { 'OK' } else { 'PRUEFEN' }
    }
    [PSCustomObject]@{
        Kriterium = 'Minimales Kennwortalter (Tage)'
        Ist       = $minAlter
        Empfohlen = ">= $MindestAlterTage"
        # Ohne Mindestalter laesst sich die Chronik aushebeln: einfach so oft wechseln,
        # bis das alte Kennwort wieder frei ist.
        Bewertung = if ($minAlter -is [int] -and $minAlter -ge $MindestAlterTage) { 'OK' } else { 'PRUEFEN' }
    }
    [PSCustomObject]@{
        Kriterium = 'Kennwortchronik'
        Ist       = $verlauf
        Empfohlen = '>= 5'
        Bewertung = if ($verlauf -is [int] -and $verlauf -ge 5) { 'OK' } else { 'PRUEFEN' }
    }
    [PSCustomObject]@{
        Kriterium = 'Sperrschwelle'
        Ist       = $sperre
        Empfohlen = "1 bis $SperrschwelleMax"
        Bewertung = if ($sperre -is [int] -and $sperre -ge 1 -and $sperre -le $SperrschwelleMax) { 'OK' } else { 'PRUEFEN' }
    }
)

$bewertung | Format-Table -AutoSize

# --- Domaenenrichtlinie ------------------------------------------------------
if (Get-Module -ListAvailable -Name ActiveDirectory) {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Write-Host '=== Standard-Domaenenrichtlinie ===' -ForegroundColor Cyan

        Get-ADDefaultDomainPasswordPolicy -ErrorAction Stop |
            Select-Object MinPasswordLength, PasswordHistoryCount, MaxPasswordAge, MinPasswordAge,
                ComplexityEnabled, LockoutThreshold, LockoutDuration, LockoutObservationWindow |
            Format-List

        $feinkoernig = Get-ADFineGrainedPasswordPolicy -Filter * -ErrorAction SilentlyContinue
        if ($feinkoernig) {
            Write-Host '=== Feinkoernige Kennwortrichtlinien ===' -ForegroundColor Cyan
            $feinkoernig | Select-Object Name, Precedence, MinPasswordLength, LockoutThreshold | Format-Table -AutoSize
        }
    }
    catch {
        Write-Host "Domaenenrichtlinie nicht abrufbar: $($_.Exception.Message)" -ForegroundColor DarkGray
    }
}
