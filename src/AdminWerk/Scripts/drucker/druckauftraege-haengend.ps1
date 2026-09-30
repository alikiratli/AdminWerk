<#
.SYNOPSIS
    Findet haengende Druckauftraege und entfernt sie auf Wunsch.
.DESCRIPTION
    Listet alle Druckauftraege, die laenger als -AlterMinuten in der Warteschlange
    stehen, mit Drucker, Dokument, Besitzer, Groesse und Zustand. Ein Auftrag mit
    Fehler, der erst seit einer Minute wartet, gilt nicht als haengend - vielleicht
    legt gerade jemand Papier nach.

    WICHTIG: Das Skript laeuft standardmaessig im Testlauf und veraendert nichts.
    Erst mit -Anwenden werden die haengenden Auftraege entfernt. Mit
    -SpoolerNeustarten wird danach zusaetzlich die Druckwarteschlange neu gestartet;
    das hilft bei Auftraegen, die dauerhaft auf "Wird geloescht" stehen.

    Bleiben haengende Auftraege zurueck (Testlauf oder Fehler beim Entfernen), endet
    das Skript mit Exitcode 1. Andere Computer werden ueber WMI mit DCOM angesprochen.
.PARAMETER Computername
    Computer, deren Warteschlangen geprueft werden. Standard: der lokale Computer.
.PARAMETER AlterMinuten
    Ab diesem Alter gilt ein Auftrag als haengend. Standard: 30 Minuten.
.PARAMETER SpoolerNeustarten
    Startet nach dem Entfernen die Druckwarteschlange neu. Nur zusammen mit -Anwenden.
    Unterbricht kurz alle Druckauftraege dieses Computers.
.PARAMETER Anwenden
    Entfernt die haengenden Auftraege tatsaechlich. Ohne diesen Schalter nur Vorschau.
.EXAMPLE
    .\druckauftraege-haengend.ps1
.EXAMPLE
    .\druckauftraege-haengend.ps1 -Computername PRINT01 -AlterMinuten 60 -SpoolerNeustarten -Anwenden
#>
[CmdletBinding()]
param(
    [string[]]$Computername = $env:COMPUTERNAME,

    [ValidateRange(1, 10080)]
    [int]$AlterMinuten = 30,

    [switch]$SpoolerNeustarten,

    [switch]$Anwenden
)

# Win32_PrintJob.StatusMask. Bewusst kein [ordered]: dort waere $x[4] die fuenfte
# Stelle, nicht der Schluessel 4.
$statusBits = @{
    1 = 'Angehalten'; 2 = 'Fehler'; 4 = 'Wird geloescht'; 8 = 'Spoolt'; 16 = 'Druckt'
    32 = 'Offline'; 64 = 'Kein Papier'; 128 = 'Gedruckt'; 256 = 'Geloescht'
    512 = 'Blockiert'; 1024 = 'Eingriff noetig'; 2048 = 'Neustart'
}

function Get-Sitzung {
    param([string]$Computer)

    if ($Computer -eq $env:COMPUTERNAME -or $Computer -eq 'localhost' -or $Computer -eq '.') {
        return $null
    }

    # DCOM statt WSMan: Get-CimInstance -ComputerName allein ginge ueber WinRM.
    $option = New-CimSessionOption -Protocol Dcom
    New-CimSession -ComputerName $Computer -SessionOption $option -ErrorAction Stop
}

function Get-Statustext {
    param([uint32]$Maske)

    $teile = foreach ($bit in ($statusBits.Keys | Sort-Object)) {
        if ($Maske -band $bit) { $statusBits[$bit] }
    }
    if ($teile) { $teile -join ', ' } else { 'Wartet' }
}

$istAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($Anwenden -and -not $istAdmin) {
    Write-Warning 'Ohne Administratorrechte lassen sich nur die eigenen Auftraege entfernen.'
}

if ($SpoolerNeustarten -and -not $Anwenden) {
    Write-Host '-SpoolerNeustarten wirkt nur zusammen mit -Anwenden.' -ForegroundColor DarkGray
}

