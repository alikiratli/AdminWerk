<#
.SYNOPSIS
    Bedient die Anwendung ueber die UI-Automation und prueft die Oberflaeche.
.DESCRIPTION
    Startet AdminWerk und klickt sich durch: Kategorien, Suche, Parameterassistent
    (Textfeld, Zahl, Schalter, Auswahlliste), Zwischenablage, Favoriten und
    "In PowerShell oeffnen". Jeder Schritt meldet OK oder FEHLER, am Ende steht eine
    Bilanz. Rueckgabewert 0, wenn alles bestanden ist, sonst 1.

    Die Favoritendatei des Benutzers wird vorher gesichert und hinterher
    wiederhergestellt - der Test darf keine Spuren hinterlassen.

    Braucht eine angemeldete Sitzung mit Bildschirm; ohne Desktop laeuft keine
    UI-Automation.

    Diese Datei ist als UTF-8 mit BOM gespeichert. Sie vergleicht Beschriftungen der
    Oberflaeche und enthaelt daher Umlaute; ohne BOM liest Windows PowerShell 5.1 sie
    als ANSI, und die Vergleiche schlagen fehl.
.PARAMETER Anwendung
    Pfad zur AdminWerk.exe. Ohne Angabe wird der Debug-, sonst der Release-Build
    neben dem Projekt gesucht.
.PARAMETER Offenlassen
    Laesst die Anwendung nach dem Test geoeffnet.
.EXAMPLE
    .\tools\oberflaechentest.ps1
.EXAMPLE
    .\tools\oberflaechentest.ps1 -Anwendung C:\AdminWerk\AdminWerk.exe -Offenlassen
#>
[CmdletBinding()]
param(
    [string]$Anwendung,
    [switch]$Offenlassen
)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

# --- Anwendung finden -------------------------------------------------------
if (-not $Anwendung) {
    $wurzel = Split-Path -Parent $PSScriptRoot
    foreach ($stand in 'Debug', 'Release') {
        $kandidat = Join-Path $wurzel "src\AdminWerk\bin\$stand\net8.0-windows\AdminWerk.exe"
        if (Test-Path -Path $kandidat) {
            $Anwendung = $kandidat
            break
        }
    }
}

if (-not $Anwendung -or -not (Test-Path -Path $Anwendung)) {
    Write-Error 'AdminWerk.exe nicht gefunden. Bitte zuerst bauen oder -Anwendung angeben.'
    exit 1
}

# --- Bilanz -----------------------------------------------------------------
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

# --- Favoriten sichern ------------------------------------------------------
$favoritenDatei = Join-Path $env:AppData 'AdminWerk\favoriten.json'
$favoritenSicherung = $null
if (Test-Path -Path $favoritenDatei) {
    $favoritenSicherung = Get-Content -Path $favoritenDatei -Raw -Encoding UTF8
}

# --- Start ------------------------------------------------------------------
Get-Process -Name AdminWerk -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600

$proz = Start-Process -FilePath $Anwendung -PassThru
Start-Sleep -Seconds 5
$proz = Get-Process -Id $proz.Id -ErrorAction SilentlyContinue

if (-not $proz -or $proz.MainWindowHandle -eq 0) {
    Write-Host 'Die Anwendung hat kein Fenster geoeffnet - Abbruch.' -ForegroundColor Red
    exit 1
}

$fenster = [System.Windows.Automation.AutomationElement]::FromHandle($proz.MainWindowHandle)

# --- Hilfsmittel ------------------------------------------------------------
$Text    = [System.Windows.Automation.ControlType]::Text
$Edit    = [System.Windows.Automation.ControlType]::Edit
$Knopf   = [System.Windows.Automation.ControlType]::Button
$Haken   = [System.Windows.Automation.ControlType]::CheckBox
$Eintrag = [System.Windows.Automation.ControlType]::ListItem
$Liste   = [System.Windows.Automation.ControlType]::List
$Auswahl = [System.Windows.Automation.ControlType]::ComboBox

function NameGleich {
    param([string]$Name)
    New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, $Name)
}

function TypGleich {
    param($Typ)
    New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $Typ)
}

function Suche {
    param([string]$Name, $Typ)

    if ($null -eq $Typ) {
        return $fenster.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (NameGleich $Name))
    }

    $fenster.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.AndCondition((NameGleich $Name), (TypGleich $Typ))))
}

