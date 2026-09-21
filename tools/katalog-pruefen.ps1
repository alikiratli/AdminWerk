<#
.SYNOPSIS
    Prueft den Skriptkatalog: Syntax, Katalogabgleich und Pflichtangaben.
.DESCRIPTION
    Drei Pruefungen in einem Durchlauf:

      1. Syntax  - jede .ps1 wird mit dem PowerShell-Parser eingelesen. Laeuft das
                   Skript unter Windows PowerShell 5.1, ist das zugleich der
                   Kompatibilitaetstest: 7er-Syntax faellt hier durch.
      2. Abgleich - jeder Katalogeintrag zeigt auf eine vorhandene Datei, und jede
                   Datei auf der Platte ist im Katalog verzeichnet.
      3. Angaben - Pflichtfelder gefuellt, Bezeichner eindeutig, Kategorie bekannt,
                   kommentarbasierte Hilfe (.SYNOPSIS) vorhanden.

    Rueckgabewert 0, wenn alles sauber ist, sonst 1. Damit als CI-Schritt verwendbar.
.EXAMPLE
    .\tools\katalog-pruefen.ps1
.EXAMPLE
    powershell.exe -File .\tools\katalog-pruefen.ps1 -Skriptverzeichnis 'C:\AdminWerk\Scripts'
#>
[CmdletBinding()]
param(
    [string]$Skriptverzeichnis
)

$ErrorActionPreference = 'Stop'

if (-not $Skriptverzeichnis) {
    $wurzel = Split-Path -Parent $PSScriptRoot
    $Skriptverzeichnis = Join-Path $wurzel 'src\AdminWerk\Scripts'
}

if (-not (Test-Path -Path $Skriptverzeichnis)) {
    Write-Error "Skriptverzeichnis nicht gefunden: $Skriptverzeichnis"
    exit 1
}

$katalogPfad = Join-Path $Skriptverzeichnis 'catalog.json'
if (-not (Test-Path -Path $katalogPfad)) {
    Write-Error "catalog.json nicht gefunden: $katalogPfad"
    exit 1
}

Write-Host "AdminWerk - Katalogpruefung"
Write-Host "Verzeichnis: $Skriptverzeichnis"
Write-Host ("PowerShell:  {0}" -f $PSVersionTable.PSVersion)
Write-Host ''

$beanstandungen = New-Object System.Collections.Generic.List[string]

# ----------------------------------------------------------------- 1. Syntax
# Schluesselwoerter, die 5.1 in Klammern nicht als Ausdruck, sondern als Befehlsnamen
# liest: 'Write-Host -Farbe (if ...)' wirft zur Laufzeit "if wurde nicht als Name eines
# Cmdlet erkannt". Der Parser sieht das nicht, der Exitcode auch nicht - daher hier.
$schluesselwoerter = @('if', 'elseif', 'switch', 'while', 'for', 'foreach', 'do', 'until', 'try')

# Operatoren, deren rechte Seite ein regulaerer Ausdruck ist.
$musterOperatoren = @(
    'match', 'notmatch', 'imatch', 'inotmatch', 'cmatch', 'cnotmatch',
    'replace', 'ireplace', 'creplace',
    'split', 'isplit', 'csplit')

