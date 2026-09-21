<#
.SYNOPSIS
    Fuehrt die Skripte dieses Pruefpakets aus und schreibt einen HTML-Bericht.
.DESCRIPTION
    Liest "paket.json" neben dieser Datei, ruft jedes darin verzeichnete Skript einmal
    auf und faengt dessen vollstaendige Ausgabe ein - auch das, was die Skripte ueber
    Write-Host ausgeben. Ergebnis ist eine HTML-Datei, die sich weitergeben laesst.

    Skripte, die am System etwas aendern koennen, werden mit dem Schalter aufgerufen,
    der sie zaehmt (im Katalog als "sichererSchalter" hinterlegt). Dieses Paket
    veraendert nichts - es liest und berichtet.

    Der Bericht haelt je Skript fest, ob der Lauf durchging, wie lange er dauerte und
    was dabei herauskam. Faellt ein Skript um, laufen die uebrigen weiter.
.PARAMETER Berichtsdatei
    Wohin der Bericht geschrieben wird. Ohne Angabe neben dieses Skript, benannt nach
    Computer und Zeitpunkt.
.PARAMETER Oeffnen
    Oeffnet den fertigen Bericht im Standardbrowser.
.EXAMPLE
    .\Start-Pruefung.ps1
.EXAMPLE
    .\Start-Pruefung.ps1 -Berichtsdatei C:\Berichte\SRV01.html -Oeffnen
#>
[CmdletBinding()]
param(
    [string]$Berichtsdatei,
    [switch]$Oeffnen
)

$ErrorActionPreference = 'Continue'

$hier = Split-Path -Parent $MyInvocation.MyCommand.Path
$paketDatei = Join-Path $hier 'paket.json'

if (-not (Test-Path -Path $paketDatei)) {
    Write-Error "paket.json nicht gefunden neben $hier"
    exit 1
}

$paket = Get-Content -Path $paketDatei -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not $Berichtsdatei) {
    $stempel = Get-Date -Format 'yyyy-MM-dd_HHmm'
    $Berichtsdatei = Join-Path $hier ("Pruefbericht_{0}_{1}.html" -f $env:COMPUTERNAME, $stempel)
}

$istAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host ''
Write-Host ("AdminWerk - {0}" -f $paket.name) -ForegroundColor Cyan
Write-Host ("Computer   : {0}" -f $env:COMPUTERNAME)
Write-Host ("Skripte    : {0}" -f $paket.skripte.Count)
Write-Host ("Rechte     : {0}" -f $(if ($istAdmin) { 'Administrator' } else { 'Standardbenutzer' }))
Write-Host ''

$brauchtAdmin = @($paket.skripte | Where-Object { $_.adminRechte })
if ($brauchtAdmin.Count -gt 0 -and -not $istAdmin) {
    Write-Warning ("{0} Skript(e) brauchen Administratorrechte. Sie laufen trotzdem, " -f $brauchtAdmin.Count +
        "melden aber vermutlich nur Teilergebnisse. Fuer einen vollstaendigen Bericht " +
        "die Sitzung als Administrator starten.")
    Write-Host ''
}

function ConvertTo-HtmlText {
    param([string]$Text)

    if ($null -eq $Text) { return '' }

    $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
}

$ergebnisse = New-Object System.Collections.Generic.List[object]
$nummer = 0