function AlleVomTyp {
    param($Typ)
    @($fenster.FindAll([System.Windows.Automation.TreeScope]::Descendants, (TypGleich $Typ)))
}

function Wert {
    param($Element)
    $Element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
}

function Setze {
    param($Element, [string]$Text)
    $Element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($Text)
    Start-Sleep -Milliseconds 500
}

function Waehle {
    param($Element)
    $Element.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    Start-Sleep -Milliseconds 700
}

function Druecke {
    param($Element)
    $Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Start-Sleep -Milliseconds 700
}

# Der Expander behaelt seinen Zustand ueber den Skriptwechsel hinweg. Blind zu
# schalten wuerde ihn beim zweiten Mal wieder zuklappen.
function KlappeAuf {
    param($Element)

    $muster = $Element.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
    if ($muster.Current.ToggleState -ne [System.Windows.Automation.ToggleState]::On) {
        $muster.Toggle()
        Start-Sleep -Milliseconds 900
    }
}

function Parameterkopf {
    AlleVomTyp $Knopf | Where-Object { $_.Current.Name -match '^Parameter \(\d+\)$' } | Select-Object -First 1
}

$kategorien = @('Alle Skripte', 'Favoriten', 'System', 'Netzwerk', 'Konten', 'Security')

# ============================================================================
Write-Host ''
Write-Host '=== 1. Start und Grundgeruest ===' -ForegroundColor Cyan

Pruefe 'Fenster offen' { $proz.MainWindowTitle -like 'AdminWerk*' } $proz.MainWindowTitle
Pruefe 'Beide Listen sind benannt' { (AlleVomTyp $Liste).Count -eq 2 }
Pruefe 'Suchfeld ist benannt' { $null -ne (Suche 'Skripte durchsuchen' $Edit) }

foreach ($k in $kategorien) {
    Pruefe "Kategorie '$k' erreichbar" { $null -ne (Suche $k $Eintrag) }.GetNewClosure()
}

# ============================================================================
Write-Host ''
Write-Host '=== 2. Kategorien durchgehen ===' -ForegroundColor Cyan

$zaehler = @{}
foreach ($k in $kategorien) {
    Waehle (Suche $k $Eintrag)
    $treffer = (AlleVomTyp $Text |
        Where-Object { $_.Current.Name -match '^\d+ Skript' } |
        Select-Object -First 1).Current.Name
    $zaehler[$k] = $treffer
    Pruefe "'$k' zeigt eine Trefferzahl" { $treffer -match '^\d+ Skript' }.GetNewClosure() $treffer
}

Waehle (Suche 'Alle Skripte' $Eintrag)

Pruefe 'Die Gesamtansicht zeigt alle Skripte' {
    $summe = 0
    foreach ($k in 'System', 'Netzwerk', 'Konten', 'Security') {
        $summe += [int]($zaehler[$k] -replace '\D', '')
    }
    $summe -eq [int]($zaehler['Alle Skripte'] -replace '\D', '')
} ("$($zaehler['Alle Skripte']) gesamt")

# ============================================================================
Write-Host ''
Write-Host '=== 3. Suche ===' -ForegroundColor Cyan

Setze (Suche 'Skripte durchsuchen' $Edit) 'BitLocker'
Start-Sleep -Milliseconds 800
$gefunden = @(AlleVomTyp $Eintrag | Where-Object { $_.Current.Name -notin $kategorien })
Pruefe 'Eine Suche filtert die Liste' { $gefunden.Count -ge 1 -and $gefunden.Count -lt 10 } "$($gefunden.Count) Treffer"

Setze (Suche 'Skripte durchsuchen' $Edit) 'gibtesnichtxyz'
Start-Sleep -Milliseconds 800
Pruefe 'Eine leere Trefferliste zeigt einen Hinweis' {
    $null -ne (AlleVomTyp $Text | Where-Object { $_.Current.Name -match 'Keine Skripte gefunden' })
}

# ============================================================================
Write-Host ''
Write-Host '=== 4. Parameterassistent: Textfeld, Zahl, Schalter ===' -ForegroundColor Cyan

Setze (Suche 'Skripte durchsuchen' $Edit) 'AD-Benutzer aus CSV'
Start-Sleep -Milliseconds 800
Waehle (AlleVomTyp $Eintrag | Where-Object { $_.Current.Name -like 'AD-Benutzer*' } | Select-Object -First 1)

