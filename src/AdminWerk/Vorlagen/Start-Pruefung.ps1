<#
.SYNOPSIS
    Fuehrt die Skripte dieses Pruefpakets aus und schreibt einen HTML-Bericht -
    oder fuehrt mehrere solcher Berichte zu einem Gesamtbericht zusammen.
.DESCRIPTION
    Liest "paket.json" neben dieser Datei, ruft jedes darin verzeichnete Skript einmal
    auf und faengt dessen vollstaendige Ausgabe ein - auch das, was die Skripte ueber
    Write-Host ausgeben. Ergebnis ist eine HTML-Datei, die sich weitergeben laesst.

    Skripte, die am System etwas aendern koennen, werden mit dem Schalter aufgerufen,
    der sie zaehmt (im Katalog als "sichererSchalter" hinterlegt). Dieses Paket
    veraendert nichts - es liest und berichtet.

    Der Bericht haelt je Skript fest, ob der Lauf durchging, wie lange er dauerte und
    was dabei herauskam. Faellt ein Skript um, laufen die uebrigen weiter.

    Jeder Bericht traegt seine Daten zusaetzlich maschinenlesbar in sich. Mit
    -Zusammenfuehren werden daraus mehrere Berichte - etwa von jedem Server einer - zu
    einem Gesamtbericht: oben eine Uebersicht Pruefung mal Computer, darunter die
    Einzelheiten je Computer. In diesem Modus wird nichts geprueft, nur gelesen.
.PARAMETER Berichtsdatei
    Wohin der Bericht geschrieben wird. Ohne Angabe neben dieses Skript, benannt nach
    Computer und Zeitpunkt; beim Zusammenfuehren in den Ordner der Berichte.
.PARAMETER Zusammenfuehren
    Berichte oder Ordner mit Berichten, die zusammengefuehrt werden sollen. Auch ein
    frueherer Gesamtbericht darf dabei sein. Gibt es von einem Computer mehrere Laeufe,
    gilt der neueste.
.PARAMETER Oeffnen
    Oeffnet den fertigen Bericht im Standardbrowser.
.EXAMPLE
    .\Start-Pruefung.ps1
.EXAMPLE
    .\Start-Pruefung.ps1 -Berichtsdatei C:\Berichte\SRV01.html -Oeffnen
.EXAMPLE
    .\Start-Pruefung.ps1 -Zusammenfuehren C:\Berichte -Oeffnen
#>
[CmdletBinding(DefaultParameterSetName = 'Pruefen')]
param(
    [string]$Berichtsdatei,

    [Parameter(Mandatory = $true, ParameterSetName = 'Zusammenfuehren')]
    [string[]]$Zusammenfuehren,

    [switch]$Oeffnen
)

$ErrorActionPreference = 'Continue'

$hier = Split-Path -Parent $MyInvocation.MyCommand.Path

# ================================================================ Hilfsmittel
function WertAnzeigen {
    param($Wert)

    if ($Wert -is [int] -or $Wert -is [long] -or $Wert -is [double] -or $Wert -is [decimal]) {
        return [string]$Wert
    }

    "'{0}'" -f $Wert
}

