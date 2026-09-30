<#
.SYNOPSIS
    Bestandsaufnahme der Drucker: Zustand, Treiber, Anschluss und Freigabe.
.DESCRIPTION
    Listet je Computer alle Drucker mit Zustand, Treiber, Anschluss und Freigabe.
    Bei TCP/IP-Anschluessen stehen Adresse, Port und SNMP dabei. Mit -AnschluesseTesten
    wird zusaetzlich geprueft, ob unter der Adresse etwas antwortet - und zwar von dem
    Rechner aus, auf dem das Skript laeuft.

    Auffaellig sind Drucker, die offline sind oder einen Fehler melden (Papierstau,
    kein Papier, Klappe offen ...). Gibt es solche, endet das Skript mit Exitcode 1;
    im Pruefpaket erscheint es dann als HINWEIS. Solche Meldungen kommen von einem
    Netzwerkdrucker in der Regel nur an, wenn am Anschluss SNMP aktiv ist.

    Andere Computer werden ueber WMI mit DCOM abgefragt, WinRM ist dafuer nicht noetig.
    Virtuelle Drucker (PDF, XPS, OneNote, Fax) bleiben ohne -MitVirtuellen aussen vor.
.PARAMETER Computername
    Abzufragende Computer, etwa die Druckserver. Standard: der lokale Computer.
.PARAMETER AnschluesseTesten
    Prueft bei TCP/IP-Anschluessen, ob der Drucker auf seinem Port antwortet.
.PARAMETER MitVirtuellen
    Nimmt auch virtuelle Drucker wie "Microsoft Print to PDF" auf.
.PARAMETER CsvPfad
    Schreibt die Liste zusaetzlich als CSV (Semikolon, UTF-8).
.EXAMPLE
    .\drucker-bestand.ps1
.EXAMPLE
    .\drucker-bestand.ps1 -Computername PRINT01, PRINT02 -AnschluesseTesten -CsvPfad C:\Berichte\drucker.csv
#>
[CmdletBinding()]
param(
    [string[]]$Computername = $env:COMPUTERNAME,

    [switch]$AnschluesseTesten,

    [switch]$MitVirtuellen,

    [string]$CsvPfad
)

# Win32_Printer.PrinterStatus und .DetectedErrorState
$druckerzustand = @{
    1 = 'Sonstiges'; 2 = 'Unbekannt'; 3 = 'Bereit'; 4 = 'Druckt'
    5 = 'Waermt auf'; 6 = 'Angehalten'; 7 = 'Offline'
}
$fehlerzustand = @{
    3 = 'Wenig Papier'; 4 = 'Kein Papier'; 5 = 'Wenig Toner'; 6 = 'Kein Toner'
    7 = 'Klappe offen'; 8 = 'Papierstau'; 9 = 'Offline'; 10 = 'Wartung noetig'
    11 = 'Ausgabefach voll'
}
# Wenig Papier und wenig Toner sind Hinweise, kein Ausfall.
$nurHinweis = @(3, 5)

$virtuellMuster = 'Microsoft Print to PDF|Microsoft XPS|OneNote|Fax|Send To Microsoft'

function Get-Sitzung {
    param([string]$Computer)

    if ($Computer -eq $env:COMPUTERNAME -or $Computer -eq 'localhost' -or $Computer -eq '.') {
        return $null
    }

    # DCOM statt WSMan: Get-CimInstance -ComputerName allein ginge ueber WinRM.
    $option = New-CimSessionOption -Protocol Dcom
    New-CimSession -ComputerName $Computer -SessionOption $option -ErrorAction Stop
}

function Test-TcpPort {
    param([string]$Adresse, [int]$Port)

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $versuch = $client.BeginConnect($Adresse, $Port, $null, $null)
        if (-not $versuch.AsyncWaitHandle.WaitOne(1500)) {
            return $false
        }
        $client.EndConnect($versuch)
        $true
    }
    catch {
        $false
    }
    finally {
        $client.Close()
    }
}

Write-Host "Frage $(@($Computername).Count) Computer ab ..." -ForegroundColor Cyan

$zeilen = New-Object System.Collections.Generic.List[object]
$portGeprueft = @{}

