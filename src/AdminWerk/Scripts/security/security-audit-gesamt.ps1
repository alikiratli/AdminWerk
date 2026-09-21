<#
.SYNOPSIS
    Vollstaendiger Sicherheitsbericht eines Windows-Systems mit Bewertung.
.DESCRIPTION
    Prueft die wichtigsten Haertungsmerkmale in einem Durchlauf: Firewall,
    Microsoft Defender, BitLocker, lokale Administratoren, Gastkonto, RDP,
    Patchstand, SMBv1, Autostart und fehlgeschlagene Anmeldungen. Am Ende steht
    eine Punktzahl, die sich fuer eine wiederkehrende Kontrolle eignet.
.NOTES
    Benoetigt Administratorrechte fuer vollstaendige Ergebnisse.
.EXAMPLE
    .\security-audit-gesamt.ps1
.EXAMPLE
    .\security-audit-gesamt.ps1 -CsvPfad C:\Berichte\audit.csv
#>
[CmdletBinding()]
param(
    [int]$AnmeldungenStunden = 24,
    [string]$CsvPfad
)

$pruefungen = [System.Collections.Generic.List[object]]::new()

function Add-Pruefung {
    param(
        [string]$Bereich,
        [string]$Pruefung,
        [ValidateSet('OK', 'WARNUNG', 'KRITISCH', 'INFO')]
        [string]$Bewertung,
        [string]$Detail
    )

    $pruefungen.Add([PSCustomObject]@{
        Bereich   = $Bereich
        Pruefung  = $Pruefung
        Bewertung = $Bewertung
        Detail    = $Detail
    })
}

$istAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $istAdmin) {
    Write-Warning 'Ohne Administratorrechte bleiben einzelne Pruefungen unvollstaendig.'
}

# --- Firewall ----------------------------------------------------------------
try {
    foreach ($profil in Get-NetFirewallProfile -ErrorAction Stop) {
        $bewertung = if ($profil.Enabled) { 'OK' } else { 'KRITISCH' }
        $detail    = if ($profil.Enabled) { 'aktiviert' } else { 'DEAKTIVIERT' }
        Add-Pruefung -Bereich 'Firewall' -Pruefung "Profil $($profil.Name)" -Bewertung $bewertung -Detail $detail
    }
}
catch {
    Add-Pruefung -Bereich 'Firewall' -Pruefung 'Profile' -Bewertung 'WARNUNG' -Detail $_.Exception.Message
}

# --- Microsoft Defender ------------------------------------------------------
try {
    $defender = Get-MpComputerStatus -ErrorAction Stop

    $bewertung = if ($defender.RealTimeProtectionEnabled) { 'OK' } else { 'KRITISCH' }
    $detail    = if ($defender.RealTimeProtectionEnabled) { 'aktiv' } else { 'DEAKTIVIERT' }
    Add-Pruefung -Bereich 'Defender' -Pruefung 'Echtzeitschutz' -Bewertung $bewertung -Detail $detail

    $bewertung = if ($defender.AntivirusEnabled) { 'OK' } else { 'KRITISCH' }
    Add-Pruefung -Bereich 'Defender' -Pruefung 'Antivirenmodul' -Bewertung $bewertung `
        -Detail "Modulversion $($defender.AMEngineVersion)"

    $signaturAlter = [int]$defender.AntivirusSignatureAge
    $bewertung = if ($signaturAlter -le 3) { 'OK' } elseif ($signaturAlter -le 7) { 'WARNUNG' } else { 'KRITISCH' }
    Add-Pruefung -Bereich 'Defender' -Pruefung 'Signaturen' -Bewertung $bewertung -Detail "$signaturAlter Tage alt"
}
catch {
    Add-Pruefung -Bereich 'Defender' -Pruefung 'Status' -Bewertung 'WARNUNG' `
        -Detail 'Defender-Status nicht abrufbar (moeglicherweise Drittanbieter-Virenschutz)'
}

# --- BitLocker ---------------------------------------------------------------
try {
    $systemlaufwerk = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
    $bewertung = if ($systemlaufwerk.ProtectionStatus -eq 'On') { 'OK' } else { 'KRITISCH' }

    Add-Pruefung -Bereich 'BitLocker' -Pruefung "Systemlaufwerk $env:SystemDrive" -Bewertung $bewertung `
        -Detail "$($systemlaufwerk.VolumeStatus), Schutz: $($systemlaufwerk.ProtectionStatus)"
}
catch {
    Add-Pruefung -Bereich 'BitLocker' -Pruefung "Systemlaufwerk $env:SystemDrive" -Bewertung 'WARNUNG' `
        -Detail 'Status nicht abrufbar'
}

