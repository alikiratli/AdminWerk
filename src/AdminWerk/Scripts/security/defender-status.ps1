<#
.SYNOPSIS
    Zeigt den vollstaendigen Status von Microsoft Defender Antivirus.
.DESCRIPTION
    Prueft Echtzeitschutz, Signaturstand, Cloud-Schutz, manipulationssicheren Schutz
    sowie die Ausschlussliste. Zusaetzlich werden die letzten Bedrohungsfunde gezeigt.
.EXAMPLE
    .\defender-status.ps1
#>
[CmdletBinding()]
param()

try {
    $status = Get-MpComputerStatus -ErrorAction Stop
}
catch {
    throw "Microsoft Defender ist nicht verfuegbar: $($_.Exception.Message)"
}

Write-Host "`n=== Microsoft Defender: $env:COMPUTERNAME ===`n" -ForegroundColor Cyan

[PSCustomObject]@{
    Antivirenmodul           = $status.AntivirusEnabled
    Echtzeitschutz           = $status.RealTimeProtectionEnabled
    VerhaltensUeberwachung   = $status.BehaviorMonitorEnabled
    ZugriffsSchutz           = $status.OnAccessProtectionEnabled
    NetzwerkInspektion       = $status.NISEnabled
    ManipulationsSchutz      = $status.IsTamperProtected
    SignaturVersion          = $status.AntivirusSignatureVersion
    SignaturAlterTage        = $status.AntivirusSignatureAge
    SignaturStand            = $status.AntivirusSignatureLastUpdated
    LetzteSchnellpruefung    = $status.QuickScanEndTime
    LetzteVollpruefung       = $status.FullScanEndTime
} | Format-List

$einstellungen = Get-MpPreference

Write-Host '=== Einstellungen ===' -ForegroundColor Cyan
[PSCustomObject]@{
    CloudSchutzStufe   = $einstellungen.MAPSReporting
    AutomatischeProbe  = $einstellungen.SubmitSamplesConsent
    PUA_Schutz         = $einstellungen.PUAProtection
    ArchiveScannen     = -not $einstellungen.DisableArchiveScanning
    WechselmedienScan  = -not $einstellungen.DisableRemovableDriveScanning
} | Format-List

# Ausschluesse sind ein beliebtes Angriffsziel - deshalb immer mit ausweisen.
Write-Host '=== Ausschluesse ===' -ForegroundColor Cyan
if ($einstellungen.ExclusionPath) {
    Write-Host 'Pfade:'     -ForegroundColor Yellow; $einstellungen.ExclusionPath      | ForEach-Object { "  $_" }
}
if ($einstellungen.ExclusionProcess) {
    Write-Host 'Prozesse:'  -ForegroundColor Yellow; $einstellungen.ExclusionProcess   | ForEach-Object { "  $_" }
}
if ($einstellungen.ExclusionExtension) {
    Write-Host 'Endungen:'  -ForegroundColor Yellow; $einstellungen.ExclusionExtension | ForEach-Object { "  $_" }
}
if (-not ($einstellungen.ExclusionPath -or $einstellungen.ExclusionProcess -or $einstellungen.ExclusionExtension)) {
    Write-Host 'Keine Ausschluesse konfiguriert.' -ForegroundColor Green
}

Write-Host "`n=== Letzte Bedrohungsfunde ===" -ForegroundColor Cyan
$funde = Get-MpThreatDetection -ErrorAction SilentlyContinue | Sort-Object InitialDetectionTime -Descending | Select-Object -First 10
if ($funde) {
    $funde | Select-Object ThreatID, InitialDetectionTime, ActionSuccess, Resources | Format-Table -AutoSize -Wrap
}
else {
    Write-Host 'Keine Funde protokolliert.' -ForegroundColor Green
}
