<#
.SYNOPSIS
    Auslastung und Ueberbuchung eines Hyper-V-Hosts: Prozessoren, Speicher, Datentraeger, Switches.
.DESCRIPTION
    Stellt je Host gegenueber, was da ist und was die VMs beanspruchen:

      Prozessoren  - virtuelle Prozessoren der laufenden VMs gegen logische
                     Prozessoren des Hosts (Verhaeltnis vCPU:LP)
      Speicher     - zugewiesener Arbeitsspeicher der laufenden VMs, freier
                     Speicher des Hosts, und ob der Startspeicher aller VMs mit
                     automatischem Start in den Host passt. Das faellt sonst erst
                     nach dem naechsten Neustart des Hosts auf.
      Datentraeger - freier Platz auf den Laufwerken, auf denen VM-Dateien liegen
      Switches     - virtuelle Switches mit Typ und Anzahl angeschlossener Adapter

    Auffaellig - und damit Exitcode 1 - sind ein vCPU:LP-Verhaeltnis ueber
    -MaxVcpuJeKern, eine VM mit mehr vCPUs als der Host logische Prozessoren hat,
    Startspeicher der Autostart-VMs ueber 90 % des Host-Speichers und Laufwerke
    unter -MinFreiProzent, ebenso ein Host, der nicht abgefragt werden kann.
    Andere Hosts spricht das Hyper-V-Modul ueber WinRM an; ihre Laufwerke werden
    ueber WMI mit DCOM gelesen.
.PARAMETER Computername
    Abzufragende Hyper-V-Hosts. Standard: der lokale Computer.
.PARAMETER MaxVcpuJeKern
    Hoechstes vertretbares Verhaeltnis virtueller zu logischen Prozessoren. Standard: 4.
.PARAMETER MinFreiProzent
    Mindestens freier Platz auf Laufwerken mit VM-Dateien, in Prozent. Standard: 15.
.EXAMPLE
    .\hyperv-host-kapazitaet.ps1
.EXAMPLE
    .\hyperv-host-kapazitaet.ps1 -Computername HV01, HV02 -MaxVcpuJeKern 3 -MinFreiProzent 20
#>
[CmdletBinding()]
param(
    [string[]]$Computername = $env:COMPUTERNAME,

    [ValidateRange(1, 32)]
    [double]$MaxVcpuJeKern = 4,

    [ValidateRange(1, 90)]
    [int]$MinFreiProzent = 15
)

if (-not (Get-Module -ListAvailable -Name Hyper-V)) {
    throw 'Das Modul "Hyper-V" fehlt. Bitte die Hyper-V-Verwaltungstools fuer Windows PowerShell installieren.'
}
Import-Module Hyper-V -ErrorAction Stop

function Test-Lokal {
    param([string]$Computer)
    $Computer -eq $env:COMPUTERNAME -or $Computer -eq 'localhost' -or $Computer -eq '.'
}

$gesamtBefunde = 0

