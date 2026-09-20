<#
.SYNOPSIS
    Prueft einen Windows-DNS-Server auf Dienststatus, Zonen und Weiterleitungen.
.DESCRIPTION
    Fuer Domaenencontroller und dedizierte DNS-Server: Dienstzustand, konfigurierte
    Zonen, Weiterleitungen sowie eine Stichprobe der Namensaufloesung.
.NOTES
    Benoetigt das Feature "DNS-Server-Tools" (Modul DnsServer).
.EXAMPLE
    .\dns-server-pruefen.ps1 -Server dc01
#>
[CmdletBinding()]
param(
    [string]$Server = $env:COMPUTERNAME,
    [string[]]$Testnamen = @('www.microsoft.com')
)

if (-not (Get-Module -ListAvailable -Name DnsServer)) {
    throw 'Das Modul "DnsServer" ist nicht verfuegbar. Bitte die DNS-Server-Tools (RSAT) installieren.'
}

Import-Module DnsServer -ErrorAction Stop

Write-Host "`n=== DNS-Dienst ===" -ForegroundColor Cyan
Get-Service -Name DNS -ComputerName $Server -ErrorAction SilentlyContinue |
    Select-Object MachineName, Name, DisplayName, Status, StartType | Format-Table -AutoSize

Write-Host '=== Zonen ===' -ForegroundColor Cyan
Get-DnsServerZone -ComputerName $Server |
    Select-Object ZoneName, ZoneType, IsDsIntegrated, IsReverseLookupZone, DynamicUpdate |
    Format-Table -AutoSize

Write-Host '=== Weiterleitungen ===' -ForegroundColor Cyan
$weiterleitung = Get-DnsServerForwarder -ComputerName $Server -ErrorAction SilentlyContinue
if ($weiterleitung.IPAddress) {
    $weiterleitung | Select-Object @{ Name = 'Weiterleitung'; Expression = { $_.IPAddress -join ', ' } },
        UseRootHint, Timeout | Format-List
}
else {
    Write-Host 'Keine Weiterleitungen konfiguriert (nur Stammhinweise).' -ForegroundColor Yellow
}

Write-Host '=== Stichprobe Namensaufloesung ===' -ForegroundColor Cyan
foreach ($name in $Testnamen) {
    try {
        $antwort = Resolve-DnsName -Name $name -Server $Server -ErrorAction Stop | Select-Object -First 1
        Write-Host ('[ OK ] {0,-32} -> {1}' -f $name, $antwort.IPAddress) -ForegroundColor Green
    }
    catch {
        Write-Host ('[FEHL] {0,-32} -> keine Antwort' -f $name) -ForegroundColor Red
    }
}
