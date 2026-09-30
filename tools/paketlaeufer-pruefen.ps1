<#
.SYNOPSIS
    Prueft den Paketlaeufer: Einzelbericht, eingebettete Daten und Zusammenfuehren.
.DESCRIPTION
    Baut in einem Temp-Ordner ein kuenstliches Pruefpaket aus drei Skripten, deren
    Ergebnis feststeht - eines laeuft durch, eines meldet ueber den Exitcode einen
    Befund, eines wirft. Der Laeufer wird damit mehrmals gestartet, jeweils unter einem
    anderen Computernamen (die Umgebungsvariable wird fuer den Kindprozess ueberschrieben).
    Danach werden die Berichte zusammengefuehrt und das Ergebnis nachgelesen.

    Die Katalogskripte sind hier bewusst nicht dabei: deren Ergebnis haengt vom
    Rechner ab, und der Test soll auf jedem Rechner dasselbe sagen.

    Diese Datei ist als UTF-8 mit BOM gespeichert, weil sie Umlaute vergleicht.
    Rueckgabewert 0, wenn alles bestanden ist, sonst 1.
.EXAMPLE
    .\tools\paketlaeufer-pruefen.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$wurzel = Split-Path -Parent $PSScriptRoot
$laeuferVorlage = Join-Path $wurzel 'src\AdminWerk\Vorlagen\Start-Pruefung.ps1'

$script:Bestanden = 0
$script:Fehlgeschlagen = 0

function Pruefe {
    param([string]$Was, [scriptblock]$Bedingung, [string]$Befund = '')

    try {
        $ergebnis = & $Bedingung
    }
    catch {
        $ergebnis = $false
        $Befund = $_.Exception.Message
    }

    $anhang = if ($Befund) { "  ($Befund)" } else { '' }

    if ($ergebnis) {
        $script:Bestanden++
        Write-Host ("  OK      {0}{1}" -f $Was, $anhang) -ForegroundColor Green
    }
    else {
        $script:Fehlgeschlagen++
        Write-Host ("  FEHLER  {0}{1}" -f $Was, $anhang) -ForegroundColor Red
    }
}

function Daten {
    param([string]$Pfad)

    $inhalt = [System.IO.File]::ReadAllText($Pfad, [System.Text.Encoding]::UTF8)
    $treffer = [regex]::Match($inhalt, '(?s)<script type="application/json" id="adminwerk-daten">(.*?)</script>')
    if ($treffer.Success) { $treffer.Groups[1].Value | ConvertFrom-Json }
}

function Laeufer {
    param([string]$Computer, [string[]]$Argumente, [string]$Kaputt = '1')

    # Kindprozess, damit der ueberschriebene Name nur dort gilt und "exit" im
    # Laeufer diesen Test nicht beendet.
    # Meldet der Laeufer absichtlich einen Fehler, kommt der ueber stderr. Unter 5.1
    # wird daraus bei 'Stop' ein Abbruch hier - gefragt ist aber nur der Exitcode.
    $ErrorActionPreference = 'Continue'

    $vorher = $env:COMPUTERNAME
    try {
        $env:COMPUTERNAME = $Computer
        $env:ADMINWERK_TEST_KAPUTT = $Kaputt
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $laeufer @Argumente *> $null
        $LASTEXITCODE
    }
    finally {
        $env:COMPUTERNAME = $vorher
        Remove-Item Env:\ADMINWERK_TEST_KAPUTT -ErrorAction SilentlyContinue
    }
}