$dateien = Get-ChildItem -Path $Skriptverzeichnis -Filter '*.ps1' -Recurse -File
foreach ($datei in $dateien) {
    $marken = $null
    $fehler = $null
    $baum = [System.Management.Automation.Language.Parser]::ParseFile(
        $datei.FullName, [ref]$marken, [ref]$fehler)

    if ($fehler -and $fehler.Count -gt 0) {
        foreach ($f in $fehler) {
            $beanstandungen.Add((
                "Syntax: {0}:{1} - {2}" -f $datei.Name, $f.Extent.StartLineNumber, $f.Message))
        }
        continue
    }

    # Regex-Literale uebersetzen. Weder der Parser noch PSScriptAnalyzer sehen, ob ein
    # Muster gueltig ist - ein vergessener doppelter Backslash faellt erst zur Laufzeit
    # auf, und dann mittendrin im Bericht.
    $vergleiche = $baum.FindAll(
        { param($knoten) $knoten -is [System.Management.Automation.Language.BinaryExpressionAst] }, $true)
    foreach ($vergleich in $vergleiche) {
        if ($musterOperatoren -notcontains $vergleich.Operator.ToString().ToLower()) { continue }

        # Bei -replace mit Ersatztext steht rechts ein Feld aus Muster und Ersatz.
        # Das Muster ist dessen erstes Element.
        $rechts = $vergleich.Right
        if ($rechts -is [System.Management.Automation.Language.ArrayLiteralAst]) {
            $rechts = $rechts.Elements[0]
        }

        if ($rechts -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { continue }

        try {
            [void][regex]::new($rechts.Value)
        }
        catch {
            $beanstandungen.Add((
                "Ungueltiges Muster: {0}:{1} - '{2}'" -f `
                    $datei.Name, $vergleich.Extent.StartLineNumber, $rechts.Value))
        }
    }

    $befehle = $baum.FindAll(
        { param($knoten) $knoten -is [System.Management.Automation.Language.CommandAst] }, $true)
    foreach ($befehl in $befehle) {
        $name = $befehl.GetCommandName()
        if ($name -and ($schluesselwoerter -contains $name.ToLower())) {
            $beanstandungen.Add((
                "Nicht 5.1-tauglich: {0}:{1} - '{2}' steht als Befehl, nicht als Ausdruck: {3}" -f `
                    $datei.Name, $befehl.Extent.StartLineNumber, $name,
                    ($befehl.Extent.Text -replace '\s+', ' ')))
        }
    }
}
Write-Host ("[1/3] Syntax      - {0} Skripte geparst und auf 5.1-Tauglichkeit geprueft" -f $dateien.Count)

# -------------------------------------------------------------- 2. Abgleich
$katalog = Get-Content -Path $katalogPfad -Raw -Encoding UTF8 | ConvertFrom-Json

$kategorieIds = @($katalog.kategorien | ForEach-Object { $_.id })
$verzeichnet = New-Object System.Collections.Generic.HashSet[string]

foreach ($eintrag in $katalog.skripte) {
    # Im Katalog stehen Pfade mit Schraegstrich; auf der Platte zaehlt der Backslash.
    $relativ = $eintrag.datei -replace '/', '\'
    $vollPfad = Join-Path $Skriptverzeichnis $relativ

    if (Test-Path -Path $vollPfad) {
        [void]$verzeichnet.Add((Resolve-Path $vollPfad).Path)
    }
    else {
        $beanstandungen.Add(("Fehlende Datei: '{0}' (Eintrag '{1}')" -f $eintrag.datei, $eintrag.id))
    }
}

foreach ($datei in $dateien) {
    if (-not $verzeichnet.Contains($datei.FullName)) {
        $relativ = $datei.FullName.Substring($Skriptverzeichnis.Length).TrimStart('\')
        $beanstandungen.Add("Verwaiste Datei, nicht im Katalog: '$relativ'")
    }
}
Write-Host ("[2/3] Abgleich    - {0} Katalogeintraege gegen {1} Dateien" -f $katalog.skripte.Count, $dateien.Count)

# --------------------------------------------------------------- 3. Angaben
$gesehen = New-Object System.Collections.Generic.HashSet[string]
foreach ($eintrag in $katalog.skripte) {
    $kennung = $eintrag.id

    if (-not $gesehen.Add($kennung)) {
        $beanstandungen.Add("Doppelter Bezeichner: '$kennung'")
    }

    foreach ($feld in @('id', 'kategorie', 'titel', 'beschreibung', 'datei', 'voraussetzung')) {
        if ([string]::IsNullOrWhiteSpace($eintrag.$feld)) {
            $beanstandungen.Add("Leeres Pflichtfeld '$feld' bei '$kennung'")
        }
    }

    if ($kategorieIds -notcontains $eintrag.kategorie) {
        $beanstandungen.Add(("Unbekannte Kategorie '{0}' bei '{1}'" -f $eintrag.kategorie, $kennung))
    }

    if (-not $eintrag.tags -or $eintrag.tags.Count -eq 0) {
        $beanstandungen.Add("Keine Schlagwoerter bei '$kennung'")
    }

    # Die Detailansicht lebt von der kommentarbasierten Hilfe - sie muss da sein.
    $vollPfad = Join-Path $Skriptverzeichnis ($eintrag.datei -replace '/', '\')
    if (-not (Test-Path -Path $vollPfad)) { continue }

    $inhalt = Get-Content -Path $vollPfad -Raw -Encoding UTF8
    if ($inhalt -notmatch '(?m)^\s*\.SYNOPSIS\s*$') {
        $beanstandungen.Add(("Keine .SYNOPSIS in '{0}'" -f $eintrag.datei))
    }

    # Kennzeichnung veraendernder Skripte gegen den Quelltext pruefen. Auf dieses
    # Feld verlaesst sich das Pruefpaket, wenn es den Laeufer baut - stimmt es nicht,
    # startet ein Auditlauf Dienste oder repariert Systemdateien.
    $t = $null
    $e = $null
    $baum = [System.Management.Automation.Language.Parser]::ParseFile($vollPfad, [ref]$t, [ref]$e)
    $parameterNamen = @()
    if ($baum.ParamBlock) {
        $parameterNamen = @($baum.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    }

    $hatAnwenden = $parameterNamen -contains 'Anwenden'
    $hatNurPruefen = $parameterNamen -contains 'NurPruefen'
    $sollVeraendert = $hatAnwenden -or $hatNurPruefen

    if ($sollVeraendert -and -not $eintrag.veraendert) {
        $beanstandungen.Add(
            ("'{0}' hat -{1} im param()-Block, ist aber nicht als veraendert gekennzeichnet" -f `
                $kennung, $(if ($hatAnwenden) { 'Anwenden' } else { 'NurPruefen' })))
    }

    if ($eintrag.veraendert -and -not $sollVeraendert) {
        $beanstandungen.Add(
            ("'{0}' ist als veraendert gekennzeichnet, hat aber weder -Anwenden noch -NurPruefen" -f $kennung))
    }

    # Ein Skript, das ohne Zutun aendert, braucht den Schalter, der es zaehmt.
    $erwarteterSchalter = if ($hatNurPruefen) { '-NurPruefen' } else { '' }
    if ($sollVeraendert -and [string]$eintrag.sichererSchalter -ne $erwarteterSchalter) {
        $beanstandungen.Add(
            ("'{0}': sichererSchalter ist '{1}', erwartet '{2}'" -f `
                $kennung, [string]$eintrag.sichererSchalter, $erwarteterSchalter))
    }
}
Write-Host ("[3/3] Angaben     - {0} Eintraege geprueft" -f $katalog.skripte.Count)
Write-Host ''

# ---------------------------------------------------------------- Ergebnis
if ($beanstandungen.Count -eq 0) {
    Write-Host "Ergebnis: keine Beanstandungen." -ForegroundColor Green
    exit 0
}

Write-Host ("Ergebnis: {0} Beanstandung(en)" -f $beanstandungen.Count) -ForegroundColor Red
foreach ($b in $beanstandungen) {
    Write-Host "  - $b" -ForegroundColor Red
}
exit 1