foreach ($computer in $Computername) {
    $sitzung = $null
    try {
        $sitzung = Get-Sitzung -Computer $computer
        $ziel = @{}
        if ($sitzung) { $ziel['CimSession'] = $sitzung }

        $drucker = @(Get-CimInstance -ClassName Win32_Printer @ziel -ErrorAction Stop)

        $anschluesse = @{}
        foreach ($p in @(Get-CimInstance -ClassName Win32_TCPIPPrinterPort @ziel -ErrorAction SilentlyContinue)) {
            $anschluesse[[string]$p.Name] = $p
        }
    }
    catch {
        Write-Warning "$computer : $($_.Exception.Message)"
        continue
    }
    finally {
        if ($sitzung) { Remove-CimSession -CimSession $sitzung }
    }

    foreach ($d in $drucker) {
        $istVirtuell = ([string]$d.DriverName -match $virtuellMuster) -or ([string]$d.Name -match $virtuellMuster)
        if ($istVirtuell -and -not $MitVirtuellen) {
            continue
        }

        $probleme = New-Object System.Collections.Generic.List[string]
        $hinweise = New-Object System.Collections.Generic.List[string]

        if ($d.WorkOffline) {
            $probleme.Add('Offline geschaltet')
        }

        $status = [int]$d.PrinterStatus
        if ($status -eq 6 -or $status -eq 7) {
            $probleme.Add($druckerzustand[$status])
        }

        $fehler = [int]$d.DetectedErrorState
        if ($fehlerzustand.ContainsKey($fehler)) {
            if ($nurHinweis -contains $fehler) { $hinweise.Add($fehlerzustand[$fehler]) }
            else { $probleme.Add($fehlerzustand[$fehler]) }
        }

        $port = $anschluesse[[string]$d.PortName]
        $adresse = ''
        $snmp = ''
        if ($port) {
            $adresse = '{0}:{1}' -f $port.HostAddress, $port.PortNumber
            $snmp = if ($port.SNMPEnabled) { 'ja' } else { 'nein' }

            if ($AnschluesseTesten) {
                # Jede Adresse nur einmal - an einem Druckserver haengen oft mehrere
                # Warteschlangen am selben Geraet.
                if (-not $portGeprueft.ContainsKey($adresse)) {
                    $portGeprueft[$adresse] = Test-TcpPort -Adresse $port.HostAddress -Port $port.PortNumber
                }
                if (-not $portGeprueft[$adresse]) {
                    $probleme.Add('Anschluss antwortet nicht')
                }
            }
        }

        $probleme = @($probleme | Select-Object -Unique)
        $zustand = if ($probleme.Count -gt 0) { $probleme -join ', ' }
                   elseif ($hinweise.Count -gt 0) { $hinweise -join ', ' }
                   elseif ($druckerzustand.ContainsKey($status)) { $druckerzustand[$status] }
                   else { 'Unbekannt' }

        $freigabe = if ($d.Shared) { [string]$d.ShareName } else { '' }

        $zeilen.Add([PSCustomObject]@{
            Computer    = $computer
            Drucker     = $d.Name
            Zustand     = $zustand
            Auffaellig  = ($probleme.Count -gt 0)
            Treiber     = $d.DriverName
            Anschluss   = $d.PortName
            Adresse     = $adresse
            SNMP        = $snmp
            Freigabe    = $freigabe
            Standard    = [bool]$d.Default
        })
    }
}

# --- Ausgabe -----------------------------------------------------------------
Write-Host "`n=== Drucker ===" -ForegroundColor Cyan
if ($zeilen.Count -eq 0) {
    Write-Host 'Keine Drucker gefunden.' -ForegroundColor DarkGray
}
else {
    $zeilen | Sort-Object Computer, Drucker |
        Format-Table Computer, Drucker, Zustand, Treiber, Anschluss, Adresse, SNMP, Freigabe -AutoSize
}

$treiber = @($zeilen | ForEach-Object { $_.Treiber } | Select-Object -Unique)
$freigegeben = @($zeilen | Where-Object { $_.Freigabe })
Write-Host ("{0} Drucker, {1} davon freigegeben, {2} verschiedene Treiber." -f `
    $zeilen.Count, $freigegeben.Count, $treiber.Count)

$auffaellig = @($zeilen | Where-Object { $_.Auffaellig })

Write-Host "`n=== Auffaellig ===" -ForegroundColor Cyan
if ($auffaellig.Count -gt 0) {
    $auffaellig | Sort-Object Computer, Drucker | Format-Table Computer, Drucker, Zustand, Adresse -AutoSize
}
else {
    Write-Host 'Kein Drucker offline oder mit Fehler.' -ForegroundColor Green
}

$ohneSnmp = @($zeilen | Where-Object { $_.SNMP -eq 'nein' })
if ($ohneSnmp.Count -gt 0) {
    Write-Host ("Hinweis: {0} TCP/IP-Anschluss/-Anschluesse ohne SNMP - Papierstau und Tonerstand dieser Geraete kommen hier nicht an." -f `
        $ohneSnmp.Count) -ForegroundColor DarkGray
}

if ($CsvPfad) {
    $zeilen | Export-Csv -Path $CsvPfad -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Host "CSV-Export: $CsvPfad" -ForegroundColor Green
}

if ($auffaellig.Count -gt 0) {
    Write-Warning ("{0} Drucker offline oder mit Fehler." -f $auffaellig.Count)
    exit 1
}