# --- Paket bauen -------------------------------------------------------------
$basis = Join-Path $env:TEMP ('AdminWerk-Laeufertest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$paketOrdner = Join-Path $basis 'paket'
$berichte = Join-Path $basis 'berichte'
New-Item -Path (Join-Path $paketOrdner 'test'), $berichte -ItemType Directory -Force | Out-Null

$laeufer = Join-Path $paketOrdner 'Start-Pruefung.ps1'
Copy-Item -Path $laeuferVorlage -Destination $laeufer

$skripte = @{
    'ok.ps1'      = "'Alles in Ordnung auf ' + `$env:COMPUTERNAME`n'Eine Ausgabe mit </script> und <b>Auszeichnung</b>'"
    'hinweis.ps1' = "'Ein Befund'`nexit 3"
    'kaputt.ps1'  = "if (`$env:ADMINWERK_TEST_KAPUTT -eq '1') { throw 'absichtlich kaputt' }`n'diesmal heil'"
}
foreach ($name in $skripte.Keys) {
    Set-Content -Path (Join-Path $paketOrdner "test\$name") -Value $skripte[$name] -Encoding ASCII
}

$paket = [ordered]@{
    name    = 'Prüfpaket Läufertest'
    erzeugt = '2026-09-29T20:00:00'
    skripte = @(
        [ordered]@{ id = 't-ok';      titel = 'Läuft durch';    datei = 'test/ok.ps1';      argumente = @{} }
        [ordered]@{ id = 't-hinweis'; titel = 'Meldet Befund';  datei = 'test/hinweis.ps1'; argumente = @{} }
        [ordered]@{ id = 't-kaputt';  titel = 'Wirft';          datei = 'test/kaputt.ps1';  argumente = @{} }
    )
}
[System.IO.File]::WriteAllText((Join-Path $paketOrdner 'paket.json'),
    (ConvertTo-Json -Depth 5 -InputObject $paket), (New-Object System.Text.UTF8Encoding($false)))

try {
    # =========================================================================
    Write-Host ''
    Write-Host '=== 1. Einzelbericht ===' -ForegroundColor Cyan

    $a1 = Join-Path $berichte 'A-alt.html'
    $code = Laeufer 'HOST-A' @('-Berichtsdatei', $a1)
    Pruefe 'Der Laeufer endet mit 0' { $code -eq 0 } "Exitcode $code"
    Pruefe 'Der Bericht wird geschrieben' { Test-Path -Path $a1 }

    $d = Daten $a1
    $e = @($d.laeufe[0].ergebnisse)
    Pruefe 'Die Daten sind eingebettet' { $d.format -eq 1 -and @($d.laeufe).Count -eq 1 }
    Pruefe 'Der Computername kommt an' { $d.laeufe[0].computer -eq 'HOST-A' } $d.laeufe[0].computer
    Pruefe 'Der Paketname mit Umlaut kommt an' { $d.laeufe[0].paket -eq 'Prüfpaket Läufertest' } $d.laeufe[0].paket
    Pruefe 'Die drei Zustaende stimmen' {
        ($e | ForEach-Object { $_.zustand }) -join ',' -eq 'OK,HINWEIS,FEHLER'
    } (($e | ForEach-Object { $_.zustand }) -join ',')
    Pruefe 'Die Ausgabe wird mitgenommen' { $e[0].ausgabe -match 'Alles in Ordnung auf HOST-A' }

    $html = [System.IO.File]::ReadAllText($a1, [System.Text.Encoding]::UTF8)
    Pruefe '"</script>" aus einer Ausgabe bricht den Datenblock nicht auf' {
        ([regex]::Matches($html, '</script>')).Count -eq 1
    }
    Pruefe 'Der Einzelbericht hat keine Uebersichtsmatrix' { $html -notmatch 'class="matrix"' }

    # =========================================================================
    Write-Host ''
    Write-Host '=== 2. Zusammenfuehren ===' -ForegroundColor Cyan

    # Die Zeitstempel haben Sekundengenauigkeit; der neuere Lauf muss spaeter liegen.
    Start-Sleep -Milliseconds 1100
    [void](Laeufer 'HOST-B' @('-Berichtsdatei', (Join-Path $berichte 'B.html')))
    Start-Sleep -Milliseconds 1100
    [void](Laeufer 'HOST-A' @('-Berichtsdatei', (Join-Path $berichte 'A-neu.html')) -Kaputt '0')

    # Etwas, das kein AdminWerk-Bericht ist, liegt oft mit im Ordner.
    Set-Content -Path (Join-Path $berichte 'fremd.html') -Value '<html><body>fremd</body></html>' -Encoding ASCII

    $vorher = @(Get-ChildItem -Path $paketOrdner -Filter '*.html').Count
    $gesamt = Join-Path $basis 'Gesamt.html'
    $code = Laeufer 'HOST-X' @('-Zusammenfuehren', $berichte, '-Berichtsdatei', $gesamt)
    $nachher = @(Get-ChildItem -Path $paketOrdner -Filter '*.html').Count

    Pruefe 'Das Zusammenfuehren endet mit 0' { $code -eq 0 } "Exitcode $code"
    Pruefe 'Beim Zusammenfuehren wird nichts geprueft' { $nachher -eq $vorher } "$vorher -> $nachher Berichte im Paket"

    $d = Daten $gesamt
    $namen = @($d.laeufe | ForEach-Object { $_.computer }) -join ','
    Pruefe 'Je Computer ein Lauf, der fremde Bericht uebersprungen' { $namen -eq 'HOST-A,HOST-B' } $namen

    $a = @($d.laeufe | Where-Object { $_.computer -eq 'HOST-A' })[0]
    $b = @($d.laeufe | Where-Object { $_.computer -eq 'HOST-B' })[0]
    Pruefe 'Von HOST-A gilt der neuere Lauf' { @($a.ergebnisse)[2].zustand -eq 'OK' } @($a.ergebnisse)[2].zustand
    Pruefe 'HOST-B behaelt seinen Fehler' { @($b.ergebnisse)[2].zustand -eq 'FEHLER' } @($b.ergebnisse)[2].zustand

    $html = [System.IO.File]::ReadAllText($gesamt, [System.Text.Encoding]::UTF8)
    Pruefe 'Die Uebersicht hat eine Spalte je Computer' {
        $html -match 'class="matrix"' -and $html -match '>HOST-A</a></th>' -and $html -match '>HOST-B</a></th>'
    }
    Pruefe 'Der ersetzte Lauf wird erwaehnt' { $html -match 'Von 3 L&auml;ufen wurden 1 durch einen neueren' }
    Pruefe 'Unauffaellige Pruefungen sind zugeklappt, auffaellige offen' {
        $html -match '<details class="block" id="c0-0">' -and $html -match '<details class="block" id="c0-1" open>'
    }

    # =========================================================================
    Write-Host ''
    Write-Host '=== 3. Gesamtbericht erneut zusammenfuehren ===' -ForegroundColor Cyan

    $weitere = Join-Path $basis 'weitere'
    New-Item -Path $weitere -ItemType Directory | Out-Null
    [void](Laeufer 'HOST-C' @('-Berichtsdatei', (Join-Path $weitere 'C.html')))

    Copy-Item -Path $gesamt -Destination $weitere
    $gesamt2 = Join-Path $basis 'Gesamt2.html'
    $code = Laeufer 'HOST-X' @('-Zusammenfuehren', $weitere, '-Berichtsdatei', $gesamt2)
    $namen = @((Daten $gesamt2).laeufe | ForEach-Object { $_.computer }) -join ','
    Pruefe 'Ein Gesamtbericht laesst sich um neue Berichte ergaenzen' {
        $code -eq 0 -and $namen -eq 'HOST-A,HOST-B,HOST-C'
    } $namen

    $code = Laeufer 'HOST-X' @('-Zusammenfuehren', (Join-Path $basis 'gibt-es-nicht'))
    Pruefe 'Ohne lesbare Berichte endet es mit einem Fehler' { $code -ne 0 } "Exitcode $code"
}
finally {
    Remove-Item -Path $basis -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
$farbe = if ($script:Fehlgeschlagen -eq 0) { 'Green' } else { 'Red' }
Write-Host ('Bilanz: {0} bestanden, {1} fehlgeschlagen' -f $script:Bestanden, $script:Fehlgeschlagen) -ForegroundColor $farbe

if ($script:Fehlgeschlagen -eq 0) { exit 0 }
exit 1
