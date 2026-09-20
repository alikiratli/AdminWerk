<#
.SYNOPSIS
    Zeigt Patchstand, ausstehende Updates und die zuletzt installierten Hotfixes.
.DESCRIPTION
    Nutzt das COM-Objekt Microsoft.Update.Session und benoetigt damit kein
    Zusatzmodul. Ergaenzend werden die letzten installierten Updates und ein
    eventuell ausstehender Neustart ausgewiesen.
.EXAMPLE
    .\windows-update-status.ps1
#>
[CmdletBinding()]
param(
    [int]$LetzteHotfixes = 10
)

Write-Host "`n=== Patchstand: $env:COMPUTERNAME ===`n" -ForegroundColor Cyan

# --- Zuletzt installierte Updates -------------------------------------------
$hotfixes = Get-HotFix -ErrorAction SilentlyContinue |
    Sort-Object InstalledOn -Descending |
    Select-Object -First $LetzteHotfixes HotFixID, Description, InstalledOn, InstalledBy

if ($hotfixes) {
    Write-Host 'Zuletzt installierte Updates:' -ForegroundColor White
    $hotfixes | Format-Table -AutoSize

    $letztes = ($hotfixes | Select-Object -First 1).InstalledOn
    if ($letztes) {
        $tage = [math]::Round(((Get-Date) - $letztes).TotalDays)
        $farbe = if ($tage -gt 45) { 'Yellow' } else { 'Green' }
        Write-Host "Letztes Update vor $tage Tagen installiert." -ForegroundColor $farbe
    }
}

# --- Ausstehende Updates ueber die Windows-Update-Schnittstelle --------------
Write-Host "`nSuche nach ausstehenden Updates ..." -ForegroundColor White

try {
    $sitzung = New-Object -ComObject Microsoft.Update.Session
    $sucher  = $sitzung.CreateUpdateSearcher()
    $treffer = $sucher.Search('IsInstalled=0 and IsHidden=0')

    if ($treffer.Updates.Count -eq 0) {
        Write-Host 'Keine ausstehenden Updates gefunden.' -ForegroundColor Green
    }
    else {
        $ausstehend = foreach ($update in $treffer.Updates) {
            [PSCustomObject]@{
                Titel        = $update.Title
                Schweregrad  = if ($update.MsrcSeverity) { $update.MsrcSeverity } else { 'ohne Einstufung' }
                GroesseMB    = [math]::Round($update.MaxDownloadSize / 1MB, 1)
                Sicherheit   = [bool]($update.Categories | Where-Object { $_.Name -match 'Sicherheit|Security' })
            }
        }

        $ausstehend | Sort-Object Schweregrad, Titel | Format-Table -AutoSize -Wrap
        Write-Warning "$($treffer.Updates.Count) Updates stehen aus."
    }
}
catch {
    Write-Warning "Windows-Update-Abfrage nicht moeglich: $($_.Exception.Message)"
}

# --- Ausstehender Neustart ---------------------------------------------------
$neustart = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
            (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')

if ($neustart) {
    Write-Warning 'Ein Neustart ist erforderlich, damit Updates wirksam werden.'
}