foreach ($eintrag in $paket.skripte) {
    $nummer++
    $pfad = Join-Path $hier $eintrag.datei

    Write-Host ("[{0}/{1}] {2}" -f $nummer, $paket.skripte.Count, $eintrag.titel) -ForegroundColor Cyan

    if (-not (Test-Path -Path $pfad)) {
        Write-Host '        Datei fehlt im Paket.' -ForegroundColor Red
        $ergebnisse.Add([PSCustomObject]@{
            Titel     = $eintrag.titel
            Datei     = $eintrag.datei
            Aufruf    = ''
            Zustand   = 'FEHLT'
            DauerS    = 0
            Ausgabe   = "Die Datei $($eintrag.datei) ist im Paket nicht enthalten."
        })
        continue
    }

    # Der sichere Schalter kommt aus dem Katalog und ist dort gegen den Quelltext
    # geprueft. Er ist der Grund, warum ein Auditlauf nichts anfasst.
    #
    # Als Hashtabelle splatten, nicht als Feld: ein gesplattetes Feld verteilt
    # PowerShell der Reihe nach auf die Stellungsparameter. '-NurPruefen' landete
    # dann als Dienstname im ersten Parameter statt als Schalter.
    $argumente = @{}
    if ($eintrag.argumente) {
        foreach ($paar in $eintrag.argumente.PSObject.Properties) {
            $argumente[$paar.Name] = $paar.Value
        }
    }

    $anzeige = foreach ($name in ($argumente.Keys | Sort-Object)) {
        if ($argumente[$name] -is [bool] -and $argumente[$name]) { "-$name" }
        else { "-$name '{0}'" -f $argumente[$name] }
    }

    $aufruf = ".\{0}{1}" -f ($eintrag.datei -replace '/', '\'), `
        $(if ($argumente.Count -gt 0) { ' ' + ($anzeige -join ' ') } else { '' })

    if ($argumente.Count -gt 0) {
        Write-Host ("        Aufruf: {0}" -f $aufruf) -ForegroundColor DarkGray
    }

    # $LASTEXITCODE ist klebrig: Skripte, die nicht selbst "exit" aufrufen, lassen den
    # Wert des vorigen stehen. Ohne Zuruecksetzen erbt jede weitere Pruefung den
    # Befund der ersten.
    $global:LASTEXITCODE = 0

    $uhr = [System.Diagnostics.Stopwatch]::StartNew()
    $zustand = 'OK'
    $ausgabe = ''

    try {
        $ausgabe = & $pfad @argumente *>&1 | Out-String
    }
    catch {
        $zustand = 'FEHLER'
        $ausgabe = $_ | Out-String
    }

    $uhr.Stop()

    # Ein Skript darf mit einem Rueckgabewert ungleich 0 auf einen Befund hinweisen -
    # das ist kein Absturz, sondern sein Ergebnis.
    if ($zustand -eq 'OK' -and $LASTEXITCODE -ne 0) {
        $zustand = 'HINWEIS'
    }

    $farbe = switch ($zustand) {
        'OK'      { 'Green' }
        'HINWEIS' { 'Yellow' }
        default   { 'Red' }
    }
    Write-Host ("        {0} in {1:N1} s" -f $zustand, $uhr.Elapsed.TotalSeconds) -ForegroundColor $farbe

    $ergebnisse.Add([PSCustomObject]@{
        Titel   = $eintrag.titel
        Datei   = $eintrag.datei
        Aufruf  = $aufruf
        Zustand = $zustand
        DauerS  = [math]::Round($uhr.Elapsed.TotalSeconds, 1)
        Ausgabe = $ausgabe
    })
}

# --------------------------------------------------------------------- Bericht
$stil = @'
  :root { color-scheme: light dark; }
  body { font-family: Segoe UI, system-ui, sans-serif; margin: 0; padding: 32px;
         background: #0E1217; color: #E6EDF3; line-height: 1.5; }
  h1 { font-size: 26px; margin: 0 0 4px 0; }
  h2 { font-size: 17px; margin: 0; font-weight: 600; }
  .kopf { border-bottom: 1px solid #242D39; padding-bottom: 20px; margin-bottom: 24px; }
  .gedaempft { color: #6B7A8C; font-size: 13px; }
  table { border-collapse: collapse; width: 100%; margin: 18px 0 30px 0; font-size: 13.5px; }
  th, td { text-align: left; padding: 8px 12px; border-bottom: 1px solid #242D39; }
  th { color: #93A1B1; font-weight: 600; }
  .block { border: 1px solid #242D39; border-radius: 8px; margin-bottom: 18px;
           background: #161C24; overflow: hidden; }
  .blockkopf { padding: 14px 18px; display: flex; align-items: baseline;
               justify-content: space-between; gap: 16px; }
  pre { margin: 0; padding: 16px 18px; background: #0B0F14; overflow-x: auto;
        font-family: Cascadia Mono, Consolas, monospace; font-size: 12.5px;
        white-space: pre-wrap; word-break: break-word; border-top: 1px solid #242D39; }
  .marke { font-size: 11.5px; font-weight: 700; letter-spacing: .04em;
           padding: 3px 9px; border-radius: 4px; white-space: nowrap; }
  .ok { background: #16321F; color: #4FD18B; }
  .hinweis { background: #3A2C13; color: #F0A94C; }
  .fehler { background: #3A1A1A; color: #FF6B6B; }
  @media (prefers-color-scheme: light) {
    body { background: #FFFFFF; color: #1A1F26; }
    .kopf, th, td, .block, pre { border-color: #E2E6EB; }
    .block { background: #F7F8FA; }
    pre { background: #FFFFFF; }
    .gedaempft, th { color: #5B6673; }
  }
'@

$zeilen = foreach ($e in $ergebnisse) {
    $klasse = switch ($e.Zustand) {
        'OK'      { 'ok' }
        'HINWEIS' { 'hinweis' }
        default   { 'fehler' }
    }
    '<tr><td>{0}</td><td><span class="marke {1}">{2}</span></td><td>{3:N1} s</td></tr>' -f `
        (ConvertTo-HtmlText $e.Titel), $klasse, $e.Zustand, $e.DauerS
}

$bloecke = foreach ($e in $ergebnisse) {
    $klasse = switch ($e.Zustand) {
        'OK'      { 'ok' }
        'HINWEIS' { 'hinweis' }
        default   { 'fehler' }
    }

    $kopfzeile = '<div class="blockkopf"><div><h2>{0}</h2><div class="gedaempft">{1}</div></div>' -f `
        (ConvertTo-HtmlText $e.Titel), (ConvertTo-HtmlText $e.Aufruf)
    $kopfzeile += '<span class="marke {0}">{1}</span></div>' -f $klasse, $e.Zustand

    '<div class="block">{0}<pre>{1}</pre></div>' -f $kopfzeile, (ConvertTo-HtmlText $e.Ausgabe.TrimEnd())
}

$gesamtdauer = ($ergebnisse | Measure-Object -Property DauerS -Sum).Sum
$auffaellig = @($ergebnisse | Where-Object { $_.Zustand -ne 'OK' }).Count

$html = @"
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Pruefbericht $($env:COMPUTERNAME)</title>
<style>
$stil
</style>
</head>
<body>
<div class="kopf">
  <h1>$(ConvertTo-HtmlText $paket.name)</h1>
  <div class="gedaempft">
    $(ConvertTo-HtmlText $env:COMPUTERNAME) &middot;
    $(Get-Date -Format 'dd.MM.yyyy HH:mm') &middot;
    $($ergebnisse.Count) Skripte &middot;
    $([math]::Round($gesamtdauer, 1)) s &middot;
    $(if ($istAdmin) { 'als Administrator' } else { 'als Standardbenutzer' })
  </div>
</div>

<table>
  <tr><th>Pruefung</th><th>Zustand</th><th>Dauer</th></tr>
  $($zeilen -join "`n  ")
</table>

$($bloecke -join "`n")

<p class="gedaempft">
  Erzeugt von AdminWerk. Dieses Paket liest und berichtet - veraendernde Skripte wurden
  mit ihrem sicheren Schalter aufgerufen.
</p>
</body>
</html>
"@

# UTF-8 ohne BOM: Browser lesen das Meta-Tag, und eine Stueckliste stoert manche Werkzeuge.
$kodierung = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Berichtsdatei, $html, $kodierung)

Write-Host ''
Write-Host ("Bericht: {0}" -f $Berichtsdatei) -ForegroundColor Green
if ($auffaellig -gt 0) {
    Write-Host ("{0} von {1} Pruefungen sind auffaellig." -f $auffaellig, $ergebnisse.Count) -ForegroundColor Yellow
}
Write-Host ''

if ($Oeffnen) {
    Start-Process -FilePath $Berichtsdatei
}