foreach ($computer in $Computername) {
    Write-Host "`n=== Hyper-V-Host: $computer ===" -ForegroundColor Cyan

    $ziel = @{}
    $cim = @{}
    $sitzung = $null
    $befunde = New-Object System.Collections.Generic.List[string]

    try {
        if (-not (Test-Lokal -Computer $computer)) {
            $ziel['ComputerName'] = $computer
            # DCOM statt WSMan: Get-CimInstance -ComputerName allein ginge ueber WinRM.
            $sitzung = New-CimSession -ComputerName $computer -SessionOption (New-CimSessionOption -Protocol Dcom) -ErrorAction Stop
            $cim['CimSession'] = $sitzung
        }

        $hvHost = Hyper-V\Get-VMHost @ziel -ErrorAction Stop
        $vms = @(Hyper-V\Get-VM @ziel -ErrorAction Stop)
        $bs = Get-CimInstance -ClassName Win32_OperatingSystem @cim -ErrorAction Stop
        $laufwerke = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' @cim -ErrorAction Stop)

        $laufend = @($vms | Where-Object { [string]$_.State -eq 'Running' })

        # --- Prozessoren -----------------------------------------------------
        $lp = [int]$hvHost.LogicalProcessorCount
        $vcpuLaufend = [int](($laufend | Measure-Object -Property ProcessorCount -Sum).Sum)
        $vcpuAlle = [int](($vms | Measure-Object -Property ProcessorCount -Sum).Sum)
        $verhaeltnis = if ($lp -gt 0) { [math]::Round($vcpuLaufend / $lp, 2) } else { 0 }

        Write-Host 'Prozessoren' -ForegroundColor White
        [PSCustomObject]@{
            LogischeProzessoren = $lp
            vCPU_laufend        = $vcpuLaufend
            vCPU_alle_VMs       = $vcpuAlle
            Verhaeltnis         = '{0}:1' -f $verhaeltnis
        } | Format-List

        if ($verhaeltnis -gt $MaxVcpuJeKern) {
            $befunde.Add(('vCPU-Verhaeltnis {0}:1 liegt ueber {1}:1.' -f $verhaeltnis, $MaxVcpuJeKern))
        }
        foreach ($vm in @($vms | Where-Object { $_.ProcessorCount -gt $lp })) {
            $befunde.Add(('{0} hat {1} vCPUs, der Host nur {2} logische Prozessoren.' -f $vm.Name, $vm.ProcessorCount, $lp))
        }

        # --- Speicher --------------------------------------------------------
        $kapazitaet = [double]$hvHost.MemoryCapacity
        $frei = [double]$bs.FreePhysicalMemory * 1KB
        $zugewiesen = [double](($laufend | Measure-Object -Property MemoryAssigned -Sum).Sum)
        $autostart = @($vms | Where-Object { [string]$_.AutomaticStartAction -ne 'Nothing' })
        $startbedarf = [double](($autostart | Measure-Object -Property MemoryStartup -Sum).Sum)

        Write-Host 'Arbeitsspeicher' -ForegroundColor White
        [PSCustomObject]@{
            HostGB               = [math]::Round($kapazitaet / 1GB, 1)
            FreiGB               = [math]::Round($frei / 1GB, 1)
            Zugewiesen_laufendGB = [math]::Round($zugewiesen / 1GB, 1)
            Autostart_VMs        = $autostart.Count
            Autostart_StartGB    = [math]::Round($startbedarf / 1GB, 1)
        } | Format-List

        if ($kapazitaet -gt 0 -and $startbedarf -gt 0.9 * $kapazitaet) {
            $befunde.Add(('Die {0} VMs mit automatischem Start brauchen {1} GB Startspeicher - mehr als 90 % der {2} GB des Hosts.' -f `
                $autostart.Count, [math]::Round($startbedarf / 1GB, 1), [math]::Round($kapazitaet / 1GB, 1)))
        }

        # --- Datentraeger ----------------------------------------------------
        $pfade = New-Object System.Collections.Generic.List[string]
        $pfade.Add([string]$hvHost.VirtualHardDiskPath)
        $pfade.Add([string]$hvHost.VirtualMachinePath)
        foreach ($vm in $vms) {
            $pfade.Add([string]$vm.Path)
            foreach ($platte in @(Hyper-V\Get-VMHardDiskDrive -VM $vm -ErrorAction SilentlyContinue)) {
                if ($platte.Path) { $pfade.Add([string]$platte.Path) }
            }
        }

        $buchstaben = @($pfade | Where-Object { $_ -match '^[A-Za-z]:' } |
            ForEach-Object { $_.Substring(0, 2).ToUpperInvariant() } | Select-Object -Unique)

        Write-Host 'Laufwerke mit VM-Dateien' -ForegroundColor White
        $zeilen = foreach ($lw in $laufwerke | Where-Object { $buchstaben -contains ([string]$_.DeviceID).ToUpperInvariant() }) {
            $prozent = if ($lw.Size -gt 0) { [math]::Round(100 * $lw.FreeSpace / $lw.Size, 1) } else { 0 }
            if ($prozent -lt $MinFreiProzent) {
                $befunde.Add(('Laufwerk {0} hat nur noch {1} % frei.' -f $lw.DeviceID, $prozent))
            }
            [PSCustomObject]@{
                Laufwerk = $lw.DeviceID
                GroesseGB = [math]::Round($lw.Size / 1GB, 1)
                FreiGB    = [math]::Round($lw.FreeSpace / 1GB, 1)
                FreiProzent = $prozent
            }
        }
        $zeilen | Format-Table -AutoSize

        if ($pfade | Where-Object { $_ -like '*\ClusterStorage\*' }) {
            Write-Host 'Hinweis: VM-Dateien auf Cluster Shared Volumes (C:\ClusterStorage) werden hier nicht gesondert ausgewertet.' -ForegroundColor DarkGray
        }

        # --- Switches --------------------------------------------------------
        Write-Host 'Virtuelle Switches' -ForegroundColor White
        # Eine leere Liste an -VM scheitert schon an der Parameterbindung.
        $adapter = @()
        if ($vms.Count -gt 0) {
            $adapter = @(Hyper-V\Get-VMNetworkAdapter -VM $vms -ErrorAction SilentlyContinue)
        }
        @(Hyper-V\Get-VMSwitch @ziel -ErrorAction SilentlyContinue) | ForEach-Object {
            $name = $_.Name
            [PSCustomObject]@{
                Switch  = $name
                Typ     = [string]$_.SwitchType
                Adapter = @($adapter | Where-Object { $_.SwitchName -eq $name }).Count
            }
        } | Format-Table -AutoSize

        $ohneSwitch = @($adapter | Where-Object { -not $_.SwitchName } |
            ForEach-Object { $_.VMName } | Select-Object -Unique)
        if ($ohneSwitch.Count -gt 0) {
            Write-Host ('Hinweis: Netzwerkadapter ohne Switch bei {0}.' -f ($ohneSwitch -join ', ')) -ForegroundColor DarkGray
        }
    }
    catch {
        $befunde.Add("Abfrage fehlgeschlagen: $($_.Exception.Message)")
    }
    finally {
        if ($sitzung) { Remove-CimSession -CimSession $sitzung }
    }

    if ($befunde.Count -eq 0) {
        Write-Host 'Keine Ueberbuchung, genug freier Platz.' -ForegroundColor Green
    }
    foreach ($b in $befunde) {
        Write-Warning ("{0}: {1}" -f $computer, $b)
    }
    $gesamtBefunde += $befunde.Count
}

if ($gesamtBefunde -gt 0) {
    exit 1
}