function ConvertTo-HtmlText {
    param([string]$Text)

    if ($null -eq $Text) { return '' }

    $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

function Get-Zustandsklasse {
    param([string]$Zustand)

    switch ($Zustand) {
        'OK'      { 'ok' }
        'HINWEIS' { 'hinweis' }
        default   { 'fehler' }
    }
}

function Get-Rechtetext {
    param($Admin)

    if ($Admin) { 'als Administrator' } else { 'als Standardbenutzer' }
}

# Die Daten stehen als JSON im Bericht selbst. Wer Berichte zusammenfuehren will,
# sammelt nur die HTML-Dateien ein, die er ohnehin hat - keine zweite Datei, die
# auf dem Weg verloren gehen kann. ConvertTo-Json maskiert <, > und & als <
# usw.; ein "</script>" in einer Skriptausgabe kann den Block also nicht beenden.
$datenMuster = '(?s)<script type="application/json" id="adminwerk-daten">(.*?)</script>'

function Read-Berichtsdaten {
    param([string]$Pfad)

    $inhalt = [System.IO.File]::ReadAllText($Pfad, [System.Text.Encoding]::UTF8)
    $treffer = [regex]::Match($inhalt, $datenMuster)
    if (-not $treffer.Success) {
        return $null
    }

    $daten = $treffer.Groups[1].Value | ConvertFrom-Json
    if ($daten.format -ne 1) {
        return $null
    }

    @($daten.laeufe)
}

function Write-Bericht {
    param(
        [object[]]$Laeufe,
        [string]$Pfad,
        # Bereits als HTML - fuer Umlaute als Entitaet, siehe unten.
        [string]$HinweisHtml = ''
    )

    # Diese Datei bleibt reines ASCII: Windows PowerShell 5.1 liest eine .ps1 ohne
    # Stueckliste als ANSI, und der Laeufer wird auf fremden Servern oft aus einer
    # Kopie gestartet, deren Kodierung niemand prueft. Sichtbare Umlaute kommen
    # deshalb als HTML-Entitaet in den Bericht.

    $stil = @'
  :root { color-scheme: light dark; }
  body { font-family: Segoe UI, system-ui, sans-serif; margin: 0; padding: 32px;
         background: #0E1217; color: #E6EDF3; line-height: 1.5; }
  h1 { font-size: 26px; margin: 0 0 4px 0; }
  h2 { font-size: 17px; margin: 0; font-weight: 600; }
  h3 { font-size: 21px; margin: 40px 0 2px 0; }
  a { color: inherit; }
  .kopf { border-bottom: 1px solid #242D39; padding-bottom: 20px; margin-bottom: 24px; }
  .gedaempft { color: #6B7A8C; font-size: 13px; }
  .warnung { color: #F0A94C; font-size: 13px; margin-top: 8px; }
  .breit { overflow-x: auto; }
  table { border-collapse: collapse; width: 100%; margin: 18px 0 30px 0; font-size: 13.5px; }
  th, td { text-align: left; padding: 8px 12px; border-bottom: 1px solid #242D39; }
  th { color: #93A1B1; font-weight: 600; }
  .matrix .zelle { text-align: center; white-space: nowrap; }
  .matrix a { text-decoration: none; }
  .block { border: 1px solid #242D39; border-radius: 8px; margin-bottom: 18px;
           background: #161C24; overflow: hidden; }
  .block > summary { padding: 14px 18px; display: flex; align-items: baseline;
                     justify-content: space-between; gap: 16px; cursor: pointer;
                     list-style: none; }
  .block > summary::-webkit-details-marker { display: none; }
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

    $mehrere = $Laeufe.Count -gt 1
    $teile = New-Object System.Collections.Generic.List[string]

    # ------------------------------------------------------------------ Kopf
    $pakete = @($Laeufe | ForEach-Object { $_.paket } | Select-Object -Unique)
    $titel = if ($pakete.Count -eq 1) { $pakete[0] } else { 'Gesamtbericht' }

    if ($mehrere) {
        $zeitpunkte = @($Laeufe | ForEach-Object { $_.zeitpunkt } | Sort-Object)
        $zeitraum = if ($zeitpunkte[0] -eq $zeitpunkte[-1]) { $zeitpunkte[0] }
                    else { '{0} bis {1}' -f $zeitpunkte[0], $zeitpunkte[-1] }
        $meta = '{0} Computer &middot; {1}' -f $Laeufe.Count, (ConvertTo-HtmlText $zeitraum)
    }
    else {
        $l = $Laeufe[0]
        $dauer = (@($l.ergebnisse) | Measure-Object -Property dauerS -Sum).Sum
        $meta = '{0} &middot; {1} &middot; {2} Skripte &middot; {3} s &middot; {4}' -f `
            (ConvertTo-HtmlText $l.computer), (ConvertTo-HtmlText $l.zeitpunkt), @($l.ergebnisse).Count,
            [math]::Round([double]$dauer, 1), (Get-Rechtetext $l.admin)
    }

    $teile.Add('<div class="kopf">')
    $teile.Add(('  <h1>{0}</h1>' -f (ConvertTo-HtmlText $titel)))
    $teile.Add(('  <div class="gedaempft">{0}</div>' -f $meta))
    if ($pakete.Count -gt 1) {
        $teile.Add(('  <div class="warnung">Die Berichte stammen aus {0} verschiedenen Paketen: {1}</div>' -f `
            $pakete.Count, (ConvertTo-HtmlText ($pakete -join ', '))))
    }
    if ($HinweisHtml) {
        $teile.Add(('  <div class="gedaempft">{0}</div>' -f $HinweisHtml))
    }
    $teile.Add('</div>')

    # ------------------------------------------------- Uebersicht (nur mehrere)
    if ($mehrere) {
        # Zeilen sind die Pruefungen in der Reihenfolge ihres ersten Auftretens,
        # erkannt an der Datei - der Titel kann sich zwischen Paketen aendern.
        $pruefungen = New-Object System.Collections.Specialized.OrderedDictionary
        foreach ($l in $Laeufe) {
            foreach ($e in @($l.ergebnisse)) {
                if (-not $pruefungen.Contains($e.datei)) { $pruefungen[$e.datei] = $e.titel }
            }
        }

        $kopfzellen = for ($li = 0; $li -lt $Laeufe.Count; $li++) {
            '<th class="zelle"><a href="#c{0}">{1}</a></th>' -f $li, (ConvertTo-HtmlText $Laeufe[$li].computer)
        }

        $teile.Add('<div class="breit"><table class="matrix">')
        $teile.Add(('  <tr><th>Pr&uuml;fung</th>{0}</tr>' -f ($kopfzellen -join '')))

        foreach ($datei in $pruefungen.Keys) {
            $zellen = for ($li = 0; $li -lt $Laeufe.Count; $li++) {
                $ergebnisse = @($Laeufe[$li].ergebnisse)
                $ei = -1
                for ($k = 0; $k -lt $ergebnisse.Count; $k++) {
                    if ($ergebnisse[$k].datei -eq $datei) { $ei = $k; break }
                }

                if ($ei -lt 0) {
                    '<td class="zelle gedaempft">&ndash;</td>'
                }
                else {
                    $z = $ergebnisse[$ei].zustand
                    '<td class="zelle"><a href="#c{0}-{1}"><span class="marke {2}">{3}</span></a></td>' -f `
                        $li, $ei, (Get-Zustandsklasse $z), $z
                }
            }
            $teile.Add(('  <tr><td>{0}</td>{1}</tr>' -f (ConvertTo-HtmlText $pruefungen[$datei]), ($zellen -join '')))
        }

        $auffaellig = for ($li = 0; $li -lt $Laeufe.Count; $li++) {
            $n = @($Laeufe[$li].ergebnisse | Where-Object { $_.zustand -ne 'OK' }).Count
            if ($n -eq 0) { '<td class="zelle gedaempft">&ndash;</td>' }
            else { '<td class="zelle">{0}</td>' -f $n }
        }
        $teile.Add(('  <tr><th>Auff&auml;llig</th>{0}</tr>' -f ($auffaellig -join '')))
        $teile.Add('</table></div>')
    }

    # ----------------------------------------------------------- Je Computer
    for ($li = 0; $li -lt $Laeufe.Count; $li++) {
        $l = $Laeufe[$li]
        $ergebnisse = @($l.ergebnisse)

        if ($mehrere) {
            $dauer = ($ergebnisse | Measure-Object -Property dauerS -Sum).Sum
            $teile.Add(('<h3 id="c{0}">{1}</h3>' -f $li, (ConvertTo-HtmlText $l.computer)))
            $teile.Add(('<div class="gedaempft">{0} &middot; {1} &middot; {2} s &middot; {3}</div>' -f `
                (ConvertTo-HtmlText $l.zeitpunkt), (ConvertTo-HtmlText $l.paket),
                [math]::Round([double]$dauer, 1), (Get-Rechtetext $l.admin)))
        }

        $teile.Add('<table>')
        $teile.Add('  <tr><th>Pr&uuml;fung</th><th>Zustand</th><th>Dauer</th></tr>')
        for ($ei = 0; $ei -lt $ergebnisse.Count; $ei++) {
            $e = $ergebnisse[$ei]
            $teile.Add(('  <tr><td><a href="#c{0}-{1}">{2}</a></td><td><span class="marke {3}">{4}</span></td><td>{5:N1} s</td></tr>' -f `
                $li, $ei, (ConvertTo-HtmlText $e.titel), (Get-Zustandsklasse $e.zustand), $e.zustand, [double]$e.dauerS))
        }
        $teile.Add('</table>')

        # Im Einzelbericht ist alles offen. Im Gesamtbericht nur das Auffaellige -
        # sonst ist die Seite bei zwanzig Servern nicht mehr zu ueberblicken.
        for ($ei = 0; $ei -lt $ergebnisse.Count; $ei++) {
            $e = $ergebnisse[$ei]
            $offen = if (-not $mehrere -or $e.zustand -ne 'OK') { ' open' } else { '' }
            $ausgabe = if ($e.ausgabe) { ([string]$e.ausgabe).TrimEnd() } else { '' }

            $teile.Add(('<details class="block" id="c{0}-{1}"{2}><summary><div><h2>{3}</h2><div class="gedaempft">{4}</div></div><span class="marke {5}">{6}</span></summary><pre>{7}</pre></details>' -f `
                $li, $ei, $offen, (ConvertTo-HtmlText $e.titel), (ConvertTo-HtmlText $e.aufruf),
                (Get-Zustandsklasse $e.zustand), $e.zustand, (ConvertTo-HtmlText $ausgabe)))
        }
    }

    $daten = ConvertTo-Json -Depth 6 -Compress -InputObject ([ordered]@{ format = 1; laeufe = @($Laeufe) })

    $seitentitel = if ($mehrere) { 'Gesamtbericht ({0} Computer)' -f $Laeufe.Count }
                   else { 'Pr&uuml;fbericht {0}' -f (ConvertTo-HtmlText $Laeufe[0].computer) }

    $html = @"
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$seitentitel</title>
<style>
$stil
</style>
</head>
<body>
$($teile -join "`n")

<p class="gedaempft">
  Erzeugt von AdminWerk. Dieses Paket liest und berichtet &ndash; ver&auml;ndernde Skripte wurden
  mit ihrem sicheren Schalter aufgerufen.
</p>
<script type="application/json" id="adminwerk-daten">$daten</script>
</body>
</html>
"@

    # UTF-8 ohne BOM: Browser lesen das Meta-Tag, und eine Stueckliste stoert manche Werkzeuge.
    $kodierung = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Pfad, $html, $kodierung)
}

# ============================================================ Zusammenfuehren
if ($PSCmdlet.ParameterSetName -eq 'Zusammenfuehren') {
    $dateien = New-Object System.Collections.Generic.List[string]
    foreach ($angabe in $Zusammenfuehren) {
        if (Test-Path -Path $angabe -PathType Container) {
            Get-ChildItem -Path $angabe -Filter '*.html' -File |
                ForEach-Object { $dateien.Add($_.FullName) }
        }
        elseif (Test-Path -Path $angabe -PathType Leaf) {
            $dateien.Add((Resolve-Path -Path $angabe).Path)
        }
        else {
            Write-Warning "Nicht gefunden: $angabe"
        }
    }

    Write-Host ''
    Write-Host 'AdminWerk - Berichte zusammenfuehren' -ForegroundColor Cyan

    $alle = New-Object System.Collections.Generic.List[object]
    foreach ($datei in $dateien) {
        try {
            $laeufe = Read-Berichtsdaten -Pfad $datei
        }
        catch {
            $laeufe = $null
        }

        if (-not $laeufe) {
            Write-Host ("  uebersprungen  {0} (kein AdminWerk-Bericht oder aelter als diese Fassung)" -f `
                (Split-Path -Leaf $datei)) -ForegroundColor DarkGray
            continue
        }

        Write-Host ("  gelesen        {0} ({1} Computer)" -f (Split-Path -Leaf $datei), $laeufe.Count)
        foreach ($l in $laeufe) { $alle.Add($l) }
    }

    # Je Computer der neueste Lauf. So laesst sich ein frueherer Gesamtbericht mit
    # neuen Einzelberichten auffrischen, ohne dass Server doppelt erscheinen.
    $neueste = @($alle |
        Group-Object -Property { ([string]$_.computer).ToUpperInvariant() } |
        ForEach-Object { $_.Group | Sort-Object -Property zeitpunkt -Descending | Select-Object -First 1 } |
        Sort-Object -Property computer)

    if ($neueste.Count -eq 0) {
        Write-Error 'Keine zusammenfuehrbaren Berichte gefunden.'
        exit 1
    }

    $ersetzt = $alle.Count - $neueste.Count
    $hinweis = ''
    $hinweisHtml = ''
    if ($ersetzt -gt 0) {
        $hinweis = 'Von {0} Laeufen wurden {1} durch einen neueren Lauf desselben Computers ersetzt.' -f `
            $alle.Count, $ersetzt
        $hinweisHtml = $hinweis.Replace('Laeufen', 'L&auml;ufen')
    }

    if (-not $Berichtsdatei) {
        $erste = $Zusammenfuehren[0]
        $ordner = if (Test-Path -Path $erste -PathType Container) { (Resolve-Path -Path $erste).Path }
                  else { Split-Path -Parent $dateien[0] }
        $Berichtsdatei = Join-Path $ordner ("Gesamtbericht_{0}.html" -f (Get-Date -Format 'yyyy-MM-dd_HHmm'))
    }

    Write-Bericht -Laeufe $neueste -Pfad $Berichtsdatei -HinweisHtml $hinweisHtml

    $mitBefund = @($neueste | Where-Object { @($_.ergebnisse | Where-Object { $_.zustand -ne 'OK' }).Count -gt 0 })
    Write-Host ''
    Write-Host ("Gesamtbericht: {0}" -f $Berichtsdatei) -ForegroundColor Green
    Write-Host ("{0} Computer, davon {1} mit Auffaelligkeiten." -f $neueste.Count, $mitBefund.Count)
    if ($hinweis) { Write-Host $hinweis -ForegroundColor DarkGray }
    Write-Host ''

    if ($Oeffnen) { Start-Process -FilePath $Berichtsdatei }
    exit 0
}

# ===================================================================== Pruefen
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

# Als Zeichenkette und sortierbar: ConvertTo-Json schreibt ein DateTime unter 5.1 als
# "\/Date(...)\/", und beim Zusammenfuehren wird nach diesem Feld sortiert.
$beginn = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

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

$ergebnisse = New-Object System.Collections.Generic.List[object]
$nummer = 0

foreach ($eintrag in $paket.skripte) {
    $nummer++
    $pfad = Join-Path $hier $eintrag.datei

    Write-Host ("[{0}/{1}] {2}" -f $nummer, $paket.skripte.Count, $eintrag.titel) -ForegroundColor Cyan

    if (-not (Test-Path -Path $pfad)) {
        Write-Host '        Datei fehlt im Paket.' -ForegroundColor Red
        $ergebnisse.Add([ordered]@{
            titel   = $eintrag.titel
            datei   = $eintrag.datei
            aufruf  = ''
            zustand = 'FEHLT'
            dauerS  = 0
            ausgabe = "Die Datei $($eintrag.datei) ist im Paket nicht enthalten."
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

    # Nur fuer die Anzeige. Zeichenketten in Anfuehrungszeichen, Zahlen ohne, Felder
    # durch Komma getrennt - mit "-f" wuerde ein Feld auf seinen ersten Wert schrumpfen.
    $anzeige = foreach ($name in ($argumente.Keys | Sort-Object)) {
        $wert = $argumente[$name]

        if ($wert -is [bool]) {
            if ($wert) { "-$name" }
        }
        elseif ($wert -is [System.Collections.IEnumerable] -and $wert -isnot [string]) {
            "-$name " + ((@($wert) | ForEach-Object { WertAnzeigen $_ }) -join ',')
        }
        else {
            "-$name " + (WertAnzeigen $wert)
        }
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

    $ergebnisse.Add([ordered]@{
        titel   = $eintrag.titel
        datei   = $eintrag.datei
        aufruf  = $aufruf
        zustand = $zustand
        dauerS  = [math]::Round($uhr.Elapsed.TotalSeconds, 1)
        ausgabe = $ausgabe
    })
}

# --------------------------------------------------------------------- Bericht
$lauf = [PSCustomObject][ordered]@{
    computer   = $env:COMPUTERNAME
    zeitpunkt  = $beginn
    admin      = [bool]$istAdmin
    paket      = [string]$paket.name
    ergebnisse = @($ergebnisse | ForEach-Object { [PSCustomObject]$_ })
}

Write-Bericht -Laeufe @($lauf) -Pfad $Berichtsdatei

$auffaellig = @($ergebnisse | Where-Object { $_.zustand -ne 'OK' }).Count

Write-Host ''
Write-Host ("Bericht: {0}" -f $Berichtsdatei) -ForegroundColor Green
if ($auffaellig -gt 0) {
    Write-Host ("{0} von {1} Pruefungen sind auffaellig." -f $auffaellig, $ergebnisse.Count) -ForegroundColor Yellow
}
Write-Host ''

if ($Oeffnen) {
    Start-Process -FilePath $Berichtsdatei
}
