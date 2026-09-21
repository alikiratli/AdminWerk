<#
.SYNOPSIS
    Waehlt in der laufenden Anwendung jedes Skript einmal aus und prueft den Assistenten.
.DESCRIPTION
    Geht die Gesamtansicht Eintrag fuer Eintrag durch. Fuer jedes Skript wird geprueft,
    ob Parameterkopf und Aufrufzeile zusammenpassen und ob die Aufrufzeile die erwartete
    Form hat. So faellt auf, wenn der Parameterdienst an einem einzelnen param()-Block
    scheitert - der Katalog waechst, der Test waechst mit.

    Am Ende steht, wie viele Skripte Parameter haben und ob die Anwendung den Durchlauf
    ueberstanden hat. Rueckgabewert 0 ohne Auffaelligkeiten, sonst 1.

    Braucht eine angemeldete Sitzung mit Bildschirm; ohne Desktop laeuft keine
    UI-Automation.
.PARAMETER Anwendung
    Pfad zur AdminWerk.exe. Ohne Angabe wird der Debug-, sonst der Release-Build
    neben dem Projekt gesucht.
.PARAMETER Offenlassen
    Laesst die Anwendung nach dem Durchlauf geoeffnet.
.EXAMPLE
    .\tools\alle-skripte-durchgehen.ps1
#>
[CmdletBinding()]
param(
    [string]$Anwendung,
    [switch]$Offenlassen
)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

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

$Edit    = [System.Windows.Automation.ControlType]::Edit
$Knopf   = [System.Windows.Automation.ControlType]::Button
$Eintrag = [System.Windows.Automation.ControlType]::ListItem

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
    $fenster.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.AndCondition((NameGleich $Name), (TypGleich $Typ))))
}

# Suche leeren und in die Gesamtansicht wechseln
(Suche 'Skripte durchsuchen' $Edit).GetCurrentPattern(
    [System.Windows.Automation.ValuePattern]::Pattern).SetValue('')
Start-Sleep -Milliseconds 800

$fenster.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (NameGleich 'Alle Skripte')).
    GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
Start-Sleep -Milliseconds 900

$skriptliste = $fenster.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
    (NameGleich 'Skripte der gewaehlten Kategorie'))

if (-not $skriptliste) {
    Write-Host 'Die Skriptliste wurde nicht gefunden - Abbruch.' -ForegroundColor Red
    exit 1
}

# Die Liste ist virtualisiert: FindAll sieht nur die sichtbaren Eintraege, deshalb
# laeuft der Durchgang ueber den ItemContainer.
$behaelter = $skriptliste.GetCurrentPattern([System.Windows.Automation.ItemContainerPattern]::Pattern)

$geprueft = 0
$mitParameter = 0
$ohneParameter = 0
$probleme = New-Object System.Collections.Generic.List[string]

$element = $null
while ($true) {
    $element = $behaelter.FindItemByProperty($element,
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $Eintrag)
    if ($null -eq $element) { break }

    $name = $element.Current.Name

    try {
        $element.GetCurrentPattern([System.Windows.Automation.VirtualizedItemPattern]::Pattern).Realize()
    }
    catch {
        Write-Verbose "Kein VirtualizedItem-Muster bei '$name' - bereits eingeblendet."
    }

    $element.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    Start-Sleep -Milliseconds 260
    $geprueft++

    $kopf = @($fenster.FindAll([System.Windows.Automation.TreeScope]::Descendants, (TypGleich $Knopf)) |
        Where-Object { $_.Current.Name -match '^Parameter \(\d+\)$' })[0]

    # Der Bereich ist zugeklappt voreingestellt; zugeklappt steht sein Inhalt gar nicht
    # im Baum der UI-Automation. Also vor jeder Pruefung aufklappen.
    if ($kopf) {
        $schalter = $kopf.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        if ($schalter.Current.ToggleState -ne [System.Windows.Automation.ToggleState]::On) {
            $schalter.Toggle()
            Start-Sleep -Milliseconds 400
        }
    }

    $zeile = Suche 'Erzeugte Aufrufzeile' $Edit

    if ($null -eq $zeile) {
        $ohneParameter++
        if ($kopf) {
            $probleme.Add(("{0}: Kopf '{1}', aber keine Aufrufzeile" -f $name, $kopf.Current.Name))
        }
        continue
    }

    $mitParameter++

    if (-not $kopf) {
        $probleme.Add(("{0}: Aufrufzeile ohne Parameterkopf" -f $name))
    }

    $wert = $zeile.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
    if ($wert -notmatch '^\.\\[\w\-]+\.ps1$') {
        $probleme.Add(("{0}: unerwartete Aufrufzeile '{1}'" -f $name, $wert))
    }
}

$proz.Refresh()
$laeuft = -not $proz.HasExited
$reagiert = $proz.Responding

if (-not $Offenlassen) {
    Get-Process -Name AdminWerk -ErrorAction SilentlyContinue | Stop-Process -Force
}

Write-Host ''
Write-Host ('Durchlaufene Skripte : {0}' -f $geprueft)
Write-Host ('  mit Parametern     : {0}' -f $mitParameter)
Write-Host ('  ohne Parameter     : {0}' -f $ohneParameter)
Write-Host ('Anwendung laeuft     : {0}' -f $laeuft)
Write-Host ('Fenster reagiert     : {0}' -f $reagiert)
Write-Host ''

if ($geprueft -eq 0) {
    Write-Host 'Kein einziges Skript erreicht - der Durchgang hat nicht funktioniert.' -ForegroundColor Red
    exit 1
}

if ($probleme.Count -eq 0 -and $laeuft -and $reagiert) {
    Write-Host 'Keine Auffaelligkeiten.' -ForegroundColor Green
    exit 0
}

if (-not $laeuft) { Write-Host 'Die Anwendung hat den Durchlauf nicht ueberstanden.' -ForegroundColor Red }

if ($probleme.Count -gt 0) {
    Write-Host ('{0} Auffaelligkeit(en):' -f $probleme.Count) -ForegroundColor Red
    foreach ($p in $probleme) {
        Write-Host "  - $p" -ForegroundColor Red
    }
}

exit 1
