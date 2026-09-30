<#
.SYNOPSIS
    Findet alte Pruefpunkte und verwaiste differenzierende Datentraeger auf Hyper-V-Hosts.
.DESCRIPTION
    Pruefpunkte sind kein Backup. Solange einer besteht, schreibt die VM in eine
    differenzierende Datei (.avhdx), die stetig waechst und jeden Lesezugriff
    verlangsamt. Das Skript listet je VM alle Pruefpunkte mit Alter und rechnet
    nach, wie viel Platz die Kette der differenzierenden Datentraeger belegt.

    Auffaellig - und damit Exitcode 1 - sind:
      * Pruefpunkte, die aelter als -AlterTage sind
      * VMs, die auf einer .avhdx laufen, obwohl es keinen Pruefpunkt mehr gibt.
        Das bleibt meist nach einer misslungenen Zusammenfuehrung zurueck und
        faellt sonst erst auf, wenn der Datentraeger voll ist.

    Andere Hosts spricht das Hyper-V-Modul ueber WinRM an; ein Host, der nicht
    abgefragt werden kann, fuehrt ebenfalls zu Exitcode 1.

    Das Skript liest nur. Pruefpunkte loescht man im Hyper-V-Manager oder mit
    Remove-VMSnapshot; die Zusammenfuehrung laeuft danach im Hintergrund und
    belastet den Datentraeger.
.PARAMETER Computername
    Abzufragende Hyper-V-Hosts. Standard: der lokale Computer.
.PARAMETER AlterTage
    Ab diesem Alter gilt ein Pruefpunkt als vergessen. Standard: 7 Tage.
.PARAMETER CsvPfad
    Schreibt die Liste der Pruefpunkte zusaetzlich als CSV (Semikolon, UTF-8).
.EXAMPLE
    .\hyperv-pruefpunkte.ps1
.EXAMPLE
    .\hyperv-pruefpunkte.ps1 -Computername HV01, HV02 -AlterTage 3