$kopf = Parameterkopf
Pruefe 'Der Parameterbereich ist vorhanden' { $null -ne $kopf } $(if ($kopf) { $kopf.Current.Name })
KlappeAuf $kopf

Pruefe 'Ein leerer Pflichtparameter wird angemahnt' {
    $null -ne (AlleVomTyp $Text | Where-Object { $_.Current.Name -match 'Noch ohne Wert' })
} (AlleVomTyp $Text | Where-Object { $_.Current.Name -match 'Noch ohne Wert' } | ForEach-Object { $_.Current.Name })

Pruefe 'Pflichtparameter sind in der Beschriftung markiert' { $null -ne (Suche 'CsvDatei *' $Text) }

$zeile = Suche 'Erzeugte Aufrufzeile' $Edit
Pruefe 'Ohne Eingaben steht nur der Dateiname' {
    (Wert $zeile) -eq '.\ad-benutzer-anlegen.ps1'
} (Wert $zeile)

# Die Beschriftung heisst "CsvDatei *", das Eingabefeld traegt den reinen Namen.
Setze (Suche 'CsvDatei' $Edit) 'C:\Onboarding\neu.csv'
Setze (Suche 'KennwortLaenge' $Edit) '20'
(Suche 'Anwenden' $Haken).GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
Start-Sleep -Milliseconds 700

$erwartet = ".\ad-benutzer-anlegen.ps1 -CsvDatei 'C:\Onboarding\neu.csv' -Anwenden -KennwortLaenge 20"
Pruefe 'Text, Schalter und Zahl stehen in der Aufrufzeile' { (Wert $zeile) -eq $erwartet } (Wert $zeile)
Pruefe 'Die Mahnung verschwindet mit der Eingabe' {
    $null -eq (AlleVomTyp $Text | Where-Object { $_.Current.Name -match 'Noch ohne Wert' })
}

# ============================================================================
Write-Host ''
Write-Host '=== 5. Kopieren und Leeren ===' -ForegroundColor Cyan

Druecke (Suche 'Aufrufzeile kopieren' $Knopf)
Pruefe 'Die Aufrufzeile liegt in der Zwischenablage' { (Get-Clipboard) -eq $erwartet } (Get-Clipboard)

Druecke (Suche 'Eingaben leeren' $Knopf)
Pruefe 'Eingaben leeren setzt alles zurueck' { (Wert $zeile) -eq '.\ad-benutzer-anlegen.ps1' } (Wert $zeile)

# ============================================================================
Write-Host ''
Write-Host '=== 6. Parameterassistent: Auswahlliste ===' -ForegroundColor Cyan

Setze (Suche 'Skripte durchsuchen' $Edit) 'Dienststatus'
Start-Sleep -Milliseconds 800
Waehle (AlleVomTyp $Eintrag | Where-Object { $_.Current.Name -like 'Dienststatus*' } | Select-Object -First 1)
KlappeAuf (Parameterkopf)

$kombi = Suche 'Sollzustand' $Auswahl
Pruefe 'ValidateSet wird zur Auswahlliste' { $null -ne $kombi }

if ($kombi) {
    $kombi.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
    Start-Sleep -Milliseconds 600

    $optionen = @($kombi.FindAll([System.Windows.Automation.TreeScope]::Descendants, (TypGleich $Eintrag)))
    $namen = ($optionen | ForEach-Object { $_.Current.Name }) -join ','
    Pruefe 'Die Auswahlliste enthaelt beide Werte' { $namen -eq 'Running,Stopped' } $namen

    $stopped = $optionen | Where-Object { $_.Current.Name -eq 'Stopped' }
    if ($stopped) {
        Waehle $stopped
        $zeile2 = Suche 'Erzeugte Aufrufzeile' $Edit
        Pruefe 'Die Auswahl landet in der Aufrufzeile' {
            (Wert $zeile2) -match "-Sollzustand 'Stopped'"
        } (Wert $zeile2)
    }
}

# ============================================================================
Write-Host ''
Write-Host '=== 7. Favoriten ===' -ForegroundColor Cyan

$stern = AlleVomTyp $Knopf |
    Where-Object { $_.Current.Name -like 'Als Favorit merken: Dienststatus*' } | Select-Object -First 1
