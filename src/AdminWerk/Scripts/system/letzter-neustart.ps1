<#
.SYNOPSIS
    Zeigt den Zeitpunkt des letzten Systemstarts und die Betriebsdauer (Uptime).
.DESCRIPTION
    Nuetzlich fuer Patch-Nachweise: Systeme mit sehr langer Laufzeit haben haeufig
    ausstehende Updates, die erst nach einem Neustart wirksam werden.
.EXAMPLE
    .\letzter-neustart.ps1 -Computername SRV01, SRV02
#>
[CmdletBinding()]
param(
    [string[]]$Computername = $env:COMPUTERNAME,

    # Ab wie vielen Tagen Laufzeit ein Neustart empfohlen wird.
    [int]$WarnungAbTagen = 30
)

foreach ($computer in $Computername) {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $computer -ErrorAction Stop
        $laufzeit = (Get-Date) - $os.LastBootUpTime

        [PSCustomObject]@{
            Computer       = $os.CSName
            Betriebssystem = $os.Caption
            LetzterStart   = $os.LastBootUpTime
            LaufzeitTage   = [math]::Round($laufzeit.TotalDays, 1)
            Laufzeit       = '{0}d {1}h {2}m' -f $laufzeit.Days, $laufzeit.Hours, $laufzeit.Minutes
            Empfehlung     = if ($laufzeit.TotalDays -gt $WarnungAbTagen) { 'Neustart empfohlen' } else { 'OK' }
        }
    }
    catch {
        Write-Warning "$computer ist nicht erreichbar: $($_.Exception.Message)"
    }
}
