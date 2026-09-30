<#
.SYNOPSIS
    Bestand und Zustand der virtuellen Maschinen auf einem oder mehreren Hyper-V-Hosts.
.DESCRIPTION
    Listet je Host alle virtuellen Maschinen mit Zustand, Generation,
    Konfigurationsversion, Prozessoren, Arbeitsspeicher, Laufzeit, Takt
    (Heartbeat), Replikation, Stoppaktion und Anzahl der Pruefpunkte.

    Auffaellig - und damit Exitcode 1 - sind VMs in einem kritischen oder
    angehaltenen Zustand, laufende VMs, deren Takt einen Fehler oder
    Kommunikationsverlust meldet, und Replikation mit Warnung oder Fehler.
    Als Hinweis erscheinen gespeicherte VMs, laufende VMs ohne Kontakt zu den
    Integrationsdiensten und Konfigurationsversionen unter dem Standard des Hosts.

    Die Cmdlets werden mit dem Modulnamen aufgerufen (Hyper-V\Get-VM): VMware
    PowerCLI bringt ein gleichnamiges Get-VM mit.

    Andere Hosts spricht das Hyper-V-Modul ueber WinRM an; dort muss WinRM laufen.
    Ein Host, der nicht abgefragt werden kann, fuehrt ebenfalls zu Exitcode 1.
.PARAMETER Computername
    Abzufragende Hyper-V-Hosts. Standard: der lokale Computer.
.PARAMETER CsvPfad
    Schreibt die Liste zusaetzlich als CSV (Semikolon, UTF-8).
.EXAMPLE
    .\hyperv-vm-bestand.ps1
.EXAMPLE
    .\hyperv-vm-bestand.ps1 -Computername HV01, HV02 -CsvPfad C:\Berichte\vms.csv
#>
[CmdletBinding()]
param(
    [string[]]$Computername = $env:COMPUTERNAME,

    [string]$CsvPfad
)

if (-not (Get-Module -ListAvailable -Name Hyper-V)) {
    throw 'Das Modul "Hyper-V" fehlt. Bitte die Hyper-V-Verwaltungstools fuer Windows PowerShell installieren.'
}
Import-Module Hyper-V -ErrorAction Stop

function Get-Ziel {
    param([string]$Computer)

    if ($Computer -eq $env:COMPUTERNAME -or $Computer -eq 'localhost' -or $Computer -eq '.') {
        return @{}
    }
    @{ ComputerName = $Computer }
}

function Get-Laufzeit {
    param([TimeSpan]$Dauer)

    if ($Dauer.TotalSeconds -lt 1) { return '-' }
    if ($Dauer.TotalDays -ge 1) { return '{0} d {1} h' -f [int][math]::Floor($Dauer.TotalDays), $Dauer.Hours }
    '{0} h {1} min' -f $Dauer.Hours, $Dauer.Minutes
}

$zeilen = New-Object System.Collections.Generic.List[object]
$nichtErreicht = 0