Pruefe 'Die Sternschaltflaeche traegt den Skripttitel' { $null -ne $stern } $(if ($stern) { $stern.Current.Name })

if ($stern) {
    Druecke $stern
    Start-Sleep -Milliseconds 800

    Pruefe 'Der Favorit wird gespeichert' {
        (Get-Content -Path $favoritenDatei -Raw -Encoding UTF8) -match 'dienste'
    }

    $zurueck = AlleVomTyp $Knopf |
        Where-Object { $_.Current.Name -like 'Favorit entfernen: Dienststatus*' } | Select-Object -First 1
    Pruefe 'Der Stern wechselt seine Beschriftung' { $null -ne $zurueck } $(if ($zurueck) { $zurueck.Current.Name })
    if ($zurueck) { Druecke $zurueck }
}

# ============================================================================
Write-Host ''
Write-Host '=== 8. Skript in die Zwischenablage ===' -ForegroundColor Cyan

Setze (Suche 'Skripte durchsuchen' $Edit) 'TCP-Ports'
Start-Sleep -Milliseconds 700
Waehle (AlleVomTyp $Eintrag | Where-Object { $_.Current.Name -like 'TCP-Ports*' } | Select-Object -First 1)
Druecke (Suche 'In Zwischenablage kopieren' $Knopf)

$inhalt = Get-Clipboard -Raw
Pruefe 'Das vollstaendige Skript wird kopiert' {
    $inhalt -match '\.SYNOPSIS' -and $inhalt -match 'param\(' -and $inhalt.Length -gt 500
} "$($inhalt.Length) Zeichen"

# ============================================================================
Write-Host ''
Write-Host '=== 9. In PowerShell oeffnen ===' -ForegroundColor Cyan

$vorher = @(Get-Process -Name powershell -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
Druecke (Suche 'In PowerShell öffnen' $Knopf)
Start-Sleep -Seconds 3
$neu = @(Get-Process -Name powershell -ErrorAction SilentlyContinue | Where-Object { $_.Id -notin $vorher })

Pruefe 'Genau eine Sitzung wird geoeffnet' { $neu.Count -eq 1 } "$($neu.Count) Prozess(e)"

if ($neu.Count -eq 1) {
    $befehlszeile = (Get-CimInstance Win32_Process -Filter "ProcessId = $($neu[0].Id)").CommandLine

    Pruefe 'Die Sitzung startet im Skriptverzeichnis' {
        $befehlszeile -match 'Set-Location -LiteralPath .*Scripts\\netzwerk'
    }
    Pruefe 'Der Aufruf steht als Text in einem Write-Host' {
        $befehlszeile -like "*Write-Host '  .\port-test.ps1*"
    }
    # Zweimal hiesse: einmal ausgegeben und einmal gestartet.
    Pruefe 'Der Aufruf kommt genau einmal vor' {
        ([regex]::Matches($befehlszeile, [regex]::Escape('.\port-test.ps1'))).Count -eq 1
    }
    Pruefe 'Der Hinweis auf die Nichtausfuehrung steht darin' {
        $befehlszeile -match 'Es wurde nichts ausgef'
    }

    Stop-Process -Id $neu[0].Id -Force
}

# ============================================================================
Write-Host ''
Write-Host '=== 10. Zustand der Anwendung ===' -ForegroundColor Cyan

$proz.Refresh()
Pruefe 'Kein Absturz waehrend des Tests' { -not $proz.HasExited }
Pruefe 'Das Fenster reagiert weiterhin' { $proz.Responding }

# --- Aufraeumen -------------------------------------------------------------
if ($null -ne $favoritenSicherung) {
    Set-Content -Path $favoritenDatei -Value $favoritenSicherung -Encoding UTF8 -NoNewline
}

if (-not $Offenlassen) {
    Get-Process -Name AdminWerk -ErrorAction SilentlyContinue | Stop-Process -Force
}

Write-Host ''
$farbe = if ($script:Fehlgeschlagen -eq 0) { 'Green' } else { 'Red' }
Write-Host ('Bilanz: {0} bestanden, {1} fehlgeschlagen' -f $script:Bestanden, $script:Fehlgeschlagen) -ForegroundColor $farbe

if ($script:Fehlgeschlagen -eq 0) { exit 0 }
exit 1