# --- Lokale Administratoren --------------------------------------------------
try {
    # SID S-1-5-32-544 statt des Gruppennamens: sprachunabhaengig.
    $administratoren = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop)
    $bewertung = if ($administratoren.Count -le 3) { 'OK' } else { 'WARNUNG' }

    Add-Pruefung -Bereich 'Konten' -Pruefung 'Lokale Administratoren' -Bewertung $bewertung `
        -Detail "$($administratoren.Count) Mitglieder: $($administratoren.Name -join ', ')"
}
catch {
    Add-Pruefung -Bereich 'Konten' -Pruefung 'Lokale Administratoren' -Bewertung 'WARNUNG' -Detail $_.Exception.Message
}

# --- Gastkonto ---------------------------------------------------------------
try {
    $gast = Get-LocalUser -ErrorAction Stop | Where-Object { $_.SID.Value -like '*-501' }
    $bewertung = if ($gast.Enabled) { 'KRITISCH' } else { 'OK' }
    $detail    = if ($gast.Enabled) { "$($gast.Name) ist AKTIV" } else { "$($gast.Name) ist deaktiviert" }

    Add-Pruefung -Bereich 'Konten' -Pruefung 'Gastkonto' -Bewertung $bewertung -Detail $detail
}
catch {
    Add-Pruefung -Bereich 'Konten' -Pruefung 'Gastkonto' -Bewertung 'WARNUNG' -Detail 'Status nicht abrufbar'
}

# --- Lange inaktive, aber aktivierte Konten ----------------------------------
try {
    $veraltet = @(Get-LocalUser -ErrorAction Stop |
        Where-Object { $_.Enabled -and $_.LastLogon -and $_.LastLogon -lt (Get-Date).AddDays(-90) })

    $bewertung = if ($veraltet.Count -gt 0) { 'WARNUNG' } else { 'OK' }
    $detail    = if ($veraltet.Count -gt 0) { $veraltet.Name -join ', ' } else { 'keine' }

    Add-Pruefung -Bereich 'Konten' -Pruefung 'Aktive Konten ohne Anmeldung (>90 Tage)' -Bewertung $bewertung -Detail $detail
}
catch {
    # Kein AD erreichbar oder keine Leseberechtigung - die Pruefung entfaellt still,
    # damit das Gesamtaudit auf einem Einzelrechner weiterlaeuft.
    Write-Verbose "Kontenpruefung uebersprungen: $($_.Exception.Message)"
}

# --- Remotedesktop -----------------------------------------------------------
$rdpSchluessel = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
$rdpGesperrt = (Get-ItemProperty -Path $rdpSchluessel -Name fDenyTSConnections -ErrorAction SilentlyContinue).fDenyTSConnections

if ($rdpGesperrt -eq 0) {
    $station = "$rdpSchluessel\WinStations\RDP-Tcp"
    $nla  = (Get-ItemProperty -Path $station -Name UserAuthentication -ErrorAction SilentlyContinue).UserAuthentication
    $port = (Get-ItemProperty -Path $station -Name PortNumber -ErrorAction SilentlyContinue).PortNumber

    Add-Pruefung -Bereich 'RDP' -Pruefung 'Remotedesktop' -Bewertung 'INFO' -Detail "aktiviert, Port $port"

    $bewertung = if ($nla -eq 1) { 'OK' } else { 'KRITISCH' }
    $detail    = if ($nla -eq 1) { 'aktiv' } else { 'DEAKTIVIERT' }
    Add-Pruefung -Bereich 'RDP' -Pruefung 'Authentifizierung auf Netzwerkebene (NLA)' -Bewertung $bewertung -Detail $detail
}
else {
    Add-Pruefung -Bereich 'RDP' -Pruefung 'Remotedesktop' -Bewertung 'OK' -Detail 'deaktiviert'
}

# --- Patchstand --------------------------------------------------------------
$letztesUpdate = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 1

if ($letztesUpdate -and $letztesUpdate.InstalledOn) {
    $tage = [math]::Round(((Get-Date) - $letztesUpdate.InstalledOn).TotalDays)
    $bewertung = if ($tage -le 45) { 'OK' } elseif ($tage -le 90) { 'WARNUNG' } else { 'KRITISCH' }

    Add-Pruefung -Bereich 'Updates' -Pruefung 'Letztes installiertes Update' -Bewertung $bewertung `
        -Detail "$($letztesUpdate.HotFixID) vor $tage Tagen"
}