foreach ($computer in $Computername) {
    $ziel = Get-Ziel -Computer $computer

    try {
        $vms = @(Hyper-V\Get-VM @ziel -ErrorAction Stop)
        $standardVersion = $null
        try {
            $standardVersion = [version](Hyper-V\Get-VMHostSupportedVersion @ziel -Default -ErrorAction Stop).Version
        }
        catch {
            # Aeltere Hosts (vor Server 2016) kennen das Cmdlet nicht.
            $standardVersion = $null
        }
    }
    catch {
        Write-Warning "$computer : $($_.Exception.Message)"
        $nichtErreicht++
        continue
    }

    foreach ($vm in $vms) {
        $probleme = New-Object System.Collections.Generic.List[string]
        $hinweise = New-Object System.Collections.Generic.List[string]

        $zustand = [string]$vm.State
        $laeuft = $zustand -eq 'Running'
        $takt = [string]$vm.Heartbeat

        if ($zustand -match 'Critical') { $probleme.Add("Zustand $zustand") }
        if ($zustand -eq 'Paused') { $probleme.Add('Angehalten') }
        if ($zustand -eq 'Saved') { $hinweise.Add('Gespeichert, laeuft nicht') }

        if ($laeuft) {
            if ($takt -eq 'Error' -or $takt -eq 'LostCommunication' -or $takt -eq 'OkApplicationsCritical') {
                $probleme.Add("Takt: $takt")
            }
            elseif ($takt -eq 'NoContact') {
                $hinweise.Add('Kein Kontakt zu den Integrationsdiensten')
            }
        }

        $replikation = [string]$vm.ReplicationHealth
        if ($replikation -eq 'Critical' -or $replikation -eq 'Warning') {
            $probleme.Add("Replikation: $replikation")
        }

        if ($standardVersion) {
            $version = $null
            if ([version]::TryParse([string]$vm.Version, [ref]$version) -and $version -lt $standardVersion) {
                $hinweise.Add(('Version {0} unter Host-Standard {1}' -f $vm.Version, $standardVersion))
            }
        }

        $pruefpunkte = @(Hyper-V\Get-VMSnapshot -VM $vm -ErrorAction SilentlyContinue).Count

        $zeilen.Add([PSCustomObject]@{
            Host         = $computer
            VM           = $vm.Name
            Zustand      = $zustand
            Gen          = $vm.Generation
            Version      = $vm.Version
            vCPU         = $vm.ProcessorCount
            StartGB      = [math]::Round($vm.MemoryStartup / 1GB, 1)
            Dynamisch    = [bool]$vm.DynamicMemoryEnabled
            ZugewiesenGB = [math]::Round($vm.MemoryAssigned / 1GB, 1)
            Laufzeit     = Get-Laufzeit -Dauer $vm.Uptime
            Takt         = if ($laeuft) { $takt } else { '-' }
            Replikation  = $replikation
            Stoppaktion  = [string]$vm.AutomaticStopAction
            Pruefpunkte  = $pruefpunkte
            Befund       = ($probleme -join '; ')
            Hinweis      = ($hinweise -join '; ')
        })
    }
}

# --- Ausgabe -----------------------------------------------------------------
Write-Host "`n=== Virtuelle Maschinen ===" -ForegroundColor Cyan
if ($zeilen.Count -eq 0) {
    Write-Host 'Keine virtuellen Maschinen gefunden.' -ForegroundColor DarkGray
}
else {
    $zeilen | Sort-Object Host, VM |
        Format-Table Host, VM, Zustand, Gen, Version, vCPU, StartGB, Dynamisch, ZugewiesenGB, Laufzeit, Takt, Pruefpunkte -AutoSize

    $laufend = @($zeilen | Where-Object { $_.Zustand -eq 'Running' })
    Write-Host ("{0} VMs, davon {1} laufend." -f $zeilen.Count, $laufend.Count)
}

$auffaellig = @($zeilen | Where-Object { $_.Befund })
$mitHinweis = @($zeilen | Where-Object { $_.Hinweis -and -not $_.Befund })

Write-Host "`n=== Auffaellig ===" -ForegroundColor Cyan
if ($auffaellig.Count -gt 0) {
    $auffaellig | Sort-Object Host, VM | Format-Table Host, VM, Befund -AutoSize -Wrap
}
else {
    Write-Host 'Keine VM in kritischem Zustand, mit Taktfehler oder gestoerter Replikation.' -ForegroundColor Green
}

if ($mitHinweis.Count -gt 0) {
    Write-Host "`n=== Hinweise ===" -ForegroundColor Cyan
    $mitHinweis | Sort-Object Host, VM | Format-Table Host, VM, Hinweis -AutoSize -Wrap
}

if ($CsvPfad) {
    $zeilen | Export-Csv -Path $CsvPfad -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Host "CSV-Export: $CsvPfad" -ForegroundColor Green
}

if ($auffaellig.Count -gt 0) {
    Write-Warning ("{0} VM(s) auffaellig." -f $auffaellig.Count)
}

# Ein Host, der nicht abgefragt werden konnte, ist kein "alles in Ordnung".
if ($nichtErreicht -gt 0) {
    Write-Warning ("{0} Computer konnte(n) nicht abgefragt werden." -f $nichtErreicht)
}

if ($auffaellig.Count -gt 0 -or $nichtErreicht -gt 0) {
    exit 1
}