$grenze = (Get-Date).AddMinutes(-$AlterMinuten)
$uebrig = 0

foreach ($computer in $Computername) {
    Write-Host "`n=== Druckauftraege: $computer ===" -ForegroundColor Cyan

    $sitzung = $null
    try {
        $sitzung = Get-Sitzung -Computer $computer
        $ziel = @{}
        if ($sitzung) { $ziel['CimSession'] = $sitzung }

        $auftraege = @(Get-CimInstance -ClassName Win32_PrintJob @ziel -ErrorAction Stop)
        $haengend = @($auftraege | Where-Object { $_.TimeSubmitted -and $_.TimeSubmitted -lt $grenze })

        Write-Host ("{0} Auftrag/Auftraege in den Warteschlangen, {1} davon aelter als {2} Minuten." -f `
            $auftraege.Count, $haengend.Count, $AlterMinuten)

        if ($haengend.Count -eq 0) {
            continue
        }

        # Name hat die Form "Drucker, Auftragsnummer".
        $haengend | Sort-Object TimeSubmitted | ForEach-Object {
            [PSCustomObject]@{
                Drucker   = ($_.Name -split ',')[0]
                Nr        = $_.JobId
                Dokument  = $_.Document
                Besitzer  = $_.Owner
                Seit      = $_.TimeSubmitted.ToString('dd.MM. HH:mm')
                Minuten   = [int]((Get-Date) - $_.TimeSubmitted).TotalMinutes
                KB        = [math]::Round($_.Size / 1KB)
                Zustand   = Get-Statustext -Maske $_.StatusMask
            }
        } | Format-Table -AutoSize

        if (-not $Anwenden) {
            $uebrig += $haengend.Count
            continue
        }

        $entfernt = 0
        foreach ($auftrag in $haengend) {
            try {
                Remove-CimInstance -InputObject $auftrag -ErrorAction Stop
                $entfernt++
            }
            catch {
                Write-Warning ("Auftrag {0} ({1}): {2}" -f $auftrag.JobId, $auftrag.Document, $_.Exception.Message)
                $uebrig++
            }
        }
        Write-Host ("{0} Auftrag/Auftraege entfernt." -f $entfernt) -ForegroundColor Green

        if ($SpoolerNeustarten) {
            Write-Host 'Starte die Druckwarteschlange neu ...' -ForegroundColor Cyan
            $dienst = Get-CimInstance -ClassName Win32_Service -Filter "Name='Spooler'" @ziel -ErrorAction Stop
            [void](Invoke-CimMethod -InputObject $dienst -MethodName StopService)

            $frist = (Get-Date).AddSeconds(30)
            do {
                Start-Sleep -Milliseconds 500
                $dienst = Get-CimInstance -ClassName Win32_Service -Filter "Name='Spooler'" @ziel
            } while ($dienst.State -ne 'Stopped' -and (Get-Date) -lt $frist)

            [void](Invoke-CimMethod -InputObject $dienst -MethodName StartService)
            Start-Sleep -Seconds 2
            $dienst = Get-CimInstance -ClassName Win32_Service -Filter "Name='Spooler'" @ziel
            $farbe = if ($dienst.State -eq 'Running') { 'Green' } else { 'Red' }
            Write-Host ("Druckwarteschlange: {0}" -f $dienst.State) -ForegroundColor $farbe
        }
        else {
            $loeschend = @($haengend | Where-Object { $_.StatusMask -band 4 })
            if ($loeschend.Count -gt 0) {
                Write-Host 'Stehen Auftraege weiter auf "Wird geloescht", hilft -SpoolerNeustarten.' -ForegroundColor DarkGray
            }
        }
    }
    catch {
        Write-Warning "$computer : $($_.Exception.Message)"
    }
    finally {
        if ($sitzung) { Remove-CimSession -CimSession $sitzung }
    }
}

if (-not $Anwenden -and $uebrig -gt 0) {
    Write-Host "`nTESTLAUF - es wurde nichts entfernt. Zum Entfernen mit -Anwenden ausfuehren." -ForegroundColor Yellow
}

if ($uebrig -gt 0) {
    exit 1
}
