<#
.SYNOPSIS
    Erfasst die Hardware- und Systemdaten eines oder mehrerer Computer.
.DESCRIPTION
    Liefert Seriennummer, Modell, CPU, Arbeitsspeicher, Datentraeger, BIOS-Version,
    Windows-Version sowie die aktive Netzwerkkonfiguration - ideal als Grundlage
    fuer die Asset-Dokumentation.
.EXAMPLE
    .\hardware-inventar.ps1 -Computername SRV01, SRV02 -CsvPfad C:\Berichte\hardware.csv
#>
[CmdletBinding()]
param(
    [string[]]$Computername = $env:COMPUTERNAME,
    [string]$CsvPfad
)

$inventar = foreach ($computer in $Computername) {
    try {
        $system    = Get-CimInstance Win32_ComputerSystem  -ComputerName $computer -ErrorAction Stop
        $bios      = Get-CimInstance Win32_BIOS            -ComputerName $computer -ErrorAction Stop
        $os        = Get-CimInstance Win32_OperatingSystem -ComputerName $computer -ErrorAction Stop
        $prozessor = Get-CimInstance Win32_Processor       -ComputerName $computer -ErrorAction Stop | Select-Object -First 1

        $datentraeger = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 3' -ComputerName $computer |
            ForEach-Object { '{0} {1} GB' -f $_.DeviceID, [math]::Round($_.Size / 1GB) }

        $adapter = Get-CimInstance Win32_NetworkAdapterConfiguration -ComputerName $computer |
            Where-Object { $_.IPEnabled } | Select-Object -First 1

        [PSCustomObject]@{
            Computer       = $system.Name
            Hersteller     = $system.Manufacturer
            Modell         = $system.Model
            Seriennummer   = $bios.SerialNumber
            BiosVersion    = ($bios.SMBIOSBIOSVersion)
            Prozessor      = $prozessor.Name.Trim()
            Kerne          = $prozessor.NumberOfCores
            LogischeKerne  = $prozessor.NumberOfLogicalProcessors
            ArbeitsspeicherGB = [math]::Round($system.TotalPhysicalMemory / 1GB, 1)
            Datentraeger   = $datentraeger -join ' | '
            Betriebssystem = $os.Caption
            OsVersion      = $os.Version
            Architektur    = $os.OSArchitecture
            IPAdresse      = ($adapter.IPAddress | Where-Object { $_ -notmatch ':' }) -join ', '
            MacAdresse     = $adapter.MACAddress
            Domaene        = $system.Domain
            LetzterStart   = $os.LastBootUpTime
        }
    }
    catch {
        Write-Warning "$computer : $($_.Exception.Message)"
    }
}

$inventar | Format-List

if ($CsvPfad) {
    $inventar | Export-Csv -Path $CsvPfad -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Host "CSV-Export: $CsvPfad" -ForegroundColor Green
}