$neustartNoetig = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
                  (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')

$bewertung = if ($neustartNoetig) { 'WARNUNG' } else { 'OK' }
$detail    = if ($neustartNoetig) { 'Neustart erforderlich' } else { 'keiner' }
Add-Pruefung -Bereich 'Updates' -Pruefung 'Ausstehender Neustart' -Bewertung $bewertung -Detail $detail

# --- SMBv1 -------------------------------------------------------------------
try {
    $smb = Get-SmbServerConfiguration -ErrorAction Stop
    $bewertung = if ($smb.EnableSMB1Protocol) { 'KRITISCH' } else { 'OK' }
    $detail    = if ($smb.EnableSMB1Protocol) { 'AKTIVIERT - sollte abgeschaltet werden' } else { 'deaktiviert' }

    Add-Pruefung -Bereich 'Protokolle' -Pruefung 'SMBv1' -Bewertung $bewertung -Detail $detail
}
catch {
    # Get-SmbServerConfiguration fehlt auf aelteren Systemen ohne SMB-Serverrolle.
    Write-Verbose "SMBv1-Pruefung uebersprungen: $($_.Exception.Message)"
}

# --- Autostart ---------------------------------------------------------------
$autostart = @(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue)
Add-Pruefung -Bereich 'Autostart' -Pruefung 'Automatisch gestartete Programme' -Bewertung 'INFO' `
    -Detail "$($autostart.Count) Eintraege"

# --- Fehlgeschlagene Anmeldungen ---------------------------------------------
try {
    $fehlanmeldungen = @(Get-WinEvent -FilterHashtable @{
        LogName   = 'Security'
        Id        = 4625
        StartTime = (Get-Date).AddHours(-$AnmeldungenStunden)
    } -ErrorAction Stop)

    $anzahl = $fehlanmeldungen.Count
    $bewertung = if ($anzahl -eq 0) { 'OK' } elseif ($anzahl -lt 10) { 'WARNUNG' } else { 'KRITISCH' }

    Add-Pruefung -Bereich 'Anmeldungen' -Pruefung "Fehlgeschlagene Anmeldungen ($AnmeldungenStunden h)" `
        -Bewertung $bewertung -Detail "$anzahl Versuche"
}
catch {
    # Get-WinEvent wirft eine Ausnahme, wenn der Filter keine Treffer liefert.
    Add-Pruefung -Bereich 'Anmeldungen' -Pruefung "Fehlgeschlagene Anmeldungen ($AnmeldungenStunden h)" `
        -Bewertung 'OK' -Detail 'keine Ereignisse gefunden'
}

# ============================== Ausgabe ======================================
Write-Host ''
Write-Host '=========================================================' -ForegroundColor Cyan
Write-Host '             WINDOWS SICHERHEITSPRUEFUNG                 ' -ForegroundColor Cyan
Write-Host '=========================================================' -ForegroundColor Cyan
Write-Host ('Computer : {0}' -f $env:COMPUTERNAME)
Write-Host ('Datum    : {0}' -f (Get-Date -Format 'dd.MM.yyyy HH:mm'))
Write-Host ('Benutzer : {0}' -f $env:USERNAME)
Write-Host ''

foreach ($bereich in ($pruefungen.Bereich | Select-Object -Unique)) {
    Write-Host "--- $bereich ---" -ForegroundColor White

    foreach ($eintrag in ($pruefungen | Where-Object Bereich -eq $bereich)) {
        $farbe = switch ($eintrag.Bewertung) {
            'OK'       { 'Green' }
            'WARNUNG'  { 'Yellow' }
            'KRITISCH' { 'Red' }
            default    { 'Gray' }
        }

        Write-Host ('  {0,-48} {1,-9} {2}' -f $eintrag.Pruefung, $eintrag.Bewertung, $eintrag.Detail) -ForegroundColor $farbe
    }

    Write-Host ''
}

# --- Bewertung ---------------------------------------------------------------
$bewertbar = @($pruefungen | Where-Object Bewertung -ne 'INFO')
$punkte = 0

foreach ($eintrag in $bewertbar) {
    $punkte += switch ($eintrag.Bewertung) {
        'OK'       { 2 }
        'WARNUNG'  { 1 }
        'KRITISCH' { 0 }
    }
}

$maximum = $bewertbar.Count * 2
$prozent = if ($maximum -gt 0) { [math]::Round(($punkte / $maximum) * 100) } else { 0 }
$note    = [math]::Round($prozent / 10, 1)
$farbe   = if ($prozent -ge 85) { 'Green' } elseif ($prozent -ge 60) { 'Yellow' } else { 'Red' }

$anzahlKritisch = @($pruefungen | Where-Object Bewertung -eq 'KRITISCH').Count
$anzahlWarnung  = @($pruefungen | Where-Object Bewertung -eq 'WARNUNG').Count
$anzahlOk       = @($pruefungen | Where-Object Bewertung -eq 'OK').Count

Write-Host '=========================================================' -ForegroundColor Cyan
Write-Host ('Sicherheitsbewertung: {0}/10 ({1} %)' -f $note, $prozent) -ForegroundColor $farbe
Write-Host ('Kritisch: {0}   Warnungen: {1}   OK: {2}' -f $anzahlKritisch, $anzahlWarnung, $anzahlOk)
Write-Host '=========================================================' -ForegroundColor Cyan

if ($CsvPfad) {
    $pruefungen | Export-Csv -Path $CsvPfad -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Host "`nCSV-Export: $CsvPfad" -ForegroundColor Green
}