#>
[CmdletBinding()]
param(
    [string[]]$Computername = $env:COMPUTERNAME,

    [ValidateRange(1, 3650)]
    [int]$AlterTage = 7,

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

# Folgt ParentPath bis zur Basis und summiert die differenzierenden Dateien.
function Get-Kette {
    param([string]$Pfad, [hashtable]$Ziel)

    $glieder = 0
    $bytes = [long]0
    $aktuell = $Pfad

    # Begrenzt, falls eine Kette durch einen Fehler auf sich selbst zeigt.
    for ($i = 0; $i -lt 64 -and $aktuell; $i++) {
        $vhd = Hyper-V\Get-VHD -Path $aktuell @Ziel -ErrorAction Stop
        if ([string]$vhd.VhdType -ne 'Differencing') { break }

        $glieder++
        $bytes += [long]$vhd.FileSize
        $aktuell = $vhd.ParentPath
    }

    [PSCustomObject]@{ Glieder = $glieder; Bytes = $bytes }
}

# Frisch nach dem Pruefpunkt ist die .avhdx wenige MB gross - "0 GB" hiesse "nichts".
function Get-Groesse {
    param([long]$Bytes)

    if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
    '{0:N0} MB' -f ($Bytes / 1MB)
}

$jetzt = Get-Date
$liste = New-Object System.Collections.Generic.List[object]
$jeVm = New-Object System.Collections.Generic.List[object]
$nichtErreicht = 0

foreach ($computer in $Computername) {
    $ziel = Get-Ziel -Computer $computer

    try {
        $vms = @(Hyper-V\Get-VM @ziel -ErrorAction Stop)
    }
    catch {
        Write-Warning "$computer : $($_.Exception.Message)"
        $nichtErreicht++
        continue
    }

    foreach ($vm in $vms) {
        $pruefpunkte = @(Hyper-V\Get-VMSnapshot -VM $vm -ErrorAction SilentlyContinue | Sort-Object CreationTime)

        foreach ($p in $pruefpunkte) {
            $alter = [int][math]::Floor(($jetzt - $p.CreationTime).TotalDays)
            $liste.Add([PSCustomObject]@{
                Host       = $computer
                VM         = $vm.Name
                Pruefpunkt = $p.Name
                Typ        = [string]$p.SnapshotType
                Erstellt   = $p.CreationTime.ToString('dd.MM.yyyy HH:mm')
                AlterTage  = $alter
                Zu_alt     = ($alter -gt $AlterTage)
            })
        }

        $glieder = 0
        $bytes = [long]0
        $aufAvhdx = New-Object System.Collections.Generic.List[string]
        foreach ($platte in @(Hyper-V\Get-VMHardDiskDrive -VM $vm -ErrorAction SilentlyContinue)) {
            if (-not $platte.Path) { continue }
            if ($platte.Path -like '*.avhdx' -or $platte.Path -like '*.avhd') {
                $aufAvhdx.Add((Split-Path -Leaf $platte.Path))
            }
            try {
                $kette = Get-Kette -Pfad $platte.Path -Ziel $ziel
                $glieder += $kette.Glieder
                $bytes += $kette.Bytes
            }
            catch {
                Write-Warning ("{0}/{1}: {2}" -f $computer, $vm.Name, $_.Exception.Message)
            }
        }

        $befund = ''
        if ($aufAvhdx.Count -gt 0 -and $pruefpunkte.Count -eq 0) {
            $befund = 'Laeuft auf differenzierendem Datentraeger ohne Pruefpunkt: ' + ($aufAvhdx -join ', ')
        }

        $automatisch = ''
        if ($vm.PSObject.Properties['AutomaticCheckpointsEnabled']) {
            $automatisch = if ($vm.AutomaticCheckpointsEnabled) { 'ja' } else { 'nein' }
        }

        if ($pruefpunkte.Count -gt 0 -or $befund) {
            $aeltester = if ($pruefpunkte.Count -gt 0) {
                [int][math]::Floor(($jetzt - $pruefpunkte[0].CreationTime).TotalDays)
            } else { $null }

            $jeVm.Add([PSCustomObject]@{
                Host           = $computer
                VM             = $vm.Name
                Pruefpunkte    = $pruefpunkte.Count
                AeltesterTage  = $aeltester
                Kettenglieder  = $glieder
                Differenz      = Get-Groesse -Bytes $bytes
                Automatisch    = $automatisch
                Befund         = $befund
            })
        }
    }
}

# --- Ausgabe -----------------------------------------------------------------
Write-Host "`n=== Pruefpunkte ===" -ForegroundColor Cyan
if ($liste.Count -eq 0) {
    Write-Host 'Keine Pruefpunkte vorhanden.' -ForegroundColor Green
}
else {
    $liste | Sort-Object Host, VM, AlterTage | Format-Table Host, VM, Pruefpunkt, Typ, Erstellt, AlterTage -AutoSize
}

if ($jeVm.Count -gt 0) {
    Write-Host "=== Je VM ===" -ForegroundColor Cyan
    $jeVm | Sort-Object Host, VM |
        Format-Table Host, VM, Pruefpunkte, AeltesterTage, Kettenglieder, Differenz, Automatisch -AutoSize
}

$zuAlt = @($liste | Where-Object { $_.Zu_alt })
$verwaist = @($jeVm | Where-Object { $_.Befund })

Write-Host "=== Auffaellig ===" -ForegroundColor Cyan
if ($zuAlt.Count -eq 0 -and $verwaist.Count -eq 0) {
    Write-Host ("Kein Pruefpunkt aelter als {0} Tage, keine verwaiste .avhdx." -f $AlterTage) -ForegroundColor Green
}
foreach ($p in $zuAlt) {
    Write-Warning ("{0}/{1}: Pruefpunkt '{2}' ist {3} Tage alt." -f $p.Host, $p.VM, $p.Pruefpunkt, $p.AlterTage)
}
foreach ($v in $verwaist) {
    Write-Warning ("{0}/{1}: {2}" -f $v.Host, $v.VM, $v.Befund)
}

$automatische = @($jeVm | Where-Object { $_.Automatisch -eq 'ja' })
if ($automatische.Count -gt 0) {
    Write-Host ("Hinweis: Bei {0} VM(s) legt Hyper-V bei jedem Start selbst einen Pruefpunkt an (Automatische Pruefpunkte)." -f `
        $automatische.Count) -ForegroundColor DarkGray
}

if ($CsvPfad) {
    $liste | Export-Csv -Path $CsvPfad -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Host "CSV-Export: $CsvPfad" -ForegroundColor Green
}

# Ein Host, der nicht abgefragt werden konnte, ist kein "alles in Ordnung".
if ($nichtErreicht -gt 0) {
    Write-Warning ("{0} Computer konnte(n) nicht abgefragt werden." -f $nichtErreicht)
}

if ($zuAlt.Count -gt 0 -or $verwaist.Count -gt 0 -or $nichtErreicht -gt 0) {
    exit 1
}
